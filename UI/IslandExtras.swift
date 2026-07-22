import SwiftUI
import AppKit

/// Light/dark theme for the notch UI, persisted across launches. The notch is
/// dark by default (it hugs the physical notch); the header toggle flips it.
final class IslandTheme: ObservableObject {
    static let shared = IslandTheme()

    @Published var mode: String {
        didSet { UserDefaults.standard.set(mode, forKey: "gardenTheme") }
    }
    private init() { mode = UserDefaults.standard.string(forKey: "gardenTheme") ?? "dark" }

    var scheme: ColorScheme { mode == "light" ? .light : .dark }
    var notchBG: Color { mode == "light" ? Color.white.opacity(0.96) : Color.black.opacity(0.9) }
    func toggle() { mode = (mode == "light") ? "dark" : "light" }
}

/// ☀︎ / ☾ toggle for the notch card header.
struct ThemeToggleButton: View {
    @ObservedObject var theme = IslandTheme.shared
    var body: some View {
        Button(theme.mode == "light" ? "☀︎" : "☾") { theme.toggle() }
            .buttonStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .help("Ganti tema terang / gelap")
    }
}

/// "+ New" — ask for a project name, spawn a detached Claude session through the
/// local /new-project endpoint, then open Terminal attached to it.
struct NewProjectButton: View {
    /// Collapse the island first so the dialog isn't hidden behind the notch.
    var collapse: (() -> Void)? = nil

    var body: some View {
        Button("+ New") { promptAndSpawn() }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.yellow)
            .help("Mulai project / agent baru")
    }

    private func promptAndSpawn() {
        collapse?()   // shrink the island out of the way…
        // …then show the dialog on the next runloop so the collapse renders first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let alert = NSAlert()
            alert.messageText = "Project baru"
            alert.informativeText = "Nama sesi (folder default: ~/nama)"
            alert.addButton(withTitle: "Buat & buka terminal")
            alert.addButton(withTitle: "Batal")
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            field.placeholderString = "api-refactor"
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            spawn(name: name)
        }
    }

    private func spawn(name: String) {
        guard let url = URL(string: "http://127.0.0.1:\(GardenServer.defaultPort)/new-project")
        else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(GardenToken.value)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name])
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            DispatchQueue.main.async { openTerminal(name: name) }
        }.resume()
    }

    /// Attach a Terminal window to the just-created tmux session so you see the
    /// live Claude session (mirrors garden-claude.sh's final `tmux attach`).
    private func openTerminal(name: String) {
        let session = "garden_" + String(name.map {
            ($0.isLetter || $0.isNumber || $0 == "_") ? $0 : "_"
        })
        let script = "tell application \"Terminal\"\n"
            + "do script \"tmux attach -t \(session)\"\n"
            + "activate\nend tell"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }
}
