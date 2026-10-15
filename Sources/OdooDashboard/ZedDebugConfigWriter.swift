import Foundation

/// Writes .zed/debug.json (3 debug configurations) into a worktree root,
/// regenerated whenever install/update modules change. Replaces the old
/// VS Code launch.json/settings.json generation now that this app opens
/// worktrees in Zed instead (see WorktreeStore's "open" action).
///
/// Zed's Debugpy adapter forwards launch config fields straight through to
/// debugpy's own DAP schema (confirmed against debugpy's documented fields:
/// program, args, env, cwd, console, justMyCode, python, stopOnEntry,
/// redirectOutput, subProcess) rather than VS Code Python extension's
/// wrapper fields -- notably "python" is `[interpreterPath, ...interpreter
/// args]` (an array), not a bare string, and there's no separate
/// "pythonArgs" field the way VS Code's launch.json has; the interpreter's
/// own flags (e.g. -Xfrozen_modules=off) go inside that same array. Zed also
/// has no confirmed equivalent of VS Code's `${input:...}` prompt
/// variables, so the install/update module lists are baked in directly
/// from the worktree's own installModules/updateModules rather than
/// prompted for on each launch.
enum ZedDebugConfigWriter {
    private static func baseArgs(_ entry: RegistryEntry) -> [String] {
        var addonsPath = ["${ZED_WORKTREE_ROOT}/odoo/addons", "${ZED_WORKTREE_ROOT}/enterprise"]
        if entry.repos["design-themes"] != nil { addonsPath.append("${ZED_WORKTREE_ROOT}/design-themes") }

        var upgradePath: [String] = []
        if entry.repos["upgrade"] != nil { upgradePath.append("${ZED_WORKTREE_ROOT}/upgrade/migrations") }
        if entry.repos["upgrade-util"] != nil { upgradePath.append("${ZED_WORKTREE_ROOT}/upgrade-util/src") }

        var args = [
            "--database=\(entry.db)",
            "--http-port=\(entry.port)",
            "--http-interface=127.0.0.1",
            "--addons-path=\(addonsPath.joined(separator: ","))",
        ]
        if !upgradePath.isEmpty {
            args.append("--upgrade-path=\(upgradePath.joined(separator: ","))")
        }
        return args
    }

    private static func config(_ name: String, entry: RegistryEntry, extraArgs: [String]) -> [String: Any] {
        [
            "label": "Odoo [\(entry.name)]: \(name)",
            "adapter": "Debugpy",
            "request": "launch",
            "cwd": "${ZED_WORKTREE_ROOT}",
            "program": "${ZED_WORKTREE_ROOT}/odoo/odoo-bin",
            "justMyCode": false,
            "env": ["PYDEVD_DISABLE_FILE_VALIDATION": "1"],
            "python": [entry.interpreter, "-Xfrozen_modules=off"],
            "console": "integratedTerminal",
            "args": baseArgs(entry) + extraArgs,
        ]
    }

    private static func buildDebugJson(_ entry: RegistryEntry) -> [[String: Any]] {
        [
            config("Start Server", entry: entry, extraArgs: [
                "--dev=all,xml", "--limit-time-real=100000", "--with-demo",
                "--update=\(entry.updateModules)", "--init=\(entry.installModules)",
            ]),
            config("Start Test", entry: entry, extraArgs: [
                "--dev=all", "--init=\(entry.installModules)", "--update=\(entry.installModules)",
                "--limit-time-real=100000", "--test-tags=/module:class.method",
                "--stop-after-init", "--log-web",
            ]),
            config("Start server without database update", entry: entry, extraArgs: [
                "--dev=all", "--limit-time-real=100000",
            ]),
        ]
    }

    static func write(worktreeRoot: URL, entry: RegistryEntry) {
        let zedDir = worktreeRoot.appendingPathComponent(".zed")
        try? FileManager.default.createDirectory(at: zedDir, withIntermediateDirectories: true)

        let debugJson = buildDebugJson(entry)
        if let data = try? JSONSerialization.data(withJSONObject: debugJson, options: [.prettyPrinted]) {
            try? data.write(to: zedDir.appendingPathComponent("debug.json"))
        }
    }
}
