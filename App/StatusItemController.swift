import AppKit
import SwiftUI

final class StatusItemController {
    private let statusItem: NSStatusItem
    private let island: IslandController

    init(store: AgentStore) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        island = IslandController(store: store)

        if let button = statusItem.button {
            let hosting = NSHostingView(rootView: GardenStripView(store: store))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.topAnchor.constraint(equalTo: button.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            ])
            button.target = self
            button.action = #selector(togglePanel)
        }
    }

    @objc private func togglePanel() {
        island.toggleExpanded()
    }
}
