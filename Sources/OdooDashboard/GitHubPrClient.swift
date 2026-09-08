import Foundation

/// Ports packages/core/src/github.ts -- given a repo + PR number, resolves
/// the PR's head branch name (used by "create worktree from PR number").
enum GitHubPrClient {
    private struct HeadRefResponse: Decodable { let headRefName: String }

    static func resolvePrHeadBranch(repo: String, number: Int) async throws -> String {
        let out = try await ProcessRunner.run(BinaryLocator.gh, [
            "pr", "view", String(number), "--repo", "\(Config.githubUpstreamOwner)/\(repo)", "--json", "headRefName",
        ])
        guard let data = out.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(HeadRefResponse.self, from: data) else {
            throw ProcessError(message: "Could not resolve head branch for \(Config.githubUpstreamOwner)/\(repo)#\(number)")
        }
        return decoded.headRefName
    }
}
