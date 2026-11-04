import Foundation
import Observation

enum Destination: String, CaseIterable, Identifiable {
    case applications, gameFolder, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .applications: tr("Applications folder", "Programmer-mappen")
        case .gameFolder: tr("Next to the game files", "Samme mappe som spillfilene")
        case .custom: tr("Another folder", "En annen mappe")
        }
    }
}

struct GameLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
}

/// The codes `build_ipa_from_nsp.py -l` accepts. The game must support the one picked.
var gameLanguages: [GameLanguage] {
    [
        .init(code: "", name: tr("English (default)", "Engelsk (standard)")),
        .init(code: "en-GB", name: tr("English (UK)", "Engelsk (britisk)")),
        .init(code: "ja", name: tr("Japanese", "Japansk")),
        .init(code: "fr", name: tr("French", "Fransk")),
        .init(code: "fr-CA", name: tr("French (Canada)", "Fransk (kanadisk)")),
        .init(code: "de", name: tr("German", "Tysk")),
        .init(code: "es", name: tr("Spanish", "Spansk")),
        .init(code: "es-419", name: tr("Spanish (Latin America)", "Spansk (latinamerikansk)")),
        .init(code: "it", name: tr("Italian", "Italiensk")),
        .init(code: "nl", name: tr("Dutch", "Nederlandsk")),
        .init(code: "pt", name: tr("Portuguese", "Portugisisk")),
        .init(code: "pt-BR", name: tr("Portuguese (Brazil)", "Portugisisk (brasiliansk)")),
        .init(code: "ru", name: tr("Russian", "Russisk")),
        .init(code: "ko", name: tr("Korean", "Koreansk")),
        .init(code: "zh-Hans", name: tr("Chinese (Simplified)", "Kinesisk (forenklet)")),
        .init(code: "zh-Hant", name: tr("Chinese (Traditional)", "Kinesisk (tradisjonell)")),
    ]
}

/// Where the app keeps its own files.
enum AppPaths {
    static let support = NSHomeDirectory() + "/Library/Application Support/NX Builder"
    /// The Python environment the app sets up itself (Setup › Set up Python).
    static let venv = support + "/python"
    static var venvPython: String { venv + "/bin/python3" }

    static let nxnativeURL = "https://github.com/seedds/nxnative.git"

    /// Where people usually clone nxnative; the first that has the build script wins.
    static func findRepo() -> String? {
        let home = NSHomeDirectory()
        let candidates = ["nxnative", "Developer/nxnative", "Documents/nxnative", "git/nxnative", "GitHub/nxnative",
                          "src/nxnative", "Projects/nxnative", "Code/nxnative", "Desktop/nxnative", "Downloads/nxnative"]
        return candidates.map { home + "/" + $0 }
            .first { FileManager.default.fileExists(atPath: $0 + "/scripts/build_ipa_from_nsp.py") }
    }
}

/// Everything the player picked, kept between starts.
@MainActor @Observable
final class AppSettings {
    var repoPath: String { didSet { save(repoPath, "repoPath") } }
    var keysPath: String { didSet { save(keysPath, "keysPath") } }
    var gamePath: String { didSet { save(gamePath, "gamePath") } }
    var destination: Destination { didSet { save(destination.rawValue, "destination") } }
    var customDestPath: String { didSet { save(customDestPath, "customDestPath") } }
    var language: String { didSet { save(language, "language") } }
    var allowOtherMetal: Bool { didSet { save(allowOtherMetal, "allowOtherMetal") } }
    var seenShaders: Bool { didSet { save(seenShaders, "seenShaders") } }
    var notify: Bool { didSet { save(notify, "notify") } }
    var appLanguage: AppLanguage { didSet { save(appLanguage.rawValue, L10n.defaultsKey) } }
    /// Apps built here, so the library finds them wherever they were saved.
    var knownApps: [String] { didSet { save(knownApps, "knownApps") } }
    /// The game folder each app was built from, for building it again and for its build folder.
    var appSources: [String: String] { didSet { save(appSources, "appSources") } }

    init() {
        let d = UserDefaults.standard
        let home = NSHomeDirectory()
        repoPath = d.string(forKey: "repoPath") ?? AppPaths.findRepo() ?? home + "/nxnative"
        let guideKeys = home + "/.switch/prod.keys"
        keysPath = d.string(forKey: "keysPath")
            ?? (FileManager.default.fileExists(atPath: guideKeys) ? guideKeys : "")
        gamePath = d.string(forKey: "gamePath") ?? ""
        destination = Destination(rawValue: d.string(forKey: "destination") ?? "") ?? .applications
        customDestPath = d.string(forKey: "customDestPath") ?? ""
        language = d.string(forKey: "language") ?? ""
        allowOtherMetal = d.bool(forKey: "allowOtherMetal")
        seenShaders = d.bool(forKey: "seenShaders")
        notify = d.object(forKey: "notify") as? Bool ?? true
        appLanguage = AppLanguage(rawValue: d.string(forKey: L10n.defaultsKey) ?? "") ?? .system
        knownApps = d.stringArray(forKey: "knownApps") ?? []
        appSources = d.dictionary(forKey: "appSources") as? [String: String] ?? [:]
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// The folder the finished app is moved to, or nil to leave it beside the game files.
    var destinationFolder: String? {
        switch destination {
        case .applications: "/Applications"
        case .gameFolder: nil
        case .custom: customDestPath.isEmpty ? nil : customDestPath
        }
    }

    /// The Python that runs the build script: the app's own environment once set up, else the
    /// `.venv` in the nxnative folder (the AppleGamingWiki guide's step 5).
    var python: String {
        FileManager.default.isExecutableFile(atPath: AppPaths.venvPython) ? AppPaths.venvPython : repoPath + "/.venv/bin/python3"
    }
    var usesOwnPython: Bool { python == AppPaths.venvPython }
    var buildScript: String { repoPath + "/scripts/build_ipa_from_nsp.py" }
    var hasRepo: Bool { FileManager.default.fileExists(atPath: buildScript) }

    func remember(app path: String, builtFrom source: String) {
        knownApps.removeAll { $0 == path }
        knownApps.insert(path, at: 0)
        appSources[path] = source
    }

    func forget(app path: String) {
        knownApps.removeAll { $0 == path }
        appSources[path] = nil
    }
}

/// Holds the app's state; one for the whole app.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    let settings = AppSettings()
    let runner = BuildRunner()
    let checker = SetupChecker()
    let library = GameLibrary()
    let recipes = RecipeStore()
    let tasks = TaskRunner()
    let updates = NxnativeUpdates()
}
