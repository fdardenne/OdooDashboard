import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// Owns the status item and a manually-positioned NSPanel for the dropdown.
/// SwiftUI's MenuBarExtra(.window) anchors its popover to the status item, so
/// a screen-wide panel would extend leftward from an icon near the right edge
/// of the screen and clip off-screen -- managing the window ourselves lets it
/// sit centered under the menu bar regardless of where the icon is.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var hotKeyTap: CFMachPort?
    private var hotKeyRunLoopSource: CFRunLoopSource?
    private var cancellable: AnyCancellable?
    private var settingsWindow: NSWindow?
    let store = WorktreeStore()
    let keyboard = KeyboardController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Forces AppSettings' one-time secrets.json -> UserDefaults migration
        // to run now, before anything (e.g. OdooTaskClient) reads Config's
        // UserDefaults-backed values -- otherwise it wouldn't happen until
        // whatever first touches AppSettings.shared, which could be as late
        // as the first keypress.
        _ = AppSettings.shared
        store.start()
        installStandardEditMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.odooIcon(alert: false)
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        cancellable = store.$worktrees.sink { [weak self] _ in
            self?.updateStatusIcon()
        }

        installHotKeyTap()
    }

    /// An accessory app with no visible menu bar of its own still needs a
    /// real NSApp.mainMenu for standard Cmd+C/X/V/A (and Cmd+Z, though
    /// SwiftUI's TextField undo support on macOS is inconsistent regardless)
    /// to work in text fields -- without an Edit menu somewhere carrying
    /// those key equivalents, AppKit never routes them to the focused field
    /// editor at all, no matter how the field itself is built.
    private func installStandardEditMenu() {
        let mainMenu = NSMenu()

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    /// Bare "$" (Shift+4 on a US layout, no other modifier) toggles the
    /// dropdown from anywhere, and must not also type "$" into whatever was
    /// focused. NSEvent.addGlobalMonitorForEvents can only *observe* events
    /// system-wide, never consume them -- the keystroke still reaches the
    /// frontmost app. A CGEventTap can actually intercept and swallow it by
    /// returning nil from the callback, but that requires Accessibility
    /// permission (not just Input Monitoring), granted manually via
    /// System Settings -> Privacy & Security -> Accessibility, since this
    /// self-signed local build can't reliably self-trigger that consent
    /// dialog either.
    private func installHotKeyTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, cgEvent, refcon in
                guard let refcon else { return Unmanaged.passRetained(cgEvent) }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                return appDelegate.handleTapEvent(type: type, cgEvent: cgEvent, tap: appDelegate.hotKeyTap)
            },
            userInfo: selfPtr
        ) else {
            // Not authorized yet (or tap creation failed) -- leave it
            // uninstalled; the shortcut simply won't fire until the app is
            // added to Accessibility and relaunched.
            return
        }
        hotKeyTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        hotKeyRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleTapEvent(type: CGEventType, cgEvent: CGEvent, tap: CFMachPort?) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(cgEvent)
        }
        guard type == .keyDown, let nsEvent = NSEvent(cgEvent: cgEvent), consumeKeyEvent(nsEvent) else {
            return Unmanaged.passRetained(cgEvent)
        }
        return nil
    }

    // MARK: - Keyboard routing

    /// Top-level router for every intercepted keydown. Bare "$" always
    /// toggles the panel (unless a text field somewhere has focus, so you
    /// can still type a literal "$"). Once the panel is open, everything
    /// else is vim-style: h/j/k/l move focus between cards, single letters
    /// trigger actions on the focused card, "/" filters, "?" shows the
    /// cheat sheet. Native controls (our own text fields, the create sheet,
    /// confirmation dialogs) are left completely alone -- we back off
    /// rather than compete with them for keystrokes.
    private func consumeKeyEvent(_ event: NSEvent) -> Bool {
        let panelOpen = panel?.isVisible ?? false

        if panelOpen && isTextFieldActive {
            return false
        }

        if AppSettings.shared.toggleShortcut.matches(event) {
            togglePanel()
            return true
        }

        guard panelOpen else { return false }
        if keyboard.hasModalOpen { return false }
        if keyboard.linkMode { return handleLinkModeKey(event) }
        if keyboard.isFiltering { return handleFilterTyping(event) }
        return handlePanelShortcut(event)
    }

    private var isTextFieldActive: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    private func handlePanelShortcut(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape: undo the most specific thing that's open first.
            if keyboard.showShortcuts {
                keyboard.showShortcuts = false
            } else if keyboard.page != .worktrees {
                keyboard.page = .worktrees
            } else if !keyboard.filterText.isEmpty {
                keyboard.filterText = ""
                keyboard.clampFocus(to: store.worktrees)
            } else {
                closePanel()
            }
            return true
        case 36, 76: // Return / keypad enter -- primary action.
            if keyboard.page == .worktrees { performAction(.open) }
            return true
        default:
            break
        }

        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
              let chars = event.charactersIgnoringModifiers else { return false }

        // These work regardless of which page is showing.
        switch chars {
        case "d":
            keyboard.page = keyboard.page == .digest ? .worktrees : .digest
            return true
        case "t":
            keyboard.page = keyboard.page == .search ? .worktrees : .search
            return true
        case "?":
            keyboard.showShortcuts.toggle()
            return true
        default:
            break
        }
        guard keyboard.page == .worktrees else { return false }

        switch chars {
        case "j": moveFocus(rowDelta: 1)
        case "k": moveFocus(rowDelta: -1)
        case "h": moveFocus(colDelta: -1)
        case "l": moveFocus(colDelta: 1)
        case "o": performAction(.open)
        case "m": performAction(.openCmux)
        case "w": performAction(.openBrowser)
        case "s": performAction(.toggleRun)
        case "r": performAction(.rebase)
        case "a": performAction(.askClaude)
        case "i": performAction(.toggleDetails)
        case "L": performAction(.toggleLogs)
        case "x": performAction(.delete)
        case "D": performAction(.dropDb)
        case "c": performAction(.copyPath)
        case "f": enterLinkMode()
        case "1": switchCategory(.main)
        case "2": switchCategory(.archived)
        case "3": switchCategory(.standard)
        case "4": switchCategory(.all)
        case "/":
            keyboard.isFiltering = true
            keyboard.filterText = ""
        case "n":
            keyboard.showCreate = true
        default:
            return false
        }
        return true
    }

    private func handleFilterTyping(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape cancels the filter entirely.
            keyboard.isFiltering = false
            keyboard.filterText = ""
            keyboard.clampFocus(to: store.worktrees)
            return true
        case 36, 76: // Return confirms and exits typing mode, filter stays applied.
            keyboard.isFiltering = false
            return true
        case 51: // Backspace/Delete.
            if !keyboard.filterText.isEmpty { keyboard.filterText.removeLast() }
            keyboard.clampFocus(to: store.worktrees)
            return true
        default:
            break
        }
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           let chars = event.characters, !chars.isEmpty {
            keyboard.filterText += chars
            keyboard.clampFocus(to: store.worktrees)
        }
        return true // swallow everything while filtering so nothing leaks through as a shortcut
    }

    // MARK: - Link-follow mode ("f")

    /// Enters link-follow mode on the focused card: its badges (odoo/
    /// enterprise/upgrade PRs, runbot, task) show numbered hints, and the
    /// next digit pressed opens that one -- a scoped-down version of
    /// Vimium's link hints, reusing StatusLogic.badgeSpecs as the single
    /// source of truth so the numbers always match what's on screen.
    private func enterLinkMode() {
        guard let name = keyboard.focusedName,
              let entry = store.worktrees.first(where: { $0.name == name }),
              StatusLogic.badgeSpecs(for: entry).contains(where: { $0.url != nil }) else { return }
        keyboard.linkMode = true
    }

    private func handleLinkModeKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape cancels without opening anything.
            keyboard.linkMode = false
            return true
        }
        guard let name = keyboard.focusedName,
              let entry = store.worktrees.first(where: { $0.name == name }) else {
            keyboard.linkMode = false
            return false
        }
        if let chars = event.charactersIgnoringModifiers,
           let target = StatusLogic.badgeSpecs(for: entry).first(where: { $0.hintKey == chars }),
           let url = target.url {
            keyboard.linkMode = false
            NSWorkspace.shared.open(url)
            return true
        }
        // Not a valid hint digit -- exit link mode and let this same
        // keystroke be handled normally instead of silently eating it.
        keyboard.linkMode = false
        return handlePanelShortcut(event)
    }

    // MARK: - Focus movement & actions

    private enum QuickAction { case open, openCmux, openBrowser, toggleRun, rebase, askClaude, toggleDetails, toggleLogs, delete, dropDb, copyPath }

    private func performAction(_ action: QuickAction) {
        guard let name = keyboard.focusedName,
              let entry = store.worktrees.first(where: { $0.name == name }) else { return }
        switch action {
        case .open:
            store.run(name, action: "open")
        case .openCmux:
            store.run(name, action: "open-cmux")
        case .openBrowser:
            guard entry.running, let url = URL(string: "http://localhost:\(entry.port)") else { return }
            NSWorkspace.shared.open(url)
        case .toggleRun:
            store.run(name, action: entry.running ? "stop" : "start")
        case .rebase:
            if StatusLogic.isOfficialVersionBranch(name) {
                Task { keyboard.rebaseReports[name] = await store.pull(name) }
            } else {
                Task { keyboard.rebaseReports[name] = await store.rebase(name) }
            }
        case .askClaude:
            store.askClaude(name)
        case .toggleDetails:
            keyboard.toggleDetails(name)
        case .toggleLogs:
            keyboard.toggleLogs(name)
        case .delete:
            guard !store.isBusy(name, "delete") else { return }
            keyboard.pendingDeleteConfirm = name
        case .dropDb:
            guard !entry.running, !store.isBusy(name, "dropdb") else { return }
            keyboard.pendingDropDbConfirm = name
        case .copyPath:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(Config.worktreesRoot.appendingPathComponent(name).path, forType: .string)
            keyboard.markCopied(name)
        }
    }

    private func switchCategory(_ category: WorktreeCategory) {
        keyboard.category = category
        keyboard.clampFocus(to: store.worktrees)
    }

    private func moveFocus(rowDelta: Int = 0, colDelta: Int = 0) {
        let entries = keyboard.filteredEntries(from: store.worktrees)
        guard !entries.isEmpty else { return }
        guard let currentName = keyboard.focusedName,
              let currentIndex = entries.firstIndex(where: { $0.name == currentName }) else {
            keyboard.focusedName = entries[0].name
            return
        }
        let delta = rowDelta * currentColumns() + colDelta
        let newIndex = min(max(currentIndex + delta, 0), entries.count - 1)
        keyboard.focusedName = entries[newIndex].name
    }

    /// Mirrors the grid's own math (GridItem(.adaptive(minimum: 380, ...))
    /// inside MenuBarContentView's 18pt-padded ScrollView) so h/j/k/l land
    /// on the visually adjacent card, not just the next one in list order.
    private func currentColumns() -> Int {
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return 1 }
        let panelWidth = screen.visibleFrame.width - 48
        let contentWidth = panelWidth - 36
        let columns = Int((contentWidth + 14) / (380 + 14))
        return max(1, columns)
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let needsAttention = store.worktrees.contains { $0.railColor == .red }
        button.image = Self.odooIcon(alert: needsAttention)
    }

    /// A plain custom-drawn ring ("stadium O") -- minimal, abstract, safe.
    /// Drawn as a template image so AppKit renders it in the menu bar's own
    /// monochrome tint, adapting to light/dark automatically.
    private static func odooIcon(alert: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let w = rect.width
            let stroke = w * 0.20
            let inset = stroke / 2 + w * 0.10
            let ringRect = rect.insetBy(dx: inset, dy: inset)
            let ring = NSBezierPath(roundedRect: ringRect, xRadius: ringRect.width / 2, yRadius: ringRect.height / 2)
            ring.lineWidth = stroke
            NSColor.black.setStroke()
            ring.stroke()

            if alert {
                let dotRect = NSRect(x: rect.maxX - 5, y: rect.minY, width: 4, height: 4)
                NSColor.black.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent, event.type == .rightMouseUp else {
            togglePanel()
            return
        }
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Odoo Dashboard", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        // Assigning a menu makes NSStatusItem show it immediately in place of
        // firing our action -- detach it right after so plain clicks keep
        // going through statusItemClicked instead of always popping this up.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        // The dropdown panel sits at .popUpMenu level (above normal windows)
        // so it can visually cover the Settings window if left open.
        closePanel()

        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: AppSettings.shared))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Odoo Dashboard Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        // AppKit auto-focuses the first key-view-loop text field on activation
        // -- undesirable here since a stray keystroke would silently edit a
        // path/token field with no reliable undo. Explicitly clear focus
        // right after, once the window has finished claiming it.
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindow?.makeFirstResponder(nil)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func togglePanel() {
        if let panel, panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        // NSScreen.main is "whichever screen has the key window" and is
        // unreliable with no window yet open -- on a multi-monitor setup it
        // can resolve to a screen the status item isn't even on. Derive the
        // screen from the status item's own button instead, which is always
        // rendered on the screen with the actual menu bar.
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let width = visible.width - 48
        let height = visible.height * 0.5

        let frame = CGRect(x: 0, y: 0, width: width, height: height)

        // NSGlassEffectView is macOS 26's actual "Liquid Glass" material --
        // more transparent and less heavily frosted than the older
        // NSVisualEffectView vibrancy materials, which is what was making the
        // panel look too blurred. Needs to be part of the real window's
        // contentView hierarchy (not wrapped through SwiftUI's .background())
        // to correctly sample what's behind the window.
        let glassView = NSGlassEffectView(frame: frame)
        glassView.style = .clear
        glassView.cornerRadius = 16
        glassView.tintColor = NSColor(Theme.panel).withAlphaComponent(0.7)

        keyboard.reset()
        keyboard.clampFocus(to: store.worktrees)

        let content = MenuBarContentView(panelWidth: width, panelHeight: height)
            .environmentObject(store)
            .environmentObject(keyboard)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = frame
        glassView.contentView = hosting

        let newPanel = KeyablePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.contentView = glassView
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.level = .popUpMenu
        newPanel.isMovable = false
        newPanel.isReleasedWhenClosed = false

        // Centered under the menu bar, not anchored to the status icon.
        let x = visible.minX + (visible.width - width) / 2
        let y = visible.maxY - height - 8
        newPanel.setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)

        newPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = newPanel

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
