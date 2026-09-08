import AppKit
import SwiftUI

/// Everything hardcoded to this one machine/person lives here instead, so
/// the app can be handed to someone else -- they just fill in their own
/// paths, GitHub identity, token, and preferred shortcut.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)

                section("Paths") {
                    pathField("Odoo workspace", subtitle: "Folder containing your base repo checkouts (odoo, enterprise, upgrade, ...)", text: $settings.odooWorkspacePath)
                    pathField("Worktrees folder", subtitle: "Where new worktrees are created", text: $settings.worktreesRootPath)
                    pathField("Data folder", subtitle: "Where the worktree registry and logs are stored", text: $settings.dataDirPath)
                }

                section("Repositories") {
                    textField("Repos to manage", subtitle: "Comma-separated, in addons-path order", text: $settings.worktreeReposRaw)
                    textField("Required repos", subtitle: "Worktree creation fails and rolls back if any of these fail", text: $settings.requiredReposRaw)
                }

                section("Python interpreters") {
                    Text("One interpreter per Odoo version -- however you manage your virtualenvs, just point each version at the python binary to use.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkDim)
                    interpreterRows
                    Button {
                        settings.interpreters.append(InterpreterMapping(version: "", path: ""))
                    } label: {
                        Label("Add version", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    Divider().background(Theme.rule)
                    pathField("Default interpreter (optional)", subtitle: "Used for any version without its own entry above", text: $settings.defaultInterpreterPath, chooseFiles: true)
                }

                section("Git") {
                    textField("Branch suffix", subtitle: "Your initials -- new branches are named <base>-<taskId>-<suffix>", text: $settings.trigram)
                }

                section("Odoo.com") {
                    secureField("API token", subtitle: "Used to show a linked task's name, stage, and status", text: $settings.odooApiKey)
                }

                section("Defaults for new worktrees") {
                    textField("Install modules", subtitle: nil, text: $settings.defaultInstallModules)
                    textField("Update modules", subtitle: nil, text: $settings.defaultUpdateModules)
                }

                section("Keyboard") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Toggle dropdown").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                            Text("Works from anywhere, even while another app is focused").font(.system(size: 11)).foregroundStyle(Theme.inkDim)
                        }
                        Spacer()
                        ShortcutRecorderView(combo: $settings.toggleShortcut)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 480, height: 680)
        .background(Theme.panel)
        .preferredColorScheme(.light)
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkDim)
                .tracking(0.5)
            VStack(alignment: .leading, spacing: 14) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.row))
        }
    }

    private func fieldLabel(_ label: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.inkDim)
            }
        }
    }

    private func boxed<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, design: .monospaced))
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ruleStrong, lineWidth: 1))
    }

    private func textField(_ label: String, subtitle: String?, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label, subtitle: subtitle)
            boxed { TextField("", text: text) }
        }
    }

    private func secureField(_ label: String, subtitle: String?, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label, subtitle: subtitle)
            boxed { SecureField("", text: text) }
        }
    }

    private func pathField(_ label: String, subtitle: String, text: Binding<String>, chooseFiles: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label, subtitle: subtitle)
            HStack(spacing: 8) {
                boxed { TextField("", text: text) }
                Button("Choose…") { choosePath(for: text, chooseFiles: chooseFiles) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ruleStrong, lineWidth: 1))
            }
        }
    }

    private func choosePath(for text: Binding<String>, chooseFiles: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = !chooseFiles
        panel.canChooseFiles = chooseFiles
        panel.allowsMultipleSelection = false
        let current = (text.wrappedValue as NSString).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: chooseFiles ? (current as NSString).deletingLastPathComponent : current)
        if panel.runModal() == .OK, let url = panel.url {
            text.wrappedValue = url.path
        }
    }

    /// Fixed choices for the common case; anything else (saas-X.Y, a custom
    /// label like a backup venv) stays reachable via "Custom…" so existing
    /// non-standard entries never get locked out of editing.
    private let standardVersions = ["master", "21.0", "20.0", "19.0", "18.0", "17.0", "16.0", "15.0"]

    private var interpreterRows: some View {
        ForEach($settings.interpreters) { $mapping in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    versionMenu(for: $mapping).frame(width: 150)
                    boxed { TextField("/path/to/bin/python", text: $mapping.path) }
                    Button("Choose…") { choosePath(for: $mapping.path, chooseFiles: true) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ruleStrong, lineWidth: 1))
                    Button {
                        settings.interpreters.removeAll { $0.id == mapping.id }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.red)
                    }
                    .buttonStyle(.plain)
                }
                if !standardVersions.contains(mapping.version) {
                    boxed { TextField("custom version, e.g. saas-18.2", text: $mapping.version) }
                }
            }
        }
    }

    private func versionMenu(for mapping: Binding<InterpreterMapping>) -> some View {
        let isStandard = standardVersions.contains(mapping.wrappedValue.version)
        return Menu {
            ForEach(standardVersions, id: \.self) { v in
                Button(v) { mapping.wrappedValue.version = v }
            }
            Divider()
            Button("Custom…") {
                if isStandard { mapping.wrappedValue.version = "" }
            }
        } label: {
            Text(mapping.wrappedValue.version.isEmpty ? "Choose…" : (isStandard ? mapping.wrappedValue.version : "Custom"))
                .font(.system(size: 12.5, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ruleStrong, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
    }
}
