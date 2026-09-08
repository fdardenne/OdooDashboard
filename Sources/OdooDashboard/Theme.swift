import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// A soft, light, self-contained palette -- forced regardless of system
/// appearance (see .preferredColorScheme(.light) on the content view),
/// mirroring the web dashboard's token set 1:1 so both surfaces read as the
/// same product.
enum Theme {
    static let panel = Color(hex: 0xfbfbfa)
    static let row = Color(hex: 0xf2f2f0)
    static let rowHover = Color(hex: 0xeaeae7)
    static let ink = Color(hex: 0x1c1e22)
    static let inkDim = Color(hex: 0x6b6e74)
    static let rule = Color(hex: 0xe4e2dc)
    static let ruleStrong = Color(hex: 0xd6d0c0)

    static let accent = Color(hex: 0x2e3a66)
    static let accentHover = Color(hex: 0x232c4f)
    static let accentBg = Color(hex: 0xeceef4)
    static let accentBorder = Color(hex: 0xccd1e2)

    /// Vivid and deliberately distinct from `accent` (used all over for
    /// primary buttons/badges) so keyboard focus reads unambiguously at a
    /// glance instead of blending into the rest of the UI.
    static let focusRing = Color(hex: 0x0a84ff)

    static let green = Color(hex: 0x1f9a47)
    static let greenBg = Color(hex: 0xe9f6ec)
    static let greenBorder = Color(hex: 0xbce3c6)

    static let red = Color(hex: 0xe53e3e)
    static let redBg = Color(hex: 0xfbebec)
    static let redBorder = Color(hex: 0xf1c3c6)

    static let yellow = Color(hex: 0xd89a00)
    static let yellowBg = Color(hex: 0xfff3d9)
    static let yellowBorder = Color(hex: 0xf2dda0)

    static let blue = Color(hex: 0x2f7df2)
    static let blueBg = Color(hex: 0xeaf1fd)
    static let blueBorder = Color(hex: 0xc2d7f7)

    static let gray = Color(hex: 0x9a9a94)
    static let grayBg = Color(hex: 0xeeece4)

    static func color(for rail: RailColor) -> Color {
        switch rail {
        case .red: return red
        case .blue: return blue
        case .green: return green
        case .gray: return gray
        }
    }

    /// checkmark = approved/clean, clock = pending/in-progress, exclamation =
    /// needs attention, minus = nothing to report yet.
    static func icon(for rail: RailColor) -> String {
        switch rail {
        case .red: return "exclamationmark"
        case .blue: return "clock.fill"
        case .green: return "checkmark"
        case .gray: return "minus"
        }
    }
}
