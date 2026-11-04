import AppKit
import Foundation
import Observation
import UserNotifications

enum BuildState: Equatable {
    case idle
    case running
    case moving(String)          // the destination folder
    case succeeded(String)       // the finished app
    case failed(String)          // why
    case cancelled

    var isBusyState: Bool {
        switch self {
        case .running, .moving: true
        default: false
        }
    }
}

enum LogKind { case info, stage, ok, warn, red, stderr }

struct LogLine: Identifiable {
    let id: Int
    let time: String
    let text: String
    let kind: LogKind

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func now() -> String { clock.string(from: Date()) }
}

/// Runs `scripts/build_ipa_from_nsp.py --platform mac-app --progress json` and follows its events
/// (nxnative's docs/frontends.md, "Building: the NSP script").
@MainActor @Observable
final class BuildRunner {
    private(set) var state: BuildState = .idle
    private(set) var stageIndex = 0
    private(set) var stageCount = 0
    private(set) var stageName = ""
    private(set) var stepName = ""
    private(set) var fraction: Double?
    private(set) var eta: Double?
    private(set) var detail = ""
    private(set) var log: [LogLine] = []
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?
    private(set) var gamePath = ""
    /// What the script said about the recipe (game profile) it builds with.
    private(set) var recipe: RecipeReport?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var reportedApp: String?
    @ObservationIgnored private var lastRed: String?
    @ObservationIgnored private var stderrTail: [String] = []
    @ObservationIgnored private var cancelRequested = false
    @ObservationIgnored private var destination: String?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var nextLineID = 0
    @ObservationIgnored private var onFinish: ((String) -> Void)?
    @ObservationIgnored private var notifyWhenDone = true
    /// The script has started on another program of a multi-program game (`==== program N`):
    /// its messages are not the main program's.
    @ObservationIgnored private var inSubProgram = false

    var isBusy: Bool { state.isBusyState }

    var hasProcess: Bool { process?.isRunning ?? false }

