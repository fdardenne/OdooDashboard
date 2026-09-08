import AppKit
import Foundation

/// A recorded keyboard shortcut: a character plus the exact modifier set
/// required (no more, no less) to avoid accidental collisions with whatever
/// else those keys might mean.
struct KeyCombo: Equatable {
    var keyEquivalent: String
    var modifiers: UInt // NSEvent.ModifierFlags rawValue, restricted to command/option/control/shift

    static let `default` = KeyCombo(keyEquivalent: "$", modifiers: NSEvent.ModifierFlags.shift.rawValue)

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    func matches(_ event: NSEvent) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return event.charactersIgnoringModifiers == keyEquivalent
            && event.modifierFlags.intersection(relevant) == modifierFlags
    }

    /// Human-readable form, e.g. "⌘⇧O" or "$".
    var displayString: String {
        var parts = ""
        if modifierFlags.contains(.control) { parts += "⌃" }
        if modifierFlags.contains(.option) { parts += "⌥" }
        if modifierFlags.contains(.shift) && keyEquivalent.count == 1 && keyEquivalent.first!.isLetter {
            // For plain letters, showing both a leading Shift glyph and the
            // shifted character is redundant chatter -- do it only for
            // producible symbols like "$" that inherently require Shift and
            // have no separate glyph to show.
            parts += "⇧"
        }
        if modifierFlags.contains(.command) { parts += "⌘" }
        parts += keyEquivalent.uppercased()
        return parts
    }
}

/// One Odoo version mapped to the Python interpreter that should run it --
/// explicit and tool-agnostic, rather than assuming everyone uses the same
/// third-party virtualenv-management convention this machine happens to.
struct InterpreterMapping: Codable, Identifiable, Equatable {
    var id = UUID()
    var version: String
    var path: String
}

/// UserDefaults keys and their default values -- shared between AppSettings
/// (the MainActor/SwiftUI-facing side, used by the Settings UI and
/// AppDelegate) and Config (read synchronously from anywhere, including
/// non-MainActor backend code, since UserDefaults itself is thread-safe).
/// Defaults match this machine's pre-existing hardcoded values, so nothing
/// changes here until something is actually edited in Settings.
enum SettingsKeys {
    static let odooWorkspacePath = "odooWorkspacePath"
    static let worktreesRootPath = "worktreesRootPath"
    static let dataDirPath = "dataDirPath"
    static let trigram = "trigram"
    static let worktreeRepos = "worktreeRepos"
    static let requiredRepos = "requiredRepos"
    static let odooApiKey = "odooApiKey"
    static let defaultInstallModules = "defaultInstallModules"
    static let defaultUpdateModules = "defaultUpdateModules"
    static let shortcutKeyEquivalent = "shortcutKeyEquivalent"
    static let shortcutModifiers = "shortcutModifiers"
    static let interpretersJson = "interpretersJson"
    static let defaultInterpreterPath = "defaultInterpreterPath"
    static let didMigrateSecrets = "didMigrateSecretsJson"
    static let didMigrateVirtualenvs = "didMigrateVirtualenvs"

    enum Defaults {
        static let odooWorkspacePath = "~/Desktop/odoo_workspace"
        static let worktreesRootPath = "~/Desktop/odoo-worktrees"
        static let dataDirPath = "~/Library/Application Support/Odoo Dashboard"
        static let trigram = "dafl"
        static let worktreeRepos = "odoo,enterprise,upgrade,design-themes,upgrade-util"
        static let requiredRepos = "odoo,enterprise"
        static let defaultInstallModules = "l10n_be_hr_payroll"
        static let defaultUpdateModules = "l10n_be_hr_payroll"
    }

