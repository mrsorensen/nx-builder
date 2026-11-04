import Foundation
import Observation

/// One command of a setup task.
struct TaskStep: Sendable {
    let title: String
    let exe: String
    let args: [String]
    var cwd: String?
    var env: [String: String]?
}

/// Runs the setup tasks the app can do itself (download nxnative, set up Python, install the Metal
/// toolchain, update nxnative), one at a time, with their output as they write it.
@MainActor @Observable
final class TaskRunner {
    enum State: Equatable { case idle, running, done, failed(String) }

    private(set) var title = ""
    private(set) var state: State = .idle
    private(set) var lines: [LogLine] = []
    private(set) var step = ""
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var cancelled = false

    var isRunning: Bool { state == .running }

    func run(_ title: String, steps: [TaskStep], then finish: (@MainActor (Bool) -> Void)? = nil) {
        guard !isRunning else { return }
        self.title = title
        state = .running
        lines = []
        cancelled = false
        Task {
            for s in steps {
                step = s.title
                append(.stage, s.title)
                let status = await runStep(s)
                if status != 0 {
                    state = .failed(cancelled ? tr("Stopped.", "Stoppet.")
                                              : tr("“\(s.title)” failed (exit code \(status)). See the output above.",
                                                   "«\(s.title)» feilet (kode \(status)). Se utskriften over."))
                    finish?(false)
                    return
                }
            }
            append(.ok, tr("Done.", "Ferdig."))
            state = .done
            finish?(true)
        }
    }

    func fail(_ title: String, _ reason: String) {
        guard !isRunning else { return }
        self.title = title
        lines = []
        state = .failed(reason)
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        cancelled = true
        process.terminate()
    }

    func dismiss() {
        guard !isRunning else { return }
        state = .idle
        lines = []
    }

    private func runStep(_ s: TaskStep) async -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: s.exe)
        p.arguments = s.args
        if let cwd = s.cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        p.environment = s.env ?? Shell.environment()
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let (exits, cont) = AsyncStream.makeStream(of: Int32.self)
        p.terminationHandler = { cont.yield($0.terminationStatus); cont.finish() }
        do {
            try p.run()
        } catch {
            append(.red, error.localizedDescription)
            return -1
        }
        process = p
        await Shell.readLines(pipe.fileHandleForReading) { line in await self.append(.info, line) }
        var status: Int32 = -1
        for await code in exits { status = code }
        process = nil
        return status
    }

    private func append(_ kind: LogKind, _ text: String) {
        lines.append(LogLine(id: nextID, time: LogLine.now(), text: text, kind: kind))
        nextID += 1
        if lines.count > 2000 { lines.removeFirst(lines.count - 2000) }
    }
}

struct SetupError: Error, Sendable {
    let message: String
}

/// The setup tasks, as commands.
enum SetupSteps {
    /// Clones nxnative into `folder`.
    static func clone(into folder: String) -> [TaskStep] {
        [TaskStep(title: tr("Downloading nxnative", "Laster ned nxnative"),
                  exe: "/usr/bin/git", args: ["clone", "--progress", AppPaths.nxnativeURL, folder])]
    }

    /// A Python environment of its own for the build script, in the app's support folder: with uv
    /// (which fetches Python 3.14 if the Mac has none), else with a Homebrew Python 3.12 or later.
    /// Capstone must be 5.x (the rewriter uses its version 5 names); lz4 is built with its library
    /// inside (PYLZ4_USE_SYSTEM_LZ4=0), which avoids a "symbol not found" error on newer Pythons.
    static func python() -> Swift.Result<[TaskStep], SetupError> {
        let venv = AppPaths.venv, py = AppPaths.venvPython
        let packages = ["capstone>=5,<6", "fonttools", "lz4"]
        var env = Shell.environment()
        env["PYLZ4_USE_SYSTEM_LZ4"] = "0"
        let check = TaskStep(title: tr("Checking the packages", "Sjekker pakkene"), exe: py, args: ["-c", PythonCheck.script])
        if let uv = Shell.which("uv") {
            return .success([
                TaskStep(title: tr("Creating the Python environment", "Lager Python-miljøet"),
                         exe: uv, args: ["venv", "--clear", "--python", "cpython-3.14-macos-aarch64-none", venv], env: env),
                TaskStep(title: tr("Installing capstone, fonttools and lz4", "Installerer capstone, fonttools og lz4"),
                         exe: uv, args: ["pip", "install", "--python", py] + packages, env: env),
                check,
            ])
        }
        for (name, minor) in [("python3.15", 15), ("python3.14", 14), ("python3.13", 13), ("python3.12", 12)] {
            // An Intel Python (a Homebrew in /usr/local from a migrated Mac) runs under Rosetta, which the build script refuses.
            guard let base = Shell.which(name),
                  Shell.run(base, ["-c", "import platform; print(platform.machine())"], timeout: 20).trimmed == "arm64" else { continue }
            return .success([
                TaskStep(title: tr("Creating the Python environment", "Lager Python-miljøet"),
                         exe: base, args: ["-m", "venv", "--clear", venv], env: env),
                TaskStep(title: tr("Installing capstone, fonttools and lz4", "Installerer capstone, fonttools og lz4"),
                         exe: py, args: ["-m", "pip", "install"] + packages + (minor < 14 ? ["backports.zstd"] : []), env: env),
                check,
            ])
        }
        return .failure(SetupError(message: tr("No uv and no Apple silicon Python 3.12 or later. Install uv with Homebrew (brew install uv), then try again.",
                           "Fant verken uv eller Python 3.12 eller nyere. Installer uv med Homebrew (brew install uv), og prøv igjen.")))
    }

