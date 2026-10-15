import Foundation

/// Ports packages/server/src/claude.ts -- headless `claude -p` for
/// description generation, and iTerm2 AppleScript automation for the
/// interactive "Ask Claude" / "Resolve with Claude" sessions.
///
/// NOTE: cmux (see BinaryLocator.cmux) was tried here instead, since the
/// user switched to it -- but live testing showed its CLI/socket API
/// (workspace create, new-split, etc.) unconditionally rejects any caller
/// that wasn't itself spawned inside a cmux-managed terminal ("Access
/// denied - only processes started inside cmux can connect"), by design.
/// There's no way for this standalone app to drive that API, so this stays
/// on iTerm2. Opening a worktree's root directory in cmux directly (`cmux
/// <path>`, which does work from outside) is a separate, simpler action --
/// see WorktreeStore's "open-cmux".
enum ClaudeClient {
    static func askClaudeText(_ prompt: String, cwd: URL? = nil, timeout: TimeInterval = 45, allowedTools: [String]? = nil) async throws -> String {
        var args = ["-p", prompt]
        if let allowedTools, !allowedTools.isEmpty {
            args += ["--allowedTools"] + allowedTools
        }
        return try await ProcessRunner.run(BinaryLocator.claude, args, cwd: cwd, timeout: timeout)
    }

    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func shellSingleQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Opens (or reuses the current window with) an iTerm2 tab, cd's into
    /// `cwd`, and runs `claude` there -- optionally seeded with `prompt` and
    /// named via `title` (both the tab name and, more durably, an iTerm2
    /// badge escape sequence, since the tab name can get stomped by
    /// automatic title tracking or Claude Code's own title-setting). Fire
    /// and forget, matching the original TS behavior exactly.
    static func openClaudeSession(cwd: String, prompt: String? = nil, title: String? = nil) {
        let claudeBin = BinaryLocator.claude
        let claudeCmd = prompt.map { "\(shellSingleQuote(claudeBin)) \(shellSingleQuote($0))" } ?? shellSingleQuote(claudeBin)

        var badgeCmd = ""
        if let title, let titleData = title.data(using: .utf8) {
            let base64 = titleData.base64EncodedString()
            badgeCmd = "printf '\\033]1337;SetBadgeFormat=%s\\a' \(base64); "
        }
        let shellCommand = "\(badgeCmd)cd \(shellSingleQuote(cwd)) && \(claudeCmd)"

        var lines = [
            "tell application \"iTerm2\"",
            "  activate",
            "  if (count of windows) = 0 then",
            "    create window with default profile",
            "  else",
            "    tell current window to create tab with default profile",
            "  end if",
            "  tell current session of current window",
        ]
        if let title {
            lines.append("    set name to \"\(appleScriptEscape(title))\"")
        }
        lines.append("    write text \"\(appleScriptEscape(shellCommand))\"")
        lines.append("  end tell")
        lines.append("end tell")
        let osaScript = lines.joined(separator: "\n")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: BinaryLocator.osascript)
        process.arguments = ["-e", osaScript]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
