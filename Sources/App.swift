import AppKit
import SwiftUI
import UserNotifications

@main
struct NXBuilderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        Migration.run()   // before the settings are read
        _model = State(initialValue: AppModel.shared)
    }

    var body: some Scene {
        Window("NX Builder", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 840, minHeight: 620)
        }
        .defaultSize(width: 980, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button(tr("About NX Builder", "Om NX Builder")) { AppDelegate.showAbout() }
            }
            CommandGroup(replacing: .help) {
                Link(tr("nxnative on GitHub", "nxnative på GitHub"), destination: URL(string: "https://github.com/seedds/nxnative")!)
                Link(tr("The games nxnative supports", "Spillene nxnative støtter"), destination: URL(string: "https://github.com/seedds/nxnative#games")!)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Work out the Terminal-like PATH off the main thread, before the first check needs it.
        Task.detached { _ = Shell.searchPath }
        UNUserNotificationCenter.current().delegate = self
    }

    /// Closing the window quits, unless a build is running: then it keeps going in the Dock.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppModel.shared.runner.isBusy && !AppModel.shared.tasks.isRunning
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let runner = AppModel.shared.runner, tasks = AppModel.shared.tasks
        if case .moving = runner.state {
            let alert = NSAlert()
            alert.messageText = tr("The game app is being moved", "Spill-appen flyttes")
            alert.informativeText = tr("Quit when it is done, or the app would be left half copied.", "Avslutt når den er ferdig, ellers blir appen halvveis kopiert.")
            alert.runModal()
            return .terminateCancel
        }
        if tasks.isRunning {
            let alert = NSAlert()
            alert.messageText = tr("“\(tasks.title)” is still running", "«\(tasks.title)» kjører fortsatt")
            alert.informativeText = tr("Quitting stops it. You can run it again from Setup.", "Hvis du avslutter, stoppes den. Du kan kjøre den på nytt fra Oppsett.")
            alert.addButton(withTitle: tr("Keep going", "Fortsett"))
            alert.addButton(withTitle: tr("Stop and quit", "Stopp og avslutt"))
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
            tasks.cancel()
            return .terminateNow
        }
        guard runner.hasProcess else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = tr("A game is still being built", "Et spill bygges fortsatt")
        alert.informativeText = tr("Quitting stops the build. What is already done is reused the next time you build.",
                                   "Hvis du avslutter, stoppes bygget. Det som allerede er ferdig, blir gjenbrukt neste gang du bygger.")
        alert.addButton(withTitle: tr("Keep building", "Fortsett å bygge"))
        alert.addButton(withTitle: tr("Stop and quit", "Stopp og avslutt"))
        if alert.runModal() == .alertSecondButtonReturn {
            runner.stopForQuit()
            return .terminateNow
        }
        return .terminateCancel
    }

    /// Clicking a notification brings the window back.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { NSApp.activate() }
    }

    @MainActor static func showAbout() {
        let credits = NSMutableAttributedString(
            string: tr("A front end for nxnative by seedds (MIT licence), which runs Switch games you own natively on Apple silicon. NX Builder contains no game files or keys.",
                       "Et grensesnitt for nxnative av seedds (MIT-lisens), som kjører Switch-spill du eier direkte på Apple silicon. NX Builder inneholder ingen spillfiler eller nøkler."),
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }
}
