import Foundation
import Observation

enum CheckStatus: Sendable { case ok, warn, fail }

/// Something the app can do itself to fix a check.
enum SetupAction: Sendable, Equatable {
    case cloneNxnative, chooseRepo, setUpPython, installMetal, chooseKeys
}

/// How to fix a check: a command to copy into Terminal, an action the app does, or a page to open.
enum CheckFix: Sendable, Equatable {
    case command(String)
    case action(SetupAction)
    case link(String, String)   // label, URL
}

struct CheckItem: Identifiable, Sendable {
    let id: String
    let title: String
    let status: CheckStatus
    let detail: String
    var fixes: [CheckFix] = []
    var more: String = ""
}

struct CheckReport: Sendable {
    var items: [CheckItem] = []
    var metalMismatch = false
}

/// Checks what building a game needs (steps 1–5 of the AppleGamingWiki guide, and what
/// `check_prereqs` in the build script asks for), without changing anything.
@MainActor @Observable
final class SetupChecker {
    private(set) var items: [CheckItem] = []
    private(set) var metalMismatch = false
    private(set) var isChecking = false
    private(set) var hasChecked = false
    @ObservationIgnored private var again = false

    var allGood: Bool { hasChecked && !items.contains { $0.status == .fail } }
    var failures: Int { items.filter { $0.status == .fail }.count }

    /// Checks again; one asked for while a check runs (a folder chosen meanwhile) runs after it.
    func run(settings: AppSettings) async {
        if isChecking { again = true; return }
        isChecking = true
        repeat {
            again = false
            let repo = settings.repoPath, keys = settings.keysPath, python = settings.python, own = settings.usesOwnPython
            let report = await Task.detached { Self.check(repo: repo, keys: keys, python: python, ownPython: own) }.value
            items = report.items
            metalMismatch = report.metalMismatch
        } while again
        isChecking = false
        hasChecked = true
    }

    /// Every Xcode on the Mac, /Applications/Xcode.app first (Spotlight finds Xcode-beta.app and
    /// versions installed beside each other, as Xcode-27.2.app).
    nonisolated static func xcodeApps() -> [String] {
        let found = Shell.run("/usr/bin/mdfind", ["kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'"], timeout: 10).output
            .split(separator: "\n").map(String.init).filter { $0.hasSuffix(".app") && !$0.contains("/.Trash/") }
        var apps = FileManager.default.fileExists(atPath: "/Applications/Xcode.app") ? ["/Applications/Xcode.app"] : []
        apps += found.filter { $0 != "/Applications/Xcode.app" }.sorted()
        return apps
    }

