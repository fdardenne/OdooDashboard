import Foundation

/// Copies the "master" Claude Code configuration -- CLAUDE.md, .claude/
/// settings*.json, and .claude/skills -- from the base odoo_workspace
/// checkout into a freshly created worktree, once at creation time. This
/// app already runs `claude`/Claude Code with the worktree root as cwd
/// (see ClaudeClient.openClaudeSession), so that's where Claude Code itself
/// looks for these. Deliberately never re-run on later updates, so any
/// worktree-local edits made afterward (e.g. a worktree-specific
/// settings.local.json) aren't clobbered.
enum ClaudeConfigCopier {
    static func copy(into worktreeRoot: URL) {
        let fm = FileManager.default
        let source = Config.odooWorkspace

        let claudeMdSource = source.appendingPathComponent("CLAUDE.md")
        if fm.fileExists(atPath: claudeMdSource.path) {
            try? fm.copyItem(at: claudeMdSource, to: worktreeRoot.appendingPathComponent("CLAUDE.md"))
        }

        let sourceClaudeDir = source.appendingPathComponent(".claude")
        guard fm.fileExists(atPath: sourceClaudeDir.path) else { return }
        let destClaudeDir = worktreeRoot.appendingPathComponent(".claude")
        try? fm.createDirectory(at: destClaudeDir, withIntermediateDirectories: true)

        for file in ["settings.json", "settings.local.json"] {
            let src = sourceClaudeDir.appendingPathComponent(file)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.copyItem(at: src, to: destClaudeDir.appendingPathComponent(file))
        }

        let skillsSource = sourceClaudeDir.appendingPathComponent("skills")
        if fm.fileExists(atPath: skillsSource.path) {
            try? fm.copyItem(at: skillsSource, to: destClaudeDir.appendingPathComponent("skills"))
        }
    }
}
