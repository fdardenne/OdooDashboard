import Foundation

/// Ports packages/server/src/app.ts's enrichEntry() -- combines a registry
/// entry with live PR/runbot/task status through the three TTL caches,
/// producing the WorktreeEntry the UI already consumes.
enum WorktreeEnricher {
    private static let prCache = TtlCache<String, [PrInfo?]>(ttl: 60)
    private static let runbotCache = TtlCache<String, RunbotStatus?>(ttl: 60)
    private static let odooTaskCache = TtlCache<String, OdooTaskInfo?>(ttl: 600)

    private static func fetchPr(for entry: RegistryEntry) async -> [PrInfo?] {
        // No PR makes sense for a trunk branch (master, 18.0, saas-19.1, ...).
        guard !StatusLogic.isOfficialVersionBranch(entry.name) else { return [] }
        return await prCache.getOrFetch(entry.name) { await PrStatusClient.getPrStatus(branch: entry.name) }
    }

    static func enrich(_ entry: RegistryEntry, fresh: Bool) async -> WorktreeEntry {
        var pid = entry.pid
        if let p = pid, !ProcessManager.isAlive(p) { pid = nil }

        if fresh {
            await prCache.invalidate(entry.name)
            await runbotCache.invalidate(entry.name)
            if !entry.taskId.isEmpty {
                await odooTaskCache.invalidate(entry.taskId)
            }
        }

        async let prResult: [PrInfo?] = fetchPr(for: entry)
        async let runbotResult: RunbotStatus? = runbotCache.getOrFetch(entry.name) { await RunbotClient.fetchRunbotStatus(branch: entry.name) }

        let pr = await prResult
        let runbot = await runbotResult

        // Once the PR is merged the task is effectively done -- stop
        // polling odoo.com for it.
        let isMerged = pr.contains { $0?.state == "MERGED" }
        var odooTask: OdooTaskInfo?
        if !entry.taskId.isEmpty, !isMerged {
            odooTask = await odooTaskCache.getOrFetch(entry.taskId) { await OdooTaskClient.fetchOdooTask(entry.taskId) }
        }

        return WorktreeEntry(
            name: entry.name,
            taskId: entry.taskId,
            fromBranch: entry.fromBranch,
            port: entry.port,
            db: entry.db,
            description: entry.description,
            installModules: entry.installModules,
            updateModules: entry.updateModules,
            running: ProcessManager.isAlive(pid),
            pr: pr,
            runbot: runbot,
            odooTask: odooTask,
            repos: entry.repos
        )
    }
}