    nonisolated static func check(repo: String, keys: String, python: String, ownPython: Bool) -> CheckReport {
        var report = CheckReport()
        let fm = FileManager.default
        let env = Shell.environment(python: python)

        // Apple silicon
        let arm = Shell.run("/usr/sbin/sysctl", ["-n", "hw.optional.arm64"], env: env, timeout: 5).trimmed == "1"
        report.items.append(arm
            ? CheckItem(id: "arm", title: "Apple silicon", status: .ok, detail: tr("This Mac has an M-series chip.", "Macen har en M-brikke."))
            : CheckItem(id: "arm", title: "Apple silicon", status: .fail,
                        detail: tr("nxnative needs a Mac with M1 or newer.", "nxnative trenger en Mac med M1 eller nyere.")))

        // Xcode, selected and licensed
        let selected = Shell.run("/usr/bin/xcode-select", ["-p"], env: env, timeout: 10).trimmed
        let xcodebuild = Shell.run("/usr/bin/xcodebuild", ["-version"], env: env, timeout: 30)
        let xcodeVersion = xcodebuild.output.split(separator: "\n").first.map(String.init) ?? ""
        let xcodes = xcodebuild.ok ? [] : xcodeApps()
        if xcodebuild.ok {
            report.items.append(CheckItem(id: "xcode", title: "Xcode", status: .ok, detail: "\(xcodeVersion) · \(selected.tildePath)"))
        } else if selected.contains("CommandLineTools"), let xcode = xcodes.first {
            report.items.append(CheckItem(id: "xcode", title: "Xcode", status: .fail,
                detail: tr("The Command Line Tools are selected instead of Xcode. Select Xcode in Terminal (it asks for your password):",
                           "Kommandolinjeverktøyene er valgt i stedet for Xcode. Velg Xcode i Terminal (den spør etter passordet ditt):"),
                fixes: [.command("sudo xcode-select -s \"\(xcode)/Contents/Developer\"")]))
        } else if xcodebuild.output.lowercased().contains("license") {
            report.items.append(CheckItem(id: "xcode", title: "Xcode", status: .fail,
                detail: tr("Xcode's licence has not been accepted. Open Xcode once, or run in Terminal:",
                           "Xcode-lisensen er ikke godtatt. Åpne Xcode én gang, eller kjør i Terminal:"),
                fixes: [.command("sudo xcodebuild -license accept")]))
        } else {
            report.items.append(CheckItem(id: "xcode", title: "Xcode", status: .fail,
                detail: tr("Install Xcode from the App Store and open it once.", "Installer Xcode fra App Store og åpne det én gang."),
                fixes: [.link(tr("Open Xcode in the App Store", "Åpne Xcode i App Store"), "macappstore://apps.apple.com/app/id497799835")],
                more: xcodebuild.trimmed))
        }

        // The Metal toolchain (a separate download since Xcode 26)
        let metal = Shell.run("/usr/bin/xcrun", ["-sdk", "macosx", "metal", "--version"], env: env, timeout: 30)
        report.items.append(metal.ok
            ? CheckItem(id: "metal", title: tr("Metal toolchain", "Metal-verktøyene"), status: .ok,
                        detail: metal.output.split(separator: "\n").first.map(String.init) ?? "")
            : CheckItem(id: "metal", title: tr("Metal toolchain", "Metal-verktøyene"), status: .fail,
                        detail: tr("Xcode's Metal toolchain is not installed. It compiles the games' shaders.",
                                   "Metal-verktøyene til Xcode er ikke installert. De kompilerer spillenes shadere."),
                        fixes: xcodebuild.ok ? [.action(.installMetal), .command("xcodebuild -downloadComponent MetalToolchain")] : [],
                        more: metal.trimmed))

        // Homebrew and the command-line tools the build script calls
        let brew = Shell.which("brew")
        let tools: [(tool: String, formula: String)] = [("git", "git"), ("zstd", "zstd"), ("glslangValidator", "glslang")]
        let missingFormulas = tools.filter { Shell.which($0.tool) == nil }.map(\.formula)
        let makeMissing = Shell.which("make") == nil
        if missingFormulas.isEmpty && !makeMissing {
            report.items.append(CheckItem(id: "tools", title: tr("Command-line tools", "Kommandolinjeverktøy"), status: .ok,
                                          detail: "git, zstd, glslang, make"))
        } else {
            var fixes: [CheckFix] = []
            if brew == nil {
                fixes.append(.link(tr("Install Homebrew", "Installer Homebrew"), "https://brew.sh"))
            }
            if !missingFormulas.isEmpty { fixes.append(.command("brew install " + missingFormulas.joined(separator: " "))) }
            let missing = missingFormulas + (makeMissing ? ["make (Xcode)"] : [])
            report.items.append(CheckItem(id: "tools", title: tr("Command-line tools", "Kommandolinjeverktøy"), status: .fail,
                detail: tr("Missing: \(missing.joined(separator: ", ")).", "Mangler: \(missing.joined(separator: ", "))."),
                fixes: fixes))
        }

        // .NET 10 (the shader translator)
        // The build compiles nxnative's extractor with `dotnet build`, so it needs the SDK, not only the runtime.
        let dotnet = Shell.which("dotnet")
        let sdks = dotnet.map { Shell.run($0, ["--list-sdks"], env: env, timeout: 30).output } ?? ""
        if let sdk10 = sdks.split(separator: "\n").first(where: { $0.hasPrefix("10.") }) {
            report.items.append(CheckItem(id: "dotnet", title: ".NET 10 SDK", status: .ok,
                                          detail: String(sdk10.split(separator: " ").first ?? sdk10)))
        } else {
            report.items.append(CheckItem(id: "dotnet", title: ".NET 10 SDK", status: .fail,
                detail: dotnet == nil
                    ? tr("nxnative needs the .NET 10 SDK. The installer asks for your password.",
                         "nxnative trenger .NET 10 SDK. Installasjonen spør etter passordet ditt.")
                    : tr("dotnet is here, but not the .NET 10 SDK (a runtime alone is not enough). The installer asks for your password.",
                         "dotnet finnes, men ikke .NET 10 SDK (bare kjøretiden er ikke nok). Installasjonen spør etter passordet ditt."),
                fixes: [.command("brew install --cask dotnet-sdk"),
                        .link(tr(".NET 10 from Microsoft", ".NET 10 fra Microsoft"), "https://dotnet.microsoft.com/download/dotnet/10.0")],
                more: sdks))
        }

        // nxnative itself
        guard fm.fileExists(atPath: repo + "/scripts/build_ipa_from_nsp.py") else {
            report.items.append(CheckItem(id: "repo", title: "nxnative", status: .fail,
                detail: tr("nxnative was not found in \(repo.tildePath). Download it, or choose the folder you cloned it into.",
                           "Fant ikke nxnative i \(repo.tildePath). Last den ned, eller velg mappen du klonet den til."),
                fixes: [.action(.cloneNxnative), .action(.chooseRepo)]))
            report.items.append(pythonItem(python: python, ownPython: ownPython))
            report.items.append(keysItem(keys))
            return report
        }
        let head = Shell.run("/usr/bin/git", ["-C", repo, "log", "-1", "--format=%h · %cs"], env: env, timeout: 15)
        report.items.append(CheckItem(id: "repo", title: "nxnative", status: .ok,
                                      detail: repo.tildePath + (head.ok ? " · \(head.trimmed)" : "")))

        // Python with lz4, Capstone 5 and fontTools
        let pyItem = pythonItem(python: python, ownPython: ownPython)
        report.items.append(pyItem)

        // The Metal compiler the shaders were tested with (dmsh_chain.lock)
        if metal.ok && pyItem.status == .ok {
            let check = Shell.run(python, [repo + "/dm/gfx/tools/own_compilers.py", "--check-metal"], cwd: repo, env: env, timeout: 60)
            if check.ok {
                report.items.append(CheckItem(id: "metalver", title: tr("Tested Metal version", "Testet Metal-versjon"), status: .ok,
                    detail: tr("This Metal compiler is the one nxnative was tested with.", "Metal-kompilatoren er den nxnative er testet med.")))
            } else {
                report.metalMismatch = true
                var tested = ""
                if let r = check.output.range(of: #"install Xcode [0-9.]+"#, options: .regularExpression) {
                    tested = " (" + check.output[r].replacingOccurrences(of: "install ", with: "") + ")"
                }
                report.items.append(CheckItem(
                    id: "metalver", title: tr("Tested Metal version", "Testet Metal-versjon"), status: .warn,
                    detail: tr("Your Xcode is not the one nxnative was tested with\(tested). Games that use NVN then stop before their shaders unless you allow this Mac's compiler when you build (untested; graphics glitches are possible). The safe way is to install the tested Xcode beside yours.",
                               "Xcode-versjonen din er ikke den nxnative er testet med\(tested). Spill som bruker NVN stopper da før shaderne, med mindre du tillater denne Macens kompilator når du bygger (ikke testet; grafikkfeil kan forekomme). Den trygge løsningen er å installere den testede Xcode-versjonen ved siden av."),
                    fixes: [.link(tr("Xcode downloads", "Last ned Xcode"), "https://developer.apple.com/download/all/")],
                    more: check.output.replacingOccurrences(of: "[RED] ", with: "")))
            }
        }

        report.items.append(keysItem(keys))
        return report
    }

