import Foundation

/// Ports packages/core/src/launchJson.ts -- writes .vscode/settings.json
/// (fixed content) and .vscode/launch.json (3 debug configurations) into a
/// worktree root, regenerated whenever install/update modules change.
enum LaunchJsonWriter {
    // [String: Any] isn't Sendable, but this dictionary is a fixed literal
    // never mutated after initialization -- safe to share across tasks.
    nonisolated(unsafe) private static let settingsJson: [String: Any] = [
        "[javascript]": ["editor.defaultFormatter": "dbaeumer.vscode-eslint"],
        "esbonio.sphinx.confDir": "",
        "[python]": ["editor.defaultFormatter": "ms-python.flake8"],
        "python.formatting.provider": "none",
        "python.languageServer": "None",
        "eslint.trace.server": "verbose",
        "Odoo.selectedConfiguration": "1",
        "Odoo.selectedProfile": "default",
        "workbench.editor.tabSizing": "fixed",
        "python-envs.pythonProjects": [],
        "python-envs.defaultEnvManager": "ms-python.python:system",
        "search.mode": "reuseEditor",
        "search.searchEditor.focusResultsOnSearch": true,
        "search.searchOnType": false,
    ]

    private static func buildLaunchJson(_ entry: RegistryEntry) -> [String: Any] {
        var addonsPath = ["${workspaceFolder}/odoo/addons", "${workspaceFolder}/enterprise"]
        if entry.repos["design-themes"] != nil { addonsPath.append("${workspaceFolder}/design-themes") }

        var upgradePath: [String] = []
        if entry.repos["upgrade"] != nil { upgradePath.append("${workspaceFolder}/upgrade/migrations") }
        if entry.repos["upgrade-util"] != nil { upgradePath.append("${workspaceFolder}/upgrade-util/src") }

        var baseArgs = [
            "--database=\(entry.db)",
            "--http-port=\(entry.port)",
            "--http-interface=127.0.0.1",
            "--addons-path=\(addonsPath.joined(separator: ","))",
        ]
        if !upgradePath.isEmpty {
            baseArgs.append("--upgrade-path=\(upgradePath.joined(separator: ","))")
        }

        let common: [String: Any] = [
            "type": "debugpy",
            "request": "launch",
            "cwd": "${workspaceFolder}",
            "program": "odoo/odoo-bin",
            "justMyCode": false,
            "pythonArgs": ["-Xfrozen_modules=off"],
            "env": ["PYDEVD_DISABLE_FILE_VALIDATION": "1"],
            "python": entry.interpreter,
            "console": "integratedTerminal",
        ]

        func config(_ name: String, extraArgs: [String]) -> [String: Any] {
            var c = common
            c["name"] = "Odoo [\(entry.name)]: \(name)"
            c["args"] = baseArgs + extraArgs
            return c
        }

        let configurations: [[String: Any]] = [
            config("Start Server", extraArgs: [
                "--dev=all,xml", "--limit-time-real=100000", "--with-demo",
                "--update=${input:update}", "--init=${input:install}",
            ]),
            config("Start Test", extraArgs: [
                "--dev=all", "--init=${input:install}", "--update=${input:install}",
                "--limit-time-real=100000", "--test-tags=${input:testTags}",
                "--stop-after-init", "--log-web",
            ]),
            config("Start server without database update", extraArgs: [
                "--dev=all", "--limit-time-real=100000",
            ]),
        ]

        let inputs: [[String: Any]] = [
            ["id": "update", "type": "promptString", "description": "Modules to update", "default": entry.updateModules],
            ["id": "install", "type": "promptString", "description": "Modules to install", "default": entry.installModules],
            ["id": "testTags", "type": "promptString", "description": "Test tags", "default": "/module:class.method"],
        ]

        return ["version": "0.2.0", "configurations": configurations, "inputs": inputs]
    }

    static func write(worktreeRoot: URL, entry: RegistryEntry) {
        let vscodeDir = worktreeRoot.appendingPathComponent(".vscode")
        try? FileManager.default.createDirectory(at: vscodeDir, withIntermediateDirectories: true)

        if let data = try? JSONSerialization.data(withJSONObject: settingsJson, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: vscodeDir.appendingPathComponent("settings.json"))
        }
        let launchJson = buildLaunchJson(entry)
        if let data = try? JSONSerialization.data(withJSONObject: launchJson, options: [.prettyPrinted]) {
            try? data.write(to: vscodeDir.appendingPathComponent("launch.json"))
        }
    }
}
