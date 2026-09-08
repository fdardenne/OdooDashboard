import Foundation

/// Configurable paths/constants, backed by UserDefaults (see AppSettings /
/// SettingsKeys) so this app can be shared to another machine without source
/// edits -- read synchronously from anywhere, including non-MainActor
/// backend code, since UserDefaults is thread-safe by contract.
enum Config {
    private static var defaults: UserDefaults { .standard }

    private static func path(_ key: String, default def: String) -> URL {
        let raw = defaults.string(forKey: key) ?? def
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
    }

    static var odooWorkspace: URL { path(SettingsKeys.odooWorkspacePath, default: SettingsKeys.Defaults.odooWorkspacePath) }
    static var worktreesRoot: URL { path(SettingsKeys.worktreesRootPath, default: SettingsKeys.Defaults.worktreesRootPath) }
    static var dataDir: URL { path(SettingsKeys.dataDirPath, default: SettingsKeys.Defaults.dataDirPath) }
    static var logsDir: URL { dataDir.appendingPathComponent("logs") }
    static var registryPath: URL { dataDir.appendingPathComponent("registry.json") }
    static var secretsPath: URL { dataDir.appendingPathComponent("secrets.json") }

    static var interpreters: [InterpreterMapping] { SettingsKeys.decodeInterpreters(defaults.string(forKey: SettingsKeys.interpretersJson)) }
    static var defaultInterpreterPath: String { defaults.string(forKey: SettingsKeys.defaultInterpreterPath) ?? "" }

    static var trigram: String { defaults.string(forKey: SettingsKeys.trigram) ?? SettingsKeys.Defaults.trigram }

    static var worktreeRepos: [String] {
        SettingsKeys.parseList(defaults.string(forKey: SettingsKeys.worktreeRepos) ?? SettingsKeys.Defaults.worktreeRepos)
    }
    static var requiredRepos: [String] {
        SettingsKeys.parseList(defaults.string(forKey: SettingsKeys.requiredRepos) ?? SettingsKeys.Defaults.requiredRepos)
    }

    static let basePort = 8069
    static let portRangeSize = 1000

    static var defaultInstallModules: String { defaults.string(forKey: SettingsKeys.defaultInstallModules) ?? SettingsKeys.Defaults.defaultInstallModules }
    static var defaultUpdateModules: String { defaults.string(forKey: SettingsKeys.defaultUpdateModules) ?? SettingsKeys.Defaults.defaultUpdateModules }

    // Not worth exposing as settings -- the same for essentially every Odoo
    // dev setup, and only ever used to build GitHub URLs/gh CLI args.
    static let githubForkOwner = "odoo-dev"
    static let githubUpstreamOwner = "odoo"

    static var odooApiKey: String { defaults.string(forKey: SettingsKeys.odooApiKey) ?? "" }
}
