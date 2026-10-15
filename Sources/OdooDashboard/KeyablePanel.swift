import AppKit

/// A plain borderless+nonactivatingPanel NSPanel measured `canBecomeKey ==
/// false` in this app (confirmed via direct logging) -- despite Apple's docs
/// implying nonactivatingPanel alone is enough for a panel to accept key
/// status, in practice it never actually became key here, so nothing typed
/// into any field it hosted ever really landed (first responder could be
/// *assigned* via makeFirstResponder, but with isKeyWindow permanently
/// false, AppKit never routes keystrokes to it). Overriding canBecomeKey
/// unconditionally is the standard fix for a borderless panel that still
/// needs real keyboard input.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