    static func parseList(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func decodeInterpreters(_ raw: String?) -> [InterpreterMapping] {
        guard let raw, let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([InterpreterMapping].self, from: data) else { return [] }
        return list
    }

    static func encodeInterpreters(_ list: [InterpreterMapping]) -> String {
        (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}

/// SwiftUI-facing settings object (Settings window, AppDelegate's shortcut
/// matching). The actual source of truth is UserDefaults -- this just wraps
/// it in @Published properties for binding/reactivity. Backend code that
/// isn't MainActor-isolated reads the same UserDefaults directly via Config,
/// so both sides always agree without needing to hop actors.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var odooWorkspacePath: String { didSet { defaults.set(odooWorkspacePath, forKey: SettingsKeys.odooWorkspacePath) } }
    @Published var worktreesRootPath: String { didSet { defaults.set(worktreesRootPath, forKey: SettingsKeys.worktreesRootPath) } }
    @Published var dataDirPath: String { didSet { defaults.set(dataDirPath, forKey: SettingsKeys.dataDirPath) } }
    @Published var trigram: String { didSet { defaults.set(trigram, forKey: SettingsKeys.trigram) } }
    @Published var worktreeReposRaw: String { didSet { defaults.set(worktreeReposRaw, forKey: SettingsKeys.worktreeRepos) } }
    @Published var requiredReposRaw: String { didSet { defaults.set(requiredReposRaw, forKey: SettingsKeys.requiredRepos) } }
    @Published var odooApiKey: String { didSet { defaults.set(odooApiKey, forKey: SettingsKeys.odooApiKey) } }
    @Published var defaultInstallModules: String { didSet { defaults.set(defaultInstallModules, forKey: SettingsKeys.defaultInstallModules) } }
    @Published var defaultUpdateModules: String { didSet { defaults.set(defaultUpdateModules, forKey: SettingsKeys.defaultUpdateModules) } }
    @Published var interpreters: [InterpreterMapping] { didSet { defaults.set(SettingsKeys.encodeInterpreters(interpreters), forKey: SettingsKeys.interpretersJson) } }
    @Published var defaultInterpreterPath: String { didSet { defaults.set(defaultInterpreterPath, forKey: SettingsKeys.defaultInterpreterPath) } }
    @Published var toggleShortcut: KeyCombo {
        didSet {
            defaults.set(toggleShortcut.keyEquivalent, forKey: SettingsKeys.shortcutKeyEquivalent)
            defaults.set(toggleShortcut.modifiers, forKey: SettingsKeys.shortcutModifiers)
        }
    }

    private init() {
        odooWorkspacePath = defaults.string(forKey: SettingsKeys.odooWorkspacePath) ?? SettingsKeys.Defaults.odooWorkspacePath
        worktreesRootPath = defaults.string(forKey: SettingsKeys.worktreesRootPath) ?? SettingsKeys.Defaults.worktreesRootPath
        dataDirPath = defaults.string(forKey: SettingsKeys.dataDirPath) ?? SettingsKeys.Defaults.dataDirPath
        trigram = defaults.string(forKey: SettingsKeys.trigram) ?? SettingsKeys.Defaults.trigram
        worktreeReposRaw = defaults.string(forKey: SettingsKeys.worktreeRepos) ?? SettingsKeys.Defaults.worktreeRepos
        requiredReposRaw = defaults.string(forKey: SettingsKeys.requiredRepos) ?? SettingsKeys.Defaults.requiredRepos
        odooApiKey = defaults.string(forKey: SettingsKeys.odooApiKey) ?? ""
        defaultInstallModules = defaults.string(forKey: SettingsKeys.defaultInstallModules) ?? SettingsKeys.Defaults.defaultInstallModules
        defaultUpdateModules = defaults.string(forKey: SettingsKeys.defaultUpdateModules) ?? SettingsKeys.Defaults.defaultUpdateModules
        interpreters = SettingsKeys.decodeInterpreters(defaults.string(forKey: SettingsKeys.interpretersJson))
        defaultInterpreterPath = defaults.string(forKey: SettingsKeys.defaultInterpreterPath) ?? ""
        let keyEquivalent = defaults.string(forKey: SettingsKeys.shortcutKeyEquivalent) ?? KeyCombo.default.keyEquivalent
        let modifiers = defaults.object(forKey: SettingsKeys.shortcutModifiers) != nil ? UInt(defaults.integer(forKey: SettingsKeys.shortcutModifiers)) : KeyCombo.default.modifiers
        toggleShortcut = KeyCombo(keyEquivalent: keyEquivalent, modifiers: modifiers)

        migrateSecretsJsonIfNeeded()
        migrateVirtualenvsIfNeeded()
    }

    /// One-time import of an API key from the old secrets.json file (used
    /// before Settings existed), so upgrading doesn't lose it.
    private func migrateSecretsJsonIfNeeded() {
        guard !defaults.bool(forKey: SettingsKeys.didMigrateSecrets) else { return }
        defaults.set(true, forKey: SettingsKeys.didMigrateSecrets)
        guard odooApiKey.isEmpty else { return }
        let secretsPath = (dataDirPath as NSString).expandingTildeInPath + "/secrets.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: secretsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["odooApiKey"] as? String, !key.isEmpty else { return }
        odooApiKey = key
    }

    /// One-time import of this machine's old ~/odev/virtualenvs/<version>/bin/python
    /// convention into explicit per-version interpreter entries, so upgrading
    /// doesn't lose the interpreters this setup already had -- new installs
    /// on another machine just see an empty list and add their own.
    private func migrateVirtualenvsIfNeeded() {
        guard !defaults.bool(forKey: SettingsKeys.didMigrateVirtualenvs) else { return }
        defaults.set(true, forKey: SettingsKeys.didMigrateVirtualenvs)
        guard interpreters.isEmpty else { return }
        let legacyDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("odev/virtualenvs")
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: legacyDir.path) else { return }
        var found: [InterpreterMapping] = []
        for version in versions.sorted() {
            let pythonPath = legacyDir.appendingPathComponent(version).appendingPathComponent("bin/python")
            if FileManager.default.isExecutableFile(atPath: pythonPath.path) {
                found.append(InterpreterMapping(version: version, path: pythonPath.path))
            }
        }
        guard !found.isEmpty else { return }
        interpreters = found
    }
}
