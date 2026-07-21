import Foundation
import Combine

/// One event reported by an external agent (Claude Code hook, curl, etc).
struct GardenEvent: Codable {
    let agent: String
    let event: String // start | tool | attention | resume | done | error
    var task: String?
    var tool: String?
}

struct Agent: Identifiable, Codable, Equatable {
    let id: String
    var task: String?
    var lastTool: String?
    var growth: Int = 0
    var isDone = false
    var isError = false
    var needsAttention = false
    var startedAt: Date
    var updatedAt: Date

    var stateLabel: String {
        if isError { return "GAME OVER" }
        if isDone { return "cherry get! 🍒" }
        if needsAttention { return "ada ghost — butuh input!" }
        switch growth {
        case ..<2: return "insert coin…"
        case ..<6: return "wakka wakka…"
        case ..<12: return "makan dots…"
        default: return "hampir tamat"
        }
    }
}

/// A permission prompt Claude Code is blocked on, waiting for allow/deny
/// from the phone dashboard (or the terminal, if it times out).
struct Approval: Identifiable, Codable {
    let id: String
    let agent: String
    let tool: String
    let detail: String
    let createdAt: Date
    var decision: String? // nil = pending, "allow" | "deny"
}

final class AgentStore: ObservableObject {
    @Published private(set) var agents: [Agent] = []
    @Published private(set) var approvals: [Approval] = []

    /// Prompts queued from the phone, keyed by agent id. The Stop hook drains
    /// this while a turn is parked, feeding the text back into the session.
    private var pendingPrompts: [String: [String]] = [:]

    /// Live terminal mirror from the tmux bridge: latest captured screen and
    /// keystrokes queued from the phone, keyed by agent id.
    private var terminals: [String: String] = [:]
    private var pendingKeys: [String: [String]] = [:]

    private var cleanupTimer: Timer?

    /// Remove finished plants after this long, and stale ones after 30 min.
    private let harvestedTTL: TimeInterval = 5 * 60
    private let staleTTL: TimeInterval = 30 * 60
    private let decidedApprovalTTL: TimeInterval = 2 * 60

    init() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.cleanup()
        }
    }

    func apply(_ e: GardenEvent) {
        assert(Thread.isMainThread)
        let now = Date()
        var agent = agents.first(where: { $0.id == e.agent })
            ?? Agent(id: e.agent, startedAt: now, updatedAt: now)

        switch e.event {
        case "start":
            agent = Agent(id: e.agent, task: e.task, startedAt: now, updatedAt: now)
        case "tool":
            agent.growth += 1
            agent.lastTool = e.tool
            agent.isDone = false
        case "attention":
            agent.needsAttention = true
        case "resume":
            agent.needsAttention = false
            agent.isDone = false
        case "done":
            agent.isDone = true
            agent.needsAttention = false
        case "error":
            agent.isError = true
        default:
            break
        }
        if let task = e.task { agent.task = task }
        agent.updatedAt = now

        if let idx = agents.firstIndex(where: { $0.id == e.agent }) {
            agents[idx] = agent
        } else {
            agents.append(agent)
        }
    }

    private func cleanup() {
        let now = Date()
        agents.removeAll { a in
            let age = now.timeIntervalSince(a.updatedAt)
            if a.isDone || a.isError { return age > harvestedTTL }
            return age > staleTTL
        }
        approvals.removeAll { a in
            let age = now.timeIntervalSince(a.createdAt)
            if a.decision != nil { return age > decidedApprovalTTL }
            return age > staleTTL
        }
        // Drop terminal mirrors and queued input for agents that aged out.
        let live = Set(agents.map { $0.id })
        terminals = terminals.filter { live.contains($0.key) }
        pendingKeys = pendingKeys.filter { live.contains($0.key) }
        pendingPrompts = pendingPrompts.filter { live.contains($0.key) }
    }

    func remove(id: String) {
        agents.removeAll { $0.id == id }
    }

    // MARK: - Approvals

    func requestApproval(id: String, agent: String, tool: String, detail: String) {
        assert(Thread.isMainThread)
        let now = Date()
        approvals.append(
            Approval(id: id, agent: agent, tool: tool, detail: detail, createdAt: now, decision: nil))

        if let idx = agents.firstIndex(where: { $0.id == agent }) {
            agents[idx].needsAttention = true
            agents[idx].updatedAt = now
        } else {
            agents.append(Agent(id: agent, needsAttention: true, startedAt: now, updatedAt: now))
        }
    }

    func decide(id: String, decision: String) {
        assert(Thread.isMainThread)
        guard decision == "allow" || decision == "deny" else { return }
        guard let idx = approvals.firstIndex(where: { $0.id == id }) else { return }
        approvals[idx].decision = decision

        let agentId = approvals[idx].agent
        let stillPending = approvals.contains { $0.agent == agentId && $0.decision == nil }
        if !stillPending, let aidx = agents.firstIndex(where: { $0.id == agentId }) {
            agents[aidx].needsAttention = false
        }
    }

    func decision(for id: String) -> String? {
        approvals.first(where: { $0.id == id })?.decision
    }

    // MARK: - Remote prompts

    /// Queue a prompt from the phone and wake the plot so it stops looking
    /// harvested while it waits to be picked up by the next parked turn.
    func enqueuePrompt(agent agentId: String, text: String) {
        assert(Thread.isMainThread)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pendingPrompts[agentId, default: []].append(text)

        let now = Date()
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            agents[idx].isDone = false
            agents[idx].needsAttention = false
            agents[idx].task = text
            agents[idx].updatedAt = now
        } else {
            agents.append(Agent(id: agentId, task: text, startedAt: now, updatedAt: now))
        }
    }

    /// Pop the oldest queued prompt for an agent, if any (consumed once).
    func dequeuePrompt(agent agentId: String) -> String? {
        assert(Thread.isMainThread)
        guard var queue = pendingPrompts[agentId], !queue.isEmpty else { return nil }
        let next = queue.removeFirst()
        pendingPrompts[agentId] = queue.isEmpty ? nil : queue
        return next
    }

    // MARK: - Terminal mirror (tmux bridge)

    /// Latest captured screen for an agent's tmux pane.
    func setTerminal(agent agentId: String, screen: String) {
        assert(Thread.isMainThread)
        terminals[agentId] = screen
    }

    func terminal(agent agentId: String) -> String? {
        terminals[agentId]
    }

    /// Queue keystroke tokens from the phone (literal text or key names like
    /// "Enter"/"Escape"/"Down"); the bridge drains and replays them into tmux.
    func enqueueKeys(agent agentId: String, keys: [String]) {
        assert(Thread.isMainThread)
        guard !keys.isEmpty else { return }
        pendingKeys[agentId, default: []].append(contentsOf: keys)
    }

    /// Drain all queued keys for an agent (consumed once), in order.
    func dequeueKeys(agent agentId: String) -> [String] {
        assert(Thread.isMainThread)
        guard let keys = pendingKeys[agentId], !keys.isEmpty else { return [] }
        pendingKeys[agentId] = nil
        return keys
    }
}
