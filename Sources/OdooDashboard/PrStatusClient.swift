import Foundation

/// Ports packages/server/src/prStatus.ts -- PR/CI/review status per repo via
/// the `gh` CLI, including Odoo's mergebot ("@robodoo r+/r-" comment)
/// approval convention, which is distinct from GitHub's native review button.
enum PrStatusClient {
    private struct RawCheck: Decodable {
        let state: String?
        let conclusion: String?
    }
    private struct RawComment: Decodable {
        let body: String?
    }
    private struct RawPr: Decodable {
        let number: Int
        let title: String
        let state: String
        let isDraft: Bool
        let reviewDecision: String?
        let url: String
        let statusCheckRollup: [RawCheck]?
        let comments: [RawComment]?
    }

    private static let mergebotApprove = try! NSRegularExpression(pattern: #"^@robodoo\s+r\+"#, options: .caseInsensitive)
    private static let mergebotReject = try! NSRegularExpression(pattern: #"^@robodoo\s+r-"#, options: .caseInsensitive)

    private static func deriveCiStatus(_ checks: [RawCheck]?) -> String {
        guard let checks, !checks.isEmpty else { return "none" }
        let states = checks.map { ($0.state ?? $0.conclusion ?? "").uppercased() }
        if states.contains(where: { $0 == "FAILURE" || $0 == "ERROR" }) { return "failure" }
        if states.contains(where: { ["PENDING", "EXPECTED", "IN_PROGRESS", "QUEUED"].contains($0) }) { return "pending" }
        if states.allSatisfy({ $0 == "SUCCESS" }) { return "success" }
        return "unknown"
    }

    /// Scans comments in chronological order; the *last* r+/r- command wins.
    private static func deriveMergebotApproved(_ comments: [RawComment]?) -> Bool {
        guard let comments else { return false }
        var approved = false
        for comment in comments {
            let body = (comment.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(body.startIndex..., in: body)
            if mergebotApprove.firstMatch(in: body, range: range) != nil {
                approved = true
            } else if mergebotReject.firstMatch(in: body, range: range) != nil {
                approved = false
            }
        }
        return approved
    }

    private static func fetchOne(repo: String, branch: String) async -> PrInfo? {
        guard let out = try? await ProcessRunner.run(BinaryLocator.gh, [
            "pr", "list", "--repo", "\(Config.githubUpstreamOwner)/\(repo)", "--head", branch, "--state", "all",
            "--json", "number,title,state,isDraft,reviewDecision,url,statusCheckRollup,comments",
            "--limit", "1",
        ]) else { return nil }
        guard let data = out.data(using: .utf8),
              let list = try? JSONDecoder().decode([RawPr].self, from: data),
              let raw = list.first else { return nil }
        return PrInfo(
            repo: repo, number: raw.number, url: raw.url, title: raw.title, state: raw.state,
            isDraft: raw.isDraft, reviewDecision: raw.reviewDecision ?? "",
            mergebotApproved: deriveMergebotApproved(raw.comments), ciStatus: deriveCiStatus(raw.statusCheckRollup)
        )
    }

    /// Fetches every configured repo in parallel; a gh failure for any one
    /// repo yields nil for that slot rather than failing the whole call.
    static func getPrStatus(branch: String) async -> [PrInfo?] {
        let repos = Config.worktreeRepos
        return await withTaskGroup(of: (Int, PrInfo?).self) { group in
            for (index, repo) in repos.enumerated() {
                group.addTask { (index, await fetchOne(repo: repo, branch: branch)) }
            }
            var results = [PrInfo?](repeating: nil, count: repos.count)
            for await (index, result) in group {
                results[index] = result
            }
            return results
        }
    }
}
