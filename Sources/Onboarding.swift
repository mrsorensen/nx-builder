import AppKit
import Foundation
import Observation

/// What a Mac needs before NX Builder can build, as found on it.
struct OnboardingStatus: Sendable, Equatable {
    var xcodeApp: String?          // an Xcode app, if the Mac has one
    var xcodeReady = false         // xcodebuild runs (Xcode selected, its licence accepted)
    var brew: String?
    var missingFormulas: [String] = []
    var dotnet10 = false
    var metal = false
    var repo = false
    var python = false
    var keys = false

    /// Everything but prod.keys, which only the player can give.
    var toolsReady: Bool { xcodeReady && missingFormulas.isEmpty && dotnet10 && metal && repo && python }

    /// An Xcode that is fully installed: while the App Store downloads it, a placeholder Xcode.app
    /// is already in /Applications, without its tools.
    nonisolated static func installedXcode() -> String? {
        SetupChecker.xcodeApps().first { FileManager.default.isExecutableFile(atPath: $0 + "/Contents/Developer/usr/bin/xcodebuild") }
    }

    nonisolated static func detect(repo: String, python: String, keys: String) -> OnboardingStatus {
        var s = OnboardingStatus()
        let env = Shell.environment(python: python)
        s.xcodeApp = installedXcode()
        s.xcodeReady = Shell.run("/usr/bin/xcodebuild", ["-version"], env: env, timeout: 30).ok
        s.brew = Shell.which("brew")
        s.metal = s.xcodeReady && Shell.run("/usr/bin/xcrun", ["-sdk", "macosx", "metal", "--version"], env: env, timeout: 30).ok
        if let dotnet = Shell.which("dotnet") {
            s.dotnet10 = Shell.run(dotnet, ["--list-sdks"], env: env, timeout: 30).output
                .split(separator: "\n").contains { $0.hasPrefix("10.") }
        }
        s.repo = FileManager.default.fileExists(atPath: repo + "/scripts/build_ipa_from_nsp.py")
        s.python = PythonCheck.run(python)?.ok == true
        s.keys = FileManager.default.fileExists(atPath: keys)
        // git and make come with Xcode; uv only makes the Python environment.
        var formulas: [(String, String)] = [("zstd", "zstd"), ("glslangValidator", "glslang")]
        if !s.python { formulas.append(("uv", "uv")) }
        s.missingFormulas = formulas.filter { Shell.which($0.0) == nil }.map(\.1)
        return s
    }
}

enum OnboardingStep: String, CaseIterable, Identifiable {
    case xcode, homebrew, tools, dotnet, metal, nxnative, python, keys
    var id: String { rawValue }

    var title: String {
        switch self {
        case .xcode: "Xcode"
        case .homebrew: "Homebrew"
        case .tools: L("Command-line tools")
        case .dotnet: ".NET 10 SDK"
        case .metal: L("Metal toolchain")
        case .nxnative: "nxnative"
        case .python: L("Python environment")
        case .keys: "prod.keys"
        }
    }

    var detail: String {
        switch self {
        case .xcode: L("Apple's developer tools, from the App Store (free, about 15 GB). You install it; NX Builder sets it up.")
        case .homebrew: L("The package manager for the tools below, from Homebrew's signed installer.")
        case .tools: L("zstd and glslang, which nxnative's build calls, and uv for Python.")
        case .dotnet: L("Microsoft's runtime for nxnative's shader translator, from Microsoft's signed installer.")
        case .metal: L("Compiles the games' shaders. A large download from Apple.")
        case .nxnative: L("The project that does the work. Downloaded to your home folder (under 1 GB).")
        case .python: L("A Python of NX Builder's own with the packages the build script needs (about 25 MB).")
        case .keys: L("The keys dumped from your own Switch. Only you can give them.")
        }
    }
}

enum StepState: Equatable {
    case done, needed, running, waiting, failed
}

struct OnboardingError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Installs everything NX Builder needs, in order, asking for the Mac's password once.
@MainActor @Observable
final class Onboarding {
    private(set) var status: OnboardingStatus?
    private(set) var active: OnboardingStep?
    private(set) var failedStep: OnboardingStep?
    private(set) var failure: String?
    private(set) var isRunning = false
    private(set) var isDetecting = false
    private(set) var waitingForXcode = false
    private(set) var downloadFraction: Double?
    private(set) var log: [LogLine] = []
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var previewing = false

    static let xcodeAppStore = URL(string: "macappstore://apps.apple.com/app/id497799835")!

