import Foundation

/// Last-known-good Odoo task info per task id, persisted to disk. The API
/// key for odoo.com expires roughly daily -- without this, every fetch that
/// fails after that (a near-constant state until someone rotates the key)
/// would blank the task badge and, worse, flip a worktree's "Done" category
/// back to "In Progress" just because the status couldn't be re-confirmed.
/// A failed live fetch falls back to whatever was last fetched successfully
/// instead of nil-ing it out.
enum OdooTaskStore {
    private static let path = Config.dataDir.appendingPathComponent("odoo_tasks_cache.json")
    private static let cache = Locked<[String: OdooTaskInfo]>(load())

    private static func load() -> [String: OdooTaskInfo] {
        guard let data = try? Data(contentsOf: path),
              let decoded = try? JSONDecoder().decode([String: OdooTaskInfo].self, from: data) else { return [:] }
        return decoded
    }

    static func get(_ taskId: String) -> OdooTaskInfo? {
        cache.withLock { $0[taskId] }
    }

    static func save(_ taskId: String, _ info: OdooTaskInfo) {
        let snapshot: [String: OdooTaskInfo]? = cache.withLock {
            guard $0[taskId] != info else { return nil }
            $0[taskId] = info
            return $0
        }
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: Config.dataDir, withIntermediateDirectories: true)
        let tmp = path.appendingPathExtension("tmp")
        try? data.write(to: tmp)
        _ = try? FileManager.default.replaceItemAt(path, withItemAt: tmp)
    }
}
