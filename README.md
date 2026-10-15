# Odoo Dashboard

<img width="3454" height="1070" alt="image" src="https://github.com/user-attachments/assets/738f5a08-859d-437e-b74f-d4b30dc0d2c7" />

A native macOS menu bar app for managing parallel Odoo development worktrees — create, run, rebase, and review multiple Odoo branches side by side, each with its own port, database, VS Code config, and status at a glance, without ever leaving the keyboard.

It replaces the usual manual routine of `git stash` / `git checkout` / re-running `odoo-bin` with a different `--http-port` every time you switch tasks: every worktree here is a fully independent checkout with its own port, database, and Python interpreter, all visible and controllable from one dropdown.

## Features

- **Git worktree management** — create a worktree from a task ID, an existing branch, a free-form branch name, or a GitHub PR number; start/stop/restart the Odoo server (installing and updating the configured modules and loading demo data every time); rebase onto the base branch (in parallel, across every repo), or pull for standard branches that don't need rebasing; delete when done, with an option to drop its database too.
- **Multi-repo aware** — each worktree spans `odoo`, `enterprise`, `upgrade`, `design-themes`, and `upgrade-util` (configurable), with the right addons-path and upgrade-path wired into a generated Zed debug configuration.
- **Live status at a glance** — GitHub PR review/CI status (including Odoo's `@robodoo r+`/`r-` mergebot convention, which GitHub's own review UI doesn't reflect), runbot build results, and linked odoo.com task name/stage/status, all cached and refreshed automatically, with the last-known task status kept on screen even if the API key expires.
- **Digest mailbox** — a running digest of the important (`REF`/`IMP`) commits landing on master for the modules you care about, written up as plain-English summaries with each point linked back to its source commit, PR, and task. Each visit picks up where the last one left off (first visit covers the past week); a manual "Generate now" button re-runs it on demand, and a "Clear" button resets the history.
- **Task search** — search a project's open tasks by meaning, not just keywords, matching against title and description; optionally include closed tasks, or attach a screenshot to search by what's on screen instead of (or alongside) a typed query.
- **Claude integration** — generate a one-line worktree description from its commits and task title, open an interactive Claude session in a new iTerm2 tab (seeded with a prompt for rebase-conflict resolution), or ask it anything about a given worktree. New worktrees automatically get the project's Claude settings, skills, and `CLAUDE.md` copied in.
- **Editor and terminal integration** — open a worktree in Zed (with a generated `.zed/debug.json` for each repo) or in cmux, whichever fits the moment.
- **Full keyboard control** — a global shortcut opens the dropdown from anywhere; once open, vim-style navigation (`h`/`j`/`k`/`l`) and single-key actions (`o` open in Zed, `m` open in cmux, `w` open the running instance, `s` start/stop, `r` rebase, `a` ask Claude, `x` delete, `/` to filter, `f` to follow a PR/runbot/task link, `d`/`t` to switch to the digest/search tabs, `?` for the full cheat sheet) mean you rarely need the mouse.
- **Fully standalone** — no background server, no web dashboard, nothing to keep running. The whole thing is one signed `.app`; it talks to `git`, `gh`, `dropdb`, `zed`, `cmux`, and `claude` directly, and reads/writes a small JSON registry on disk.
- **Configurable for anyone** — every machine-specific assumption (workspace/worktrees paths, which repos to manage, per-version Python interpreters, GitHub identity, the global shortcut, an Odoo.com API token, the digest's watched modules, the search project id) lives in a Settings window, not in source code.

## Requirements

- macOS 26 (Tahoe) or later — the dropdown uses `NSGlassEffectView`, a macOS 26 API, for its glass background.
- Xcode / Swift 6.2 toolchain to build from source.
- A local checkout of the Odoo repos you work with (`odoo`, `enterprise`, `upgrade`, ... — whichever you configure).
- [`gh`](https://cli.github.com) (GitHub CLI), authenticated — used for PR/CI status and PR-number-based worktree creation.
- PostgreSQL client tools on `PATH` (`dropdb`) — used to drop a worktree's database.
- [Zed](https://zed.dev) with the `zed` CLI installed — used for "Open in Zed" and the generated debug configurations.
- [cmux](https://cmux.dev) with the `cmux` CLI installed — used for "Open in cmux" (optional).
- [Claude Code](https://claude.com/claude-code) CLI — used for description generation, digest summaries, task search matching, and the "Ask Claude" / conflict-resolution flows.
- [iTerm2](https://iterm2.com) — interactive Claude sessions open in a new iTerm2 tab.
- One Python interpreter per Odoo version you work with (configured in Settings — see below).

The only external Swift package dependency is [SwiftSoup](https://github.com/scinfu/SwiftSoup) (HTML parsing for runbot status), fetched automatically by Swift Package Manager.

## Installation

### From the DMG

Grab `OdooDashboard.dmg`, open it, and drag **OdooDashboard.app** to **Applications**.

### From source

```bash
swift build -c release
```

Then either run `.build/release/OdooDashboard` directly, or assemble and code-sign an app bundle:

```bash
mkdir -p OdooDashboard.app/Contents/MacOS OdooDashboard.app/Contents/Resources
cp .build/release/OdooDashboard OdooDashboard.app/Contents/MacOS/
cp Info.plist.template OdooDashboard.app/Contents/Info.plist
cp AppIcon.icns OdooDashboard.app/Contents/Resources/
codesign --force --deep --sign - OdooDashboard.app   # ad-hoc is fine for local use
```

(The assembled `.app` itself isn't checked in — it's build output, like `.build/`. `AppIcon.icns` and `Info.plist.template` are the actual source assets.)

### Running at login

A LaunchAgent keeps it running in the background:

```xml
<!-- ~/Library/LaunchAgents/com.yourname.odoo-dashboard.plist -->
<plist version="1.0">
<dict>
  <key>Label</key><string>com.yourname.odoo-dashboard</string>
  <key>ProgramArguments</key>
  <array><string>/Applications/OdooDashboard.app/Contents/MacOS/OdooDashboard</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
</dict>
</plist>
```

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.yourname.odoo-dashboard.plist
```

### Permissions

The global shortcut (see below) needs two permissions, granted manually the first time since a locally-signed app can't reliably trigger the system prompt itself:

- **System Settings → Privacy & Security → Input Monitoring** — add the app, enable it.
- **System Settings → Privacy & Security → Accessibility** — same.

Quit and relaunch the app after granting both.

## Configuration

Everything machine-specific lives in **Settings** (right-click the menu bar icon → *Settings…*):

| Section | What it configures |
|---|---|
| **Paths** | Where your base repo checkouts live, where new worktrees are created, and where the registry/logs are stored. |
| **Repositories** | Which repos to manage, and which are required for a worktree to be considered valid. |
| **Python interpreters** | One Python binary per Odoo version (e.g. `18.0` → `/path/to/venv/bin/python`), plus an optional default for anything unlisted. |
| **Git** | The suffix appended to generated branch names (`<base>-<taskId>-<suffix>`). |
| **Odoo.com** | An API token for looking up linked task name/stage/status, and the project id Task Search runs against. |
| **Defaults for new worktrees** | Default install/update modules seeded into new worktrees. |
| **Digest** | Comma-separated list of modules to watch for `REF`/`IMP` commits on master. |
| **Keyboard** | The global shortcut that opens the dropdown — click the recorder and press any key combo. |

Settings are stored in `UserDefaults` (per-user, per-machine) — nothing here is checked into source.

## Usage

Press your configured shortcut (default: `$`) from anywhere to open the dropdown. Click a card's buttons, or use the keyboard once it's open:

| Key | Action |
|---|---|
| `j` / `k` / `h` / `l` | Move focus between cards |
| `Enter` / `o` | Open in Zed |
| `m` | Open in cmux |
| `w` | Open the running instance in a browser |
| `s` | Start / stop |
| `r` | Rebase (or pull, for standard branches) |
| `a` | Ask Claude |
| `i` | Toggle details |
| `L` | Toggle logs |
| `c` | Copy worktree path |
| `f` then a digit | Follow a PR/runbot/task link |
| `x` | Delete (with confirmation) |
| `D` | Drop database (with confirmation) |
| `/` | Filter by name, branch, or description |
| `n` | New worktree |
| `d` | Switch to the Digest tab |
| `t` | Switch to the Search tab |
| `1` / `2` / `3` / `4` | Switch category (In Progress / Done / Standard / All) |
| `?` | Toggle the shortcuts cheat sheet |
| `Esc` | Close the filter, then the panel |

### Digest

The Digest tab reads like a mailbox: every time you open it, it generates a new entry covering every important commit (`REF`/`IMP`) landing on master since the last entry — or the past week, the first time you ever open it. Each entry is a short written summary with inline links back to the exact commits, PRs, and tasks it's based on. Use "Generate now" to force a refresh ahead of the next scheduled one, or "Clear" to wipe the mailbox and start over.

### Task search

The Search tab runs a single lookup of a project's open tasks (configured by project id in Settings → Odoo.com) and ranks them by relevance to a typed query, an attached screenshot, or both. Paste an image directly into the search field to search by what's on screen; toggle "include closed" to widen the search to done/canceled tasks too.

## Architecture

Everything runs inside a single Swift Package — an `NSStatusItem` plus a borderless `NSPanel` hosting a SwiftUI view tree. There is no server process and no network dependency beyond the external services listed above:

- **`WorktreeManager`** — creates/deletes/rebases/starts/stops worktrees, orchestrating `GitClient` (a thin, argv-only wrapper around `git`), `Registry` (an atomically-written, lock-protected JSON file — the single source of truth for what worktrees exist), `PortAllocator`, `InterpreterResolver`, `ZedDebugConfigWriter`, and `ClaudeConfigCopier` (copies Claude settings/skills/`CLAUDE.md` into every new worktree).
- **`WorktreeEnricher`** — merges live PR status (`PrStatusClient`, via `gh`), runbot status (`RunbotClient`, scraping via SwiftSoup), and Odoo task status (`OdooTaskClient`) onto each worktree, through a small TTL cache with in-flight de-duplication.
- **`ClaudeClient`** — headless `claude -p` calls for description generation, digest summaries, and task search matching, plus iTerm2 AppleScript automation for interactive sessions.
- **`DigestGenerator`** / **`DigestSummarizer`** / **`DigestStore`** — scan master for important commits on the watched modules, turn them into a cited written summary, and persist each run as an entry in the digest mailbox.
- **`OdooTaskClient`** / **`TaskSearchMatcher`** — one bulk fetch of a project's tasks, ranked against a query (and/or screenshot) by relevance.
- **`WorktreeStore`** — the `ObservableObject` the SwiftUI layer binds to; owns polling and busy-state tracking.
- **`AppSettings`** / **`Config`** — user-editable settings (MainActor, for the Settings UI) and a thread-safe read path (`UserDefaults`-backed, safe to call from anywhere) for the rest of the app.

### Project layout

```
Sources/OdooDashboard/
├── OdooDashboardApp.swift     status item, global shortcut, keyboard router
├── WorktreeManager.swift      worktree create/delete/rebase/start/stop
├── GitClient.swift            git operations
├── Registry.swift             on-disk worktree registry
├── WorktreeEnricher.swift     PR/runbot/task enrichment + caching
├── PrStatusClient.swift       gh CLI wrapper
├── RunbotClient.swift         runbot HTML scraping
├── OdooTaskClient.swift       odoo.com task lookup + project task search
├── ClaudeClient.swift         claude CLI + iTerm2 automation
├── ZedDebugConfigWriter.swift generates .zed/debug.json per worktree
├── DigestGenerator.swift      scans master for watched-module commits
├── DigestSummarizer.swift     turns commits into a cited written summary
├── DigestStore.swift          on-disk digest mailbox
├── DigestView.swift           digest tab UI
├── TaskSearchMatcher.swift    LLM-ranked task search
├── TaskSearchView.swift       search tab UI
├── FocusableTextField.swift   paste-aware text input for the search field
├── AppSettings.swift          Settings model
├── SettingsView.swift         Settings UI
├── WorktreeCardView.swift     the card UI
└── ...
AppIcon.icns             app icon (source asset)
Info.plist.template      bundle metadata (copied in when assembling the .app)
Package.swift
```

## Data on disk

- `~/Library/Application Support/Odoo Dashboard/registry.json` — every worktree's metadata (paths, port, database, interpreter, task id, description).
- `~/Library/Application Support/Odoo Dashboard/logs/<worktree>.log` — that worktree's `odoo-bin` output.
- `~/Library/Application Support/Odoo Dashboard/digests.json` — the digest mailbox history.

These paths are configurable in Settings.
