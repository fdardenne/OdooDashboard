import AppKit
import SwiftUI

/// The digest "mailbox" page, embedded in the panel (see MenuBarContentView's
/// pageTabs) -- lists every digest ever generated, newest first. Opening this
/// page is what triggers generating the next one, covering the time since
/// the last one was made (or the last 7 days, the very first time); the
/// "Generate now" button forces one on demand regardless of that cadence.
struct DigestView: View {
    @State private var mailbox: [DigestEntry] = []
    @State private var isLoading = true
    @State private var expanded: Set<UUID> = []
    @State private var pendingClearConfirm = false

    private var configuredModules: [String] { Config.digestModules }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if configuredModules.isEmpty {
                emptyState(
                    icon: "envelope.badge",
                    title: "No modules configured",
                    subtitle: "Add comma-separated module names in Settings → Digest to start tracking them."
                )
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                    Text("Scanning master and summarizing with Claude…")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mailbox.isEmpty {
                emptyState(icon: "tray", title: "No digests yet", subtitle: nil)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(mailbox) { entry in
                            issueView(entry)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await load()
        }
    }

    private func load() async {
        mailbox = await DigestService.consult()
        if let first = mailbox.first { expanded.insert(first.id) }
        isLoading = false
    }

    private func forceRefresh() async {
        isLoading = true
        mailbox = await DigestService.consult(force: true)
        if let first = mailbox.first { expanded.insert(first.id) }
        isLoading = false
    }

    private func clearAndRegenerate() async {
        DigestStore.clear()
        mailbox = []
        expanded = []
        isLoading = true
        await load()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Digest").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                if !configuredModules.isEmpty {
                    Text("Watching: \(configuredModules.joined(separator: ", "))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim)
                }
            }
            Spacer()
            if !configuredModules.isEmpty {
                ActionButton(title: "Generate now", icon: "arrow.clockwise", isDisabled: isLoading) {
                    Task { await forceRefresh() }
                }
                if !mailbox.isEmpty {
                    ActionButton(title: "Clear", icon: "trash", style: .danger) {
                        pendingClearConfirm = true
                    }
                    .confirmationDialog(
                        "Clear digest history? The next time you open Digest, it'll start over from a 7-day window.",
                        isPresented: $pendingClearConfirm, titleVisibility: .visible
                    ) {
                        Button("Clear History", role: .destructive) {
                            Task { await clearAndRegenerate() }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    private func emptyState(icon: String, title: String, subtitle: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Theme.inkDim)
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkDim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func issueView(_ entry: DigestEntry) -> some View {
        let isExpanded = expanded.contains(entry.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpanded { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkDim)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Self.rangeFormatter.string(from: entry.rangeStart)) → \(Self.rangeFormatter.string(from: entry.rangeEnd))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Text(entry.items.isEmpty ? "Nothing matched" : "\(entry.items.count) commit\(entry.items.count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkDim)
                    }
                    Spacer()
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let summary = entry.summary, !summary.isEmpty {
                        summaryView(summary, items: entry.items)
                    }
                    ForEach(entry.items) { item in
                        itemView(item)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.row))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.rule, lineWidth: 1))
    }

    private func summaryView(_ summary: String, items: [DigestItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(Theme.accent)
                Text("Summary").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.accent)
            }
            Text(Self.linkedSummary(summary, items: items))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentBg))
    }

    /// Claude is asked (see DigestSummarizer) to cite each claim with the
    /// exact "PR #N" / "task-N" text from the input it was given -- turns
    /// those citations into real clickable links here, resolved against
    /// `items`' own URLs (never a URL Claude might have produced itself).
    private static let prCitationRegex = try! NSRegularExpression(pattern: #"PR #(\d+)"#)
    private static let taskCitationRegex = try! NSRegularExpression(pattern: #"task-(\d+)"#)

    private static func linkedSummary(_ text: String, items: [DigestItem]) -> AttributedString {
        var prUrls: [Int: String] = [:]
        var taskUrls: [String: String] = [:]
        for item in items {
            if let n = item.prNumber, let u = item.prUrl { prUrls[n] = u }
            if let t = item.taskId, let u = item.taskUrl { taskUrls[t] = u }
        }

        let mutable = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let nsText = text as NSString

        func applyLinks(_ regex: NSRegularExpression, resolve: (String) -> String?) {
            for match in regex.matches(in: text, range: fullRange) where match.numberOfRanges > 1 {
                let id = nsText.substring(with: match.range(at: 1))
                guard let urlString = resolve(id), let url = URL(string: urlString) else { continue }
                mutable.addAttribute(.link, value: url, range: match.range)
            }
        }
        applyLinks(prCitationRegex) { prUrls[Int($0) ?? -1] }
        applyLinks(taskCitationRegex) { taskUrls[$0] }

        return AttributedString(mutable)
    }

    private func itemView(_ item: DigestItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                BadgePill(text: item.tag, tone: item.tag == "REF" ? .blue : .green)
                BadgePill(text: item.module, tone: .neutral)
                Text(item.repo).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.inkDim)
                Spacer()
            }
            Text(item.subject)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let prNumber = item.prNumber, let prUrl = item.prUrl, let url = URL(string: prUrl) {
                    link("PR #\(prNumber)", url: url)
                } else if let url = URL(string: item.commitUrl) {
                    link("View commit", url: url)
                }
                if let taskId = item.taskId, let taskUrl = item.taskUrl, let url = URL(string: taskUrl) {
                    link("task-\(taskId)", url: url)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
    }

    private func link(_ title: String, url: URL) -> some View {
        Button(title) { NSWorkspace.shared.open(url) }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.accent)
            .underline()
    }
}