    static func metalToolchain() -> [TaskStep] {
        [TaskStep(title: tr("Downloading the Metal toolchain (a large download)", "Laster ned Metal-verktøyene (en stor nedlasting)"),
                  exe: "/usr/bin/xcodebuild", args: ["-downloadComponent", "MetalToolchain"])]
    }

    static func update(repo: String) -> [TaskStep] {
        [TaskStep(title: tr("Fetching the latest nxnative", "Henter siste nxnative"),
                  exe: "/usr/bin/git", args: ["-C", repo, "pull", "--ff-only"])]
    }
}

/// What the build script needs of its Python (check_prereqs and check_capstone in the script),
/// printed as one line of JSON.
enum PythonCheck {
    static let script = """
    import json, platform, sys
    r = {"python": sys.version.split()[0], "ok": False}
    try:
        if platform.machine() != "arm64":
            raise RuntimeError("an Intel (" + platform.machine() + ") Python under Rosetta; the build script needs an Apple silicon one")
        import lz4.block, fontTools, capstone
        r["capstone"] = capstone.__version__
        try:
            import compression.zstd
        except ImportError:
            import backports.zstd
        r["ok"] = capstone.cs_version()[0] == 5
        if not r["ok"]: r["error"] = "Capstone " + capstone.__version__ + " is not 5.x"
    except Exception as e:
        r["error"] = str(e)
    print(json.dumps(r))
    """

    struct Outcome: Sendable {
        let ok: Bool
        let version: String
        let error: String
    }

    static func run(_ python: String) -> Outcome? {
        guard FileManager.default.isExecutableFile(atPath: python) else { return nil }
        let r = Shell.run(python, ["-c", script], env: Shell.environment(python: python), timeout: 60)
        guard let line = r.output.split(separator: "\n").last,
              let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return Outcome(ok: false, version: "", error: r.trimmed)
        }
        return Outcome(ok: obj["ok"] as? Bool ?? false, version: obj["python"] as? String ?? "", error: obj["error"] as? String ?? "")
    }
}

/// Whether nxnative has new commits, and what its authors told front ends about them.
@MainActor @Observable
final class NxnativeUpdates {
    private(set) var behind: Int?
    private(set) var current = ""
    private(set) var localChanges: [String] = []
    private(set) var checking = false
    private(set) var frontEndNotes: [String] = []

    func check(repo: String) async {
        guard !checking, FileManager.default.fileExists(atPath: repo + "/.git") else { return }
        checking = true
        let result = await Task.detached { () -> (Int?, String, [String]) in
            let git = "/usr/bin/git"
            _ = Shell.run(git, ["-C", repo, "fetch", "--quiet"], timeout: 60)
            let count = Int(Shell.run(git, ["-C", repo, "rev-list", "--count", "HEAD..@{u}"], timeout: 15).trimmed)
            let head = Shell.run(git, ["-C", repo, "log", "-1", "--format=%h · %cs"], timeout: 15).trimmed
            // Not trimmed: each line starts with two status columns and a space (" M pyproject.toml").
            let dirty = Shell.run(git, ["-C", repo, "status", "--porcelain", "--untracked-files=no"], timeout: 15).output
                .split(separator: "\n").filter { $0.count > 3 }.map { String($0.dropFirst(3)) }
            return (count, head, dirty)
        }.value
        behind = result.0
        current = result.1
        localChanges = result.2
        checking = false
    }

    /// The HEAD before an update, so its `Front-ends:` lines can be read after it (docs/frontends.md, Following main).
    nonisolated static func head(repo: String) -> String {
        Shell.run("/usr/bin/git", ["-C", repo, "rev-parse", "HEAD"], timeout: 15).trimmed
    }

    func readNotes(repo: String, since old: String) async {
        guard !old.isEmpty else { return }
        let log = await Shell.runAsync("/usr/bin/git", ["-C", repo, "log", "\(old)..HEAD", "--format=%B"], timeout: 30)
        frontEndNotes = log.output.split(separator: "\n").map(String.init).filter { $0.hasPrefix("Front-ends:") }
    }
}
