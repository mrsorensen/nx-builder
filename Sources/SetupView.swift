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
                    Label(tr("\(checker.failures) thing(s) to fix before you can build. Each has a button or a command to copy into Terminal.",
                             "\(checker.failures) ting må fikses før du kan bygge. Hver har en knapp eller en kommando du kan kopiere inn i Terminal."),
                          systemImage: "wrench.and.screwdriver")
                        .foregroundStyle(.orange)
                }
            }

            if tasks.state != .idle {
                Section(tasks.title) { TaskPanel(tasks: tasks) }
            }

            Section(tr("Folders and keys", "Mapper og nøkler")) {
                PathRow(title: tr("nxnative folder", "nxnative-mappe"), path: settings.repoPath,
                        placeholder: tr("Choose the nxnative folder", "Velg nxnative-mappen"),
                        missing: !settings.hasRepo) {
                    chooseRepo()
                }
                PathRow(title: "prod.keys", path: settings.keysPath,
                        placeholder: tr("Choose the keys dumped from your Switch", "Velg nøkkelfilen fra din Switch"),
                        missing: !FileManager.default.fileExists(atPath: settings.keysPath)) {
                    chooseKeys()
                }
            }

            Section {
                if checker.items.isEmpty && checker.isChecking {
                    HStack { ProgressView().controlSize(.small); Text(tr("Checking …", "Sjekker …")).foregroundStyle(.secondary) }
                }
                ForEach(checker.items) { item in
                    CheckRow(item: item, busy: tasks.isRunning || model.runner.isBusy, perform: perform)
                }
            } header: {
                HStack {
                    Text(tr("What building needs", "Det bygging trenger"))
                    Spacer()
                    if checker.isChecking { ProgressView().controlSize(.small) }
                    Button(tr("Check again", "Sjekk på nytt"), action: recheck)
                        .disabled(checker.isChecking)
                }
            }

            Section("nxnative") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(updateTitle(updates))
                        Text(tr("nxnative gets fixes and new games almost daily. Build a game again after an update to get them.",
                                "nxnative får rettelser og nye spill nesten daglig. Bygg et spill på nytt etter en oppdatering for å få dem."))
                            .font(.caption).foregroundStyle(.secondary)
                        if !updates.localChanges.isEmpty {
                            Text(tr("Changed here: \(updates.localChanges.joined(separator: ", ")). If an update stops on them, NX Builder's own Python environment does not need the guide's change to pyproject.toml.",
                                    "Endret her: \(updates.localChanges.joined(separator: ", ")). Stopper en oppdatering på dem, trenger ikke NX Builders eget Python-miljø guidens endring i pyproject.toml."))
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if updates.checking { ProgressView().controlSize(.small) }
                    Button(tr("Check", "Sjekk")) { Task { await updates.check(repo: settings.repoPath) } }
                        .disabled(updates.checking || !settings.hasRepo)
                    Button(tr("Update", "Oppdater"), action: update)
                        .disabled(tasks.isRunning || model.runner.isBusy || !settings.hasRepo)
                }
                if !updates.frontEndNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Notes for front ends in this update (NX Builder may need an update if one says “break”):",
                                "Merknader til front ends i denne oppdateringen (NX Builder kan trenge en oppdatering hvis en sier «break»):"))
                            .font(.caption)
                        ForEach(updates.frontEndNotes, id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
                    }
                }
                Button { showRecipes = true } label: {
                    Label(tr("Games with a recipe, and the version each needs", "Spill med oppskrift, og versjonen hvert trenger"), systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.link)
                Button { showControls = true } label: {
                    Label(tr("Keyboard and controllers", "Tastatur og kontroller"), systemImage: "keyboard")
                }
                .buttonStyle(.link)
            }

            Section("NX Builder") {
                SwiftUI.Picker(tr("Language", "Språk"), selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                if settings.appLanguage != .system && (settings.appLanguage == .norwegian) != L10n.norwegian {
                    Text(tr("Applies the next time NX Builder starts.", "Gjelder neste gang NX Builder starter."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(tr("Notify me when a build finishes", "Varsle meg når et bygg er ferdig"), isOn: $settings.notify)
                Text(tr("NX Builder only runs nxnative's own build script. It contains no game files or keys: use dumps of games you own and the keys from your own Switch.",
                        "NX Builder kjører bare nxnatives eget byggeskript. Den inneholder ingen spillfiler eller nøkler: bruk dumper av spill du eier og nøklene fra din egen Switch."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tr("Setup", "Oppsett"))
        .sheet(isPresented: $showControls) { ControlsSheet() }
        .sheet(isPresented: $showRecipes) { RecipeListView() }
        .task { if model.updates.behind == nil { await model.updates.check(repo: model.settings.repoPath) } }
        .alert(tr("Setup", "Oppsett"), isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") {}
        } message: {
            Text(problem ?? "")
        }
    }

    private func updateTitle(_ updates: NxnativeUpdates) -> String {
        let current = updates.current.isEmpty ? "" : tr("Version \(updates.current)", "Versjon \(updates.current)")
        switch updates.behind {
        case nil: return current.isEmpty ? tr("Updates", "Oppdateringer") : current
        case 0?: return current + tr(" · up to date", " · oppdatert")
        case let n?: return current + tr(" · \(n) new change(s) available", " · \(n) nye endringer tilgjengelig")
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
                model.tasks.run(tr("Setting up Python", "Setter opp Python"), steps: steps, then: afterTask)
            case .failure(let error):
                model.tasks.fail(tr("Setting up Python", "Setter opp Python"), error.message)
            }
        case .installMetal:
            model.tasks.run(tr("Installing the Metal toolchain", "Installerer Metal-verktøyene"), steps: SetupSteps.metalToolchain(), then: afterTask)
        }
    }

    private func chooseRepo() {
        if let path = FilePicker.folder(message: tr("Choose the folder you cloned nxnative into.", "Velg mappen der nxnative ligger."), startingAt: model.settings.repoPath) {
            model.settings.repoPath = path
            recheck()
            Task { await model.updates.check(repo: path) }
        }
    }

    private func chooseKeys() {
        if let path = FilePicker.file(message: tr("Choose the prod.keys dumped from your own Switch.", "Velg prod.keys fra din egen Switch."), startingAt: model.settings.keysPath) {
            model.settings.keysPath = path
            recheck()
        }
    }

    private func clone() {
        guard let parent = FilePicker.folder(message: tr("Where should nxnative go? A folder “nxnative” is made inside the one you choose (under 1 GB).",
                                                         "Hvor skal nxnative ligge? En mappe «nxnative» lages inni den du velger (under 1 GB)."),
                                             startingAt: NSHomeDirectory()) else { return }
        let dest = parent + "/nxnative"
        if FileManager.default.fileExists(atPath: dest) {
            if FileManager.default.fileExists(atPath: dest + "/scripts/build_ipa_from_nsp.py") {
                model.settings.repoPath = dest
                recheck()
            } else {
                problem = tr("\(dest.tildePath) already exists. Choose another place, or remove that folder first.",
                             "\(dest.tildePath) finnes allerede. Velg et annet sted, eller fjern den mappen først.")
            }
            return
        }
        model.tasks.run(tr("Downloading nxnative", "Laster ned nxnative"), steps: SetupSteps.clone(into: dest)) { ok in
            if ok { model.settings.repoPath = dest }
            afterTask(ok)
        }
    }

    private func update() {
        let repo = model.settings.repoPath
        Task {
            let old = await Task.detached { NxnativeUpdates.head(repo: repo) }.value
            model.tasks.run(tr("Updating nxnative", "Oppdaterer nxnative"), steps: SetupSteps.update(repo: repo)) { ok in
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
                    Label(tr("Done", "Ferdig"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed(let reason):
                    Label(reason, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                case .idle:
                    EmptyView()
                }
                Spacer()
                if tasks.isRunning {
                    Button(tr("Stop", "Stopp")) { tasks.cancel() }
                } else {
                    Button(tr("Close", "Lukk")) { tasks.dismiss() }
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
                    Button(expanded ? tr("Hide details", "Skjul detaljer") : tr("Details", "Detaljer")) { expanded.toggle() }
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
                Button(copied == command ? tr("Copied", "Kopiert") : tr("Copy", "Kopier")) {
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
        case .cloneNxnative: tr("Download nxnative …", "Last ned nxnative …")
        case .chooseRepo: tr("Choose its folder …", "Velg mappen …")
        case .setUpPython: tr("Set up Python", "Sett opp Python")
        case .installMetal: tr("Install the Metal toolchain", "Installer Metal-verktøyene")
        case .chooseKeys: tr("Choose prod.keys …", "Velg prod.keys …")
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
