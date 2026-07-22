import SwiftUI
import AppKit

/// The expanded notch card with per-agent detail.
struct IslandView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject private var theme = IslandTheme.shared
    var state: IslandState? = nil
    @State private var showQR = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AGENT ARCADE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow)
                Spacer()
                Text("localhost:\(GardenServer.defaultPort)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                RemoteApprovalToggleView()
            }

            if store.agents.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        PixelSpriteView(art: Sprites.pacmanOpen, pixel: 3)
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(Sprites.dotColor).frame(width: 6, height: 6)
                        }
                        PixelSpriteView(art: Sprites.cherry, pixel: 3)
                    }
                    Text("Belum ada agen yang jalan")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("curl -X POST localhost:\(GardenServer.defaultPort)/event \\\n  -d '{\"agent\":\"demo\",\"event\":\"start\"}'")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(store.agents) { agent in
                    AgentRowView(agent: agent, store: store)
                }
            }

            UsageStripView()

            if showQR { QRPanelView() }

            HStack(spacing: 10) {
                NewProjectButton(collapse: { state?.expanded = false })
                LoginToggleView()
                Spacer()
                ThemeToggleButton()
                Button(showQR ? "📱 hide QR" : "📱 QR") {
                    withAnimation(.easeOut(duration: 0.15)) { showQR.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(showQR ? .yellow : .secondary)
                CopyLinkView()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(NotchShape(radius: 18).fill(theme.notchBG))
        .overlay(NotchShape(radius: 18).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .environment(\.colorScheme, theme.scheme)
    }
}

struct RemoteApprovalToggleView: View {
    @State private var armed = RemoteApproval.isArmed

    var body: some View {
        Button(armed ? "📡 remote approval: ON" : "remote approval: off") {
            RemoteApproval.setArmed(!armed)
            armed = RemoteApproval.isArmed
        }
        .buttonStyle(.plain)
        .font(.system(size: 9, weight: armed ? .bold : .regular, design: .monospaced))
        .foregroundStyle(armed ? Color.green : Color.secondary)
        .onAppear { armed = RemoteApproval.isArmed }
    }
}

/// Copies the phone dashboard URL (with the auth token) to the clipboard, so
/// you can AirDrop/message it to your phone and "Add to Home Screen".
struct CopyLinkView: View {
    @State private var copied = false

    var body: some View {
        Button(copied ? "✓ copied" : "🔗 copy phone link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(GardenServer.phoneURL(), forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(copied ? .green : .secondary)
    }
}

/// The scannable dashboard link. Shows a warning if Tailscale is down, since
/// the link then only resolves on the local network.
struct QRPanelView: View {
    var body: some View {
        let url = GardenServer.phoneURL()
        let onTailscale = GardenServer.tailscaleIPv4() != nil
        VStack(spacing: 8) {
            if let img = QRCode.image(for: url, side: 180) {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 180, height: 180)
                    .padding(8)
                    .background(Color.white)
                    .cornerRadius(10)
            }
            Text(onTailscale ? "scan pakai kamera HP (via Tailscale)"
                             : "⚠️ Tailscale mati — link ini cuma jalan di LAN")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(onTailscale ? Color.secondary : Color.orange)
                .multilineTextAlignment(.center)
            Text(url)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }
}

struct LoginToggleView: View {
    @State private var enabled = LoginItem.isEnabled

    var body: some View {
        Button(enabled ? "✓ launch at login" : "launch at login") {
            LoginItem.setEnabled(!enabled)
            enabled = LoginItem.isEnabled
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(enabled ? .yellow : .secondary)
        .onAppear { enabled = LoginItem.isEnabled }
    }
}

struct AgentRowView: View {
    let agent: Agent
    let store: AgentStore

    private var pending: Approval? {
        store.approvals.first { $0.agent == agent.id && $0.decision == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 10) {
            AgentPlotView(agent: agent, pixel: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.id)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                if let task = agent.task, !task.isEmpty {
                    Text(task)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(agent.stateLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(agent.needsAttention ? .orange : .secondary)
                if let tool = agent.lastTool {
                    Text("⚒ \(tool)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(elapsed)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                if agent.isDone || agent.isError {
                    Button("clear") { store.remove(id: agent.id) }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.yellow)
                }
            }
        }

            if let ap = pending {
                ApprovalActionView(approval: ap, store: store)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(pending != nil ? Color.orange.opacity(0.16) : Color.primary.opacity(0.06))
        )
    }

    private var elapsed: String {
        let s = Int(Date().timeIntervalSince(agent.startedAt))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}

/// Allow/Deny row shown inside an agent card when a tool is waiting for a
/// verdict. Deciding here races the phone, the watch, and the terminal —
/// whichever answers first wins (the hook polls GET /approval/<id>).
struct ApprovalActionView: View {
    let approval: Approval
    let store: AgentStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.fill")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
            Text("\(approval.tool): \(approval.detail)")
                .font(.system(size: 9, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Button("✓ Allow") { store.decide(id: approval.id, decision: "allow") }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)
            Button("✗ Deny") { store.decide(id: approval.id, decision: "deny") }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}

/// AI-model spend today vs the daily budget, with a 7-day sparkline. Turns
/// yellow at 80% ("tinggal dikit"), red at 100% ("OVER BUDGET").
struct UsageStripView: View {
    @ObservedObject var usage = UsageMonitor.shared

    private var color: Color {
        if usage.pct >= 1 { return .red }
        if usage.pct >= 0.8 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("MODEL SPEND")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "$%.2f / $%.0f", usage.today, usage.budget))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Button("−") { UsageMonitor.shared.setDailyBudget(max(1, usage.budget - 25)) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("+") { UsageMonitor.shared.setDailyBudget(usage.budget + 25) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3).fill(color)
                        .frame(width: geo.size.width * CGFloat(min(usage.pct, 1)))
                }
            }
            .frame(height: 6)
            HStack(spacing: 6) {
                if usage.pct >= 0.8 {
                    Text(usage.pct >= 1 ? "OVER BUDGET" : "tinggal dikit")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                }
                Spacer()
                if !usage.topModel.isEmpty {
                    Text(usage.topModel.replacingOccurrences(of: "claude-", with: ""))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                SparklineView(values: usage.spark, color: color)
                    .frame(width: 70, height: 16)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

/// 7 little bars, tallest = highest-spend day.
struct SparklineView: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 1, 0.0001)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.75))
                        .frame(height: max(2, geo.size.height * CGFloat(v / maxV)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
