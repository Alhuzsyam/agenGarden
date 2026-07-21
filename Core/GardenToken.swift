import Foundation

/// Shared secret that gates the state endpoints, so a random device on the
/// LAN/tailnet can't drive your agents. Generated once and persisted to
/// ~/.agent-garden-token (0600) — the same file the bridge hook reads, so the
/// two sides agree without any configuration.
enum GardenToken {
    static let fileURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".agent-garden-token")

    /// Loaded once at startup: reuse the persisted token, or mint and store one.
    static let value: String = load()

    private static func load() -> String {
        if let data = try? Data(contentsOf: fileURL),
           let existing = String(data: data, encoding: .utf8)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        let token = generate()
        FileManager.default.createFile(
            atPath: fileURL.path,
            contents: Data(token.utf8),
            attributes: [.posixPermissions: 0o600])
        return token
    }

    private static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
