import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Ports packages/core/src/process.ts -- spawns/stops the odoo-bin process
/// directly (not via VS Code's debugger, which is launch.json's job).
enum ProcessManager {
    static func isAlive(_ pid: Int32?) -> Bool {
        guard let pid, pid > 0 else { return false }
        return kill(pid, 0) == 0
    }

    private static func odooBinArgs(_ entry: RegistryEntry) -> [String] {
        var addonsPath = ["odoo/addons", "enterprise"]
        if entry.repos["design-themes"] != nil { addonsPath.append("design-themes") }

        var args = [
            "-d", entry.db,
            "--http-port", String(entry.port),
            "--http-interface", "127.0.0.1",
            "--addons-path", addonsPath.joined(separator: ","),
        ]

        var upgradePath: [String] = []
        if entry.repos["upgrade"] != nil { upgradePath.append("upgrade/migrations") }
        if entry.repos["upgrade-util"] != nil { upgradePath.append("upgrade-util/src") }
        if !upgradePath.isEmpty {
            args.append(contentsOf: ["--upgrade-path", upgradePath.joined(separator: ",")])
        }
        return args
    }

    /// Spawns odoo-bin in its own process group (so stopProcess's group-kill
    /// takes its children down too), stdout+stderr appended to the worktree's
    /// log file, detached from this app so it survives independently.
    static func startProcess(worktreeRoot: URL, entry: RegistryEntry) throws -> Int32 {
        let odooBin = worktreeRoot.appendingPathComponent("odoo/odoo-bin").path
        FileManager.default.createFile(atPath: entry.logFile, contents: nil)
        guard let logHandle = FileHandle(forWritingAtPath: entry.logFile) else {
            throw ProcessError(message: "Could not open log file at \(entry.logFile)")
        }
        logHandle.seekToEndOfFile()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: entry.interpreter)
        process.arguments = [odooBin] + odooBinArgs(entry)
        process.currentDirectoryURL = worktreeRoot
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        let pid = process.processIdentifier
        // Move into its own process group so stopProcess can signal the
        // whole group (odoo-bin's own children included), not just this pid.
        // Brief exec-order race is inherent here (same as Node's equivalent).
        setpgid(pid, pid)
        return pid
    }

    static func stopProcess(_ pid: Int32) {
        guard isAlive(pid) else { return }
        if kill(-pid, SIGTERM) != 0 {
            kill(pid, SIGTERM)
        }
    }
}
