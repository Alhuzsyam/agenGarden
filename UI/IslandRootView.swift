import SwiftUI

/// Notch shape: flat on top (hugs the screen edge), rounded bottom corners.
struct NotchShape: InsettableShape {
    var radius: CGFloat = 16
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> NotchShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in raw: CGRect) -> Path {
        let rect = raw.insetBy(dx: insetAmount, dy: insetAmount)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Morphs between the compact notch and the expanded detail card.
struct IslandRootView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var state: IslandState

    var body: some View {
        Group {
            if state.expanded {
                IslandView(store: store, state: state)
            } else {
                CompactPillView(store: store)
            }
        }
        .frame(width: state.width)
        .onHover { state.hovering = $0 }
        .onTapGesture {
            if !state.expanded { state.expanded = true }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.expanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.width)
    }
}

/// The always-on compact notch: just the running-agent count, far left.
struct CompactPillView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject private var theme = IslandTheme.shared

    private var anyAttention: Bool {
        store.agents.contains { $0.needsAttention }
    }

    var body: some View {
        HStack {
            Text("\(store.agents.count)")
                .font(.system(size: 18, weight: .light, design: .monospaced))
                .foregroundStyle(anyAttention ? Color.orange : (theme.mode == "light" ? Color.black : Color.white))
            Spacer(minLength: 0)
            PatrolPacmanView()
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.top, 5)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity)
        .background(NotchShape(radius: 16).fill(theme.notchBG))
        .overlay(NotchShape(radius: 16).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .environment(\.colorScheme, theme.scheme)
    }
}

/// Pac-Man patrolling back and forth on the right side of the compact notch.
struct PatrolPacmanView: View {
    private let trackWidth: CGFloat = 70
    private let spriteWidth: CGFloat = 12 * 1.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period = 5.0
            let phase = t.truncatingRemainder(dividingBy: period) / period
            let forward = phase < 0.5
            let progress = forward ? phase * 2 : (1 - phase) * 2
            let open = Int(t / 0.2) % 2 == 0

            PixelSpriteView(art: Sprites.pacman(open: open), pixel: 1.6)
                .scaleEffect(x: forward ? 1 : -1, y: 1)
                .offset(x: progress * (trackWidth - spriteWidth))
                .frame(width: trackWidth, alignment: .leading)
        }
    }
}