    func state(of step: OnboardingStep) -> StepState {
        if active == step { return waitingForXcode ? .waiting : .running }
        if failedStep == step { return .failed }
        guard let s = status else { return .needed }
        switch step {
        case .xcode: return s.xcodeReady ? .done : .needed
        case .homebrew: return s.brew != nil || s.missingFormulas.isEmpty ? .done : .needed
        case .tools: return s.missingFormulas.isEmpty ? .done : .needed
        case .dotnet: return s.dotnet10 ? .done : .needed
        case .metal: return s.metal ? .done : .needed
        case .nxnative: return s.repo ? .done : .needed
        case .python: return s.python ? .done : .needed
        case .keys: return s.keys ? .done : .needed
        }
    }

    func refresh(settings: AppSettings) async {
        guard !previewing else { return }
        isDetecting = true
        let repo = settings.repoPath, python = settings.python, keys = settings.keysPath
        status = await Task.detached { OnboardingStatus.detect(repo: repo, python: python, keys: keys) }.value
        isDetecting = false
    }

    func cancel() {
        cancelled = true
        process?.terminate()
    }

    // MARK: - The pipeline

    func install(settings: AppSettings) async {
        guard !isRunning else { return }
        isRunning = true
        cancelled = false
        failure = nil
        failedStep = nil
        log = []
        defer { isRunning = false; active = nil; waitingForXcode = false; downloadFraction = nil; process = nil }
        do {
            try await run(settings: settings)
            append(.ok, L("Everything is installed."))
        } catch {
            failedStep = active
            failure = cancelled ? L("Stopped.") : error.localizedDescription
            append(.red, failure ?? "")
        }
        await refresh(settings: settings)
    }

    private func run(settings: AppSettings) async throws {
        await refresh(settings: settings)
        guard var s = status else { return }

        // 1. Xcode only comes from the App Store, with the player's Apple ID: open its page and wait.
        if s.xcodeApp == nil {
            active = .xcode
            waitingForXcode = true
            append(.stage, L("Waiting for Xcode from the App Store …"))
            NSWorkspace.shared.open(Self.xcodeAppStore)
            while await Task.detached(operation: { OnboardingStatus.installedXcode() }).value == nil {
                try await Task.sleep(for: .seconds(10))
                if cancelled { throw OnboardingError(message: L("Stopped.")) }
            }
            try await Task.sleep(for: .seconds(20))   // the App Store finishes moving it into place
            waitingForXcode = false
            await refresh(settings: settings)
            s = status ?? s
        }

        // 2. The signed installer packages, checked before anything runs.
        let downloads = AppPaths.support + "/Downloads"
        try? FileManager.default.createDirectory(atPath: downloads, withIntermediateDirectories: true)
        var packages: [String] = []
        if s.brew == nil && !s.missingFormulas.isEmpty {
            active = .homebrew
            packages.append(try await fetchHomebrew(into: downloads))
        }
        if !s.dotnet10 {
            active = .dotnet
            packages.append(try await fetchDotnet(into: downloads))
        }

        // 3. Everything that needs the administrator's password, in one prompt.
        var commands = packages.map { "/usr/sbin/installer -pkg \(Self.shellQuote($0)) -target /" }
        if !s.xcodeReady, let xcode = s.xcodeApp {
            commands += ["/usr/bin/xcode-select -s \(Self.shellQuote(xcode + "/Contents/Developer"))",
                         "/usr/bin/xcodebuild -license accept",
                         "/usr/bin/xcodebuild -runFirstLaunch"]
        }
        if !commands.isEmpty {
            active = s.xcodeReady ? (s.dotnet10 ? .homebrew : .dotnet) : .xcode
            append(.stage, L("Installing with your password …"))
            let prompt = L("NX Builder needs your password to install what nxnative needs.")
            let code = try await runCommand("/usr/bin/osascript", ["-e", Self.adminScript(commands, prompt: prompt)])
            if code != 0 { throw OnboardingError(message: L("The installation with your password did not finish (cancelled, or a package failed). See the details.")) }
            for package in packages { try? FileManager.default.removeItem(atPath: package) }
            await refresh(settings: settings)
            s = status ?? s
        }

        // 4. Homebrew's tools, as the player (Homebrew refuses root).
        if !s.missingFormulas.isEmpty {
            active = .tools
            guard let brew = Shell.which("brew") ?? s.brew else { throw OnboardingError(message: L("Homebrew is not installed.")) }
            append(.stage, "brew install " + s.missingFormulas.joined(separator: " "))
            var env = Shell.environment()
            env["HOMEBREW_NO_ENV_HINTS"] = "1"
            if try await runCommand(brew, ["install"] + s.missingFormulas, env: env) != 0 {
                throw OnboardingError(message: L("Homebrew could not install %@.", s.missingFormulas.joined(separator: ", ")))
            }
        }

        // 5. The Metal toolchain, Xcode's separate download.
        await refresh(settings: settings)
        s = status ?? s
        if !s.metal {
            active = .metal
            append(.stage, L("Downloading the Metal toolchain …"))
            if try await runCommand("/usr/bin/xcodebuild", ["-downloadComponent", "MetalToolchain"]) != 0 {
                throw OnboardingError(message: L("Xcode could not download the Metal toolchain."))
            }
        }

        // 6. nxnative, where the settings expect it.
        if !s.repo {
            active = .nxnative
            let dest = settings.repoPath
            if FileManager.default.fileExists(atPath: dest) {
                throw OnboardingError(message: L("%@ already exists but is not nxnative. Choose nxnative's folder in Setup, or remove that folder.", dest.tildePath))
            }
            append(.stage, L("Downloading nxnative …"))
            if try await runCommand("/usr/bin/git", ["clone", "--progress", AppPaths.nxnativeURL, dest]) != 0 {
                throw OnboardingError(message: L("nxnative could not be downloaded."))
            }
        }

        // 7. The Python environment.
        await refresh(settings: settings)
        s = status ?? s
        if !s.python {
            active = .python
            switch SetupSteps.python() {
            case .failure(let error): throw OnboardingError(message: error.message)
            case .success(let steps):
                for step in steps {
                    append(.stage, step.title)
                    if try await runCommand(step.exe, step.args, env: step.env) != 0 {
                        throw OnboardingError(message: L("“%@” failed.", step.title))
                    }
                }
            }
        }
        active = nil
    }

