import AppKit
import SwiftUI

// Dev-only preview path: renders the dropdown's actual SwiftUI view tree
// straight to a PNG via ImageRenderer, with no screen-capture APIs involved --
// useful for visual review in a sandbox with no Screen Recording permission.
// Remove this file (and restore `@main` on OdooDashboardApp) once no longer needed.
if CommandLine.arguments.contains("--preview") {
    Task { @MainActor in
        _ = AppSettings.shared // trigger secrets.json migration, matching real app startup
        let store = WorktreeStore()
        let keyboard = KeyboardController()
        if let catArg = CommandLine.arguments.first(where: { $0.hasPrefix("--category=") }),
           let rawValue = Int(catArg.replacingOccurrences(of: "--category=", with: "")),
           let cat = WorktreeCategory(rawValue: rawValue) {
            keyboard.category = cat
        }
        await store.refresh() // already awaits full enrichment before returning
        try? await Task.sleep(nanoseconds: 500_000_000)
        FileHandle.standardError.write("worktrees: \(store.worktrees.count), reachable: \(store.serverReachable)\n".data(using: .utf8)!)
        for entry in store.worktrees {
            FileHandle.standardError.write("- \(entry.name): port=\(entry.port) running=\(entry.running) pr=\(entry.pr.compactMap { $0 }.count) runbot=\(entry.runbot != nil) task=\(entry.odooTask != nil) repos=\(entry.repos.keys.sorted())\n".data(using: .utf8)!)
        }
        // ImageRenderer can't lay out ScrollView content (no real viewport to
        // size against) -- swap it for a plain grid, preview-only, purely to
        // visually QA the header/card styling. The real app's ScrollView is
        // already confirmed working via the live Accessibility-tree dump.
        let previewWidth: CGFloat = 1680 // approximates this Mac's built-in display, screen width - 48
        let view = VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("~/odoo-dashboard")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)

            HStack(spacing: 4) {
                ForEach(WorktreeCategory.allCases, id: \.self) { cat in
                    let count = store.worktrees.filter { WorktreeCategory.matches(cat, $0) }.count
                    Text("\(cat.title) \(count) [\(cat.rawValue)]")
                        .font(.system(size: 12, weight: cat == keyboard.category ? .bold : .regular, design: .monospaced))
                        .foregroundStyle(cat == keyboard.category ? Theme.accent : Theme.inkDim)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 380, maximum: 460), spacing: 14)], spacing: 14) {
                ForEach(store.worktrees.filter { WorktreeCategory.matches(keyboard.category, $0) }) { entry in
                    WorktreeCardView(entry: entry).environmentObject(store).environmentObject(keyboard)
                }
            }
            .padding(18)
        }
        .frame(width: previewWidth)
        .background(Theme.panel)
        .preferredColorScheme(.light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        if let nsImage = renderer.nsImage,
            let tiff = nsImage.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:]) {
            let path = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/preview.png"
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        } else {
            print("render failed")
        }
        exit(0)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(40))
} else {
    // NSApplication.delegate is weak -- keep a strong local reference so it
    // isn't deallocated immediately after assignment. It stays alive for the
    // whole run() call since both share this block's scope.
    let appDelegate: AppDelegate = MainActor.assumeIsolated { AppDelegate() }
    MainActor.assumeIsolated {
        NSApplication.shared.delegate = appDelegate
    }
    NSApplication.shared.run()
}
