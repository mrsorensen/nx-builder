import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A labelled path with a «Velg…» button.
struct PathRow: View {
    let title: String
    let path: String
    let placeholder: String
    var missing = false
    let choose: () -> Void

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if missing && !path.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help(tr("No longer there", "Finnes ikke lenger"))
                }
                Text(path.isEmpty ? placeholder : path.tildePath)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
                Button(tr("Choose…", "Velg…"), action: choose)
            }
        }
    }
}

/// Native open panels.
@MainActor
enum FilePicker {
    static func folder(message: String, startingAt start: String) -> String? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = tr("Choose", "Velg")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = startURL(start)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func file(message: String, startingAt start: String) -> String? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = tr("Choose", "Velg")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = startURL(start)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// A game file (XCI, NSP, NSZ, XCZ or NUP), or the folder holding a game's files.
    static func game(startingAt start: String) -> String? {
        let panel = NSOpenPanel()
        panel.message = tr("Choose the game file (XCI or NSP), or the folder with the base game, update and any DLC.", "Velg spillfilen (XCI eller NSP), eller mappen med grunnspill, oppdatering og eventuell DLC.")
        panel.prompt = tr("Choose", "Velg")
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = GameFile.extensions.sorted().flatMap { ext in
            [ext, ext.uppercased()].compactMap { UTType(filenameExtension: $0) }
        } + [.folder]
        panel.directoryURL = startURL(start)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private static func startURL(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return URL(fileURLWithPath: isDir.boolValue ? path : path.deletingLastPathComponent)
        }
        return nil
    }
}

extension NSWorkspace {
    func revealInFinder(_ path: String) {
        activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFolder(_ path: String) {
        open(URL(fileURLWithPath: path))
    }
}
