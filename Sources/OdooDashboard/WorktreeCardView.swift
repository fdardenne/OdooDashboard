import AppKit
import SwiftUI

struct WorktreeCardView: View {
    let entry: WorktreeEntry
    @EnvironmentObject var store: WorktreeStore
    @EnvironmentObject var keyboard: KeyboardController

    @State private var editingDescription = false
    @State private var descriptionDraft = ""

    @State private var taskIdDraft = ""
    @State private var installDraft = ""
    @State private var updateDraft = ""
    @State private var detailsDirty = false

    @State private var logsText = ""
    @State private var logsTimer: Timer?

    private var isFocused: Bool { keyboard.focusedName == entry.name }
    private var copied: Bool { keyboard.copiedName == entry.name }
    private var showDetails: Bool { keyboard.isDetailsOpen(entry.name) }
    private var showLogs: Bool { keyboard.isLogsOpen(entry.name) }
    private var rebaseReport: [RebaseReportItem]? { keyboard.rebaseReports[entry.name] }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { keyboard.pendingDeleteConfirm == entry.name },
            set: { keyboard.pendingDeleteConfirm = $0 ? entry.name : nil }
        )
    }

    private var dropDbConfirmBinding: Binding<Bool> {
        Binding(
            get: { keyboard.pendingDropDbConfirm == entry.name },
            set: { keyboard.pendingDropDbConfirm = $0 ? entry.name : nil }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !editingDescription { descriptionView } else { descriptionField }

            FlowLayout(spacing: 6) { badges }

            FlowLayout(spacing: 6) { actionButtons }

            if let rebaseReport { rebaseReportView(rebaseReport) }
            if showDetails { detailsPanel }
            if showLogs { logsView }

            // Absorbs the extra space LazyVGrid gives every card in a row to
            // match the row's tallest card, so top AND bottom edges line up
            // instead of shorter cards floating inside taller allotted space.
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.row))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isFocused ? Theme.focusRing : railBorder, lineWidth: isFocused ? 2 : (entry.railColor == .red ? 1.5 : 1)))
        .onChange(of: showLogs) { _, isOn in isOn ? startLogs() : stopLogs() }
        .onAppear { seedDetailsDrafts() }
        .onChange(of: entry.taskId) { _, _ in if !detailsDirty { seedDetailsDrafts() } }
    }

    private var railBorder: Color {
        entry.railColor == .red ? Theme.red.opacity(0.5) : Theme.rule
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            badge
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onTapGesture { copyPath() }
                        .help("Click to copy the worktree folder path")
                    if copied {
                        Text("copied!")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.greenBg))
                    }
                }
                Text(metaText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkDim)
            }
            Spacer(minLength: 4)
            if entry.running {
                Button {
                    if let url = URL(string: "http://localhost:\(entry.port)") { NSWorkspace.shared.open(url) }
                } label: {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 13))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.blueBg))
                        .foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
                .help("Open http://localhost:\(entry.port)")
            }
        }
    }

    private var metaText: String {
        let portText = String(entry.port)
        return ":\(portText)  ·  \(entry.fromBranch)"
    }

    /// This badge is a single-glance rollup of the same info spelled out in
    /// the pills below (worst of PR review/CI, runbot, task state) -- green
    /// checkmark = approved & clean, blue clock = something's in progress,
    /// red "!" = needs attention, gray "-" = nothing to report yet. The small
    /// green dot means the worktree's odoo-bin process is currently running.
    private var overallStatusTooltip: String {
        let statusText: String
        switch entry.railColor {
        case .green: statusText = "Overall status: approved & clean"
        case .blue: statusText = "Overall status: in progress (CI running or task in progress)"
        case .red: statusText = "Overall status: needs attention"
        case .gray: statusText = "Overall status: nothing to report yet"
        }
        return entry.running ? "\(statusText)\nRunning on :\(entry.port)" : statusText
    }

    @ViewBuilder
    private var badge: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.color(for: entry.railColor))
                .frame(width: 42, height: 42)
            Image(systemName: Theme.icon(for: entry.railColor))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
            if entry.running {
                Circle()
                    .fill(Theme.green)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(Theme.panel, lineWidth: 2))
                    .offset(x: 3, y: 3)
            }
        }
        .help(overallStatusTooltip)
    }

    private func copyPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Config.worktreesRoot.appendingPathComponent(entry.name).path, forType: .string)
        keyboard.markCopied(entry.name)
    }

    // MARK: - Description

    private var descriptionView: some View {
        HStack(spacing: 6) {
            Text(entry.description.isEmpty ? "+ add description" : entry.description)
                .font(.system(size: 13))
                .foregroundStyle(entry.description.isEmpty ? Theme.inkDim : Theme.ink.opacity(0.85))
                .italic(entry.description.isEmpty)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture {
                    descriptionDraft = entry.description
                    editingDescription = true
                }
            Button {
                Task { await store.generateDescription(entry.name) }
            } label: {
                Image(systemName: "sparkle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkDim)
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy(entry.name, "gen-desc"))
            .help("Generate from this branch's commits and task with Claude")
        }
    }

    private var descriptionField: some View {
        TextField("One-line description…", text: $descriptionDraft, onCommit: saveDescription)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent, lineWidth: 1))
    }

    private func saveDescription() {
        editingDescription = false
        if descriptionDraft != entry.description {
            Task { await store.updateDetails(entry.name, description: descriptionDraft) }
        }
    }

    // MARK: - Badges

    private var showLinkHints: Bool { isFocused && keyboard.linkMode }

    @ViewBuilder
    private var badges: some View {
        ForEach(StatusLogic.badgeSpecs(for: entry)) { spec in
            BadgePill(
                text: spec.text,
                tone: spec.tone,
                url: spec.url,
                tooltip: spec.tooltip,
                hintKey: showLinkHints ? spec.hintKey : nil
            )
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionButtons: some View {
        ActionButton(title: "Open in VS Code", icon: "arrow.up.forward.app", style: .primary, isDisabled: store.isBusy(entry.name, "open"), hint: "o") {
            store.run(entry.name, action: "open")
        }
        if entry.running {
            ActionButton(title: "Stop", icon: "stop.fill", isDisabled: store.isBusy(entry.name, "stop"), hint: "s") {
                store.run(entry.name, action: "stop")
            }
            ActionButton(title: "Restart", icon: "arrow.clockwise", isDisabled: store.isBusy(entry.name, "restart")) {
                store.run(entry.name, action: "restart")
            }
        } else {
            ActionButton(title: "Start", icon: "play.fill", style: .success, isDisabled: store.isBusy(entry.name, "start"), hint: "s") {
                store.run(entry.name, action: "start")
            }
        }
        ActionButton(title: "Rebase", icon: "arrow.triangle.2.circlepath", isDisabled: store.isBusy(entry.name, "rebase"), hint: "r") {
            Task { keyboard.rebaseReports[entry.name] = await store.rebase(entry.name) }
        }
        ActionButton(title: "Ask Claude", icon: "sparkles", isDisabled: store.isBusy(entry.name, "ask-claude"), hint: "a") {
            store.askClaude(entry.name)
        }
        ActionButton(title: "Details", icon: "slider.horizontal.3", hint: "i") {
            keyboard.toggleDetails(entry.name)
        }
        ActionButton(title: showLogs ? "Hide logs" : "Logs", icon: "doc.plaintext", hint: "L") {
            keyboard.toggleLogs(entry.name)
        }
        ActionButton(title: "Drop DB", icon: "cylinder.split.1x2", style: .danger, isDisabled: entry.running || store.isBusy(entry.name, "dropdb"), hint: "D") {
            dropDbConfirmBinding.wrappedValue = true
        }
        .confirmationDialog("Drop database \"\(entry.db)\"? This cannot be undone.", isPresented: dropDbConfirmBinding, titleVisibility: .visible) {
            Button("Drop Database", role: .destructive) { store.run(entry.name, action: "dropdb") }
        }
        ActionButton(title: "Delete", icon: "trash", style: .danger, isDisabled: store.isBusy(entry.name, "delete"), hint: "x") {
            deleteConfirmBinding.wrappedValue = true
        }
        .confirmationDialog("Delete worktree \"\(entry.name)\"?", isPresented: deleteConfirmBinding, titleVisibility: .visible) {
            Button("Delete Only", role: .destructive) { Task { await store.delete(entry.name, dropDb: false) } }
            Button("Delete and Drop Database", role: .destructive) { Task { await store.delete(entry.name, dropDb: true) } }
        } message: {
            Text("This removes the git worktrees and the folder.")
        }
    }

    // MARK: - Rebase report

    private func rebaseReportView(_ report: [RebaseReportItem]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(report) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.ok ? Theme.green : (item.conflict == true ? Theme.red : Theme.yellow))
                        .frame(width: 6, height: 6)
                    Text(rebaseLine(item))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink)
                    if item.conflict == true {
                        Button("Resolve with Claude") {
                            let repoPath = entry.repos[item.repo] ?? Config.worktreesRoot.appendingPathComponent(entry.name).appendingPathComponent(item.repo).path
                            store.askClaude(
                                entry.name,
                                prompt: "The git rebase conflict is in this repo: \(repoPath) — cd there first. Run `git rebase origin/\(entry.fromBranch)` to re-trigger the conflict (it was aborted), then resolve the conflicting files carefully and continue the rebase with `git rebase --continue`."
                            )
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .underline()
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
    }

    private func rebaseLine(_ item: RebaseReportItem) -> String {
        if item.ok { return "\(item.repo): rebased cleanly" }
        if item.conflict == true { return "\(item.repo): CONFLICT (aborted)" }
        return "\(item.repo): \(item.message ?? "failed")"
    }

    // MARK: - Details

    private func seedDetailsDrafts() {
        guard !detailsDirty else { return }
        taskIdDraft = entry.taskId
        installDraft = entry.installModules
        updateDraft = entry.updateModules
    }

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailsField("Odoo task id", text: $taskIdDraft, placeholder: "6482307")
            detailsField("Install modules", text: $installDraft, placeholder: "l10n_be_hr_payroll")
            detailsField("Update modules", text: $updateDraft, placeholder: "l10n_be_hr_payroll")
            ActionButton(title: "Save", style: .primary, isDisabled: !detailsDirty) {
                Task {
                    await store.updateDetails(entry.name, taskId: taskIdDraft, installModules: installDraft, updateModules: updateDraft)
                    detailsDirty = false
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
    }

    private func detailsField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkDim)
            TextField(placeholder, text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = $0; detailsDirty = true }))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.row))
        }
    }

    // MARK: - Logs

    private func startLogs() {
        Task { logsText = await store.fetchLogs(entry.name) }
        logsTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in logsText = await store.fetchLogs(entry.name) }
        }
    }

    private func stopLogs() {
        logsTimer?.invalidate()
        logsTimer = nil
    }

    private var logsView: some View {
        ScrollView {
            Text(logsText.isEmpty ? "(no log output yet)" : logsText)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color(hex: 0xd6d8dc))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 200)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x1c1e22)))
    }
}
