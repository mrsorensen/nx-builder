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
                Button(L("About NX Builder")) { AppDelegate.showAbout() }
            }
            CommandGroup(replacing: .help) {
                Link(L("nxnative on GitHub"), destination: URL(string: "https://github.com/seedds/nxnative")!)
                Link(L("The games nxnative supports"), destination: URL(string: "https://github.com/seedds/nxnative#games")!)
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
            alert.messageText = L("The game app is being moved")
            alert.informativeText = L("Quit when it is done, or the app would be left half copied.")
            alert.runModal()
            return .terminateCancel
        }
        if tasks.isRunning {
            let alert = NSAlert()
            alert.messageText = L("“%@” is still running", "\(tasks.title)")
            alert.informativeText = L("Quitting stops it. You can run it again from Setup.")
            alert.addButton(withTitle: L("Keep going"))
            alert.addButton(withTitle: L("Stop and quit"))
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
            tasks.cancel()
            return .terminateNow
        }
        guard runner.hasProcess else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = L("A game is still being built")
        alert.informativeText = L("Quitting stops the build. What is already done is reused the next time you build.")
        alert.addButton(withTitle: L("Keep building"))
        alert.addButton(withTitle: L("Stop and quit"))
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
            string: L("A front end for nxnative by seedds (MIT licence), which runs Switch games you own natively on Apple silicon. NX Builder contains no game files or keys."),
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }
}
