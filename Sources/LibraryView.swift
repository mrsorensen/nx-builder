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
                    Label(L("No games yet"), systemImage: "gamecontroller")
                } description: {
                    Text(L("Games you build show up here. nxnative game apps in the Applications folder are found too."))
                } actions: {
                    Button(L("Build a game"), action: showBuild)
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
        .navigationTitle(L("My games"))
        .toolbar {
            ToolbarItem {
                Button { showControls = true } label: {
                    Label(L("Keyboard and controllers"), systemImage: "keyboard")
                }
                .help(L("Keyboard and controllers"))
            }
            ToolbarItem {
                Button {
                    Task { await library.refresh(known: model.settings.knownApps) }
                } label: {
                    Label(L("Refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(library.isScanning)
            }
        }
        .task { await library.refresh(known: model.settings.knownApps) }
        .sheet(isPresented: $showControls) { ControlsSheet() }
        .confirmationDialog(L("Move “%@” to the Trash?", "\(toTrash?.name ?? "")"),
                            isPresented: Binding(get: { toTrash != nil }, set: { if !$0 { toTrash = nil } })) {
            Button(L("Move to Trash"), role: .destructive) {
                guard let app = toTrash else { return }
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: app.path), resultingItemURL: nil)
                    model.settings.forget(app: app.path)
                } catch {
                    notice = L("Could not move the app: %@", "\(error.localizedDescription)")
                }
                Task { await library.refresh(known: model.settings.knownApps) }
            }
        } message: {
            Text(L("Your saves stay, so you can build the game again and carry on where you were."))
        }
        .confirmationDialog(L("Delete the build folder of “%@”?", "\(toClean?.app.name ?? "")"),
                            isPresented: Binding(get: { toClean != nil }, set: { if !$0 { toClean = nil } })) {
            Button(L("Delete"), role: .destructive) {
                guard let target = toClean else { return }
                Task { await deleteBuildFolder(target.folder) }
            }
        } message: {
            Text(L("%@ holds the extracted game, shaders and logs. The game app does not need it and keeps working. Building the game again makes it anew, which then takes as long as the first build. It is deleted for good, not moved to the Trash.", "\(toClean?.folder.tildePath ?? "")"))
        }
        .alert(L("My games"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
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
            notice = L("The game files are no longer in %@.", "\(source.tildePath)")
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
        if let error { notice = L("Could not delete it all: %@", "\(error)") }
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
            Text(app.version.isEmpty ? app.titleID : L("Version %@", "\(app.version)"))
                .font(.caption).foregroundStyle(.secondary)
            if let buildSize, buildSize > 0 {
                Text(L("Build folder: %@", "\(formatBytes(buildSize))"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Button(action: play) {
                Label(L("Play"), systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(hovering ? 0.8 : 0.45)))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: play)
        .contextMenu {
            Button(L("Play"), action: play)
            if let rebuild { Button(L("Build again …"), action: rebuild) }
            Button(L("Show in Finder")) { NSWorkspace.shared.revealInFinder(app.path) }
            Button(L("Keyboard and controllers"), action: showControls)
            Divider()
            Button(L("Open the game's log")) {
                if FileManager.default.fileExists(atPath: app.logFile) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: app.logFile))
                } else {
                    notice = L("No log yet. It is made the first time you start the game.")
                }
            }
            Button(L("Open the save folder")) {
                if FileManager.default.fileExists(atPath: app.dataFolder) {
                    NSWorkspace.shared.openFolder(app.dataFolder)
                } else {
                    notice = L("No save folder yet. It is made the first time you start the game.")
                }
            }
            Divider()
            if let clean {
                Button(L("Delete the build folder") + (buildSize.map { " (\(formatBytes($0)))" } ?? "") + " …", action: clean)
            }
            Button(L("Move to Trash …"), role: .destructive, action: trash)
        }
        .help(app.path.tildePath)
    }

    private func play() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: .init())
    }
}
