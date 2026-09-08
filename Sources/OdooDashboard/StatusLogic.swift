import Foundation

/// Mirrors the coloring/URL logic in the web dashboard's WorktreeCard.tsx so
/// both surfaces agree on what each status means.
enum StatusLogic {
    private static let officialVersionBranch = try! NSRegularExpression(pattern: #"^(master|\d+\.\d+|saas-\d+\.\d+)$"#)

    static func isOfficialVersionBranch(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        return officialVersionBranch.firstMatch(in: name, range: range) != nil
    }

    static func prTone(_ pr: PrInfo) -> BadgePill.Tone {
        if pr.state == "MERGED" { return .green }
        if pr.state == "CLOSED" { return .red }
        if pr.ciStatus == "failure" { return .red }
        if pr.reviewDecision == "CHANGES_REQUESTED" { return .red }
        if pr.ciStatus == "pending" { return .yellow }
        if pr.reviewDecision == "APPROVED" || pr.mergebotApproved { return .green }
        return .yellow
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
                    specs.append(BadgeSpec(
                        text: "\(repo) #\(pr.number)\(pr.isDraft ? " draft" : "")",
                        tone: prTone(pr), url: url, tooltip: pr.title, hintKey: hint(for: url)
                    ))
                } else {
                    let url = createPrUrl(repo: repo, entry: entry)
                    specs.append(BadgeSpec(
                        text: "\(repo): no PR", tone: .neutral, url: url,
                        tooltip: "Create a PR for \(repo)", hintKey: hint(for: url)
                    ))
                }
            }
        }
        if let runbot = entry.runbot {
            let batchUrlString = runbot.batchUrl.isEmpty ? runbot.bundleUrl : runbot.batchUrl
            let url = URL(string: batchUrlString)
            specs.append(BadgeSpec(
                text: "runbot: \(runbot.status) (\(runbot.batchTimeAgo))",
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
