import Foundation

/// One-line, human-readable status updates emitted mid-action (create,
/// rebase, pull) so the UI can show what's happening instead of a bare spinner.
typealias ProgressReporter = @Sendable (String) -> Void

struct CreateOptions {
    var taskId: String? = nil
    var fromBranch: String? = nil
    var branch: String? = nil
    var nameOverride: String? = nil
    var interpreterOverride: String? = nil
}

struct RepoCreateResult {
    var path: String
    var ok: Bool
    var error: String? = nil
    var detached: Bool? = nil
}

struct CreateResult {
    var entry: RegistryEntry
    var repoResults: [String: RepoCreateResult]
}

struct DetailUpdates {
    var taskId: String? = nil
    var description: String? = nil
    var installModules: String? = nil
    var updateModules: String? = nil
}

/// Ports packages/core/src/worktree.ts -- the orchestration layer wiring
/// GitClient, Registry, PortAllocator, InterpreterResolver, ZedDebugConfigWriter,
/// and ProcessManager together. Function-for-function port of the TS file.
enum WorktreeManager {
    private static func dbNameFor(_ branch: String) -> String {
        let sanitized = branch.unicodeScalars.map { scalar -> Character in
            (CharacterSet.alphanumerics.contains(scalar) || scalar == "_") ? Character(scalar) : "_"
        }
        return "wt_" + String(sanitized).lowercased()
    }

    private static func dropDatabase(_ db: String) async throws {
        _ = try await ProcessRunner.run(BinaryLocator.dropdb, ["--if-exists", db])
    }

    /// origin/18.0 -> "18.0", origin/saas-18.2-foo -> "saas-18.2",
    /// origin/master-123-dafl -> "master"
    private static func inferVersionPrefix(_ branch: String) -> String {
        if branch.hasPrefix("saas-") {
            let parts = branch.split(separator: "-")
            if parts.count > 1 { return "saas-\(parts[1])" }
            return branch
        }
        return String(branch.split(separator: "-").first ?? Substring(branch))
    }

    /// Fetches `branch` from whichever of `remotes` has it first (origin,
    /// then the dev fork) and returns a startPoint ref for `git worktree
    /// add`, or nil.
    private static func resolveStartPoint(_ baseRepoPath: URL, branch: String, remotes: [String]) async -> String? {
        for remote in remotes {
            guard await GitClient.remoteExists(baseRepoPath, remote: remote) else { continue }
            guard await GitClient.remoteBranchExists(baseRepoPath, remote: remote, ref: branch) else { continue }
            try? await GitClient.fetch(baseRepoPath, remote: remote, ref: branch)
            return "\(remote)/\(branch)"
        }
        return nil
    }

