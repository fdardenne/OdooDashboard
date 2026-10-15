import Foundation

/// Ports packages/core/src/git.ts exactly -- one function per git op, run in
/// the correct directory (base repo vs. the worktree itself, which matters
/// a lot for rebase/log commands).
enum GitClient {
    private static func git(_ args: [String], cwd: URL) async throws -> String {
        try await ProcessRunner.run(BinaryLocator.git, args, cwd: cwd)
    }

    static func fetch(_ repoPath: URL, remote: String, ref: String) async throws {
        _ = try await git(["fetch", remote, ref], cwd: repoPath)
    }

    static func remoteBranchExists(_ repoPath: URL, remote: String, ref: String) async -> Bool {
        (try? await git(["ls-remote", "--exit-code", "--heads", remote, ref], cwd: repoPath))
            .map { !$0.isEmpty } ?? false
    }

    static func remoteExists(_ repoPath: URL, remote: String) async -> Bool {
        (try? await git(["remote", "get-url", remote], cwd: repoPath)) != nil
    }

    static func localBranchExists(_ repoPath: URL, branch: String) async -> Bool {
        (try? await git(["rev-parse", "--verify", "-q", "refs/heads/\(branch)"], cwd: repoPath)) != nil
    }

    /// A branch can only be checked out in one worktree at a time (including
    /// the main checkout, which git counts as a worktree too).
    static func isBranchCheckedOutElsewhere(_ repoPath: URL, branch: String) async -> Bool {
        guard let out = try? await git(["worktree", "list", "--porcelain"], cwd: repoPath) else { return false }
        return out.split(separator: "\n").contains(Substring("branch refs/heads/\(branch)"))
    }

    static func revParse(_ repoPath: URL, ref: String) async throws -> String {
        try await git(["rev-parse", ref], cwd: repoPath)
    }

    struct WorktreeAddResult { let detached: Bool }

    /// Creates a new branch from startPoint and adds a worktree for it,
    /// unless the branch already exists locally -- then attaches it, unless
    /// it's checked out elsewhere (e.g. it's "master", checked out in the
    /// main odoo_workspace checkout), in which case falls back to a detached
    /// checkout of its current commit.
    static func worktreeAdd(_ repoPath: URL, destPath: URL, branch: String, startPoint: String) async throws -> WorktreeAddResult {
        if await localBranchExists(repoPath, branch: branch) {
            if await isBranchCheckedOutElsewhere(repoPath, branch: branch) {
                let sha = try await revParse(repoPath, ref: branch)
                _ = try await git(["worktree", "add", "--detach", destPath.path, sha], cwd: repoPath)
                return WorktreeAddResult(detached: true)
            }
            _ = try await git(["worktree", "add", destPath.path, branch], cwd: repoPath)
            return WorktreeAddResult(detached: false)
        }
        _ = try await git(["worktree", "add", "-b", branch, destPath.path, startPoint], cwd: repoPath)
        return WorktreeAddResult(detached: false)
    }

    static func worktreeRemove(_ repoPath: URL, worktreePath: URL, force: Bool = false) async throws {
        var args = ["worktree", "remove", worktreePath.path]
        if force { args.append("--force") }
        _ = try await git(args, cwd: repoPath)
    }

    static func rebase(_ worktreePath: URL, onto ontoRef: String) async throws {
        _ = try await git(["rebase", ontoRef], cwd: worktreePath)
    }

    /// For standard/trunk branches (master, 18.0, ...) there's nothing to
    /// rebase onto -- the worktree just needs to catch up to its own remote
    /// branch. Fast-forward only, so it never silently invents a merge
    /// commit or clobbers local work.
    static func fastForwardMerge(_ worktreePath: URL, ref: String) async throws {
        _ = try await git(["merge", "--ff-only", ref], cwd: worktreePath)
    }

    static func rebaseAbort(_ worktreePath: URL) async {
        _ = try? await git(["rebase", "--abort"], cwd: worktreePath)
    }

    static func isRebaseInProgress(_ worktreePath: URL) async -> Bool {
        (try? await git(["rev-parse", "--verify", "-q", "REBASE_HEAD"], cwd: worktreePath)) != nil
    }

    /// Commit subjects unique to this worktree relative to `ontoRef` (e.g.
    /// "origin/master"), newest first. [] rather than throwing if ontoRef
    /// isn't available locally (e.g. never fetched).
    static func logSubjects(_ worktreePath: URL, onto ontoRef: String, limit: Int = 30) async -> [String] {
        guard let out = try? await git(["log", "\(ontoRef)..HEAD", "--oneline", "-n", String(limit)], cwd: worktreePath) else { return [] }
        return out.isEmpty ? [] : out.split(separator: "\n").map(String.init)
    }
}
