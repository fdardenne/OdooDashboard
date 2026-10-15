import Foundation

@MainActor
final class WorktreeStore: ObservableObject {
    @Published var worktrees: [WorktreeEntry] = []
    @Published var serverReachable = true
    @Published var busy: Set<String> = [] // "<name>:<action>" currently in flight
    /// Versions with a configured Python interpreter (Settings -> Python
    /// Interpreters) -- offered as quick-pick suggestions for "from branch"
    /// in the create sheet, since those are the versions guaranteed to
    /// resolve an interpreter. Not a restriction: any branch name works.
    @Published var configuredVersions: [String] = []
    /// One-line "what's happening right now" text for a long-running action,
    /// keyed the same way as `busy` ("<name>:<action>"). Cleared once the
    /// action finishes (success or failure).
    @Published var actionStatus: [String: String] = [:]
    /// Same idea for the create-worktree sheet, which has no worktree name yet.
    @Published var createProgress: String?

    private var timer: Timer?

    func start() {
        Task { await self.refresh() }
        loadConfiguredVersions()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh(fresh: Bool = false) async {
        let entries = WorktreeManager.listWorktrees()
        let enriched = await withTaskGroup(of: WorktreeEntry.self) { group in
            for entry in entries {
                group.addTask { await WorktreeEnricher.enrich(entry, fresh: fresh) }
            }
            var results: [WorktreeEntry] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        self.worktrees = enriched.sorted { $0.name < $1.name }
        self.serverReachable = true
        loadConfiguredVersions() // cheap; keeps quick-pick suggestions in sync with Settings edits
    }

    private func loadConfiguredVersions() {
        configuredVersions = Config.interpreters.map(\.version).sorted()
    }

    // MARK: - Generic actions

    /// Fire-and-refresh: for simple actions with no meaningful response body.
    func run(_ name: String, action: String, body: [String: Any]? = nil) {
        let key = "\(name):\(action)"
        busy.insert(key)
        Task {
            switch action {
            case "open":
                _ = try? await ProcessRunner.run(BinaryLocator.zed, [Config.worktreesRoot.appendingPathComponent(name).path])
            case "open-cmux":
                _ = try? await ProcessRunner.run(BinaryLocator.cmux, [Config.worktreesRoot.appendingPathComponent(name).path])
            case "start":
                _ = try? await WorktreeManager.startWorktree(name)
            case "stop":
                try? await WorktreeManager.stopWorktree(name)
            case "restart":
                _ = try? await WorktreeManager.restartWorktree(name)
            case "dropdb":
                try? await WorktreeManager.dropWorktreeDb(name)
            case "ask-claude":
                if let entry = try? WorktreeManager.getWorktree(name) {
                    ClaudeClient.openClaudeSession(
                        cwd: Config.worktreesRoot.appendingPathComponent(name).path,
                        prompt: body?["prompt"] as? String,
                        title: entry.name
                    )
                }
            default:
                break
            }
            await refresh()
            busy.remove(key)
        }
    }

    func isBusy(_ name: String, _ action: String) -> Bool {
        busy.contains("\(name):\(action)")
    }

    // MARK: - Actions with typed responses

    func rebase(_ name: String) async -> [RebaseReportItem] {
        let key = "\(name):rebase"
        busy.insert(key)
        defer { busy.remove(key); actionStatus[key] = nil }
        let reports = (try? await WorktreeManager.rebaseWorktree(name) { [weak self] text in
            Task { @MainActor in self?.actionStatus[key] = text }
        }) ?? []
        await refresh()
        return reports
    }

    func pull(_ name: String) async -> [RebaseReportItem] {
        let key = "\(name):pull"
        busy.insert(key)
        defer { busy.remove(key); actionStatus[key] = nil }
        let reports = (try? await WorktreeManager.pullWorktree(name) { [weak self] text in
            Task { @MainActor in self?.actionStatus[key] = text }
        }) ?? []
        await refresh()
        return reports
    }

    func updateDetails(_ name: String, taskId: String? = nil, description: String? = nil, installModules: String? = nil, updateModules: String? = nil) async {
        let updates = DetailUpdates(taskId: taskId, description: description, installModules: installModules, updateModules: updateModules)
        _ = try? await WorktreeManager.updateWorktreeDetails(name, updates)
        await refresh()
    }

    func generateDescription(_ name: String) async {
        let key = "\(name):gen-desc"
        busy.insert(key)
        defer { busy.remove(key) }
        guard let entry = try? WorktreeManager.getWorktree(name) else { return }

        var seen = Set<String>()
        var subjects: [String] = []
        for repo in ["odoo", "enterprise"] {
            guard let path = entry.repos[repo] else { continue }
            let repoSubjects = await GitClient.logSubjects(URL(fileURLWithPath: path), onto: "origin/\(entry.fromBranch)")
            for subject in repoSubjects where seen.insert(subject).inserted {
                subjects.append(subject)
            }
        }

        let odooTask = entry.taskId.isEmpty ? nil : await OdooTaskClient.fetchOdooTask(entry.taskId)
        guard !subjects.isEmpty || odooTask != nil else { return }

        var contextParts: [String] = []
        if let odooTask { contextParts.append("Odoo task title: \(odooTask.name)") }
        if !subjects.isEmpty { contextParts.append("Git commit subjects:\n\(subjects.joined(separator: "\n"))") }

        let prompt = """
        Summarize this into ONE short label (under 12 words, no trailing period, plain text, no quotes) suitable as a one-line UI description for this branch. Prefer the task title's intent over restating commit noise, but use the commits to sharpen it if useful:

        \(contextParts.joined(separator: "\n\n"))
        """

        guard let description = try? await ClaudeClient.askClaudeText(prompt) else { return }
        _ = try? await WorktreeManager.updateWorktreeDetails(name, DetailUpdates(description: description))
        await refresh()
    }

    func askClaude(_ name: String, prompt: String? = nil) {
        var body: [String: Any] = [:]
        if let prompt { body["prompt"] = prompt }
        run(name, action: "ask-claude", body: body)
    }

    func delete(_ name: String, dropDb: Bool) async {
        let key = "\(name):delete"
        busy.insert(key)
        defer { busy.remove(key) }
        try? await WorktreeManager.deleteWorktree(name, dropDb: dropDb)
        await refresh()
    }

    func fetchLogs(_ name: String) async -> String {
        guard let entry = try? WorktreeManager.getWorktree(name),
              let data = try? Data(contentsOf: URL(fileURLWithPath: entry.logFile)),
              let content = String(data: data, encoding: .utf8) else { return "" }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(200).joined(separator: "\n")
    }

    struct CreateError: Error { let message: String }

    /// Reads the draft straight off `keyboard` (not local view @State) and
    /// writes progress/busy/error back onto it too, so the in-flight
    /// creation and its form survive the panel being closed and reopened
    /// mid-submit -- see the comment on KeyboardController's create* fields.
    func submitCreate(_ keyboard: KeyboardController) {
        guard !keyboard.createBusy else { return }
        keyboard.createBusy = true
        keyboard.createError = nil
        Task {
            do {
                switch keyboard.createMode {
                case .branch:
                    let branch = keyboard.createBranchName.trimmingCharacters(in: .whitespaces)
                    let taskId = keyboard.createTaskId.trimmingCharacters(in: .whitespaces)
                    let fromBranch = keyboard.createFromBranch.trimmingCharacters(in: .whitespaces)
                    try await create(taskId: taskId.isEmpty ? nil : taskId, fromBranch: fromBranch.isEmpty ? nil : fromBranch, branch: branch)
                case .pr:
                    try await create(prNumber: Int(keyboard.createPrNumber.trimmingCharacters(in: .whitespaces)), prRepo: keyboard.createPrRepo)
                }
                keyboard.resetCreateDraft()
                keyboard.showCreate = false
            } catch let e as CreateError {
                keyboard.createError = e.message
            } catch {
                keyboard.createError = error.localizedDescription
            }
            keyboard.createBusy = false
        }
    }

    func create(taskId: String? = nil, fromBranch: String? = nil, branch: String? = nil, prNumber: Int? = nil, prRepo: String? = nil) async throws {
        var opts = CreateOptions(taskId: taskId, fromBranch: fromBranch, branch: branch)
        defer { createProgress = nil }
        if let prNumber, let prRepo {
            createProgress = "Resolving PR #\(prNumber) head branch…"
            do {
                opts.branch = try await GitHubPrClient.resolvePrHeadBranch(repo: prRepo, number: prNumber)
            } catch {
                throw CreateError(message: "Could not resolve PR #\(prNumber) in \(prRepo): \(error.localizedDescription)")
            }
        }
        guard opts.branch != nil || opts.taskId != nil else {
            throw CreateError(message: "Provide either a task id or a PR number/branch.")
        }
        do {
            _ = try await WorktreeManager.createWorktree(opts) { [weak self] text in
                Task { @MainActor in self?.createProgress = text }
            }
        } catch {
            throw CreateError(message: error.localizedDescription)
        }
        await refresh(fresh: true)
    }
}
