import SwiftUI

/// A labeled, hoverable pill button matching the web dashboard's <button>
/// styling -- text + optional icon, darkens on hover, tone-able.
struct ActionButton: View {
    enum Style { case plain, primary, success, danger }

    let title: String
    var icon: String? = nil
    var style: Style = .plain
    var isDisabled: Bool = false
    /// Single-key shortcut shown as a small "keycap" badge, e.g. "o" or "⏎".
    var hint: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.system(size: 12.5, weight: .medium))
                if let hint {
                    Text(hint)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(foreground.opacity(0.15)))
                        .foregroundStyle(foreground.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(background))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border, lineWidth: 1))
            .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        switch style {
        case .plain: return hovering ? Theme.accentBg : Theme.panel
        case .primary: return hovering ? Theme.accentHover : Theme.accent
        case .success: return hovering ? Theme.green : Theme.greenBg
        case .danger: return hovering ? Theme.red : Theme.redBg
        }
    }

    private var foreground: Color {
        switch style {
        case .plain: return hovering ? Theme.accent : Theme.ink
        case .primary: return .white
        case .success: return hovering ? .white : Theme.green
        case .danger: return hovering ? .white : Theme.red
        }
    }

    private var border: Color {
        switch style {
        case .plain: return hovering ? Theme.accent : Theme.ruleStrong
        case .primary: return Theme.accent
        case .success: return Theme.greenBorder
        case .danger: return Theme.redBorder
        }
    }
}
