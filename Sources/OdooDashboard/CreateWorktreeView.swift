import SwiftUI

struct CreateWorktreeView: View {
    @EnvironmentObject var store: WorktreeStore
    @EnvironmentObject var keyboard: KeyboardController

    private let prRepos = Config.worktreeRepos

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New worktree").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)

            Picker("", selection: $keyboard.createMode) {
                ForEach(CreateMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch keyboard.createMode {
            case .branch: branchFields
            case .pr: prFields
            }

            if let error = keyboard.createError {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.red)
            }

            if keyboard.createBusy, let progress = store.createProgress {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                    Text(progress).font(.system(size: 12)).foregroundStyle(Theme.inkDim)
                }
            }

            HStack {
                Spacer()
                ActionButton(title: "Cancel") { keyboard.showCreate = false }
                ActionButton(title: keyboard.createBusy ? "Creating…" : "Create", style: .primary, isDisabled: keyboard.createBusy || !canSubmit) {
                    store.submitCreate(keyboard)
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
    }

    private var canSubmit: Bool {
        switch keyboard.createMode {
        case .branch: return !keyboard.createBranchName.trimmingCharacters(in: .whitespaces).isEmpty
        case .pr: return !keyboard.createPrNumber.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    // Any branch name works -- new or existing, any naming scheme. Task id
    // is just metadata for the Odoo task badge, not something the branch
    // name has to encode. We still take a free guess at it from whatever's
    // typed (the "version-taskid-trigram" convention is common but not
    // required), purely to save typing -- never overwrites a value the
    // user already entered themselves.
    private var branchFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Branch name") { TextField("any-branch-name", text: $keyboard.createBranchName).textFieldStyle(.plain) }
                .onChange(of: keyboard.createBranchName) { _, newValue in
                    if keyboard.createTaskId.isEmpty, let inferred = StatusLogic.inferredTaskId(fromBranch: newValue.trimmingCharacters(in: .whitespaces)) {
                        keyboard.createTaskId = inferred
                    }
                }
            Text("Existing branches are looked up on origin, then the \(Config.githubForkOwner) fork, and attached as-is. A name that doesn't exist anywhere yet is created fresh off \"From branch\" below.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkDim)

            field("Odoo task id (optional)") { TextField("6482307", text: $keyboard.createTaskId).textFieldStyle(.plain) }

            VStack(alignment: .leading, spacing: 6) {
                field("From branch") { TextField("master", text: $keyboard.createFromBranch).textFieldStyle(.plain) }
                if !store.configuredVersions.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(store.configuredVersions, id: \.self) { version in
                            Button(version) { keyboard.createFromBranch = version }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(keyboard.createFromBranch == version ? Theme.accentBg : Theme.row))
                                .foregroundStyle(keyboard.createFromBranch == version ? Theme.accent : Theme.inkDim)
                        }
                    }
                }
                Text("Only used if \"Branch name\" doesn't exist yet in a repo -- that's what it gets created from.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var prFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Repo") {
                Picker("", selection: $keyboard.createPrRepo) {
                    ForEach(prRepos, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                field("PR number") { TextField("129020", text: $keyboard.createPrNumber).textFieldStyle(.plain) }
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
}