    static func createWorktree(_ opts: CreateOptions, progress: ProgressReporter? = nil) async throws -> CreateResult {
        let trimmedBranch = opts.branch?.trimmingCharacters(in: .whitespaces)
        let explicitBranch = (trimmedBranch?.isEmpty == false) ? trimmedBranch : nil
        guard explicitBranch != nil || opts.taskId != nil || opts.nameOverride != nil else {
            throw ProcessError(message: "Provide either a taskId (to create a new branch) or an explicit branch to check out.")
        }

        let fromBranch = opts.fromBranch ?? (explicitBranch.map { inferVersionPrefix($0) } ?? "master")
        let branch = explicitBranch ?? opts.nameOverride ?? "\(fromBranch)-\(opts.taskId ?? "")-\(Config.trigram)"
        // In task mode we branch off origin/fromBranch; in explicit-branch
        // mode we look for the branch itself on origin, then the dev fork.
        let remoteCandidates = explicitBranch != nil ? ["origin", "dev"] : ["origin"]
        let remoteRefToFind = explicitBranch ?? fromBranch

        progress?("Checking \"\(branch)\" is free…")
        let registry = Registry.loadRegistry()
        if registry.worktrees[branch] != nil {
            throw ProcessError(message: "Worktree \"\(branch)\" already exists. Use a different name or delete it first.")
        }

        let destRoot = Config.worktreesRoot.appendingPathComponent(branch)
        if FileManager.default.fileExists(atPath: destRoot.path) {
            throw ProcessError(message: "Directory already exists: \(destRoot.path)")
        }

        // Each repo's worktree is fully independent -- create them all
        // concurrently instead of one at a time.
        let repos = Config.worktreeRepos
        progress?("Creating worktrees in \(repos.count) repo\(repos.count == 1 ? "" : "s")…")
        var repoResults: [String: RepoCreateResult] = [:]
        var doneCount = 0
        await withTaskGroup(of: (String, RepoCreateResult).self) { group in
            for repo in repos {
                group.addTask {
                    let baseRepoPath = Config.odooWorkspace.appendingPathComponent(repo)
                    let destPath = destRoot.appendingPathComponent(repo)
                    guard FileManager.default.fileExists(atPath: baseRepoPath.path) else {
                        return (repo, RepoCreateResult(path: destPath.path, ok: false, error: "repo not found in odoo_workspace"))
                    }
                    do {
                        let detached: Bool
                        if await GitClient.localBranchExists(baseRepoPath, branch: branch) {
                            detached = try await GitClient.worktreeAdd(baseRepoPath, destPath: destPath, branch: branch, startPoint: "").detached
                        } else if let startPoint = await resolveStartPoint(baseRepoPath, branch: remoteRefToFind, remotes: remoteCandidates) {
                            detached = try await GitClient.worktreeAdd(baseRepoPath, destPath: destPath, branch: branch, startPoint: startPoint).detached
                        } else {
                            // This repo doesn't have `branch` at all (e.g. importing a
                            // branch that only touched enterprise, not odoo) -- create
                            // it fresh off fromBranch instead of failing the whole thing.
                            guard let fallbackStart = await resolveStartPoint(baseRepoPath, branch: fromBranch, remotes: ["origin"]) else {
                                throw ProcessError(message: "\"\(remoteRefToFind)\" not found locally or on remote(s) [\(remoteCandidates.joined(separator: ", "))] in \(repo), and base branch \"\(fromBranch)\" not found on origin either")
                            }
                            detached = try await GitClient.worktreeAdd(baseRepoPath, destPath: destPath, branch: branch, startPoint: fallbackStart).detached
                        }
                        return (repo, RepoCreateResult(path: destPath.path, ok: true, detached: detached))
                    } catch {
                        return (repo, RepoCreateResult(path: destPath.path, ok: false, error: error.localizedDescription))
                    }
                }
            }
            for await (repo, result) in group {
                repoResults[repo] = result
                doneCount += 1
                progress?("Created \(doneCount)/\(repos.count) repo worktrees…")
            }
        }

        let missingRequired = Config.requiredRepos.filter { !(repoResults[$0]?.ok ?? false) }
        if !missingRequired.isEmpty {
            progress?("Rolling back — \(missingRequired.joined(separator: ", ")) failed…")
            // Roll back any worktrees that DID get created before failing.
            await withTaskGroup(of: Void.self) { group in
                for repo in Config.worktreeRepos {
                    guard let result = repoResults[repo], result.ok else { continue }
                    group.addTask {
                        try? await GitClient.worktreeRemove(Config.odooWorkspace.appendingPathComponent(repo), worktreePath: URL(fileURLWithPath: result.path), force: true)
                    }
                }
            }
            try? FileManager.default.removeItem(at: destRoot)
            let details = missingRequired.map { "\($0): \(repoResults[$0]?.error ?? "unknown error")" }.joined(separator: "; ")
            throw ProcessError(message: "Failed to create required repo worktree(s) [\(missingRequired.joined(separator: ", "))]: \(details)")
        }

        progress?("Allocating port & resolving interpreter…")
        let usedPorts = Set(registry.worktrees.values.map(\.port))
        let port = try PortAllocator.allocatePort(usedPorts: usedPorts)
        let db = dbNameFor(branch)
        let interpreter = try opts.interpreterOverride ?? InterpreterResolver.resolveInterpreter(fromBranch)
        let logFile = Config.logsDir.appendingPathComponent("\(branch).log").path
        try? FileManager.default.createDirectory(at: Config.logsDir, withIntermediateDirectories: true)

        var reposMap: [String: String] = [:]
        for (repo, result) in repoResults where result.ok {
            reposMap[repo] = result.path
        }

        let entry = RegistryEntry(
            name: branch, taskId: opts.taskId ?? "", fromBranch: fromBranch,
            createdAt: ISO8601DateFormatter().string(from: Date()), repos: reposMap,
            port: port, db: db, interpreter: interpreter, pid: nil, logFile: logFile,
            installModules: Config.defaultInstallModules, updateModules: Config.defaultUpdateModules, description: ""
        )

        progress?("Writing Zed debug config…")
        ZedDebugConfigWriter.write(worktreeRoot: destRoot, entry: entry)

        progress?("Copying Claude settings and skills…")
        ClaudeConfigCopier.copy(into: destRoot)

        progress?("Saving to registry…")

        try await Registry.withRegistry { reg in
            reg.worktrees[branch] = entry
        }

        return CreateResult(entry: entry, repoResults: repoResults)
    }

