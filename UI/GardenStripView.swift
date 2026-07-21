import SwiftUI

/// The glanceable row that lives in the menu bar.
struct GardenStripView: View {
    @ObservedObject var store: AgentStore

    var body: some View {
        HStack(spacing: 4) {
            if store.agents.isEmpty {
                PixelSpriteView(art: Sprites.pacmanClosed, pixel: 1.5)
                    .opacity(0.5)
            } else {
                ForEach(store.agents) { agent in
                    AgentPlotView(agent: agent)
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
    }
}

/// One agent as a Pac-Man lane: chomping Pac-Man eats dots (tool calls),
/// a ghost shows up when the agent needs input, a cherry when it's done.
struct AgentPlotView: View {
    let agent: Agent
    var pixel: CGFloat = 1.5

    private var dotsRemaining: Int {
        agent.isDone ? 0 : max(0, 4 - agent.growth / 3)
    }

    var body: some View {
        HStack(spacing: 2) {
            if agent.isError {
                PixelSpriteView(art: Sprites.gameOver, pixel: pixel)
            } else {
                if agent.isDone {
                    PixelSpriteView(art: Sprites.pacmanClosed, pixel: pixel)
                } else {
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        let open = Int(context.date.timeIntervalSinceReferenceDate / 0.25) % 2 == 0
                        PixelSpriteView(art: Sprites.pacman(open: open), pixel: pixel)
                    }
                }

                ForEach(0..<dotsRemaining, id: \.self) { _ in
                    Circle()
                        .fill(Sprites.dotColor)
                        .frame(width: 2 * pixel, height: 2 * pixel)
                }

                if agent.needsAttention {
                    TimelineView(.periodic(from: .now, by: 0.6)) { context in
                        let blink = Int(context.date.timeIntervalSinceReferenceDate / 0.6) % 2 == 0
                        PixelSpriteView(art: Sprites.ghost, pixel: pixel)
                            .opacity(blink ? 1 : 0.35)
                    }
                }

                if agent.isDone {
                    PixelSpriteView(art: Sprites.cherry, pixel: pixel)
                }
            }
        }
    }
}
