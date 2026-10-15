import Foundation

/// Turns the raw matched-commit list into a short plain-English recap via
/// headless `claude -p` (the same mechanism as the worktree description
/// generator) -- the structured per-commit links still come straight from
/// git/mergebot trailers, so a bad or missing summary never breaks those.
enum DigestSummarizer {
    static func summarize(_ items: [DigestItem]) async -> String? {
        guard !items.isEmpty else { return nil }

        // Same commit can appear once per matched module -- collapse those
        // before handing the list to Claude so it isn't repeated in the prompt.
        // PR/task refs are included so Claude can cite its sources -- the
        // exact "PR #N" / "task-N" text it echoes back gets turned into a
        // real clickable link afterward (see DigestView.linkedSummary),
        // matched deterministically against these same numbers, never
        // trusting a URL Claude might invent itself.
        var seen = Set<String>()
        let lines = items.compactMap { item -> String? in
            guard seen.insert(item.sha).inserted else { return nil }
            var refs: [String] = []
            if let pr = item.prNumber { refs.append("PR #\(pr)") }
            if let task = item.taskId { refs.append("task-\(task)") }
            let refsSuffix = refs.isEmpty ? "" : " (\(refs.joined(separator: ", ")))"
            return "- [\(item.tag)] \(item.module): \(item.subject)\(refsSuffix)"
        }.joined(separator: "\n")

        let prompt = """
        You're writing a short internal digest for an Odoo developer catching up after time away, about modules they specifically watch. Below are commit subjects already filtered to meaningful [REF]/[IMP] changes (real refactors/improvements, not fixes or translations) pushed to master, each with its PR number and/or task id if known.

        Summarize what actually changed, in plain English, as 3-6 short bullet points (use "-"). Group related commits together where it makes sense. End each bullet with the exact "(PR #N)" and/or "(task-N)" reference(s) it's based on, copied verbatim from the input -- this is how the reader traces a claim back to its source, so never invent, alter, or omit a reference that's present in the input for something you mention. The parenthetical must contain ONLY "PR #N" and/or "task-N" text copied from the input, nothing else -- if a commit has no PR/task number given in the input, end that bullet with no parenthetical at all (never a placeholder, and never the [REF]/[IMP] tag). Don't mention commit hashes. Be concise and skimmable -- this is a quick catch-up, not a changelog.

        Output ONLY the bullet list itself -- no preamble, no closing remarks, no showing your work or revising an earlier draft. Get it right in one pass.

        Commits:
        \(lines)
        """

        return try? await ClaudeClient.askClaudeText(prompt, timeout: 60)
    }
}
