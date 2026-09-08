import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var store: WorktreeStore
    @EnvironmentObject var keyboard: KeyboardController
    let panelWidth: CGFloat
    let panelHeight: CGFloat

    private var visibleEntries: [WorktreeEntry] {
        keyboard.filteredEntries(from: store.worktrees)
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                if keyboard.isFiltering || !keyboard.filterText.isEmpty { filterBar }

                if !store.serverReachable {
                    unreachable
                } else if store.worktrees.isEmpty {
                    empty
                } else if visibleEntries.isEmpty {
                    noMatches
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380, maximum: 460), spacing: 14)], spacing: 14) {
                            ForEach(visibleEntries) { entry in
                                WorktreeCardView(entry: entry)
                            }
                        }
                        .padding(18)
                    }
                }
            }

            if keyboard.showShortcuts { shortcutsOverlay }
        }
        .frame(width: panelWidth, height: panelHeight)
        // The glass/vibrancy comes from the native NSGlassEffectView the
        // AppDelegate mounts this view onto (see showPanel()), which already
        // carries its own subtle tint -- keep this one very light so the panel
        // reads as transparent glass, not a tinted pane.
        .background(Theme.panel.opacity(0.05))
        .preferredColorScheme(.light)
        .sheet(isPresented: $keyboard.showCreate) {
            CreateWorktreeView().environmentObject(store)
        }
        .onChange(of: store.worktrees.map(\.name)) { _, _ in
            keyboard.clampFocus(to: store.worktrees)
        }
    }

    private var header: some View {
        HStack {
            Text("~/odoo-dashboard")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ink)
            Spacer()
            ActionButton(title: "Shortcuts", icon: "keyboard", hint: "?") {
                keyboard.showShortcuts.toggle()
            }
            ActionButton(title: "Refresh", icon: "arrow.clockwise") {
                Task { await store.refresh(fresh: true) }
            }
            ActionButton(title: "New worktree", icon: "plus", style: .primary, hint: "n") {
                keyboard.showCreate = true
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(Theme.accent)
            Text("/")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
            Text(keyboard.filterText.isEmpty ? "type to filter…" : keyboard.filterText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(keyboard.filterText.isEmpty ? Theme.inkDim : Theme.ink)
            if keyboard.isFiltering {
                Rectangle().fill(Theme.accent).frame(width: 1.5, height: 14)
            }
            Spacer()
            Text("Esc to clear")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkDim)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Theme.accentBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
    }

    private var noMatches: some View {
        Text("No worktrees match \"\(keyboard.filterText)\"")
            .font(.system(size: 15))
            .foregroundStyle(Theme.inkDim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shortcutsOverlay: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard shortcuts")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            HStack(alignment: .top, spacing: 32) {
                shortcutGroup("Navigate", [("j / k", "move down / up"), ("h / l", "move left / right"), ("Enter", "open in VS Code")])
                shortcutGroup("Actions", [("o", "open in VS Code"), ("s", "start / stop"), ("r", "rebase"), ("a", "ask Claude"), ("i", "details"), ("L", "logs"), ("c", "copy path"), ("f", "follow a link (PR/runbot/task)")])
                shortcutGroup("Other", [("x", "delete"), ("D", "drop DB"), ("/", "filter (name/branch/desc)"), ("n", "new worktree"), ("?", "toggle this"), ("Esc", "close")])
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.row))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.ruleStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onTapGesture { keyboard.showShortcuts = false }
    }

    private func shortcutGroup(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkDim)
            ForEach(rows, id: \.0) { key, label in
                HStack(spacing: 8) {
                    Text(key)
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .frame(minWidth: 44, alignment: .leading)
                        .foregroundStyle(Theme.accent)
                    Text(label)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private var unreachable: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 28))
                .foregroundStyle(Theme.inkDim)
            Text("Could not load worktrees")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("Check that ~/Desktop/odoo-wt/data/registry.json is readable")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        Text("No worktrees yet")
            .font(.system(size: 16))
            .foregroundStyle(Theme.inkDim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
