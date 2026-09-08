import SwiftUI

struct CreateWorktreeView: View {
    @EnvironmentObject var store: WorktreeStore
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable { case task = "New task", branch = "Branch", pr = "PR number" }

    @State private var mode: Mode = .task
    @State private var taskId = ""
    @State private var fromBranch = "master"
    @State private var branchName = ""
    @State private var prNumber = ""
    @State private var prRepo = "enterprise"
    @State private var busy = false
    @State private var error: String?

    private let prRepos = Config.worktreeRepos

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New worktree").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)

            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .task: taskFields
            case .branch: branchFields
            case .pr: prFields
            }

            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.red)
            }

            HStack {
                Spacer()
                ActionButton(title: "Cancel") { dismiss() }
                ActionButton(title: busy ? "Creating…" : "Create", style: .primary, isDisabled: busy || !canSubmit) {
                    submit()
                }
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(Theme.panel)
        // This sheet is a separate window and doesn't reliably inherit
        // MenuBarContentView's .preferredColorScheme(.light) -- without this,
        // a system in Dark Mode renders default-colored text (title, picker
        // labels, typed field text) in white on this intentionally-light
        // background, i.e. invisible.
        .preferredColorScheme(.light)
        .onAppear {
            if store.configuredVersions.contains("master") { fromBranch = "master" }
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .task: return !taskId.trimmingCharacters(in: .whitespaces).isEmpty
        case .branch: return !branchName.trimmingCharacters(in: .whitespaces).isEmpty
        case .pr: return !prNumber.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var taskFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Task ID") { TextField("6482307", text: $taskId).textFieldStyle(.plain) }
            VStack(alignment: .leading, spacing: 6) {
                field("From branch") { TextField("master", text: $fromBranch).textFieldStyle(.plain) }
                if !store.configuredVersions.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(store.configuredVersions, id: \.self) { version in
                            Button(version) { fromBranch = version }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(fromBranch == version ? Theme.accentBg : Theme.row))
                                .foregroundStyle(fromBranch == version ? Theme.accent : Theme.inkDim)
                        }
                    }
                    Text("Versions with a configured Python interpreter -- any git branch works here, this is just a shortcut.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkDim)
                }
            }
            field("Branch name (preview)") {
                Text("\(fromBranch)-\(taskId.isEmpty ? "<taskId>" : taskId)-\(Config.trigram)")
                    .foregroundStyle(Theme.inkDim)
                    .font(.system(size: 12.5, design: .monospaced))
            }
        }
    }

    private var branchFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            field("Existing branch name") { TextField("master-6482307-dafl", text: $branchName).textFieldStyle(.plain) }
            Text("Looked up on origin, then the \(Config.githubForkOwner) fork. Attaches the existing branch if you already have it checked out locally.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkDim)
        }
    }

    private var prFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Repo") {
                Picker("", selection: $prRepo) {
                    ForEach(prRepos, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                field("PR number") { TextField("129020", text: $prNumber).textFieldStyle(.plain) }
                Text("Resolves the PR's head branch and checks it out across all repos.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkDim)
            }
        }
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkDim)
            content()
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.row))
        }
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            do {
                switch mode {
                case .task:
                    try await store.create(taskId: taskId.trimmingCharacters(in: .whitespaces), fromBranch: fromBranch)
                case .branch:
                    try await store.create(branch: branchName.trimmingCharacters(in: .whitespaces))
                case .pr:
                    try await store.create(prNumber: Int(prNumber.trimmingCharacters(in: .whitespaces)), prRepo: prRepo)
                }
                dismiss()
            } catch let e as WorktreeStore.CreateError {
                error = e.message
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
