import AppKit
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    let showBuild: () -> Void
    @State private var toTrash: GameApp?
    @State private var toClean: (app: GameApp, folder: String)?
    @State private var notice: String?
    @State private var showControls = false

    var body: some View {
        let library = model.library
        Group {
            if library.apps.isEmpty {
                ContentUnavailableView {
                    Label(tr("No games yet", "Ingen spill ennå"), systemImage: "gamecontroller")
                } description: {
                    Text(tr("Games you build show up here. nxnative game apps in the Applications folder are found too.",
                            "Spill du bygger, dukker opp her. Spill-apper fra nxnative i Programmer-mappen blir også funnet."))
                } actions: {
                    Button(tr("Build a game", "Bygg et spill"), action: showBuild)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 230), spacing: 16)], spacing: 16) {
                        let busy = model.runner.isBusy || model.tasks.isRunning
                        ForEach(library.apps) { app in
                            let folder = app.buildFolder(source: source(of: app))
                            GameCard(app: app, buildFolder: folder, buildSize: folder.flatMap { library.buildSizes[$0] },
                                     notice: $notice,
                                     showControls: { showControls = true },
                                     rebuild: busy ? nil : source(of: app).map { source in { rebuild(from: source) } },
                                     clean: busy ? nil : folder.map { f in { toClean = (app, f) } },
                                     trash: { toTrash = app })
                            .task(id: folder) { if let folder, library.buildSizes[folder] == nil { await library.measure(folder) } }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(tr("My games", "Mine spill"))
        .toolbar {
            ToolbarItem {
                Button { showControls = true } label: {
                    Label(tr("Keyboard and controllers", "Tastatur og kontroller"), systemImage: "keyboard")
                }
                .help(tr("Keyboard and controllers", "Tastatur og kontroller"))
            }
            ToolbarItem {
                Button {
                    Task { await library.refresh(known: model.settings.knownApps) }
                } label: {
                    Label(tr("Refresh", "Oppdater listen"), systemImage: "arrow.clockwise")
                }
                .disabled(library.isScanning)
            }
        }
        .task { await library.refresh(known: model.settings.knownApps) }
        .sheet(isPresented: $showControls) { ControlsSheet() }
        .confirmationDialog(tr("Move “\(toTrash?.name ?? "")” to the Trash?", "Flytte «\(toTrash?.name ?? "")» til papirkurven?"),
                            isPresented: Binding(get: { toTrash != nil }, set: { if !$0 { toTrash = nil } })) {
            Button(tr("Move to Trash", "Flytt til papirkurven"), role: .destructive) {
                guard let app = toTrash else { return }
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: app.path), resultingItemURL: nil)
                    model.settings.forget(app: app.path)
                } catch {
                    notice = tr("Could not move the app: \(error.localizedDescription)", "Kunne ikke flytte appen: \(error.localizedDescription)")
                }
                Task { await library.refresh(known: model.settings.knownApps) }
            }
        } message: {
            Text(tr("Your saves stay, so you can build the game again and carry on where you were.",
                    "Lagringsfilene dine blir liggende, så du kan bygge spillet på nytt og fortsette der du var."))
        }
        .confirmationDialog(tr("Delete the build folder of “\(toClean?.app.name ?? "")”?", "Slette byggemappen til «\(toClean?.app.name ?? "")»?"),
                            isPresented: Binding(get: { toClean != nil }, set: { if !$0 { toClean = nil } })) {
            Button(tr("Delete", "Slett"), role: .destructive) {
                guard let target = toClean else { return }
                Task { await deleteBuildFolder(target.folder) }
            }
        } message: {
            Text(tr("\(toClean?.folder.tildePath ?? "") holds the extracted game, shaders and logs. The game app does not need it and keeps working. Building the game again makes it anew, which then takes as long as the first build. It is deleted for good, not moved to the Trash.",
                    "\(toClean?.folder.tildePath ?? "") inneholder det utpakkede spillet, shadere og logger. Spill-appen trenger den ikke og virker videre. Bygger du spillet på nytt, lages den på nytt, og det tar da like lang tid som første gang. Den slettes for godt, ikke til papirkurven."))
        }
        .alert(tr("My games", "Mine spill"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") {}
        } message: {
            Text(notice ?? "")
        }
    }

    /// The game folder an app was built from: as recorded at its build, or, for an app built before
    /// that was recorded, the chosen game folder when it holds this game's build folder.
    private func source(of app: GameApp) -> String? {
        if let known = model.settings.appSources[app.path] { return known }
        let current = model.settings.gamePath
        guard !current.isEmpty, FileManager.default.fileExists(atPath: current + "/\(app.titleID)_build") else { return nil }
        return current
    }

    private func rebuild(from source: String) {
        guard FileManager.default.fileExists(atPath: source) else {
            notice = tr("The game files are no longer in \(source.tildePath).", "Spillfilene ligger ikke lenger i \(source.tildePath).")
            return
        }
        model.settings.gamePath = source
        showBuild()
    }

    private func deleteBuildFolder(_ folder: String) async {
        let error = await Task.detached { () -> String? in
            do { try FileManager.default.removeItem(atPath: folder); return nil } catch { return error.localizedDescription }
        }.value
        model.library.forgetSize(folder)
        if let error { notice = tr("Could not delete it all: \(error)", "Kunne ikke slette alt: \(error)") }
        await model.library.refresh(known: model.settings.knownApps)
    }
}

