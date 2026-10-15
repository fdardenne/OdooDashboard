import AppKit
import Foundation

/// The 4 top-level views onto the worktree list, switched with 1/2/3/4.
enum WorktreeCategory: Int, CaseIterable {
    case main = 1
    case archived = 2
    case standard = 3
    case all = 4

    var title: String {
        switch self {
        case .main: return "In Progress"
        case .archived: return "Done"
        case .standard: return "Standard"
        case .all: return "All"
        }
    }

    private static func isArchived(_ entry: WorktreeEntry) -> Bool {
        entry.odooTask?.stageName.localizedCaseInsensitiveContains("deployed") ?? false
    }

    /// In Progress = everything not Done and not Standard. Done = task
    /// stage is "Deployed". Standard = an official version branch
    /// (master, 18.0, saas-17.2, ...). All = no filtering.
    static func matches(_ category: WorktreeCategory, _ entry: WorktreeEntry) -> Bool {
        switch category {
        case .all: return true
        case .standard: return StatusLogic.isOfficialVersionBranch(entry.name)
        case .archived: return isArchived(entry)
        case .main: return !isArchived(entry) && !StatusLogic.isOfficialVersionBranch(entry.name)
        }
    }
}

enum CreateMode: String, CaseIterable { case branch = "Branch", pr = "PR number" }

/// The top-level pages of the panel, switched with "d" (digest) / "t" (search).
enum PanelPage { case worktrees, digest, search }

/// Shared keyboard-navigation state for the vim-style control scheme. Card
/// UI that used to be private @State inside WorktreeCardView (details/logs
/// panels, rebase report, delete confirmations, the copy-path flash) lives
/// here instead, keyed by worktree name, so the global key handler in
/// AppDelegate can drive it on the currently-focused card without owning
/// any SwiftUI view state itself.
@MainActor
final class KeyboardController: ObservableObject {
    @Published var focusedName: String?
    @Published var category: WorktreeCategory = .main
    @Published var page: PanelPage = .worktrees

    @Published var filterText: String = ""
    @Published var isFiltering: Bool = false
    @Published var showShortcuts: Bool = false
    @Published var showCreate: Bool = false
    /// True while "f" link-follow mode is active on the focused card --
    /// its badges show numbered hints and the next digit key opens one.
    @Published var linkMode: Bool = false

    // Create-worktree sheet draft -- lives here rather than as local @State
    // on CreateWorktreeView so it survives the panel's NSHostingView being
    // torn down and rebuilt, which happens every time the status item is
    // clicked (showPanel() always builds a fresh view tree). Without this,
    // toggling the dropdown while a creation is still in flight (or while
    // the user is mid-typing) silently wiped whatever was in the form.
    @Published var createMode: CreateMode = .branch
    @Published var createTaskId: String = ""
    @Published var createFromBranch: String = "master"
    @Published var createBranchName: String = ""
    @Published var createPrNumber: String = ""
    @Published var createPrRepo: String = Config.worktreeRepos.first ?? ""
    @Published var createBusy: Bool = false
    @Published var createError: String?

    func resetCreateDraft() {
        createMode = .branch
        createTaskId = ""
        createFromBranch = "master"
        createBranchName = ""
        createPrNumber = ""
        createPrRepo = Config.worktreeRepos.first ?? ""
        createError = nil
    }

    // Task Search's query/results -- same reasoning as the create-worktree
    // draft above: TaskSearchView is rebuilt from scratch on every panel
    // toggle, so anything kept as local @State (the query, the toggle, the
    // results) was silently wiped every time the dropdown closed and reopened.
    @Published var searchQuery: String = ""
    @Published var searchIncludeClosed: Bool = false
    @Published var searchIsSearching: Bool = false
    @Published var searchHasSearched: Bool = false
    @Published var searchResults: [OdooTaskSummary] = []
    @Published var searchError: String?
    /// A pasted screenshot to include in the match -- see TaskSearchService,
    /// which saves it to disk and hands Claude the path to read.
    @Published var searchScreenshot: NSImage?

    @Published var detailsOpen: Set<String> = []
    @Published var logsOpen: Set<String> = []
    /// Cards whose one-line description is currently being edited. Lives
    /// here (not local @State on WorktreeCardView) for the same reason as
    /// detailsOpen/logsOpen -- the global key handler needs to know a text
    /// field is active so it backs off instead of eating every keystroke
    /// as a vim shortcut.
    @Published var editingDescription: Set<String> = []
    @Published var rebaseReports: [String: [RebaseReportItem]] = [:]
    @Published var copiedName: String?
    @Published var pendingDeleteConfirm: String?
    @Published var pendingDropDbConfirm: String?

    /// True while a native dialog/sheet -- or an inline text field like
    /// Details, the description editor, or task search -- is up and should
    /// own the keyboard itself. The global tap backs off entirely rather
    /// than compete with it for arrow keys, Enter, Escape, or plain letters.
    /// This is state-based (page/open-set membership), not a live AppKit
    /// first-responder/@FocusState check -- that proved unreliable for text
    /// fields embedded in the borderless dropdown panel (as opposed to the
    /// Create sheet, a real separate window): a plain always-visible
    /// TextField (Task Search's query field) can fail to actually pick up
    /// focus on click here, so gating on "did it report itself focused"
    /// leaves the keystrokes swallowed with nowhere to land. Tracking
    /// "the page/section that owns this field is open" instead sidesteps
    /// that entirely.
    var hasModalOpen: Bool {
        pendingDeleteConfirm != nil || pendingDropDbConfirm != nil || showCreate
            || !detailsOpen.isEmpty || !editingDescription.isEmpty || page == .search
    }

    func isDetailsOpen(_ name: String) -> Bool { detailsOpen.contains(name) }
    func toggleDetails(_ name: String) {
        if detailsOpen.contains(name) { detailsOpen.remove(name) } else { detailsOpen.insert(name) }
    }

    func isEditingDescription(_ name: String) -> Bool { editingDescription.contains(name) }

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
        guard WorktreeCategory.matches(category, entry) else { return false }
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
