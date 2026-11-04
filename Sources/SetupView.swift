import AppKit
import SwiftUI

struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var showControls = false
    @State private var showRecipes = false
    @State private var problem: String?

    var body: some View {
        @Bindable var settings = model.settings
        let checker = model.checker
        let tasks = model.tasks
        let updates = model.updates

        Form {
            if checker.hasChecked && checker.failures > 0 {
                Section {
                    Label(L("%@ thing(s) to fix before you can build. Each has a button or a command to copy into Terminal.", "\(checker.failures)"),
                          systemImage: "wrench.and.screwdriver")
                        .foregroundStyle(.orange)
                }
            }

            if tasks.state != .idle {
                Section(tasks.title) { TaskPanel(tasks: tasks) }
            }

            Section(L("Folders and keys")) {
                PathRow(title: L("nxnative folder"), path: settings.repoPath,
                        placeholder: L("Choose the nxnative folder"),
                        missing: !settings.hasRepo) {
                    chooseRepo()
                }
                PathRow(title: "prod.keys", path: settings.keysPath,
                        placeholder: L("Choose the keys dumped from your Switch"),
                        missing: !FileManager.default.fileExists(atPath: settings.keysPath)) {
                    chooseKeys()
                }
            }

            Section {
                if checker.items.isEmpty && checker.isChecking {
                    HStack { ProgressView().controlSize(.small); Text(L("Checking …")).foregroundStyle(.secondary) }
                }
                ForEach(checker.items) { item in
                    CheckRow(item: item, busy: tasks.isRunning || model.runner.isBusy, perform: perform)
                }
            } header: {
                HStack {
                    Text(L("What building needs"))
                    Spacer()
                    if checker.isChecking { ProgressView().controlSize(.small) }
                    Button(L("Check again"), action: recheck)
                        .disabled(checker.isChecking)
                }
            }

            Section("nxnative") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(updateTitle(updates))
                        Text(L("nxnative gets fixes and new games almost daily. Build a game again after an update to get them."))
                            .font(.caption).foregroundStyle(.secondary)
                        if !updates.localChanges.isEmpty {
                            Text(L("Changed here: %@. If an update stops on them, NX Builder's own Python environment does not need the guide's change to pyproject.toml.", "\(updates.localChanges.joined(separator: ", "))"))
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if updates.checking { ProgressView().controlSize(.small) }
                    Button(L("Check")) { Task { await updates.check(repo: settings.repoPath) } }
                        .disabled(updates.checking || !settings.hasRepo)
                    Button(L("Update now"), action: update)
                        .disabled(tasks.isRunning || model.runner.isBusy || !settings.hasRepo)
                }
                if !updates.frontEndNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Notes for front ends in this update (NX Builder may need an update if one says “break”):"))
                            .font(.caption)
                        ForEach(updates.frontEndNotes, id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
                    }
                }
                Button { showRecipes = true } label: {
                    Label(L("Games with a recipe, and the version each needs"), systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.link)
                Button { showControls = true } label: {
                    Label(L("Keyboard and controllers"), systemImage: "keyboard")
                }
                .buttonStyle(.link)
            }

            Section("NX Builder") {
                SwiftUI.Picker(L("Language"), selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                if settings.appLanguage != .system && settings.appLanguage != L10n.language {
                    Text(L("Applies the next time NX Builder starts."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(L("Notify me when a build finishes"), isOn: $settings.notify)
                Text(L("NX Builder only runs nxnative's own build script. It contains no game files or keys: use dumps of games you own and the keys from your own Switch."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L("Setup"))
        .sheet(isPresented: $showControls) { ControlsSheet() }
        .sheet(isPresented: $showRecipes) { RecipeListView() }
        .task { if model.updates.behind == nil { await model.updates.check(repo: model.settings.repoPath) } }
        .alert(L("Setup"), isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") {}
        } message: {
            Text(problem ?? "")
        }
    }

    private func updateTitle(_ updates: NxnativeUpdates) -> String {
        let current = updates.current.isEmpty ? "" : L("Version %@", "\(updates.current)")
        switch updates.behind {
        case nil: return current.isEmpty ? L("Updates") : current
        case 0?: return current + L(" · up to date")
        case let n?: return current + L(" · %@ new change(s) available", "\(n)")
        }
    }

    // MARK: - Actions

    private func recheck() {
        Task {
            await model.recipes.reload(repo: model.settings.repoPath)
            await model.checker.run(settings: model.settings)
        }
    }

    private func afterTask(_ ok: Bool) {
        recheck()
        Task { await model.updates.check(repo: model.settings.repoPath) }
    }

    private func perform(_ action: SetupAction) {
        switch action {
        case .chooseRepo: chooseRepo()
        case .chooseKeys: chooseKeys()
        case .cloneNxnative: clone()
        case .setUpPython:
            switch SetupSteps.python() {
            case .success(let steps):
                model.tasks.run(L("Setting up Python"), steps: steps, then: afterTask)
            case .failure(let error):
                model.tasks.fail(L("Setting up Python"), error.message)
            }
        case .installMetal:
            model.tasks.run(L("Installing the Metal toolchain"), steps: SetupSteps.metalToolchain(), then: afterTask)
        }
    }

    private func chooseRepo() {
        if let path = FilePicker.folder(message: L("Choose the folder you cloned nxnative into."), startingAt: model.settings.repoPath) {
            model.settings.repoPath = path
            recheck()
            Task { await model.updates.check(repo: path) }
        }
    }

    private func chooseKeys() {
        if let path = FilePicker.file(message: L("Choose the prod.keys dumped from your own Switch."), startingAt: model.settings.keysPath) {
            model.settings.keysPath = path
            recheck()
        }
    }

    private func clone() {
        guard let parent = FilePicker.folder(message: L("Where should nxnative go? A folder “nxnative” is made inside the one you choose (under 1 GB)."),
                                             startingAt: NSHomeDirectory()) else { return }
        let dest = parent + "/nxnative"
        if FileManager.default.fileExists(atPath: dest) {
            if FileManager.default.fileExists(atPath: dest + "/scripts/build_ipa_from_nsp.py") {
                model.settings.repoPath = dest
                recheck()
            } else {
                problem = L("%@ already exists. Choose another place, or remove that folder first.", "\(dest.tildePath)")
            }
            return
        }
        model.tasks.run(L("Downloading nxnative"), steps: SetupSteps.clone(into: dest)) { ok in
            if ok { model.settings.repoPath = dest }
            afterTask(ok)
        }
    }

    private func update() {
        let repo = model.settings.repoPath
        Task {
            let old = await Task.detached { NxnativeUpdates.head(repo: repo) }.value
            model.tasks.run(L("Updating nxnative"), steps: SetupSteps.update(repo: repo)) { ok in
                if ok { Task { await model.updates.readNotes(repo: repo, since: old) } }
                afterTask(ok)
            }
        }
    }
}

/// A setup task's progress and output.
struct TaskPanel: View {
    let tasks: TaskRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                switch tasks.state {
                case .running:
                    ProgressView().controlSize(.small)
                    Text(tasks.step)
                case .done:
                    Label(L("Done"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed(let reason):
                    Label(reason, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                case .idle:
                    EmptyView()
                }
                Spacer()
                if tasks.isRunning {
                    Button(L("Stop")) { tasks.cancel() }
                } else {
                    Button(L("Close")) { tasks.dismiss() }
                }
            }
            if !tasks.lines.isEmpty { LogView(lines: tasks.lines, height: 120...220) }
        }
    }
}

struct CheckRow: View {
    let item: CheckItem
    let busy: Bool
    let perform: (SetupAction) -> Void
    @State private var expanded = false
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: icon).foregroundStyle(color).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                    Text(item.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !item.more.isEmpty {
                    Button(expanded ? L("Hide details") : L("Details")) { expanded.toggle() }
                        .buttonStyle(.link).font(.caption)
                }
            }
            if item.status != .ok && !item.fixes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(item.fixes.enumerated()), id: \.offset) { _, fix in fixView(fix) }
                }
                .padding(.leading, 28)
            }
            if expanded {
                Text(item.more.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 28)
            }
        }
    }

    @ViewBuilder private func fixView(_ fix: CheckFix) -> some View {
        switch fix {
        case .command(let command):
            HStack(spacing: 8) {
                Text(command)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                Button(copied == command ? L("Copied") : L("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = command
                }
                .controlSize(.small)
            }
        case .action(let action):
            Button(label(action)) { perform(action) }
                .controlSize(.small)
                .disabled(busy)
        case .link(let title, let url):
            if let url = URL(string: url) {
                Link(title, destination: url).font(.callout)
            }
        }
    }

    private func label(_ action: SetupAction) -> String {
        switch action {
        case .cloneNxnative: L("Download nxnative …")
        case .chooseRepo: L("Choose its folder …")
        case .setUpPython: L("Set up Python")
        case .installMetal: L("Install the Metal toolchain")
        case .chooseKeys: L("Choose prod.keys …")
        }
    }

    private var icon: String {
        switch item.status {
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch item.status {
        case .ok: .green
        case .warn: .orange
        case .fail: .red
        }
    }
}
