import Foundation

/// Whether phone approval is armed. Off by default: the approval hook checks
/// this marker file first and immediately falls back to a normal terminal
/// prompt when it's absent, so live/attended sessions are unaffected. Arm it
/// right before stepping away; disarm when back at the desk.
enum RemoteApproval {
    static let markerURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".agent-garden-remote-approval")

    static var isArmed: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    static func setArmed(_ on: Bool) {
        if on {
            FileManager.default.createFile(atPath: markerURL.path, contents: nil)
        } else {
            try? FileManager.default.removeItem(at: markerURL)
        }
    }
}
