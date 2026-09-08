import Foundation

/// Shared keyboard-navigation state for the vim-style control scheme. Card
/// UI that used to be private @State inside WorktreeCardView (details/logs
/// panels, rebase report, delete confirmations, the copy-path flash) lives
/// here instead, keyed by worktree name, so the global key handler in
/// AppDelegate can drive it on the currently-focused card without owning
/// any SwiftUI view state itself.
@MainActor
final class KeyboardController: ObservableObject {
    @Published var focusedName: String?

    @Published var filterText: String = ""
    @Published var isFiltering: Bool = false
    @Published var showShortcuts: Bool = false
    @Published var showCreate: Bool = false
    /// True while "f" link-follow mode is active on the focused card --
    /// its badges show numbered hints and the next digit key opens one.
    @Published var linkMode: Bool = false

    @Published var detailsOpen: Set<String> = []
    @Published var logsOpen: Set<String> = []
    @Published var rebaseReports: [String: [RebaseReportItem]] = [:]
    @Published var copiedName: String?
    @Published var pendingDeleteConfirm: String?
    @Published var pendingDropDbConfirm: String?

    /// True while a native dialog/sheet is up that should own the keyboard
    /// itself -- the global tap backs off entirely rather than compete with
    /// it for arrow keys, Enter, Escape, etc.
    var hasModalOpen: Bool {
        pendingDeleteConfirm != nil || pendingDropDbConfirm != nil || showCreate
    }

    func isDetailsOpen(_ name: String) -> Bool { detailsOpen.contains(name) }
    func toggleDetails(_ name: String) {
        if detailsOpen.contains(name) { detailsOpen.remove(name) } else { detailsOpen.insert(name) }
    }

    func isLogsOpen(_ name: String) -> Bool { logsOpen.contains(name) }
    func toggleLogs(_ name: String) {
        if logsOpen.contains(name) { logsOpen.remove(name) } else { logsOpen.insert(name) }
    }

    func markCopied(_ name: String) {
        copiedName = name
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedName == name { copiedName = nil }
        }
    }

    func matches(_ entry: WorktreeEntry) -> Bool {
        let term = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return true }
        return entry.name.lowercased().contains(term)
            || entry.fromBranch.lowercased().contains(term)
            || entry.description.lowercased().contains(term)
    }

    func filteredEntries(from all: [WorktreeEntry]) -> [WorktreeEntry] {
        all.filter(matches)
    }

    /// Keeps focus valid (and non-nil when possible) whenever the visible
    /// set of cards changes -- a refresh, a filter keystroke, a deletion.
    func clampFocus(to all: [WorktreeEntry]) {
        let entries = filteredEntries(from: all)
        if let focusedName, entries.contains(where: { $0.name == focusedName }) { return }
        focusedName = entries.first?.name
    }

    func reset() {
        filterText = ""
        isFiltering = false
        showShortcuts = false
        linkMode = false
    }
}
