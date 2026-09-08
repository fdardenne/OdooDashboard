import Foundation

/// Ports packages/server/src/odooTask.ts -- looks up a task on odoo.com
/// itself (not a customer database, so no db name needed) via its JSON/2 API.
enum OdooTaskClient {
    /// Odoo's JSON/2 many2one convention: `[id, displayName]`, or `false`
    /// if unset. Never throws -- anything unexpected just resolves to none.
    private enum M2O: Decodable {
        case some(Int, String)
        case none

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(), let isFalse = try? single.decode(Bool.self), isFalse == false {
                self = .none
                return
            }
            guard var arr = try? decoder.unkeyedContainer(),
                  let id = try? arr.decode(Int.self),
                  let name = try? arr.decode(String.self) else {
                self = .none
                return
            }
            self = .some(id, name)
        }

        var name: String {
            if case .some(_, let name) = self { return name }
            return ""
        }
    }

    private struct RawTask: Decodable {
        let id: Int
        let name: String
        let stage_id: M2O?
        let state: String?
        let project_id: M2O?
    }

    static func fetchOdooTask(_ taskId: String) async -> OdooTaskInfo? {
        guard let id = Int(taskId) else { return nil }
        let apiKey = Config.odooApiKey
        guard !apiKey.isEmpty else { return nil }

        var request = URLRequest(url: URL(string: "https://www.odoo.com/json/2/project.task/read")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "ids": [id],
            "fields": ["name", "stage_id", "state", "project_id"],
        ])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let tasks = try? JSONDecoder().decode([RawTask].self, from: data),
              let task = tasks.first else { return nil }

        return OdooTaskInfo(
            id: task.id,
            name: task.name,
            stageName: task.stage_id?.name ?? "",
            state: task.state ?? "",
            url: "https://www.odoo.com/odoo/my-tasks/\(task.id)"
        )
    }
}
