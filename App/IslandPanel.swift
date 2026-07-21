import AppKit
import SwiftUI
import Combine

final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var hovering = false
    @Published var width: CGFloat = 340
}

/// iPhone-style Dynamic Island pinned to the top-center of the screen:
/// a compact pill while agents run, expands on hover/click, and pulses
/// open briefly when an agent needs attention or finishes.
final class IslandController {
    private let store: AgentStore
    private let state = IslandState()
    private let panel: KeyablePanel
    private let hosting: NSHostingView<IslandRootView>
    private var cancellables = Set<AnyCancellable>()
    private var collapseWork: DispatchWorkItem?
    private var clickMonitor: Any?
    private var previousAgents: [String: Agent] = [:]

    init(store: AgentStore) {
        self.store = store
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        hosting = NSHostingView(rootView: IslandRootView(store: store, state: state))
        panel.contentView = hosting

        state.$expanded
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expanded in self?.expandedChanged(expanded) }
            .store(in: &cancellables)

        state.$hovering
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hovering in self?.hoveringChanged(hovering) }
            .store(in: &cancellables)

        store.$agents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] agents in self?.agentsChanged(agents) }
            .store(in: &cancellables)
    }

    func toggleExpanded() {
        if !panel.isVisible { panel.orderFrontRegardless() }
        state.expanded.toggle()
        if !state.expanded && store.agents.isEmpty { panel.orderOut(nil) }
    }

    // MARK: - Reactions

    private func expandedChanged(_ expanded: Bool) {
        relayout(animated: panel.isVisible)
        if expanded {
            panel.makeKey()
            installClickMonitor()
        } else {
            removeClickMonitor()
            if store.agents.isEmpty { panel.orderOut(nil) }
        }
    }

    private func hoveringChanged(_ hovering: Bool) {
        collapseWork?.cancel()
        if hovering {
            if !state.expanded { state.expanded = true }
        } else if state.expanded {
            scheduleCollapse(after: 0.4)
        }
    }

    private func agentsChanged(_ agents: [Agent]) {
        if agents.isEmpty {
            if !state.expanded { panel.orderOut(nil) }
        } else {
            if !panel.isVisible {
                relayout(animated: false)
                panel.orderFrontRegardless()
            }
        }
        relayout(animated: panel.isVisible)

        // Live-activity style pulse on important transitions.
        let important = agents.contains { agent in
            let old = previousAgents[agent.id]
            let newAttention = agent.needsAttention && !(old?.needsAttention ?? false)
            let newDone = agent.isDone && !(old?.isDone ?? false)
            return newAttention || newDone
        }
        previousAgents = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        if important && !state.expanded {
            state.expanded = true
            scheduleCollapse(after: 3.0)
        }
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.state.hovering else { return }
            self.state.expanded = false
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Layout

    private func relayout(animated: Bool) {
        guard let screen = NSScreen.main else { return }

        // Island width scales with the screen, like the iPhone's island.
        let screenWidth = screen.frame.width
        let targetWidth = state.expanded
            ? min(max(screenWidth * 0.48, 460), 800)
            : min(max(screenWidth * 0.28, 300), 520)
        if state.width != targetWidth { state.width = targetWidth }

        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        size.width = targetWidth
        let frame = NSRect(
            x: (screen.frame.midX - size.width / 2).rounded(),
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: - Outside clicks

    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.state.expanded = false
        }
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
