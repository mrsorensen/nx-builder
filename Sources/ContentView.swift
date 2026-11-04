import SwiftUI

enum SidebarItem: Hashable {
    case build, library, setup
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .build

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label {
                    HStack {
                        Text(L("Build a game"))
                        Spacer()
                        if model.runner.isBusy { ProgressView().controlSize(.small) }
                    }
                } icon: { Image(systemName: "hammer") }
                .tag(SidebarItem.build)

                Label(L("My games"), systemImage: "gamecontroller")
                    .badge(model.library.apps.count)
                    .tag(SidebarItem.library)

                Label {
                    HStack {
                        Text(L("Setup"))
                        Spacer()
                        if model.tasks.isRunning {
                            ProgressView().controlSize(.small)
                        } else if model.checker.hasChecked && !model.checker.allGood {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        } else if let behind = model.updates.behind, behind > 0 {
                            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                                .help(L("nxnative has updates"))
                        }
                    }
                } icon: { Image(systemName: "checklist") }
                .tag(SidebarItem.setup)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            switch selection ?? .build {
            case .build: BuildView(showSetup: { selection = .setup })
            case .library: LibraryView(showBuild: { selection = .build })
            case .setup: SetupView()
            }
        }
        .task {
            await model.recipes.reload(repo: model.settings.repoPath)
            await model.checker.run(settings: model.settings)
            // A first start on a Mac that is not set up yet opens on Setup.
            if !model.checker.allGood && model.settings.gamePath.isEmpty { selection = .setup }
            await model.library.refresh(known: model.settings.knownApps)
            await model.updates.check(repo: model.settings.repoPath)
        }
    }
}
