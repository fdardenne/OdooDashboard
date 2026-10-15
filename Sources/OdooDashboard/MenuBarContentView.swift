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
                pageTabs

                if keyboard.page == .digest {
                    DigestView()
                } else if keyboard.page == .search {
                    TaskSearchView().environmentObject(keyboard)
                } else {
                    categoryTabs
                    if keyboard.isFiltering || !keyboard.filterText.isEmpty { filterBar }

                    if !store.serverReachable {
                        unreachable
                    } else if store.worktrees.isEmpty {
                        empty
                    } else if visibleEntries.isEmpty {
                        noMatches
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380, maximum: 460), spacing: 14)], spacing: 14) {
                                    ForEach(visibleEntries) { entry in
                                        WorktreeCardView(entry: entry).id(entry.name)
                                    }
                                }
                                .padding(18)
                            }
                            .onChange(of: keyboard.focusedName) { _, newValue in
                                guard let newValue else { return }
                                withAnimation(.easeOut(duration: 0.15)) {
                                    proxy.scrollTo(newValue, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }

            if keyboard.showShortcuts { shortcutsOverlay }
        }
        .frame(width: panelWidth, height: panelHeight)
        // The glass/vibrancy comes from the native NSGlassEffectView the
        // AppDelegate mounts this view onto (see showPanel()), which already
        // carries a matching tint -- a fully transparent panel reads as
        // outright ugly over a dark desktop/wallpaper/window, so both need
        // enough white behind them to stay legible regardless of what's back there.
        .background(Theme.panel.opacity(0.7))
        .preferredColorScheme(.light)
        .sheet(isPresented: $keyboard.showCreate) {
            CreateWorktreeView().environmentObject(store).environmentObject(keyboard)
        }
        .onChange(of: store.worktrees.map(\.name)) { _, _ in
            keyboard.clampFocus(to: store.worktrees)
        }
    }

    private var pageTabs: some View {
        HStack(spacing: 4) {
            pageTab("Worktrees", icon: "square.grid.2x2", page: .worktrees)
            pageTab("Digest", icon: "envelope", page: .digest, hint: "d")
            pageTab("Search", icon: "magnifyingglass", page: .search, hint: "t")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private func pageTab(_ title: String, icon: String, page: PanelPage, hint: String? = nil) -> some View {
        let active = keyboard.page == page
        return Button {
            keyboard.page = page
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.system(size: 12.5, weight: .medium))
                if let hint {
                    Text(hint)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill((active ? Theme.accent : Theme.inkDim).opacity(0.15)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(active ? Theme.accentBg : Color.clear))
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Theme.accent : Theme.inkDim)
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
            if keyboard.page == .worktrees {
                ActionButton(title: "New worktree", icon: "plus", style: .primary, hint: "n") {
                    keyboard.showCreate = true
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
    }

    private var categoryTabs: some View {
        HStack(spacing: 4) {
            ForEach(WorktreeCategory.allCases, id: \.self) { cat in
                let active = keyboard.category == cat
                let count = store.worktrees.filter { WorktreeCategory.matches(cat, $0) }.count
                Button {
                    keyboard.category = cat
                    keyboard.clampFocus(to: store.worktrees)
                } label: {
                    HStack(spacing: 5) {
                        Text(cat.title).font(.system(size: 12.5, weight: .medium))
                        Text("\(count)")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(active ? Theme.accent.opacity(0.7) : Theme.inkDim.opacity(0.7))
                        Text("\(cat.rawValue)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill((active ? Theme.accent : Theme.inkDim).opacity(0.15)))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(active ? Theme.accentBg : Color.clear))
                }
                .buttonStyle(.plain)
                .foregroundStyle(active ? Theme.accent : Theme.inkDim)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
        let text = keyboard.filterText.isEmpty
            ? "No worktrees in \(keyboard.category.title)"
            : "No worktrees match \"\(keyboard.filterText)\" in \(keyboard.category.title)"
        return Text(text)
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
                shortcutGroup("Navigate", [("j / k", "move down / up"), ("h / l", "move left / right"), ("Enter", "open in Zed")])
                shortcutGroup("Actions", [("o", "open in Zed"), ("m", "open in cmux"), ("w", "open running instance"), ("s", "start / stop"), ("r", "rebase"), ("a", "ask Claude"), ("i", "details"), ("L", "logs"), ("c", "copy path"), ("f", "follow a link (PR/runbot/task)")])
                shortcutGroup("Categories", [("1", "In Progress"), ("2", "Done"), ("3", "Standard"), ("4", "All")])
                shortcutGroup("Other", [("x", "delete"), ("D", "drop DB"), ("/", "filter (name/branch/desc)"), ("n", "new worktree"), ("d", "toggle digest page"), ("t", "toggle search page"), ("?", "toggle this"), ("Esc", "close")])
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
            Text("Check that the worktree registry is readable (see Settings → Paths)")
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
