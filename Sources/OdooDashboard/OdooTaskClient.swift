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

    /// Text/Html fields come back as `false` when unset, same as many2one --
    /// decode leniently rather than failing the whole task on an empty one.
    private enum FlexibleString: Decodable {
        case some(String)
        case none

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) {
                self = .some(s)
            } else {
                self = .none
            }
        }

        var value: String {
            if case .some(let s) = self { return s }
            return ""
        }
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

    private struct RawSearchTask: Decodable {
        let id: Int
        let name: String
        let description: FlexibleString?
        let stage_id: M2O?
    }

    /// Fetches every task in a project in one call (search_read), for the
    /// caller to match against a query itself (see TaskSearchMatcher) --
    /// excludes closed tasks by default since a long-running project can
    /// have many thousands of them. NOTE: the exclusion domain
    /// (state not in [1_done, 1_canceled]) matches modern Odoo's project.task
    /// "state" field as of this writing; unverified against a live account
    /// at the time this was written (the configured API key had expired) --
    /// worth double-checking against a real project once a valid key is set.
    static func searchTasks(projectId: Int, includeClosed: Bool) async throws -> [OdooTaskSummary] {
        let apiKey = Config.odooApiKey
        guard !apiKey.isEmpty else {
            throw ProcessError(message: "No Odoo API token configured (Settings → Odoo.com).")
        }

        var domain: [[Any]] = [["project_id", "=", projectId]]
        if !includeClosed {
            domain.append(["state", "not in", ["1_done", "1_canceled"]])
        }

        var request = URLRequest(url: URL(string: "https://www.odoo.com/json/2/project.task/search_read")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "domain": domain,
            "fields": ["name", "description", "stage_id"],
            "limit": 2000,
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ProcessError(message: "Could not reach odoo.com: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProcessError(message: "Unexpected response from odoo.com")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProcessError(message: "odoo.com returned \(http.statusCode): \(body.prefix(300))")
        }
        guard let raw = try? JSONDecoder().decode([RawSearchTask].self, from: data) else {
            throw ProcessError(message: "Could not parse odoo.com's response")
        }

        return raw.map { task in
            OdooTaskSummary(
                id: task.id,
                name: task.name,
                description: stripHtml(task.description?.value ?? ""),
                stageName: task.stage_id?.name ?? "",
                url: "https://www.odoo.com/odoo/my-tasks/\(task.id)"
            )
        }
    }

    private static func stripHtml(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let decoded = noTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return decoded.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
