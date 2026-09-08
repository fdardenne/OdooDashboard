import Foundation

/// Resolves absolute paths for the CLI tools this app shells out to
/// (git, gh, dropdb, code, claude, osascript). Launched as a GUI app, the
/// process gets launchd's minimal PATH (no /usr/local/bin, /opt/homebrew/bin,
/// or ~/.local/bin) -- so bare names often fail to resolve. Check the common
/// install locations directly instead of relying on PATH.
enum BinaryLocator {
    private static let searchDirs = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
        "/usr/bin",
        "/bin",
    ]

    private static let cache = Locked<[String: String]>([:])

    /// Returns an absolute path if found in any known location, else the
    /// bare name (letting Process fall back to whatever PATH is available).
    static func resolve(_ name: String) -> String {
        if let cached = cache.withLock({ $0[name] }) { return cached }
        for dir in searchDirs {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                cache.withLock { $0[name] = candidate }
                return candidate
            }
        }
        cache.withLock { $0[name] = name }
        return name
    }

    static var git: String { resolve("git") }
    static var gh: String { resolve("gh") }
    static var dropdb: String { resolve("dropdb") }
    static var code: String { resolve("code") }
    static var osascript: String { resolve("osascript") }

    /// claude.ts's own preference: ~/.local/bin/claude if present, else bare.
    static var claude: String {
        let local = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path
        return FileManager.default.isExecutableFile(atPath: local) ? local : resolve("claude")
    }
}
