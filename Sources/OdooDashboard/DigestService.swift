import Foundation

/// Ties the mailbox together with "what to scan next": first consult ever
/// covers the last 7 days, every consult after that covers since the
/// previous one -- so opening the digest is itself what advances it.
enum DigestService {
    /// Opening/closing the sheet in quick succession shouldn't manufacture
    /// near-duplicate entries for essentially the same instant.
    private static let minRegenInterval: TimeInterval = 5 * 60

    /// `force` bypasses the cooldown -- used by the "Generate now" button so
    /// testing (or just wanting fresher data right away) doesn't require
    /// waiting out the window or clearing history first.
    @MainActor
    static func consult(force: Bool = false) async -> [DigestEntry] {
        var mailbox = DigestStore.load()
        let modules = Config.digestModules
        guard !modules.isEmpty else { return mailbox }

        let now = Date()
        if !force, let mostRecent = mailbox.first, now.timeIntervalSince(mostRecent.generatedAt) < minRegenInterval {
            return mailbox
        }

        let since = mailbox.first?.rangeEnd ?? now.addingTimeInterval(-7 * 24 * 3600)
        let items = await DigestGenerator.generate(modules: modules, since: since, until: now)
        let summary = await DigestSummarizer.summarize(items)
        let entry = DigestEntry(rangeStart: since, rangeEnd: now, items: items, summary: summary)
        DigestStore.append(entry)
        mailbox.insert(entry, at: 0)
        return mailbox
    }
}
