import AppKit
import SwiftUI

struct BuildView: View {
    @Environment(AppModel.self) private var model
    let showSetup: () -> Void

    @State private var files: [GameFile] = []
    @State private var freeSpace: Int64?
    @State private var hasOldBuild = false
    /// The game's profile lists the shaders nxnative's playtests used (shader_seen.tsv), which
    /// a fast build (--seen-shaders) needs. Only a few profiles have one.
    @State private var fastBuildAvailable = false
    @State private var precheck = RecipePrecheck()
    @State private var showRecipes = false
    @State private var showControls = false
    @State private var askMetal = false
    @State private var problem: String?
    @State private var dropTargeted = false
    /// A game file picked on its own in a shared folder (Downloads), waiting for the player's choice.
    @State private var looseFile: String?

    private var recipe: Recipe? { precheck.titleID.flatMap { model.recipes.recipe($0) } }

    var body: some View {
        @Bindable var settings = model.settings
        let runner = model.runner

        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        PathRow(title: tr("Game", "Spill"), path: settings.gamePath,
                                placeholder: tr("Choose an XCI or NSP file, or its folder", "Velg en XCI- eller NSP-fil, eller mappen den ligger i"),
                                missing: !FileManager.default.fileExists(atPath: settings.gamePath)) {
                            if let path = FilePicker.game(startingAt: settings.gamePath) { choose(path) }
                        }
                        if !settings.gamePath.isEmpty { gameFiles }
                        if !files.isEmpty { RecipeHintRow(check: precheck, recipe: recipe) }
                    } header: {
                        Text(tr("The game", "Spillet"))
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("Tip: you can also drop a file or folder on the window. The base game and its update go in the same folder, from the same region, in the version the game's recipe was made for.",
                                    "Tips: Du kan også dra en fil eller mappe inn i vinduet. Grunnspillet og oppdateringen må ligge i samme mappe, være samme region og den versjonen spillets oppskrift er laget for."))
                                .font(.caption).foregroundStyle(.secondary)
                            Button(tr("Which games have a recipe, and which version they need …", "Se hvilke spill som har oppskrift, og hvilken versjon de trenger …")) { showRecipes = true }
                                .buttonStyle(.link).font(.caption)
                        }
                    }
                    .disabled(runner.isBusy)

                    Section(tr("Settings", "Innstillinger")) {
                        PathRow(title: "prod.keys", path: settings.keysPath,
                                placeholder: tr("Choose the keys dumped from your Switch", "Velg nøkkelfilen fra din Switch"),
                                missing: !FileManager.default.fileExists(atPath: settings.keysPath)) {
                            if let path = FilePicker.file(message: tr("Choose the prod.keys dumped from your own Switch.", "Velg prod.keys fra din egen Switch."), startingAt: settings.keysPath) {
                                settings.keysPath = path
                            }
                        }
                        SwiftUI.Picker(tr("Game language", "Språk i spillet"), selection: $settings.language) {
                            ForEach(gameLanguages) { Text($0.name).tag($0.code) }
                        }
                        SwiftUI.Picker(tr("Save the app in", "Lagre appen i"), selection: $settings.destination) {
                            ForEach(Destination.allCases) { Text($0.label).tag($0) }
                        }
                        if settings.destination == .custom {
                            PathRow(title: tr("Folder", "Mappe"), path: settings.customDestPath, placeholder: tr("Choose a folder", "Velg en mappe")) {
                                if let path = FilePicker.folder(message: tr("Where should the finished app go?", "Hvor skal den ferdige appen ligge?"), startingAt: settings.customDestPath) {
                                    settings.customDestPath = path
                                }
                            }
                        }
                        if fastBuildAvailable {
                            Toggle(isOn: $settings.seenShaders) {
                                Text(tr("Fast build", "Raskt bygg"))
                                Text(tr("Builds only the shaders nxnative's playtests used: minutes instead of hours, but untested places may lack graphics.",
                                        "Bygger bare shaderne fra nxnatives testspilling: minutter i stedet for timer, men steder som ikke er testet, kan mangle grafikk."))
                            }
                        }
                        if model.checker.metalMismatch || settings.allowOtherMetal {
                            Toggle(isOn: $settings.allowOtherMetal) {
                                Text(tr("Build with this Mac's Metal compiler", "Bygg med denne Macens Metal-kompilator"))
                                Text(tr("Your Xcode is not the one nxnative was tested with. Without this, games that use NVN stop before their shaders. Untested: graphics glitches are possible.",
                                        "Xcode-versjonen din er ikke den nxnative er testet med. Uten denne stopper bygget av spill som bruker NVN. Ikke testet: grafikkfeil kan forekomme."))
                            }
                        }
                    }
                    .disabled(runner.isBusy)

                    if runner.state != .idle {
                        Section(tr("Progress", "Fremdrift")) {
                            ProgressPanel(runner: runner)
                        }
                        .id("progress")
                    }
                }
                .formStyle(.grouped)
                .onChange(of: runner.state) { _, new in
                    // Show the progress when a build starts or ends; the settings stay one scroll away.
                    if case .moving = new { return }
                    if new == .idle { return }
                    withAnimation { proxy.scrollTo("progress", anchor: .top) }
                }
            }

            Divider()
            bottomBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .navigationTitle(tr("Build a game", "Bygg et spill"))
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !runner.isBusy, let url = urls.first else { return false }
            choose(url.path)
            return true
        } isTargeted: { dropTargeted = $0 }
        .onChange(of: settings.gamePath, initial: true) { refreshFiles() }
        .onChange(of: runner.state) { refreshFiles() }
        .sheet(isPresented: $showRecipes) { RecipeListView() }
        .sheet(isPresented: $showControls) { ControlsSheet() }
        .alert(tr("Put the game in a folder of its own?", "Legge spillet i en egen mappe?"),
               isPresented: Binding(get: { looseFile != nil }, set: { if !$0 { looseFile = nil } })) {
            Button(tr("Move to its own folder", "Flytt til egen mappe")) { moveLooseFile() }
            Button(tr("Use the folder it is in", "Bruk mappen den ligger i")) {
                if let file = looseFile { settings.gamePath = file.deletingLastPathComponent }
                looseFile = nil
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) { looseFile = nil }
        } message: {
            if let file = looseFile {
                let url = URL(fileURLWithPath: file)
                let folder = GameFile.folderName(for: url), parent = file.deletingLastPathComponent.tildePath
                Text(tr("nxnative builds from one folder per game and puts a build folder of several GB beside the game files. “\(url.lastPathComponent)” moves to a new folder, “\(folder)”, in \(parent). Put the update and any DLC in that folder too.",
                        "nxnative bygger fra én mappe per spill og lager en byggemappe på flere GB ved siden av spillfilene. «\(url.lastPathComponent)» flyttes til en ny mappe, «\(folder)», i \(parent). Legg oppdateringen og eventuell DLC i den samme mappen."))
            }
        }
        .alert(tr("Build with this Mac's Metal compiler?", "Bygge med denne Macens Metal-kompilator?"), isPresented: $askMetal) {
            Button(tr("Build anyway", "Bygg likevel")) {
                settings.allowOtherMetal = true
                startBuild()
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        } message: {
            Text(tr("Your Xcode's Metal compiler is not the one nxnative tested its shaders with, so nxnative stops games that use NVN before their shaders. You can build with it anyway (untested: graphics glitches are possible), or install the tested Xcode beside yours first. The choice is kept for later builds.",
                    "Xcode-versjonen din har ikke Metal-kompilatoren nxnative testet shaderne med, så nxnative stopper spill som bruker NVN før shaderne. Du kan bygge med den likevel (ikke testet: grafikkfeil kan forekomme), eller installere den testede Xcode-versjonen ved siden av først. Valget huskes til senere bygg."))
        }
        .alert(tr("Cannot build yet", "Kan ikke bygge ennå"), isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") {}
        } message: {
            Text(problem ?? "")
        }
    }

    // MARK: - Pieces

    @ViewBuilder private var gameFiles: some View {
        if files.isEmpty {
            Text(tr("No NSP, XCI, NSZ or NUP files here.", "Fant ingen NSP-, XCI-, NSZ- eller NUP-filer her."))
                .foregroundStyle(.secondary)
        } else {
            ForEach(files) { file in
                HStack {
                    Image(systemName: file.symbol).foregroundStyle(.secondary).frame(width: 18)
                    Text(file.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if !file.label.isEmpty {
                        Text(file.label)
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))
                    }
                    if file.size > 0 {
                        Text(formatBytes(file.size)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            if let freeSpace {
                let total = files.reduce(Int64(0)) { $0 + $1.size }
                let needed = hasOldBuild ? 0 : total * 2 + 10_000_000_000
                HStack {
                    Image(systemName: freeSpace < needed ? "exclamationmark.triangle.fill" : "internaldrive")
                        .foregroundStyle(freeSpace < needed ? .orange : .secondary)
                        .frame(width: 18)
                    Text(tr("Free space: \(formatBytes(freeSpace))", "Ledig plass: \(formatBytes(freeSpace))")
                         + (hasOldBuild ? tr(" · an earlier build is here, so the next one is faster", " · tidligere bygg finnes, neste bygg går raskere")
                                        : tr(" · a first build needs about \(formatBytes(needed))", " · første bygg trenger ca. \(formatBytes(needed))")))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var bottomBar: some View {
        let runner = model.runner
        HStack(spacing: 10) {
            if !model.checker.allGood && model.checker.hasChecked {
                Button {
                    showSetup()
                } label: {
                    Label(tr("Something is missing in Setup", "Noe mangler i oppsettet"), systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.link)
            }
            Spacer()
            switch runner.state {
            case .running:
                Button(tr("Stop", "Avbryt"), role: .cancel) { runner.cancel() }
                    .keyboardShortcut(.cancelAction)
            case .moving:
                ProgressView().controlSize(.small)
            case .succeeded(let app):
                Button(tr("Keyboard and controllers", "Tastatur og kontroller")) { showControls = true }
                Button(tr("Show in Finder", "Vis i Finder")) { NSWorkspace.shared.revealInFinder(app) }
                Button(tr("Build again", "Bygg på nytt")) { startBuild() }
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: app))
                } label: {
                    Label(tr("Play", "Spill nå"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            case .failed(let reason):
                if let folder = runner.buildFolder, FileManager.default.fileExists(atPath: folder + "/logs") {
                    Button(tr("Open the logs", "Åpne loggene")) { NSWorkspace.shared.openFolder(folder + "/logs") }
                }
                if let fix = BuildFix(reason: reason, settings: model.settings) {
                    Button(fix.label) {
                        fix.apply(to: model.settings)
                        startBuild()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    buildButton
                }
            case .cancelled, .idle:
                buildButton
            }
        }
    }

    private var buildButton: some View {
        Button {
            startBuild()
        } label: {
            Label(tr("Build the game", "Bygg spillet"), systemImage: "hammer.fill")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(model.settings.gamePath.isEmpty || model.tasks.isRunning)
    }

    // MARK: - Actions

    /// A folder or .nup file is used as it is. A single XCI / NSP is used through its folder when
    /// that folder holds only game files; in a shared folder (Downloads) the player is asked first.
    private func choose(_ path: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        guard GameFile.packageExtensions.contains(ext) else {
            model.settings.gamePath = path
            return
        }
        let folder = path.deletingLastPathComponent
        if GameFile.isGameFolder(folder) {
            model.settings.gamePath = folder
        } else {
            looseFile = path
        }
    }

    private func moveLooseFile() {
        guard let file = looseFile else { return }
        looseFile = nil
        let fm = FileManager.default
        let url = URL(fileURLWithPath: file)
        let folder = url.deletingLastPathComponent().appendingPathComponent(GameFile.folderName(for: url))
        let target = folder.appendingPathComponent(url.lastPathComponent)
        do {
            if fm.fileExists(atPath: target.path) {
                problem = tr("\(folder.path.tildePath) already has a file of that name.", "Det finnes allerede en fil med samme navn i \(folder.path.tildePath).")
                return
            }
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.moveItem(at: url, to: target)   // the same folder's volume: a rename, instant
            model.settings.gamePath = folder.path
        } catch {
            problem = tr("Could not move the file: \(error.localizedDescription)", "Kunne ikke flytte filen: \(error.localizedDescription)")
        }
    }

    private func refreshFiles() {
        let path = model.settings.gamePath
        let repo = model.settings.repoPath
        Task {
            let result = await Task.detached { () -> ([GameFile], Int64?, Bool, Bool, RecipePrecheck) in
                let files = GameFile.scan(path)
                let check = RecipePrecheck.make(files: files, repo: repo)
                let seen = GameFile.baseTitleID(files).map { repo + "/dm/games/\($0)/shader_seen.tsv" }
                let fast = seen.map { FileManager.default.fileExists(atPath: $0) } ?? false
                var folder = path
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), !isDir.boolValue {
                    folder = folder.deletingLastPathComponent
                }
                let free = (try? URL(fileURLWithPath: folder).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                    .volumeAvailableCapacityForImportantUsage
                let old = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).contains { $0.hasSuffix("_build") }
                return (files, free, old, fast, check)
            }.value
            files = result.0
            freeSpace = result.1
            hasOldBuild = result.2
            fastBuildAvailable = result.3
            precheck = result.4
        }
    }

    private func startBuild() {
        let settings = model.settings
        let fm = FileManager.default
        guard !model.tasks.isRunning else {
            problem = tr("“\(model.tasks.title)” is running in Setup. Build when it is done.", "«\(model.tasks.title)» kjører under Oppsett. Bygg når den er ferdig.")
            return
        }
        guard fm.fileExists(atPath: settings.gamePath) else {
            problem = tr("Choose the game files first.", "Velg spillfilene først.")
            return
        }
        guard !files.isEmpty else {
            problem = tr("The folder has no game files (NSP, XCI, NSZ, XCZ or NUP).", "Mappen har ingen spillfiler (NSP, XCI, NSZ, XCZ eller NUP).")
            return
        }
        if files.contains(where: \.needsKeys) && !fm.fileExists(atPath: settings.keysPath) {
            problem = tr("NSP and XCI files need the prod.keys from your own Switch. Choose the file under Settings.",
                         "NSP- og XCI-filer trenger prod.keys fra din egen Switch. Velg filen under Innstillinger.")
            return
        }
        guard settings.hasRepo else {
            problem = tr("nxnative was not found in \(settings.repoPath.tildePath). Download it or choose its folder in Setup.",
                         "Fant ikke nxnative i \(settings.repoPath.tildePath). Last den ned eller velg mappen under Oppsett.")
            return
        }
        guard fm.isExecutableFile(atPath: settings.python) else {
            problem = tr("There is no Python environment for the build script yet. Set it up in Setup.",
                         "Det finnes ikke noe Python-miljø for byggeskriptet ennå. Sett det opp under Oppsett.")
            return
        }
        if settings.destination == .custom && settings.customDestPath.isEmpty {
            problem = tr("Choose the folder the app goes in.", "Velg mappen appen skal lagres i.")
            return
        }
        // A game known not to use NVN needs no answer about the Metal compiler.
        let mayUseNVN = recipe.map { $0.graphics.contains("NVN") } ?? true
        if model.checker.metalMismatch && !settings.allowOtherMetal && mayUseNVN {
            askMetal = true
            return
        }
        let source = settings.gamePath
        model.runner.start(settings: settings, seenShaders: fastBuildAvailable && settings.seenShaders) { app in
            settings.remember(app: app, builtFrom: source)
            Task { await model.library.refresh(known: settings.knownApps) }
        }
    }
}

// MARK: - Known failures with a one-click way on

/// A failure the build script explains, and the setting that gets past it.
enum BuildFix {
    case withoutFastBuild      // the profile has no shader_seen.tsv for --seen-shaders
    case allowOtherMetal       // this Xcode's Metal compiler is not the one nxnative tested with

    /// The failure the script's message names, whatever the settings are now.
    init?(reason: String) {
        if reason.contains("--seen-shaders") {
            self = .withoutFastBuild
        } else if reason.contains("Metal compiler is not the one") {
            self = .allowOtherMetal
        } else {
            return nil
        }
    }

    /// The fix, when the setting it changes is not changed already.
    @MainActor init?(reason: String, settings: AppSettings) {
        switch BuildFix(reason: reason) {
        case .withoutFastBuild? where settings.seenShaders: self = .withoutFastBuild
        case .allowOtherMetal? where !settings.allowOtherMetal: self = .allowOtherMetal
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .withoutFastBuild: tr("Build without fast build", "Bygg uten raskt bygg")
        case .allowOtherMetal: tr("Build with this Metal compiler", "Bygg med denne Metal-kompilatoren")
        }
    }

    /// Why the build stopped, shown above the script's own message.
    var explanation: String {
        switch self {
        case .withoutFastBuild:
            tr("This game has no list of the shaders nxnative's playtests used, so a fast build is not possible. It has to be built with every shader.",
               "Dette spillet har ingen liste over shaderne fra nxnatives testspilling, så «Raskt bygg» går ikke. Det må bygges med alle shaderne.")
        case .allowOtherMetal:
            tr("Your Xcode does not have the Metal compiler nxnative was tested with. You can build with yours anyway (untested, graphics glitches are possible), or install the tested Xcode beside it and build again.",
               "Xcode-versjonen din har ikke Metal-kompilatoren nxnative er testet med. Du kan bygge med denne likevel (ikke testet, grafikkfeil kan forekomme), eller installere den testede Xcode-versjonen ved siden av og bygge på nytt.")
        }
    }

    @MainActor func apply(to settings: AppSettings) {
        switch self {
        case .withoutFastBuild: settings.seenShaders = false
        case .allowOtherMetal: settings.allowOtherMetal = true
        }
    }
}

// MARK: - Progress

struct ProgressPanel: View {
    @Environment(AppModel.self) private var model
    let runner: BuildRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            status
            if let report = runner.recipe {
                RecipeCard(report: report, recipe: model.recipes.recipe(report.id))
            }
            HStack {
                Text(tr("Log", "Logg")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(runner.logText, forType: .string)
                } label: {
                    Label(tr("Copy log", "Kopier loggen"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless).font(.caption)
                .disabled(runner.log.isEmpty)
            }
            LogView(lines: runner.log)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var status: some View {
        switch runner.state {
        case .running:
            HStack(alignment: .firstTextBaseline) {
                Text(runner.stageCount > 0
                     ? tr("Step \(runner.stageIndex) of \(runner.stageCount): \(runner.stageName)", "Steg \(runner.stageIndex) av \(runner.stageCount): \(runner.stageName)")
                     : tr("Starting …", "Starter …"))
                    .font(.headline)
                Spacer()
                if let start = runner.startedAt {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(formatDuration(context.date.timeIntervalSince(start)))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            if let fraction = runner.fraction {
                ProgressView(value: min(max(fraction, 0), 1))
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            HStack {
                Text([runner.stepName, runner.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                if let eta = runner.eta, eta > 0 {
                    Text(tr("about \(formatDuration(eta)) left in this step", "ca. \(formatDuration(eta)) igjen av dette steget")).monospacedDigit()
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(tr("A game's first build takes from a few minutes to about an hour. The Mac stays awake until it is done.",
                    "Første bygg av et spill kan ta fra noen minutter til rundt en time. Macen holdes våken så lenge."))
                .font(.caption).foregroundStyle(.tertiary)
        case .moving(let folder):
            HStack {
                ProgressView().controlSize(.small)
                Text(tr("Moving the app to \(folder.tildePath) …", "Flytter appen til \(folder.tildePath) …"))
            }
        case .succeeded(let app):
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    let name = (app.lastPathComponent as NSString).deletingPathExtension
                    Text(tr("Done! \(name) is ready.", "Ferdig! \(name) er klar.")).font(.headline)
                    Text(app.tildePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if let start = runner.startedAt, let end = runner.finishedAt {
                        Text(tr("Took \(formatDuration(end.timeIntervalSince(start))).", "Tok \(formatDuration(end.timeIntervalSince(start))).")).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(tr("The first start takes a few minutes: macOS shows “Verifying …” while it checks the new app. Later starts take seconds.",
                            "Første start tar noen minutter: macOS viser «Verifiserer …» mens den sjekker den nye appen. Senere starter tar sekunder."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
            }
        case .failed(let reason):
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("The build stopped", "Bygget stoppet")).font(.headline)
                    if let fix = BuildFix(reason: reason) {
                        Text(fix.explanation).font(.callout)
                    }
                    Text(reason).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(tr("More: the logs in the game's _build folder. To ask for help, copy the log below.",
                            "Mer: loggene i spillets _build-mappe. Kopier loggen under hvis du vil be om hjelp."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).font(.title2)
            }
        case .cancelled:
            Label(tr("The build was stopped. What was done is reused next time.", "Bygget ble avbrutt. Det som ble ferdig, blir gjenbrukt neste gang."), systemImage: "stop.circle")
        case .idle:
            EmptyView()
        }
    }
}

struct LogView: View {
    let lines: [LogLine]
    var height: ClosedRange<CGFloat> = 160...320

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(line.time).foregroundStyle(.tertiary)
                            Text(line.text).foregroundStyle(color(line.kind))
                                .fontWeight(line.kind == .stage ? .semibold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .id(line.id)
                    }
                }
                .textSelection(.enabled)
                .padding(8)
            }
            .frame(minHeight: height.lowerBound, maxHeight: height.upperBound)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            .onChange(of: lines.last?.id) {
                if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func color(_ kind: LogKind) -> Color {
        switch kind {
        case .info: .primary
        case .stage: .accentColor
        case .ok: .green
        case .warn: .orange
        case .red: .red
        case .stderr: .secondary
        }
    }
}
