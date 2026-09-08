import AppKit
import SwiftUI

/// Click, then press a key combo -- captures the next non-empty keydown sent
/// to this window as the new shortcut. Only listens while actively
/// recording, via a local monitor (no Accessibility/Input Monitoring
/// permission needed, unlike the app's global toggle shortcut itself).
struct ShortcutRecorderView: View {
    @Binding var combo: KeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stopRecording() : startRecording()
        } label: {
            Text(recording ? "Press a key…" : combo.displayString)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .frame(minWidth: 100)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(recording ? Theme.accentBg : Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(recording ? Theme.accent : Theme.ruleStrong, lineWidth: 1))
                .foregroundStyle(Theme.ink)
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return nil }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            combo = KeyCombo(keyEquivalent: chars, modifiers: mods.rawValue)
            stopRecording()
            return nil // swallow it -- don't let the captured key also act normally
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