    // MARK: - Downloads

    /// Homebrew's latest signed installer package, from its GitHub release.
    private func fetchHomebrew(into folder: String) async throws -> String {
        append(.stage, L("Downloading Homebrew …"))
        let api = try await fetchJSON(Self.homebrewRelease)
        guard let (url, size) = Self.homebrewPackage(in: api) else {
            throw OnboardingError(message: L("Homebrew's installer was not found on GitHub."))
        }
        let path = folder + "/Homebrew.pkg"
        try await download(url, to: path, size: size)
        try await verifyPackage(path, signer: "Homebrew")
        return path
    }

    /// Microsoft's newest .NET 10 SDK installer for Apple silicon, checked against its published SHA-512.
    private func fetchDotnet(into folder: String) async throws -> String {
        append(.stage, L("Downloading .NET 10 …"))
        let meta = try await fetchJSON(Self.dotnetReleases)
        guard let (url, hash) = Self.dotnetPackage(in: meta) else {
            throw OnboardingError(message: L("Microsoft's list of .NET 10 releases could not be read."))
        }
        let path = folder + "/dotnet-sdk.pkg"
        try await download(url, to: path, size: nil)
        let sum = await Shell.runAsync("/usr/bin/shasum", ["-a", "512", path], timeout: 120).trimmed.split(separator: " ").first.map(String.init) ?? ""
        guard sum.lowercased() == hash.lowercased() else {
            try? FileManager.default.removeItem(atPath: path)
            throw OnboardingError(message: L("The .NET download does not match Microsoft's checksum."))
        }
        try await verifyPackage(path, signer: "Microsoft")
        return path
    }

    /// The Apple developer teams whose installers NX Builder runs: Homebrew's packages are signed by a
    /// maintainer's Developer ID (Patrick Linnane, 927JGANW46), .NET's by Microsoft (UBF8T346G9).
    nonisolated static let trustedTeams = ["Homebrew": ["927JGANW46"], "Microsoft": ["UBF8T346G9"]]

    nonisolated static let homebrewRelease = "https://api.github.com/repos/Homebrew/brew/releases/latest"
    nonisolated static let dotnetReleases = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json"