    static func listWorktrees() -> [RegistryEntry] {
        Registry.loadRegistry().worktrees.values.sorted { $0.name < $1.name }
    }

    static func getWorktree(_ name: String) throws -> RegistryEntry {
        guard let entry = Registry.loadRegistry().worktrees[name] else {
            throw ProcessError(message: "No such worktree: \(name)")
        }
        return entry
    }

    static func deleteWorktree(_ name: String, dropDb: Bool) async throws {
        let entry = try getWorktree(name)
        if ProcessManager.isAlive(entry.pid) {
            ProcessManager.stopProcess(entry.pid!)
        }
        await withTaskGroup(of: Void.self) { group in
            for (repo, worktreePath) in entry.repos {
                group.addTask {
                    let baseRepoPath = Config.odooWorkspace.appendingPathComponent(repo)
                    try? await GitClient.worktreeRemove(baseRepoPath, worktreePath: URL(fileURLWithPath: worktreePath), force: true)
                }
            }
        }
        let destRoot = Config.worktreesRoot.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destRoot)

        if dropDb {
            try? await dropDatabase(entry.db)
        }

        try await Registry.withRegistry { reg in
            reg.worktrees.removeValue(forKey: name)
        }
    }

    /// Drops a worktree's database without touching the worktree itself.
    /// Refuses while running since odoo-bin holds connections to it.
    static func dropWorktreeDb(_ name: String) async throws {
        let entry = try getWorktree(name)
        if ProcessManager.isAlive(entry.pid) {
            throw ProcessError(message: "Stop \"\(name)\" before dropping its database (odoo-bin still holds connections to \(entry.db)).")
        }
        try await dropDatabase(entry.db)
    }

    static func updateWorktreeDetails(_ name: String, _ updates: DetailUpdates) async throws -> RegistryEntry {
        try await Registry.withRegistry { reg in
            guard var entry = reg.worktrees[name] else {
                throw ProcessError(message: "No such worktree: \(name)")
            }
            if let v = updates.taskId { entry.taskId = v }
            if let v = updates.description { entry.description = v }
            if let v = updates.installModules { entry.installModules = v }
            if let v = updates.updateModules { entry.updateModules = v }
            ZedDebugConfigWriter.write(worktreeRoot: Config.worktreesRoot.appendingPathComponent(name), entry: entry)
            reg.worktrees[name] = entry
            return entry
        }
    }

    /// Fetches the base branch and rebases each repo's worktree onto it,
    /// concurrently. Never force-pushes. On conflict, aborts that repo's
    /// rebase and reports it -- the caller resolves manually.
    static func rebaseWorktree(_ name: String, progress: ProgressReporter? = nil) async throws -> [RebaseReportItem] {
        let entry = try getWorktree(name)
        let repos = Config.worktreeRepos.filter { entry.repos[$0] != nil }
        progress?("Fetching origin/\(entry.fromBranch) in \(repos.count) repo\(repos.count == 1 ? "" : "s")…")
        var reportsByRepo: [String: RebaseReportItem] = [:]
        var doneCount = 0
        await withTaskGroup(of: RebaseReportItem.self) { group in
            for repo in repos {
                guard let worktreePath = entry.repos[repo] else { continue }
                group.addTask {
                    let baseRepoPath = Config.odooWorkspace.appendingPathComponent(repo)
                    let wtPath = URL(fileURLWithPath: worktreePath)
                    do {
                        try await GitClient.fetch(baseRepoPath, remote: "origin", ref: entry.fromBranch)
                        try await GitClient.rebase(wtPath, onto: "origin/\(entry.fromBranch)")
                        return RebaseReportItem(repo: repo, ok: true, conflict: nil, message: nil)
                    } catch {
                        let conflict = await GitClient.isRebaseInProgress(wtPath)
                        if conflict { await GitClient.rebaseAbort(wtPath) }
                        return RebaseReportItem(repo: repo, ok: false, conflict: conflict, message: error.localizedDescription)
                    }
                }
            }
            for await report in group {
                reportsByRepo[report.repo] = report
                doneCount += 1
                progress?("Rebased \(doneCount)/\(repos.count) repos…")
            }
        }
        return Config.worktreeRepos.compactMap { reportsByRepo[$0] }
    }

    /// Standard/trunk branches (master, 18.0, ...) aren't rebased -- there's
    /// no divergent base to replay onto. Instead fetch + fast-forward merge
    /// each repo's worktree to its own remote branch, concurrently.
    static func pullWorktree(_ name: String, progress: ProgressReporter? = nil) async throws -> [RebaseReportItem] {
        let entry = try getWorktree(name)
        let repos = Config.worktreeRepos.filter { entry.repos[$0] != nil }
        progress?("Fetching origin/\(entry.fromBranch) in \(repos.count) repo\(repos.count == 1 ? "" : "s")…")
        var reportsByRepo: [String: RebaseReportItem] = [:]
        var doneCount = 0
        await withTaskGroup(of: RebaseReportItem.self) { group in
            for repo in repos {
                guard let worktreePath = entry.repos[repo] else { continue }
                group.addTask {
                    let baseRepoPath = Config.odooWorkspace.appendingPathComponent(repo)
                    let wtPath = URL(fileURLWithPath: worktreePath)
                    do {
                        try await GitClient.fetch(baseRepoPath, remote: "origin", ref: entry.fromBranch)
                        try await GitClient.fastForwardMerge(wtPath, ref: "origin/\(entry.fromBranch)")
                        return RebaseReportItem(repo: repo, ok: true, conflict: nil, message: nil)
                    } catch {
                        return RebaseReportItem(repo: repo, ok: false, conflict: false, message: error.localizedDescription)
                    }
                }
            }
            for await report in group {
                reportsByRepo[report.repo] = report
                doneCount += 1
                progress?("Pulled \(doneCount)/\(repos.count) repos…")
            }
        }
        return Config.worktreeRepos.compactMap { reportsByRepo[$0] }
    }

    static func startWorktree(_ name: String) async throws -> Int32 {
        let entry = try getWorktree(name)
        if ProcessManager.isAlive(entry.pid) {
            throw ProcessError(message: "\(name) is already running (pid \(entry.pid!))")
        }
        let worktreeRoot = Config.worktreesRoot.appendingPathComponent(name)
        let pid = try ProcessManager.startProcess(worktreeRoot: worktreeRoot, entry: entry)
        try await Registry.withRegistry { reg in
            reg.worktrees[name]?.pid = pid
        }
        return pid
    }

    static func stopWorktree(_ name: String) async throws {
        let entry = try getWorktree(name)
        if let pid = entry.pid { ProcessManager.stopProcess(pid) }
        try await Registry.withRegistry { reg in
            reg.worktrees[name]?.pid = nil
        }
    }

    static func restartWorktree(_ name: String) async throws -> Int32 {
        try await stopWorktree(name)
        try await Task.sleep(nanoseconds: 500_000_000)
        return try await startWorktree(name)
    }
}
