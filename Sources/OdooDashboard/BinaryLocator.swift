import Foundation

/// Resolves absolute paths for the CLI tools this app shells out to
/// (git, gh, dropdb, claude, zed, cmux, osascript). Launched as a GUI app, the
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
    static var osascript: String { resolve("osascript") }

    /// Zed's CLI isn't always installed onto PATH the way VS Code's `code`
    /// is (no PATH entry found on this machine despite Zed being
    /// installed) -- fall back to the CLI binary inside whichever Zed.app
    /// variant is actually present (stable, then Preview) before giving up
    /// to the bare name.
    static var zed: String {
        let resolved = resolve("zed")
        guard resolved == "zed" else { return resolved }
        for appName in ["Zed.app", "Zed Preview.app"] {
            let candidate = "/Applications/\(appName)/Contents/MacOS/cli"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return resolved
    }

    /// Same story as Zed -- no PATH entry found on this machine despite
    /// cmux.app being installed, so fall back to its bundled executable.
    /// Only `cmux <path>` (open a directory) is usable from outside cmux --
    /// its richer CLI/socket commands (workspace/split/send) reject any
    /// caller not spawned inside a cmux-managed terminal, by design
    /// (confirmed live: "Access denied - only processes started inside
    /// cmux can connect").
    static var cmux: String {
        let resolved = resolve("cmux")
        guard resolved == "cmux" else { return resolved }
        let candidate = "/Applications/cmux.app/Contents/MacOS/cmux"
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : resolved
    }

    /// claude.ts's own preference: ~/.local/bin/claude if present, else bare.
    static var claude: String {
        let local = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path
        return FileManager.default.isExecutableFile(atPath: local) ? local : resolve("claude")
    }
}