    nonisolated private static func pythonItem(python: String, ownPython: Bool) -> CheckItem {
        let title = tr("Python packages", "Python-pakker")
        guard let outcome = PythonCheck.run(python) else {
            return CheckItem(id: "python", title: title, status: .fail,
                detail: tr("No Python environment for the build script yet. NX Builder can set one up (a few minutes, about 100 MB).",
                           "Det finnes ikke noe Python-miljø for byggeskriptet ennå. NX Builder kan sette opp et (noen minutter, ca. 100 MB)."),
                fixes: [.action(.setUpPython)] + (Shell.which("uv") == nil ? [.command("brew install uv")] : []))
        }
        let place = ownPython ? tr("NX Builder's own environment", "NX Builders eget miljø") : python.deletingLastPathComponent.deletingLastPathComponent.tildePath
        if outcome.ok {
            return CheckItem(id: "python", title: title, status: .ok,
                             detail: "Python \(outcome.version) · lz4, Capstone 5, fontTools · \(place)")
        }
        return CheckItem(id: "python", title: title, status: .fail,
            detail: tr("The Python in \(place) is missing a package or has the wrong one. Set up NX Builder's own environment instead:",
                       "Python i \(place) mangler en pakke eller har feil versjon. Sett opp NX Builders eget miljø i stedet:"),
            fixes: [.action(.setUpPython)] + (Shell.which("uv") == nil ? [.command("brew install uv")] : []),
            more: outcome.error)
    }

    nonisolated private static func keysItem(_ keys: String) -> CheckItem {
        FileManager.default.fileExists(atPath: keys)
            ? CheckItem(id: "keys", title: "prod.keys", status: .ok, detail: keys.tildePath)
            : CheckItem(id: "keys", title: "prod.keys", status: keys.isEmpty ? .warn : .fail,
                        detail: keys.isEmpty
                            ? tr("Not chosen yet. NSP and XCI files need the prod.keys dumped from your own Switch.",
                                 "Ikke valgt ennå. NSP- og XCI-filer trenger prod.keys dumpet fra din egen Switch.")
                            : tr("\(keys.tildePath) is gone.", "Fant ikke \(keys.tildePath)."),
                        fixes: [.action(.chooseKeys)])
    }
}
