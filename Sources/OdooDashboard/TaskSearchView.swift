import AppKit
import SwiftUI

/// The task search page (see MenuBarContentView's pageTabs) -- searches the
/// Odoo project configured in Settings -> Task Search by fetching its whole
/// task list in one call and letting Claude match the query against each
/// task's title/description (see TaskSearchMatcher), rather than a naive
/// keyword filter.
struct TaskSearchView: View {
    @EnvironmentObject var keyboard: KeyboardController

    private var projectId: Int? { Config.taskSearchProjectId }

    private var canSearch: Bool {
        !keyboard.searchIsSearching
            && (!keyboard.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || keyboard.searchScreenshot != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if projectId == nil {
                emptyState(
                    icon: "magnifyingglass",
                    title: "No project configured",
                    subtitle: "Set a project id in Settings → Task Search to search its tasks."
                )
            } else {
                searchBar

                if keyboard.searchIsSearching {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                        Text("Fetching tasks and matching with Claude…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkDim)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = keyboard.searchError {
                    emptyState(icon: "exclamationmark.triangle", title: "Search failed", subtitle: errorMessage)
                } else if keyboard.searchHasSearched && keyboard.searchResults.isEmpty {
                    emptyState(icon: "tray", title: "No matching tasks", subtitle: nil)
                } else if !keyboard.searchResults.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(keyboard.searchResults) { task in
                                taskRow(task)
                            }
                        }
                        .padding(16)
                    }
                } else {
                    emptyState(icon: "text.magnifyingglass", title: "Search this project's tasks", subtitle: "Claude reads each task's title and description to find real matches, not just keyword overlap. Paste (⌘V) a screenshot to search with it too.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Global vim shortcuts already back off entirely while
        // keyboard.page == .search (see hasModalOpen) regardless of which
        // control has focus, so Escape has to be handled locally here --
        // there's no global routing left to fall back on for it.
        .onExitCommand { keyboard.page = .worktrees }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Task Search").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
            if let projectId {
                Text("Project #\(projectId)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkDim)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    if keyboard.searchQuery.isEmpty {
                        Text("Search tasks…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkDim)
                    }
                    FocusableTextField(text: $keyboard.searchQuery, autoFocus: true) {
                        TaskSearchService.search(keyboard)
                    } onImagePaste: { image in
                        keyboard.searchScreenshot = image
                    }
                }
                .frame(height: 20)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.row))
                ActionButton(title: "Search", style: .primary, isDisabled: !canSearch) {
                    TaskSearchService.search(keyboard)
                }
            }
            if let screenshot = keyboard.searchScreenshot {
                screenshotPreview(screenshot)
            }
            HStack {
                Toggle("Include closed tasks", isOn: $keyboard.searchIncludeClosed)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkDim)
                Spacer()
                Text("⌘V to attach a screenshot")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkDim)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    private func screenshotPreview(_ image: NSImage) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.rule, lineWidth: 1))
            Text("Screenshot attached").font(.system(size: 12)).foregroundStyle(Theme.inkDim)
            Spacer()
            Button {
                keyboard.searchScreenshot = nil
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkDim)
            }
            .buttonStyle(.plain)
            .help("Remove screenshot")
        }
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
                    .frame(maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func taskRow(_ task: OdooTaskSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(task.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !task.stageName.isEmpty {
                    BadgePill(text: task.stageName, tone: .neutral)
                }
            }
            if !task.description.isEmpty {
                Text(task.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkDim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("task-\(task.id)") {
                if let url = URL(string: task.url) { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.accent)
            .underline()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.row))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.rule, lineWidth: 1))
    }
}