    func start(settings: AppSettings, seenShaders: Bool, onSuccess: @escaping (String) -> Void) {
        guard !isBusy else { return }
        resetForStart()
        gamePath = settings.gamePath
        destination = settings.destinationFolder
        onFinish = onSuccess
        notifyWhenDone = settings.notify
        if notifyWhenDone {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        let repo = settings.repoPath, python = settings.python
        // The child makes itself a process group leader before it becomes the build script,
        // so Cancel can reach the script and every tool it started, as Ctrl-C in a terminal does.
        var args = ["-c", "import os, sys; os.setpgid(0, 0); os.execv(sys.executable, [sys.executable] + sys.argv[1:])",
                    settings.buildScript, settings.gamePath,
                    "--platform", "mac-app", "--progress", "json"]
        if FileManager.default.fileExists(atPath: settings.keysPath) { args += ["--keys", settings.keysPath] }
        if !settings.language.isEmpty { args += ["--language", settings.language] }
        if settings.allowOtherMetal { args.append("--allow-other-metal") }
        if seenShaders { args.append("--seen-shaders") }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: repo)
        p.environment = Shell.environment(python: python)
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err

        let (exits, exitCont) = AsyncStream.makeStream(of: Int32.self)
        p.terminationHandler = { proc in
            exitCont.yield(proc.terminationStatus)
            exitCont.finish()
        }

        append(.info, L("Building %@ …", "\(settings.gamePath.lastPathComponent)"))
        do {
            try p.run()
        } catch {
            state = .failed(L("Could not start the build script: %@", "\(error.localizedDescription)"))
            return
        }
        process = p
        state = .running
        startedAt = Date()
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .suddenTerminationDisabled],
            reason: "Building a game with nxnative")

        let outHandle = out.fileHandleForReading, errHandle = err.fileHandleForReading
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await Shell.readLines(outHandle) { line in await self.handleStdout(line) } }
                group.addTask { await Shell.readLines(errHandle) { line in await self.handleStderr(line) } }
            }
            var status: Int32 = -1
            for await s in exits { status = s }
            await self.finished(status: status)
        }
    }

    func cancel() {
        guard let p = process, p.isRunning else { return }
        cancelRequested = true
        append(.warn, L("Stopping … (what is done is reused next time)"))
        let group = p.processIdentifier
        killpg(group, SIGINT)
        Task {
            try? await Task.sleep(for: .seconds(15))
            if p.isRunning { killpg(group, SIGTERM) }
        }
    }

    /// Stops the build before the app quits; waits a few seconds for it to clean up.
    func stopForQuit() {
        guard let p = process, p.isRunning else { return }
        cancelRequested = true
        let group = p.processIdentifier
        killpg(group, SIGINT)
        let deadline = Date().addingTimeInterval(6)
        while p.isRunning && Date() < deadline { usleep(100_000) }
        if p.isRunning { killpg(group, SIGTERM) }
    }

    func clear() {
        guard !isBusy else { return }
        state = .idle
        log = []
        stageIndex = 0; stageCount = 0; stageName = ""; stepName = ""; detail = ""
        fraction = nil; eta = nil
        recipe = nil
    }

    /// The log as plain text, for a bug report or a forum post.
    var logText: String {
        log.map { "\($0.time) \($0.text)" }.joined(separator: "\n")
    }

    // MARK: - Events

    private func resetForStart() {
        log = []
        stageIndex = 0; stageCount = 0; stageName = ""; stepName = ""; detail = ""
        fraction = nil; eta = nil
        reportedApp = nil; lastRed = nil; stderrTail = []
        recipe = nil
        inSubProgram = false
        cancelRequested = false
        startedAt = nil; finishedAt = nil
    }

    private func handleStdout(_ line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ev = obj["ev"] as? String else {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { append(.info, line) }
            return
        }
        switch ev {
        case "stage":
            stageIndex = obj["k"] as? Int ?? stageIndex
            stageCount = obj["n"] as? Int ?? stageCount
            stageName = obj["name"] as? String ?? ""
            stepName = obj["step"] as? String ?? ""
            fraction = nil; eta = nil; detail = ""
            append(.stage, "[\(stageIndex)/\(stageCount)] \(stageName)")
        case "step":
            stepName = obj["step"] as? String ?? ""
            fraction = nil; eta = nil; detail = ""
        case "progress":
            if let n = obj["n"] as? Int { stageCount = n }
            stepName = obj["step"] as? String ?? stepName
            fraction = (obj["frac"] as? NSNumber)?.doubleValue
            eta = (obj["eta"] as? NSNumber)?.doubleValue
            detail = progressDetail(obj)
        case "stage_end":
            let ok = obj["ok"] as? Bool ?? true
            let warn = obj["warn"] as? Bool ?? false
            let name = obj["name"] as? String ?? stageName
            let summary = obj["summary"] as? String ?? ""
            let elapsed = (obj["elapsed"] as? NSNumber)?.doubleValue ?? 0
            let mark = !ok ? "✗" : warn ? "⚠" : "✓"
            let text = "\(mark) \(name) (\(formatDuration(elapsed)))" + (summary.isEmpty ? "" : ": \(summary)")
            append(!ok ? .red : warn ? .warn : .ok, text)
            if ok { fraction = 1 }
        case "say":
            guard var msg = obj["msg"] as? String else { return }
            var time: String?
            if let r = msg.range(of: #"^\[\d\d:\d\d:\d\d\] "#, options: .regularExpression) {
                time = String(msg[r]).trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                msg.removeSubrange(r)
            }
            let red = msg.hasPrefix("[RED] ")
            if red {
                msg.removeFirst("[RED] ".count)
                lastRed = msg
            }
            if msg.hasPrefix("==== program") { inSubProgram = true }
            // The report at the end is the main program's again ("this Mac app uses …").
            if !inSubProgram || msg.contains("this Mac app") { RecipeReport.update(&recipe, with: msg) }
            if !inSubProgram, reportedApp == nil, msg.hasPrefix("app name:"), let r = msg.range(of: "; app: ", options: .backwards) {
                reportedApp = String(msg[r.upperBound...])
            }
            append(red ? .red : .info, msg, time: time)
        default:
            break   // shaders_stale and newer events: a say with the same news follows
        }
    }

    private func handleStderr(_ line: String) {
        stderrTail.append(line)
        if stderrTail.count > 40 { stderrTail.removeFirst(stderrTail.count - 40) }
        append(.stderr, line)
    }

    private func progressDetail(_ obj: [String: Any]) -> String {
        var parts: [String] = []
        if let done = (obj["done"] as? NSNumber)?.int64Value {
            let unit = obj["unit"] as? String ?? ""
            let total = (obj["total"] as? NSNumber)?.int64Value
            let about = (obj["est"] as? Bool ?? false) ? L("about ") : ""
            let of = L(" of ")
            if unit == "B" {
                parts.append(formatBytes(done) + (total.map { of + about + formatBytes($0) } ?? ""))
            } else {
                parts.append("\(done)" + (total.map { "\(of)\(about)\($0)" } ?? "") + (unit.isEmpty ? "" : " \(unit)"))
            }
        }
        if let note = obj["note"] as? String, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    private func append(_ kind: LogKind, _ text: String, time: String? = nil) {
        log.append(LogLine(id: nextLineID, time: time ?? LogLine.now(), text: text, kind: kind))
        nextLineID += 1
        if log.count > 3000 { log.removeFirst(log.count - 3000) }
    }

    // MARK: - The end of a build

    private func finished(status: Int32) async {
        process = nil
        defer {   // after the app is moved too: a copy to another volume keeps the Mac awake as well
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            activity = nil
        }
        finishedAt = Date()

        if status == 0 && !cancelRequested {
            guard let built = reportedApp ?? findBuiltApp() else {
                state = .failed(L("The build finished, but the app was not found. See the log."))
                notify(success: false)
                return
            }
            var final = built
            if let dest = destination, !Self.sameFolder(built.deletingLastPathComponent, dest) {
                state = .moving(dest)
                append(.info, L("Moving the app to %@ …", "\(dest.tildePath)"))
                let result = await Task.detached { Result { try Self.moveApp(built, toFolder: dest) } }.value
                switch result {
                case .success(let moved):
                    final = moved.path
                    if let old = moved.trashed {
                        append(.info, L("The earlier build, %@, went to the Trash.", "\(old.tildePath)"))
                    }
                case .failure(let error):
                    append(.warn, L("Could not move the app (%@). It is in %@.", "\(error.localizedDescription)", "\(built.deletingLastPathComponent.tildePath)"))
                }
            }
            append(.ok, L("Done: %@", "\(final.tildePath)"))
            state = .succeeded(final)
            onFinish?(final)
            notify(success: true, app: final)
        } else if cancelRequested || status == 130 {
            state = .cancelled
            append(.warn, L("The build was stopped."))
        } else {
            let reason = lastRed
                ?? stderrTail.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                ?? L("The build script stopped with exit code %@.", "\(status)")
            state = .failed(reason)
            notify(success: false)
        }
    }

    /// The newest .app beside the game files, for when the script's message was not seen.
    private func findBuiltApp() -> String? {
        var folder = gamePath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), !isDir.boolValue {
            folder = folder.deletingLastPathComponent
        }
        let started = startedAt ?? .distantPast
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: folder), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls
            .filter { $0.pathExtension == "app" }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      date >= started.addingTimeInterval(-5) else { return nil }
                return (url, date)
            }
            .max { $0.1 < $1.1 }?.0.path
    }

    nonisolated static func sameFolder(_ a: String, _ b: String) -> Bool {
        URL(fileURLWithPath: a).resolvingSymlinksInPath().standardizedFileURL == URL(fileURLWithPath: b).resolvingSymlinksInPath().standardizedFileURL
    }

    struct OccupiedError: LocalizedError {
        let path: String
        var errorDescription: String? {
            L("%@ is another app, not an earlier build of this game, so it was left alone", "\(path.tildePath)")
        }
    }

    /// Moves the new app into `folder`. An app of the same name there goes to the Trash only when it
    /// is an earlier nxnative build of the same game (same DMTitleID); any other app stops the move.
    nonisolated static func moveApp(_ source: String, toFolder folder: String) throws -> (path: String, trashed: String?) {
        let fm = FileManager.default
        let src = URL(fileURLWithPath: source).resolvingSymlinksInPath()
        let dstFolder = URL(fileURLWithPath: folder).resolvingSymlinksInPath()
        if sameFolder(src.deletingLastPathComponent().path, dstFolder.path) { return (src.path, nil) }
        let dst = dstFolder.appendingPathComponent(src.lastPathComponent)
        try fm.createDirectory(at: dstFolder, withIntermediateDirectories: true)
        var trashed: String?
        if fm.fileExists(atPath: dst.path) {
            guard let old = GameLibrary.read(dst.path)?.titleID, old == GameLibrary.read(src.path)?.titleID else {
                throw OccupiedError(path: dst.path)
            }
            try fm.trashItem(at: dst, resultingItemURL: nil)
            trashed = dst.path
        }
        try fm.moveItem(at: src, to: dst)
        return (dst.path, trashed)
    }

    private func notify(success: Bool, app: String? = nil) {
        NSSound(named: success ? "Glass" : "Basso")?.play()
        guard !NSApp.isActive else { return }
        NSApp.requestUserAttention(.informationalRequest)
        guard notifyWhenDone else { return }
        let content = UNMutableNotificationContent()
        if success {
            let name = ((app ?? "").lastPathComponent as NSString).deletingPathExtension
            content.title = L("%@ is ready", "\(name)")
            content.body = L("The game was built. The first start takes a few minutes while macOS checks the app.")
        } else {
            content.title = L("The build stopped")
            content.body = lastRed ?? L("See NX Builder for why.")
        }
        content.sound = nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// The game's build folder (`<title ID>_build`), when the script made one.
    var buildFolder: String? {
        guard !gamePath.isEmpty else { return nil }
        var folder = gamePath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), !isDir.boolValue {
            folder = folder.deletingLastPathComponent
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return names.first { $0.hasSuffix("_build") }.map { folder + "/" + $0 }
    }
}