struct GameCard: View {
    let app: GameApp
    let buildFolder: String?
    let buildSize: Int64?
    @Binding var notice: String?
    let showControls: () -> Void
    let rebuild: (() -> Void)?
    let clean: (() -> Void)?
    let trash: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .shadow(radius: hovering ? 6 : 2, y: 2)
            Text(app.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
            Text(app.version.isEmpty ? app.titleID : tr("Version \(app.version)", "Versjon \(app.version)"))
                .font(.caption).foregroundStyle(.secondary)
            if let buildSize, buildSize > 0 {
                Text(tr("Build folder: \(formatBytes(buildSize))", "Byggemappe: \(formatBytes(buildSize))"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Button(action: play) {
                Label(tr("Play", "Spill"), systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(hovering ? 0.8 : 0.45)))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: play)
        .contextMenu {
            Button(tr("Play", "Spill"), action: play)
            if let rebuild { Button(tr("Build again …", "Bygg på nytt …"), action: rebuild) }
            Button(tr("Show in Finder", "Vis i Finder")) { NSWorkspace.shared.revealInFinder(app.path) }
            Button(tr("Keyboard and controllers", "Tastatur og kontroller"), action: showControls)
            Divider()
            Button(tr("Open the game's log", "Åpne spillets logg")) {
                if FileManager.default.fileExists(atPath: app.logFile) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: app.logFile))
                } else {
                    notice = tr("No log yet. It is made the first time you start the game.", "Ingen logg ennå. Den lages første gang du starter spillet.")
                }
            }
            Button(tr("Open the save folder", "Åpne lagringsmappen")) {
                if FileManager.default.fileExists(atPath: app.dataFolder) {
                    NSWorkspace.shared.openFolder(app.dataFolder)
                } else {
                    notice = tr("No save folder yet. It is made the first time you start the game.", "Ingen lagringsmappe ennå. Den lages første gang du starter spillet.")
                }
            }
            Divider()
            if let clean {
                Button(tr("Delete the build folder", "Slett byggemappen") + (buildSize.map { " (\(formatBytes($0)))" } ?? "") + " …", action: clean)
            }
            Button(tr("Move to Trash …", "Flytt til papirkurven …"), role: .destructive, action: trash)
        }
        .help(app.path.tildePath)
    }

    private func play() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: .init())
    }
}
