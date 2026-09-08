import Foundation
import SwiftSoup

/// Ports packages/server/src/runbot.ts -- scrapes a runbot search page for
/// the exact-name-matching bundle row. Runbot's HTML is undocumented and
/// version-specific, so these selectors are load-bearing and fragile by
/// nature (same as the original TS scraper).
enum RunbotClient {
    private static let batchClassStatus: [String: String] = [
        "bg-success-subtle": "success",
        "bg-danger-subtle": "failure",
        "bg-killed-subtle": "killed",
        "bg-warning-subtle": "running",
    ]

    private static func closestAncestor(_ element: Element, tag: String) -> Element? {
        var current = element.parent()
        while let el = current {
            if el.tagName() == tag { return el }
            current = el.parent()
        }
        return nil
    }

    private static func firstMatch(_ root: Element, _ css: String) -> Element? {
        (try? root.select(css))?.first()
    }

    private static func text(_ element: Element?) -> String {
        guard let element else { return "" }
        return (try? element.text().trimmingCharacters(in: .whitespaces)) ?? ""
    }

    private static func absHref(_ element: Element?) -> String {
        guard let element else { return "" }
        return (try? element.absUrl("href")) ?? ""
    }

    private static func parseRunbotHtml(_ html: String, branch: String) -> RunbotStatus? {
        guard let doc = try? SwiftSoup.parse(html, "https://runbot.odoo.com"),
              let rows = try? doc.select(".bundle_row") else { return nil }

        for row in rows.array() {
            guard let nameElement = firstMatch(row, ".col-md-3 b, .col-lg-2 b"), text(nameElement) == branch else { continue }

            let bundleUrl = closestAncestor(nameElement, tag: "a").map(absHref) ?? ""

            guard let batchTile = firstMatch(row, ".batch_tile") else {
                return RunbotStatus(bundleUrl: bundleUrl, batchUrl: "", batchTimeAgo: "", status: "unknown", builds: [])
            }

            var status = "unknown"
            if let card = firstMatch(batchTile, ".card") {
                let classes = ((try? card.className()) ?? "").split(separator: " ").map(String.init)
                for cls in classes where batchClassStatus[cls] != nil {
                    status = batchClassStatus[cls]!
                    break
                }
            }

            let batchLink = firstMatch(batchTile, "a")
            let batchUrl = absHref(batchLink)
            let batchTimeAgo = batchLink.map { text(firstMatch($0, ".badge")) } ?? ""

            var builds: [RunbotBuild] = []
            if let slots = try? batchTile.select(".slot_container") {
                for slot in slots.array() {
                    let dropdown = firstMatch(slot, "build-options-dropdown")
                    let name = text(firstMatch(slot, ".slot_name span"))
                    let buildUrl = absHref(firstMatch(slot, ".slot_name"))
                    let runUrlRaw = firstMatch(slot, "a.fa-sign-in").map(absHref)

                    let globalState: String
                    if let dropdown, let gs = try? dropdown.attr("data-global_state"), !gs.isEmpty {
                        globalState = gs
                    } else {
                        globalState = "unknown"
                    }
                    let globalResult: String
                    if let dropdown, let gr = try? dropdown.attr("data-global_result"), !gr.isEmpty {
                        globalResult = gr
                    } else {
                        globalResult = "unknown"
                    }

                    builds.append(RunbotBuild(
                        name: name.isEmpty ? "?" : name,
                        buildUrl: buildUrl,
                        runUrl: (runUrlRaw?.isEmpty ?? true) ? nil : runUrlRaw,
                        globalState: globalState,
                        globalResult: globalResult
                    ))
                }
            }

            return RunbotStatus(bundleUrl: bundleUrl, batchUrl: batchUrl, batchTimeAgo: batchTimeAgo, status: status, builds: builds)
        }
        return nil
    }

    static func fetchRunbotStatus(branch: String) async -> RunbotStatus? {
        guard let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://runbot.odoo.com/runbot/rd-1?search=\(encoded)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (odoo-wt dashboard)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { return nil }
        return parseRunbotHtml(html, branch: branch)
    }
}
