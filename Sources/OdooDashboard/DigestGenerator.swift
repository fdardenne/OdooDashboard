import Foundation

/// Scans odoo + enterprise's origin/master history for "important" commits
/// (tagged [REF] or [IMP] -- the usual convention for a real change, as
/// opposed to a [FIX]/[I18N]/[TEST] tweak) touching any of the modules
/// configured in Settings -> Digest.
enum DigestGenerator {
    private static let importantTags: Set<String> = ["REF", "IMP"]
    private static let repos = ["odoo", "enterprise"]

    private static let tagRegex = try! NSRegularExpression(pattern: #"^\[([A-Za-z0-9_]+)\]"#)
    /// Odoo's mergebot appends a "task-XXXXXXX" line or "Task-id: XXXXXXX"
    /// trailer to the full commit message (not the subject) when a PR is
    /// linked to a task.
    private static let taskRegex = try! NSRegularExpression(pattern: #"task-id\s*:\s*(\d+)|task-(\d+)"#, options: .caseInsensitive)
    /// Mergebot also appends "closes odoo/<repo>#<number>" (or "Part-of:")
    /// once it lands the PR -- landed commits get a new sha via rebase, so
    /// this is the only reliable way back to the PR (GitHub's commit->PR
    /// association API doesn't find it, since the sha it merged no longer
    /// matches the one now on master).
    private static let prRegex = try! NSRegularExpression(pattern: #"(?:closes|part-of)\s+odoo/([a-z-]+)#(\d+)"#, options: .caseInsensitive)

    static func generate(modules: [String], since: Date, until: Date) async -> [DigestItem] {
        guard !modules.isEmpty else { return [] }
        var items: [DigestItem] = []
        for repo in repos {
            items.append(contentsOf: await scanRepo(repo, modules: modules, since: since, until: until))
        }
        return items.sorted { $0.date > $1.date }
    }

    private struct ParsedCommit {
        let sha: String
        let date: Date
        let subject: String
        let files: [String]
    }

    private static func scanRepo(_ repo: String, modules: [String], since: Date, until: Date) async -> [DigestItem] {
        let repoPath = Config.odooWorkspace.appendingPathComponent(repo)
        guard FileManager.default.fileExists(atPath: repoPath.path) else { return [] }
        try? await GitClient.fetch(repoPath, remote: "origin", ref: "master")

        let iso = ISO8601DateFormatter()
        let sep = "\u{1f}"
        // Subject-only + name-only here, deliberately -- the full commit
        // body (needed for task/PR trailers) can itself contain blank
        // lines, which would break the blank-line-separated block parsing
        // this relies on. Full bodies are fetched separately below, only
        // for commits that actually match.
        guard let raw = try? await ProcessRunner.run(BinaryLocator.git, [
            "log", "origin/master",
            "--since=\(iso.string(from: since))",
            "--until=\(iso.string(from: until))",
            "--no-merges",
            "--pretty=format:%H\(sep)%cI\(sep)%s",
            "--name-only",
        ], cwd: repoPath) else { return [] }

        let commits = parseLog(raw, sep: sep)

        var matched: [(commit: ParsedCommit, module: String, tag: String)] = []
        for commit in commits {
            guard let tag = extractTag(commit.subject), importantTags.contains(tag.uppercased()) else { continue }
            for module in modules where commit.files.contains(where: { pathTouchesModule($0, module: module) }) {
                matched.append((commit, module, tag.uppercased()))
            }
        }
        guard !matched.isEmpty else { return [] }

        // Several watched modules can match the same commit -- fetch each
        // unique sha's full body only once.
        let uniqueShas = Set(matched.map(\.commit.sha))
        var bodyBySha: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for sha in uniqueShas {
                group.addTask {
                    let body = try? await ProcessRunner.run(BinaryLocator.git, ["log", "-1", "--format=%B", sha], cwd: repoPath)
                    return (sha, body)
                }
            }
            for await (sha, body) in group {
                if let body { bodyBySha[sha] = body }
            }
        }

        return matched.map { entry in
            let body = bodyBySha[entry.commit.sha] ?? ""
            let taskId = extractTaskId(body)
            let pr = extractPr(body)
            return DigestItem(
                repo: repo,
                sha: entry.commit.sha,
                date: entry.commit.date,
                tag: entry.tag,
                module: entry.module,
                subject: entry.commit.subject,
                commitUrl: "https://github.com/\(Config.githubUpstreamOwner)/\(repo)/commit/\(entry.commit.sha)",
                taskId: taskId,
                taskUrl: taskId.map { "https://www.odoo.com/odoo/my-tasks/\($0)" },
                prNumber: pr?.number,
                prUrl: pr.map { "https://github.com/\(Config.githubUpstreamOwner)/\($0.repo)/pull/\($0.number)" }
            )
        }
    }

    /// `git log --pretty=format:"%H<sep>%cI<sep>%s" --name-only` output: each
    /// commit is a header line followed immediately by its changed file
    /// paths, commits separated by a blank line.
    private static func parseLog(_ raw: String, sep: String) -> [ParsedCommit] {
        let iso = ISO8601DateFormatter()
        var commits: [ParsedCommit] = []
        for block in raw.components(separatedBy: "\n\n") {
            var lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard !lines.isEmpty else { continue }
            let header = lines.removeFirst()
            let parts = header.components(separatedBy: sep)
            guard parts.count >= 3, let date = iso.date(from: parts[1]) else { continue }
            let subject = parts[2...].joined(separator: sep)
            let files = lines.filter { !$0.isEmpty }
            commits.append(ParsedCommit(sha: parts[0], date: date, subject: subject, files: files))
        }
        return commits
    }

    private static func extractTag(_ subject: String) -> String? {
        let range = NSRange(subject.startIndex..., in: subject)
        guard let match = tagRegex.firstMatch(in: subject, range: range), match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: subject) else { return nil }
        return String(subject[r])
    }

    private static func extractTaskId(_ body: String) -> String? {
        let range = NSRange(body.startIndex..., in: body)
        guard let match = taskRegex.firstMatch(in: body, range: range) else { return nil }
        for i in 1..<match.numberOfRanges {
            if let r = Range(match.range(at: i), in: body) { return String(body[r]) }
        }
        return nil
    }

    private static func extractPr(_ body: String) -> (repo: String, number: Int)? {
        let range = NSRange(body.startIndex..., in: body)
        guard let match = prRegex.firstMatch(in: body, range: range), match.numberOfRanges > 2,
              let repoRange = Range(match.range(at: 1), in: body),
              let numRange = Range(match.range(at: 2), in: body),
              let number = Int(body[numRange]) else { return nil }
        return (String(body[repoRange]), number)
    }

    private static func pathTouchesModule(_ path: String, module: String) -> Bool {
        path.split(separator: "/").contains(Substring(module))
    }
}
