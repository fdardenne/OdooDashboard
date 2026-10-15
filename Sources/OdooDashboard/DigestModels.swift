import Foundation

/// One commit that matched a watched module -- an "important" change
/// (usually tagged [REF] or [IMP]) pushed to master in odoo or enterprise.
struct DigestItem: Codable, Identifiable, Sendable {
    var id: String { "\(sha)-\(module)" }
    let repo: String
    let sha: String
    let date: Date
    let tag: String
    let module: String
    let subject: String
    let commitUrl: String
    let taskId: String?
    let taskUrl: String?
    let prNumber: Int?
    let prUrl: String?
}

/// One "issue" of the mailbox -- everything that matched between two points
/// in time, generated the moment the user opened the digest.
struct DigestEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let generatedAt: Date
    let rangeStart: Date
    let rangeEnd: Date
    let items: [DigestItem]
    /// A short Claude-written recap of `items`, in plain English -- nil if
    /// there was nothing to summarize or the `claude` CLI wasn't reachable.
    /// Missing from entries persisted before this existed, which decodes
    /// fine since it's Optional.
    var summary: String?

    init(rangeStart: Date, rangeEnd: Date, items: [DigestItem], summary: String? = nil) {
        self.id = UUID()
        self.generatedAt = Date()
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.items = items
        self.summary = summary
    }
}