    /// The .pkg asset of Homebrew's latest GitHub release: its URL and size.
    nonisolated static func homebrewPackage(in release: [String: Any]) -> (String, Int64?)? {
        guard let assets = release["assets"] as? [[String: Any]],
              let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".pkg") == true }),
              let url = asset["browser_download_url"] as? String else { return nil }
        return (url, (asset["size"] as? NSNumber)?.int64Value)
    }

    /// The newest .NET 10 SDK's Apple silicon installer in Microsoft's release list: its URL and SHA-512.
    nonisolated static func dotnetPackage(in meta: [String: Any]) -> (String, String)? {
        guard let latest = meta["latest-sdk"] as? String, let releases = meta["releases"] as? [[String: Any]] else { return nil }
        for release in releases {
            let sdks = [release["sdk"] as? [String: Any]].compactMap { $0 } + (release["sdks"] as? [[String: Any]] ?? [])
            for sdk in sdks where sdk["version"] as? String == latest {
                if let file = (sdk["files"] as? [[String: Any]])?.first(where: { $0["rid"] as? String == "osx-arm64" && ($0["name"] as? String)?.hasSuffix(".pkg") == true }),
                   let url = file["url"] as? String, let hash = file["hash"] as? String {
                    return (url, hash)
                }
            }
        }
        return nil
    }

    /// For the snapshot tool: shows a Mac that still needs things, without detecting.
    func preview(_ status: OnboardingStatus, active: OnboardingStep? = nil, waitingForXcode: Bool = false) {
        previewing = true
        self.status = status
        self.active = active
        self.waitingForXcode = waitingForXcode
    }

    /// Gatekeeper accepts the package as a notarized Developer ID installer from the expected team.
    private func verifyPackage(_ path: String, signer: String) async throws {
        let assess = await Shell.runAsync("/usr/sbin/spctl", ["-a", "-vv", "-t", "install", path], timeout: 120)
        guard Self.trusted(assessment: assess.ok ? assess.output : "", signer: signer) else {
            try? FileManager.default.removeItem(atPath: path)
            throw OnboardingError(message: L("%@ is not signed as expected, so it was not installed.", path.lastPathComponent))
        }
        append(.ok, L("%@: signed and notarized.", path.lastPathComponent))
    }

    /// `spctl -a -vv -t install` said "source=Notarized Developer ID" and an origin from the signer's team.
    nonisolated static func trusted(assessment: String, signer: String) -> Bool {
        guard assessment.contains("source=Notarized Developer ID"),
              let origin = assessment.split(separator: "\n").first(where: { $0.hasPrefix("origin=Developer ID Installer:") }) else { return false }
        return (trustedTeams[signer] ?? []).contains { origin.hasSuffix("(\($0))") }
    }

    private func fetchJSON(_ url: String) async throws -> [String: Any] {
        let result = await Shell.runAsync("/usr/bin/curl", ["-fsSL", "-H", "User-Agent: NX-Builder", url], timeout: 60)
        guard result.ok, let obj = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any] else {
            throw OnboardingError(message: L("Could not reach %@. Check the internet connection.", URL(string: url)?.host ?? url))
        }
        return obj
    }

    /// curl to a file, with the progress read from the file's size.
    private func download(_ url: String, to path: String, size: Int64?) async throws {
        try? FileManager.default.removeItem(atPath: path)
        var expected = size
        if expected == nil {
            let head = await Shell.runAsync("/usr/bin/curl", ["-fsSLI", url], timeout: 30).output
            expected = head.split(separator: "\n").last { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int64($0.split(separator: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") }
        }
        downloadFraction = 0
        let watcher = Task { @MainActor in
            while !Task.isCancelled {
                if let expected, expected > 0, let done = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber {
                    downloadFraction = min(1, Double(done.int64Value) / Double(expected))
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        defer { watcher.cancel(); downloadFraction = nil }
        if try await runCommand("/usr/bin/curl", ["-fL", "--silent", "--show-error", "-o", path, url]) != 0 {
            throw OnboardingError(message: L("The download from %@ failed.", URL(string: url)?.host ?? url))
        }
    }

    // MARK: - Running tools

    /// Runs a tool to the end with its output in the log; throws when stopped.
    private func runCommand(_ exe: String, _ args: [String], env: [String: String]? = nil) async throws -> Int32 {
        if cancelled { throw OnboardingError(message: L("Stopped.")) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = env ?? Shell.environment()
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let (exits, cont) = AsyncStream.makeStream(of: Int32.self)
        p.terminationHandler = { cont.yield($0.terminationStatus); cont.finish() }
        try p.run()
        process = p
        await Shell.readLines(pipe.fileHandleForReading) { line in await self.append(.info, line) }
        var status: Int32 = -1
        for await code in exits { status = code }
        process = nil
        if cancelled { throw OnboardingError(message: L("Stopped.")) }
        return status
    }

    private func append(_ kind: LogKind, _ text: String) {
        log.append(LogLine(id: nextID, time: LogLine.now(), text: text, kind: kind))
        nextID += 1
        if log.count > 3000 { log.removeFirst(log.count - 3000) }
    }

    // MARK: - Quoting

    nonisolated static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// One `do shell script` with administrator privileges: macOS asks for the password in its own dialog.
    nonisolated static func adminScript(_ commands: [String], prompt: String) -> String {
        "do shell script " + appleScriptString(commands.joined(separator: " && ")) + " with prompt " + appleScriptString(prompt) + " with administrator privileges"
    }
}
