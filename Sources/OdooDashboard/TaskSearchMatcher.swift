import Foundation

/// Matches a free-text query (and optionally a pasted screenshot) against
/// the full task list fetched by OdooTaskClient.searchTasks, via headless
/// `claude -p` -- same mechanism as the digest summarizer and worktree
/// description generator. Claude reads title + description (not just
/// keywords) and returns which tasks actually match, ranked by relevance;
/// we never trust it to invent a task, only to pick ids out of the list we
/// hand it.
enum TaskSearchMatcher {
    /// Kept short per task to bound the prompt -- a project's full open-task
    /// list can still be sizeable even with closed ones excluded.
    private static let descriptionSnippetLength = 220

    static func match(query: String, in tasks: [OdooTaskSummary], screenshotPath: String? = nil) async throws -> [OdooTaskSummary] {
        guard !tasks.isEmpty else { return [] }

        let byId = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let lines = tasks.map { task -> String in
            let snippet = task.description.count > descriptionSnippetLength
                ? String(task.description.prefix(descriptionSnippetLength)) + "…"
                : task.description
            return snippet.isEmpty ? "\(task.id): \(task.name)" : "\(task.id): \(task.name) -- \(snippet)"
        }.joined(separator: "\n")

        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        let queryLine = trimmedQuery.isEmpty ? "(none given -- match using only the attached screenshot below)" : "\"\(trimmedQuery)\""
        let screenshotLine = screenshotPath.map { path in
            "\n\nThe user also attached a screenshot. Before matching, read/view it with your Read tool at this path, and use what it shows (error messages, UI, whatever's pictured) together with the text query to judge relevance: \(path)"
        } ?? ""

        let prompt = """
        Below is a list of Odoo project tasks (id: title -- description snippet). Find the tasks that genuinely match this search query, judging by meaning (title and description), not just literal keyword overlap:

        Query: \(queryLine)\(screenshotLine)

        Tasks:
        \(lines)

        Output ONLY a JSON array of the matching task ids, ordered from most to least relevant, e.g. [123456, 654321]. If nothing matches, output []. No other text.
        """

        let allowedTools = screenshotPath != nil ? ["Read"] : nil
        guard let raw = try? await ClaudeClient.askClaudeText(prompt, timeout: 150, allowedTools: allowedTools) else {
            throw ProcessError(message: "Claude didn't respond -- check that the `claude` CLI is installed and working.")
        }

        guard let ids = Self.extractIds(from: raw) else {
            throw ProcessError(message: "Couldn't parse Claude's response as a list of task ids.")
        }

        return ids.compactMap { byId[$0] }
    }

    /// Claude is asked for bare JSON but tolerated leniently -- pull out the
    /// first `[...]` block rather than requiring the whole response to be
    /// clean JSON with nothing else around it.
    private static func extractIds(from text: String) -> [Int]? {
        guard let open = text.firstIndex(of: "["), let close = text.lastIndex(of: "]"), open < close else { return nil }
        let jsonSlice = text[open...close]
        guard let data = jsonSlice.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([Int].self, from: data)
    }
}
