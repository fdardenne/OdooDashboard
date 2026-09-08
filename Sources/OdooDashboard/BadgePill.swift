import AppKit
import SwiftUI

/// A small colored status pill -- mirrors the web dashboard's .badge/.tone-*
/// classes. Opens `url` in the default browser when tapped, if given.
struct BadgePill: View {
    enum Tone { case green, red, yellow, blue, neutral }

    let text: String
    var tone: Tone = .neutral
    var url: URL? = nil
    var tooltip: String? = nil
    /// Shown as a small numbered badge in the corner while the card is in
    /// "f" link-follow mode -- press that digit to open this pill's URL.
    var hintKey: String? = nil

    @State private var hovering = false

    var body: some View {
        label
            .contentShape(Rectangle())
            .onHover { hovering = url != nil && $0 }
            .onTapGesture { if let url { NSWorkspace.shared.open(url) } }
            .help(tooltip ?? "")
            .overlay(alignment: .topTrailing) {
                if let hintKey {
                    Text(hintKey)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(minWidth: 13, minHeight: 13)
                        .background(Circle().fill(Theme.focusRing))
                        .offset(x: 6, y: -6)
                }
            }
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .foregroundStyle(foreground)
            .opacity(hovering ? 0.82 : 1)
    }

    private var background: Color {
        switch tone {
        case .green: return Theme.greenBg
        case .red: return Theme.redBg
        case .yellow: return Theme.yellowBg
        case .blue: return Theme.blueBg
        case .neutral: return Theme.grayBg
        }
    }

    private var foreground: Color {
        switch tone {
        case .green: return Theme.green
        case .red: return Theme.red
        case .yellow: return Theme.yellow
        case .blue: return Theme.blue
        case .neutral: return Theme.inkDim
        }
    }

    private var border: Color {
        switch tone {
        case .green: return Theme.greenBorder
        case .red: return Theme.redBorder
        case .yellow: return Theme.yellowBorder
        case .blue: return Theme.blueBorder
        case .neutral: return .clear
        }
    }
}
