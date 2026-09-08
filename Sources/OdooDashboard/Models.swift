import Foundation

struct PrInfo: Decodable, Sendable {
    let repo: String
    let number: Int
    let url: String
    let title: String
    let state: String
    let isDraft: Bool
    let reviewDecision: String
    let mergebotApproved: Bool
    let ciStatus: String
}

struct RunbotBuild: Decodable, Sendable {
    let name: String
    let buildUrl: String
    let runUrl: String?
    let globalState: String
    let globalResult: String
}

struct RunbotStatus: Decodable, Sendable {
    let bundleUrl: String
    let batchUrl: String
    let batchTimeAgo: String
    let status: String
    let builds: [RunbotBuild]
}

struct RebaseReportItem: Decodable, Identifiable, Sendable {
    var id: String { repo }
    let repo: String
    let ok: Bool
    let conflict: Bool?
    let message: String?
}

struct OdooTaskInfo: Decodable, Sendable {
    let id: Int
    let name: String
    let stageName: String
    let state: String
    let url: String
}

struct WorktreeEntry: Decodable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let taskId: String
    let fromBranch: String
    let port: Int
    let db: String
    let description: String
    let installModules: String
    let updateModules: String
    let running: Bool
    let pr: [PrInfo?]
    let runbot: RunbotStatus?
    let odooTask: OdooTaskInfo?
    /// Absolute path to each repo's checkout within this worktree (e.g.
    /// "odoo" -> ".../odoo-worktrees/<name>/odoo") -- used to tell Claude
    /// exactly which folder a rebase conflict is in.
    let repos: [String: String]

    /// Worst-status color for the row's status rail -- mirrors the web
    /// dashboard's railClass() so both surfaces read the same way.
    var railColor: RailColor {
        let prBad = pr.contains { $0?.ciStatus == "failure" || $0?.reviewDecision == "CHANGES_REQUESTED" }
        if prBad || runbot?.status == "failure" { return .red }
        let prPending = pr.contains { $0?.ciStatus == "pending" }
        let taskInProgress = odooTask?.state.contains("in_progress") ?? false
        if prPending || taskInProgress { return .blue }
        let approved = pr.contains { $0?.mergebotApproved == true || $0?.reviewDecision == "APPROVED" }
        if approved { return .green }
        return .gray
    }
}

enum RailColor: Sendable {
    case red, blue, green, gray
}

/// A rendered badge pill plus, when it links somewhere, the digit key that
/// opens it in "f" link-follow mode. See StatusLogic.badgeSpecs(for:).
struct BadgeSpec: Identifiable {
    let id = UUID()
    let text: String
    let tone: BadgePill.Tone
    let url: URL?
    let tooltip: String?
    let hintKey: String?
}
