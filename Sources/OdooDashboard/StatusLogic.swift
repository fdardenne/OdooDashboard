import Foundation

/// Mirrors the coloring/URL logic in the web dashboard's WorktreeCard.tsx so
/// both surfaces agree on what each status means.
enum StatusLogic {
    private static let officialVersionBranch = try! NSRegularExpression(pattern: #"^(master|\d+\.\d+|saas-\d+\.\d+)$"#)

    static func isOfficialVersionBranch(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        return officialVersionBranch.firstMatch(in: name, range: range) != nil
    }

    /// Best-effort Odoo task id out of a branch name like
    /// "master-6482307-dafl" or "saas-18.2-6501419-xyz" -- the first
    /// purely-numeric, task-id-length segment. Version segments ("18.0",
    /// "18") and the trailing trigram never match since they aren't 5+
    /// digits with no dot, so this only fires on an actual task id.
    static func inferredTaskId(fromBranch branch: String) -> String? {
        let parts: [Substring] = branch.split(separator: "-")
        return parts.first { $0.count >= 5 && $0.allSatisfy(\.isNumber) }.map(String.init)
    }

    /// Pure PR-review-state coloring -- CI status is shown separately via
    /// the runbot/build badges, so it doesn't also drive this tone.
    /// merged/closed = done (green). r+/approved = will be merged (green).
    /// changes requested/conflicting = actually blocked (red).
    static func prTone(_ pr: PrInfo) -> BadgePill.Tone {
        if pr.state == "MERGED" || pr.state == "CLOSED" { return .green }
        if pr.reviewDecision == "CHANGES_REQUESTED" || pr.mergeable == "CONFLICTING" { return .red }
        if pr.mergebotApproved || pr.reviewDecision == "APPROVED" { return .green }
        return .yellow
    }

    /// One-word status, in priority order: merged > closed > r+'d >
    /// approved > changes requested > conflict. nil when none apply (e.g. a
    /// plain pending-review PR) -- the badge just shows the PR number then.
    static func prStatusLabel(_ pr: PrInfo) -> String? {
        if pr.state == "MERGED" { return "merged" }
        if pr.state == "CLOSED" { return "closed" }
        if pr.mergebotApproved { return "r+" }
        if pr.reviewDecision == "APPROVED" { return "approved" }
        if pr.reviewDecision == "CHANGES_REQUESTED" { return "changes requested" }
        if pr.mergeable == "CONFLICTING" { return "conflict" }
        return nil
    }

    static func runbotTone(_ status: String) -> BadgePill.Tone {
        switch status {
        case "success": return .green
        case "failure": return .red
        case "running": return .yellow
        default: return .neutral
        }
    }

    static func buildTone(_ result: String) -> BadgePill.Tone {
        if result == "ok" { return .green }
        if result == "ko" { return .red }
        return .neutral
    }

    static func taskTone(_ state: String) -> BadgePill.Tone {
        if state.contains("approved") || state.contains("done") { return .green }
        if state.contains("changes_requested") || state.contains("cancel") { return .red }
        if state.contains("in_progress") { return .blue }
        return .yellow
    }

    static func createPrUrl(repo: String, entry: WorktreeEntry) -> URL? {
        let allowed = CharacterSet.urlPathAllowed
        let base = entry.fromBranch.addingPercentEncoding(withAllowedCharacters: allowed) ?? entry.fromBranch
        let branch = entry.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? entry.name
        return URL(string: "https://github.com/\(Config.githubUpstreamOwner)/\(repo)/compare/\(base)...\(Config.githubForkOwner):\(repo):\(branch)?expand=1")
    }

    /// Single source of truth for the badge row -- both WorktreeCardView
    /// (rendering) and AppDelegate's "f" link-follow keyboard mode (opening)
    /// read from this so the numbered hints always match what the pill in
    /// the UI actually points to.
    static func badgeSpecs(for entry: WorktreeEntry) -> [BadgeSpec] {
        var specs: [BadgeSpec] = []
        var hintCounter = 1
        func hint(for url: URL?) -> String? {
            guard url != nil else { return nil }
            defer { hintCounter += 1 }
            return String(hintCounter)
        }

        // Only the per-repo PR badges are official-branch-only (there's no PR
        // to open/create from master onto itself) -- runbot and task status
        // are meaningful for any branch and, mirroring the web dashboard,
        // stay visible regardless.
        if !isOfficialVersionBranch(entry.name) {
            for repo in Config.worktreeRepos {
                if let pr = entry.pr.first(where: { $0?.repo == repo }) ?? nil {
                    let url = URL(string: pr.url)
                    let statusSuffix = prStatusLabel(pr).map { " · \($0)" } ?? ""
                    specs.append(BadgeSpec(
                        text: "\(repo) #\(pr.number)\(pr.isDraft ? " draft" : "")\(statusSuffix)",
                        tone: prTone(pr), url: url, tooltip: pr.title, hintKey: hint(for: url)
                    ))
                } else if Config.requiredRepos.contains(repo) {
                    // Only the required repos (odoo/enterprise by default) show
                    // a "no PR" badge -- for everything else, a PR is optional,
                    // so skip the badge entirely rather than clutter the row.
                    let url = createPrUrl(repo: repo, entry: entry)
                    specs.append(BadgeSpec(
                        text: "\(repo): no PR", tone: .neutral, url: url,
                        tooltip: "Create a PR for \(repo)", hintKey: hint(for: url)
                    ))
                }
            }
        }
        if let runbot = entry.runbot {
            // Just a stable link to the bundle overview -- per-build status is
            // already conveyed by the build badges below, so this one doesn't
            // need to repeat it (and always uses bundleUrl, not the
            // most-recent-batch URL, since that one changes every run).
            let url = URL(string: runbot.bundleUrl)
            specs.append(BadgeSpec(
                text: "runbot bundle",
                tone: runbotTone(runbot.status), url: url, tooltip: nil, hintKey: hint(for: url)
            ))
            for build in runbot.builds {
                let buildUrl = URL(string: build.runUrl ?? build.buildUrl)
                specs.append(BadgeSpec(
                    text: "\(build.name): \(build.globalResult)",
                    tone: buildTone(build.globalResult), url: buildUrl, tooltip: nil, hintKey: hint(for: buildUrl)
                ))
            }
        } else {
            specs.append(BadgeSpec(text: "runbot: no bundle", tone: .neutral, url: nil, tooltip: nil, hintKey: nil))
        }
        if !entry.taskId.isEmpty {
            if let task = entry.odooTask {
                let url = URL(string: task.url)
                specs.append(BadgeSpec(
                    text: "\(task.stageName.isEmpty ? "task" : task.stageName) #\(entry.taskId)",
                    tone: taskTone(task.state), url: url, tooltip: "\(task.name) — \(task.stageName)", hintKey: hint(for: url)
                ))
            } else {
                let url = URL(string: "https://www.odoo.com/odoo/my-tasks/\(entry.taskId)")
                specs.append(BadgeSpec(text: "odoo task #\(entry.taskId)", tone: .neutral, url: url, tooltip: nil, hintKey: hint(for: url)))
            }
        }
        return specs
    }
}
