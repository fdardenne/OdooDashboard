import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// On-disk shape of a worktree entry -- matches packages/core/src/types.ts's
/// WorktreeEntry exactly (registry.json is a shared format; keeping it
/// identical means the file this app reads/writes is unchanged from what the
/// old Node tool produced).
struct RegistryEntry: Codable, Sendable {
    var name: String
    var taskId: String
    var fromBranch: String
    var createdAt: String
    var repos: [String: String]
    var port: Int
    var db: String
    var interpreter: String
    var pid: Int32?
    var logFile: String
    var installModules: String
    var updateModules: String
    var description: String

    init(name: String, taskId: String, fromBranch: String, createdAt: String, repos: [String: String], port: Int, db: String, interpreter: String, pid: Int32?, logFile: String, installModules: String, updateModules: String, description: String) {
        self.name = name
        self.taskId = taskId
        self.fromBranch = fromBranch
        self.createdAt = createdAt
        self.repos = repos
        self.port = port
        self.db = db
        self.interpreter = interpreter
        self.pid = pid
        self.logFile = logFile
        self.installModules = installModules
        self.updateModules = updateModules
        self.description = description
    }

    // Backfills fields missing from an entry written by an older version of
    // this tool, mirroring registry.ts's migrate() -- so a legacy
    // registry.json without installModules/updateModules/description still
    // decodes instead of failing outright.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        taskId = try c.decode(String.self, forKey: .taskId)
        fromBranch = try c.decode(String.self, forKey: .fromBranch)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        repos = try c.decodeIfPresent([String: String].self, forKey: .repos) ?? [:]
        port = try c.decode(Int.self, forKey: .port)
        db = try c.decode(String.self, forKey: .db)
        interpreter = try c.decode(String.self, forKey: .interpreter)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        logFile = try c.decode(String.self, forKey: .logFile)
        installModules = try c.decodeIfPresent(String.self, forKey: .installModules) ?? Config.defaultInstallModules
        updateModules = try c.decodeIfPresent(String.self, forKey: .updateModules) ?? Config.defaultUpdateModules
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

struct RegistryFile: Codable {
    var worktrees: [String: RegistryEntry]
}

/// Ports packages/core/src/registry.ts -- atomic reads/writes plus a simple
/// exclusive-create lockfile so concurrent access (this app plus, in theory,
/// anything else touching registry.json) doesn't corrupt it.
enum Registry {
    private static let lockPath = Config.registryPath.path + ".lock"

    private static func ensureDirs() {
        try? FileManager.default.createDirectory(at: Config.dataDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Config.logsDir, withIntermediateDirectories: true)
    }

    private static func readRaw() -> RegistryFile {
        ensureDirs()
        guard let data = try? Data(contentsOf: Config.registryPath),
              !data.isEmpty,
              let registry = try? JSONDecoder().decode(RegistryFile.self, from: data) else {
            return RegistryFile(worktrees: [:])
        }
        return registry
    }

    private static func writeRaw(_ registry: RegistryFile) throws {
        ensureDirs()
        let data = try JSONEncoder.prettyRegistry.encode(registry)
        let tmpPath = Config.registryPath.path + ".\(ProcessInfo.processInfo.processIdentifier).tmp"
        try data.write(to: URL(fileURLWithPath: tmpPath))
        // POSIX rename is atomic on the same volume -- same technique the
        // Node tool used, so a crash mid-write can never corrupt the file.
        if rename(tmpPath, Config.registryPath.path) != 0 {
            let err = errno
            throw ProcessError(message: "Failed to atomically write registry.json (errno \(err))")
        }
    }

    private static func acquireLock() async {
        let deadline = Date().addingTimeInterval(5)
        while true {
            let fd = open(lockPath, O_CREAT | O_EXCL | O_WRONLY, 0o644)
            if fd >= 0 {
                close(fd)
                return
            }
            if Date() > deadline {
                // Stale/crashed lock -- bust it and try again.
                unlink(lockPath)
                continue
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private static func releaseLock() {
        unlink(lockPath)
    }

    static func loadRegistry() -> RegistryFile {
        readRaw()
    }

    /// The only way to mutate the registry -- locks, reads, lets `body`
    /// mutate in place (or compute a return value), writes, unlocks.
    @discardableResult
    static func withRegistry<T>(_ body: (inout RegistryFile) throws -> T) async throws -> T {
        await acquireLock()
        defer { releaseLock() }
        var registry = readRaw()
        let result = try body(&registry)
        try writeRaw(registry)
        return result
    }
}

private extension JSONEncoder {
    static var prettyRegistry: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
