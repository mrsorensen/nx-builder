import Foundation
import Observation

/// A game nxnative has a recipe for: its game profile, `dm/games/<title ID>/`, as the games table in
/// `dm/games/README.md` lists it, with the version it was brought up on.
struct Recipe: Identifiable, Hashable, Sendable {
    let titleID: String
    let name: String
    let build: String        // as the table says: "1.9.0", "1.00 (base)"
    let engine: String
    let graphics: String
    var id: String { titleID }

    /// Made for the base game without an update.
    var baseOnly: Bool { build.contains("(base)") }

    var buildLabel: String {
        baseOnly ? build.replacingOccurrences(of: " (base)", with: "") + tr(" (no update)", " (uten oppdatering)") : build
    }

    var noteURL: URL? { URL(string: "https://github.com/seedds/nxnative/blob/main/dm/games/\(titleID)/README.md") }
}

/// A version a recipe registers: its `build` row in game.tsv.
struct RecipeBuild: Hashable, Sendable {
    let version: String      // v1114112
    let display: String      // 1.9.0
}

enum RecipeBook {
    /// Every row of the games table. Nothing when the repository is not where the settings say.
    nonisolated static func load(repo: String) -> [Recipe] {
        guard let text = try? String(contentsOfFile: repo + "/dm/games/README.md", encoding: .utf8) else { return [] }
        var recipes: [Recipe] = []
        for line in text.split(separator: "\n") where line.hasPrefix("| [") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 7, let close = cells[1].range(of: "](", options: .backwards) else { continue }
            let name = String(cells[1][cells[1].index(after: cells[1].startIndex)..<close.lowerBound])
            let id = cells[2].trimmingCharacters(in: CharacterSet(charactersIn: "`")).uppercased()
            guard id.count == 16 else { continue }
            recipes.append(Recipe(titleID: id, name: name, build: cells[3], engine: cells[5], graphics: cells[6]))
        }
        return recipes
    }

    /// The profile's name and registered versions from its game.tsv, or nil when there is no profile.
    nonisolated static func profile(repo: String, id: String) -> (name: String, builds: [RecipeBuild])? {
        guard let text = try? String(contentsOfFile: "\(repo)/dm/games/\(id)/game.tsv", encoding: .utf8) else { return nil }
        var name = ""
        var builds: [RecipeBuild] = []
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\t").map(String.init)
            if f.count >= 2, f[0] == "name" { name = f[1] }
            if f.count >= 3, f[0] == "build" { builds.append(RecipeBuild(version: f[1], display: f[2])) }
        }
        return (name, builds)
    }
}

/// The recipes of the nxnative checkout in the settings.
@MainActor @Observable
final class RecipeStore {
    private(set) var recipes: [Recipe] = []
    private var byID: [String: Recipe] = [:]

    func reload(repo: String) async {
        let list = await Task.detached { RecipeBook.load(repo: repo) }.value
        byID = Dictionary(list.map { ($0.titleID, $0) }, uniquingKeysWith: { first, _ in first })
        recipes = list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func recipe(_ id: String) -> Recipe? { byID[id.uppercased()] }
}

/// What the build script says about the recipe it builds with (scripts/build_ipa_from_nsp.py):
/// `game profile: <id>` once it knows the game, `<why>: packing v<N> from a profile derived from it`
/// when the version is not the recipe's own, `derived game profile for v<N> (<display>)`, the
/// `app name: …; version: …` line, and its report at the end.
struct RecipeReport: Equatable, Sendable {
    var id: String
    var provisional = false
    /// The script built from a profile derived from the recipe, and why.
    var derivedReason: String?
    /// The version being built is not one the recipe registers: its fixes do not apply.
    var versionMismatch = false
    /// The display version being built ("1.5.0").
    var yourVersion: String?

    /// Takes one of the script's messages, its clock and `[RED] ` already removed.
    static func update(_ report: inout RecipeReport?, with msg: String) {
        if msg.hasPrefix("game profile: ") {   // the first is the game's; a multi-program game's others follow
            guard report == nil else { return }
            let id = msg.dropFirst("game profile: ".count).prefix(16)
            report = RecipeReport(id: id.uppercased(), provisional: msg.contains("(provisional:"))
            return
        }
        guard var r = report else { return }
        if msg.hasSuffix("from a profile derived from it"), let cut = msg.range(of: ": packing ") {
            let reason = String(msg[..<cut.lowerBound])
            r.derivedReason = reason
            if reason.contains("is not a version game profile") || reason.contains("not the builds game profile") {
                r.versionMismatch = true
            }
        } else if msg.hasPrefix("derived game profile for "),
                  let m = msg.range(of: #"\(([^)]*)\)"#, options: .regularExpression) {
            r.yourVersion = String(msg[m].dropFirst().dropLast())
        } else if msg.hasPrefix("app name:"),
                  let m = msg.range(of: #"; version: [^;]+"#, options: .regularExpression), r.yourVersion == nil {
            r.yourVersion = String(msg[m].dropFirst("; version: ".count))
        } else if msg.contains("was not brought up on") {
            r.versionMismatch = true
        }
        report = r
    }
}

/// What the game folder's file names say before a build: the game, and whether the folder has the
/// version its recipe was made for. Names without a [title ID] or [v<N>] tag tell nothing.
struct RecipePrecheck: Equatable, Sendable {
    var titleID: String?
    var profileName: String?
    var builds: [RecipeBuild] = []
    /// The newest [v<N>] tag on the base game and update files.
    var newestTag: String?

    var hasProfile: Bool { profileName != nil }
    var versionMatches: Bool? {
        guard let newestTag, !builds.isEmpty else { return nil }
        return builds.contains { $0.version == newestTag }
    }

    nonisolated static func make(files: [GameFile], repo: String) -> RecipePrecheck {
        var check = RecipePrecheck()
        guard let id = GameFile.baseTitleID(files) else { return check }
        check.titleID = id
        if let profile = RecipeBook.profile(repo: repo, id: id) {
            check.profileName = profile.name
            check.builds = profile.builds
        }
        let tags = files.filter { $0.role != .dlc }.compactMap(\.version)
        check.newestTag = tags.max { (Int($0.dropFirst()) ?? 0) < (Int($1.dropFirst()) ?? 0) }
        return check
    }
}
