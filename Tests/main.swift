// Headless checks of NX Builder's logic, run by test.sh: no window opens.
// With NXB_DRAW=<folder> it also draws the cards there as PNG files; -appLanguage en|nb|de|fr|es|pt-BR|ja|zh-Hans picks the language.
import AppKit
import SwiftUI

var failures = 0
@MainActor func check(_ ok: Bool, _ what: String, _ line: Int = #line) {
    print(ok ? "ok   \(what)" : "FAIL \(what) (line \(line))")
    if !ok { failures += 1 }
}

func report(_ messages: [String]) -> RecipeReport? {
    var r: RecipeReport?
    for m in messages { RecipeReport.update(&r, with: m) }
    return r
}

let botw = "01007EF00011E000"
let repo = NSHomeDirectory() + "/nxnative"

// The script's messages, in the forms scripts/build_ipa_from_nsp.py writes them.
let mismatch = report([
    "game profile: \(botw)",
    "v720896 is not a version game profile \(botw) registers (v1114112 1.9.0): packing v720896 from a profile derived from it",
    "derived game profile for v720896 (1.5.0): /x/\(botw)_build/profile/\(botw)",
    "app name: The Legend of Zelda: Breath of the Wild; version: 1.5.0; bundle ID: org.nxnative.01007ef00011e000; app: /x/Zelda.app",
    "this Mac app uses v720896 (1.5.0), which game profile \(botw) was not brought up on (v1114112 1.9.0): its settings, with this version's own shaders",
])
check(mismatch?.id == botw, "recipe ID from 'game profile:'")
check(mismatch?.versionMismatch == true, "another version is a mismatch")
check(mismatch?.yourVersion == "1.5.0", "the version being built: \(mismatch?.yourVersion ?? "nil")")
check(mismatch?.provisional == false, "a registered recipe is not provisional")

let fine = report([
    "game profile: \(botw)",
    "app name: The Legend of Zelda: Breath of the Wild; version: 1.9.0; bundle ID: org.nxnative.01007ef00011e000; app: /x/Zelda.app",
])
check(fine?.versionMismatch == false && fine?.derivedReason == nil, "the recipe's own version is fine")
check(fine?.yourVersion == "1.9.0", "version from the app name line")

let shaderOnly = report([
    "game profile: \(botw)",
    "the folder has no v0, whose files game profile \(botw)'s shader tables were made from: packing v1114112 from a profile derived from it",
])
check(shaderOnly?.derivedReason != nil && shaderOnly?.versionMismatch == false, "missing shader-table version is not a mismatch")

let guessed = report(["game profile: 0100ABCD12340000 (provisional: /x/profile/0100ABCD12340000)"])
check(guessed?.provisional == true && guessed?.id == "0100ABCD12340000", "provisional recipe")

check(report(["app name: X; version: 1.0; bundle ID: y"]) == nil, "nothing before 'game profile:'")

// The recipes in the checkout.
let recipes = RecipeBook.load(repo: repo)
check(recipes.count > 100, "games table read: \(recipes.count) recipes")
let zelda = recipes.first { $0.titleID == botw }
check(zelda?.name == "The Legend of Zelda: Breath of the Wild" && zelda?.build == "1.9.0", "BotW recipe: \(zelda?.name ?? "-") \(zelda?.build ?? "-")")
check(recipes.contains { $0.baseOnly }, "some recipes are for the base game alone")
let profile = RecipeBook.profile(repo: repo, id: botw)
check(profile?.builds == [RecipeBuild(version: "v1114112", display: "1.9.0")], "BotW game.tsv build rows")

// What the file names say before a build.
func file(_ name: String) -> GameFile { GameFile.named(name) }
let old = RecipePrecheck.make(files: [file("Zelda [01007EF00011E000][v0].nsp"), file("Zelda [01007EF00011E800][v720896].nsp")], repo: repo)
check(old.titleID == botw && old.newestTag == "v720896" && old.versionMatches == false, "1.5.0 update tag does not match")
let right = RecipePrecheck.make(files: [file("Zelda [01007EF00011E000][v0].nsp"), file("Zelda [01007EF00011E800][v1114112].nsp"),
                                        file("Zelda DLC [01007EF00011F001][v196608].nsp")], repo: repo)
check(right.versionMatches == true, "1.9.0 update tag matches (DLC tags ignored)")
let untagged = RecipePrecheck.make(files: [file("game.xci")], repo: repo)
check(untagged.titleID == nil, "a name without tags tells nothing")
let unknown = RecipePrecheck.make(files: [file("Game [0100ABCD12340000][v0].nsp")], repo: repo)
check(unknown.titleID != nil && !unknown.hasProfile, "a game without a recipe")

// The key map matches the host's (dm/host/front_mac.m key_bit / on_key).
let host = (try? String(contentsOfFile: repo + "/dm/host/front_mac.m", encoding: .utf8)) ?? ""
check(host.contains("case 38: return 0;  case 40: return 1;  case 32: return 2;  case 34: return 3;    // J K U I → A B X Y"), "host: J K U I are A B X Y")
check(host.contains("case 12: return 6;  case 14: return 7;  case 6: return 8;   case 8: return 9;    // Q E Z C → L R ZL ZR"), "host: Q E Z C are L R ZL ZR")
check(host.contains("case 3: return 4;   case 5: return 5;") && host.contains("case 36: return 10; case 48: return 11;"), "host: F G stick presses, Return Tab + −")
check(host.contains("NSEventModifierFlagShift") && host.contains("case 13: g_w = down"), "host: WASD and Shift + arrows")
check(Array(KeyMap.buttons.map(\.keys.first!).prefix(10)) == ["J", "K", "U", "I", "Q", "E", "Z", "C", "⏎", "⇥"], "the sheet lists the same keys")

// File roles from the usual dump names.
check(GameFile.named("Zelda [01007EF00011E000][v0].nsp").role == .base, "base game role")
check(GameFile.named("Zelda [01007EF00011E800][v1114112].nsp").role == .update && GameFile.named("Zelda [01007EF00011E800][v1114112].nsp").version == "v1114112", "update role and version")
check(GameFile.named("Zelda DLC [01007EF00011F001][v196608].nsp").role == .dlc, "DLC role")
check(GameFile.named("game.xci").role == .unknown, "an untagged name has no role")
check(GameFile.folderName(for: URL(fileURLWithPath: "/x/Test Spill [0100000000010000][v0] (EUR).xci")) == "Test Spill", "folder name without tags")

// The Python check, on the checkout's own environment.
let repoPython = repo + "/.venv/bin/python3"
if FileManager.default.isExecutableFile(atPath: repoPython) {
    let outcome = PythonCheck.run(repoPython)
    check(outcome?.ok == true, "PythonCheck on \(repoPython.tildePath): \(outcome.map { $0.ok ? $0.version : $0.error } ?? "nil")")
}
check(PythonCheck.run("/nonexistent/python3") == nil, "no Python, no outcome")

// The whole setup check on this Mac (read-only).
let report = SetupChecker.check(repo: repo, keys: "", python: repoPython, ownPython: false)
for item in report.items { print("     \(item.status) \(item.title): \(item.detail.prefix(90))") }
check(report.items.contains { $0.id == "repo" && $0.status == .ok }, "setup check finds nxnative")
check(report.items.contains { $0.id == "keys" && $0.status == .warn && $0.fixes == [.action(.chooseKeys)] }, "no keys is a warning with a choose button")
let noRepo = SetupChecker.check(repo: "/nonexistent/nxnative", keys: "", python: "/nonexistent/python3", ownPython: false)
check(noRepo.items.contains { $0.id == "repo" && $0.fixes.contains(.action(.cloneNxnative)) }, "a missing nxnative offers the download")
check(noRepo.items.contains { $0.id == "python" && $0.fixes.contains(.action(.setUpPython)) }, "a missing Python offers the setup")

// The Python setup's commands.
if case .success(let steps) = SetupSteps.python() {
    check(steps.count == 3 && steps.last?.exe == AppPaths.venvPython, "Python setup: \(steps.map { $0.exe.lastPathComponent + " " + $0.args.prefix(2).joined(separator: " ") })")
} else { check(false, "Python setup has a plan") }

// Languages.
check(L10n.format("%@ of %@", ["1", "2"]) == "1 of 2", "format: plain placeholders")
check(L10n.format("%2$@ – %1$@", ["a", "b"]) == "b – a", "format: positional placeholders")
check(L10n.format("100%% %@", ["x"]) == "100% x" && L10n.format("100%", []) == "100%", "format: percent signs")
check(AppLanguage.matching(["de-NO"]) == .de && AppLanguage.matching(["nb-NO"]) == .nb && AppLanguage.matching(["no"]) == .nb, "Mac language: German, Norwegian")
check(AppLanguage.matching(["zh-Hant-TW", "ja-JP"]) == .ja && AppLanguage.matching(["zh-Hans-CN"]) == .zhHans, "Mac language: Chinese scripts")
check(AppLanguage.matching(["pt-PT"]) == .ptBR && AppLanguage.matching(["sv-SE"]) == .en && AppLanguage.matching(["en-US", "nb"]) == .en, "Mac language: fallbacks")
check(AppLanguage(stored: "norwegian") == .nb && AppLanguage(stored: "english") == .en && AppLanguage(stored: nil) == .system, "the first version's stored choice")
for language in AppLanguage.allCases where language != .system && language != .en {
    let table = L10n.load(language)
    if !table.isEmpty { check(table.count > 200, "\(language.rawValue): \(table.count) translations load") }
}

// Review fixes.
let multi = report(["game profile: 010049900F546000", "app name: Super Mario 3D All-Stars; version: 1.1.0; bundle ID: x; app: /x/Mario.app",
                    "==== program 1", "game profile: 010049900F546001"])
check(multi?.id == "010049900F546000", "a multi-program game keeps its first recipe")

let scratch = NSTemporaryDirectory() + "nxb-tests-\(getpid())"
let fm = FileManager.default
@MainActor func fakeApp(_ path: String, titleID: String?) {
    try? fm.createDirectory(atPath: path + "/Contents", withIntermediateDirectories: true)
    var plist: [String: Any] = ["CFBundleName": (path.lastPathComponent as NSString).deletingPathExtension]
    if let titleID { plist["DMTitleID"] = titleID }
    (plist as NSDictionary).write(toFile: path + "/Contents/Info.plist", atomically: true)
}
fakeApp(scratch + "/games/Celeste.app", titleID: "0100000000010000")
fakeApp(scratch + "/dest/Celeste.app", titleID: nil)            // someone's own Mac game of the same name
do {
    _ = try BuildRunner.moveApp(scratch + "/games/Celeste.app", toFolder: scratch + "/dest")
    check(false, "moving over another app must refuse")
} catch {
    check(error is BuildRunner.OccupiedError && fm.fileExists(atPath: scratch + "/dest/Celeste.app/Contents/Info.plist")
          && fm.fileExists(atPath: scratch + "/games/Celeste.app"), "an app that is not an earlier build is left alone")
}
let same = try? BuildRunner.moveApp(scratch + "/games/Celeste.app", toFolder: scratch + "/games/../games")
check(same?.trashed == nil && fm.fileExists(atPath: scratch + "/games/Celeste.app"), "moving into its own folder does nothing")
let moved = try? BuildRunner.moveApp(scratch + "/games/Celeste.app", toFolder: scratch + "/empty")
check(moved?.trashed == nil && fm.fileExists(atPath: scratch + "/empty/Celeste.app"), "a move into an empty folder")

try? fm.createDirectory(atPath: scratch + "/many", withIntermediateDirectories: true)
for name in ["A [0100000000010000][v0].nsp", "B [0100000000020000][v0].nsp"] { fm.createFile(atPath: scratch + "/many/" + name, contents: Data()) }
check(!GameFile.isGameFolder(scratch + "/many"), "a folder of two games is shared")
try? fm.createDirectory(atPath: scratch + "/one", withIntermediateDirectories: true)
for name in ["A [0100000000010000][v0].nsp", "A [0100000000010800][v65536].nsp"] { fm.createFile(atPath: scratch + "/one/" + name, contents: Data()) }
check(GameFile.isGameFolder(scratch + "/one"), "a base game and its update are one game's folder")
try? fm.removeItem(atPath: scratch)

check(SetupChecker.xcodeApps().first == "/Applications/Xcode.app" || !fm.fileExists(atPath: "/Applications/Xcode.app"), "Xcode found: \(SetupChecker.xcodeApps())")
check(report.items.contains { $0.id == "dotnet" && $0.status == .ok }, "the .NET 10 SDK is found")

let updates = NxnativeUpdates()
await updates.check(repo: repo)
check(updates.localChanges.allSatisfy { !$0.hasPrefix(" ") && !$0.isEmpty } && (updates.localChanges.isEmpty || updates.localChanges.contains("pyproject.toml")),
      "local changes in nxnative: \(updates.localChanges)")

// Pictures of the cards, drawn off screen.
if let draw = ProcessInfo.processInfo.environment["NXB_DRAW"] {
    let out = URL(fileURLWithPath: draw)
    do {
        @MainActor func draw<V: View>(_ name: String, _ view: V, scheme: ColorScheme) {
            let renderer = ImageRenderer(content: view
                .padding(16)
                .frame(width: 680)
                .background(scheme == .dark ? Color(white: 0.16) : .white)
                .environment(\.colorScheme, scheme))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("FAIL draw \(name)"); failures += 1; return
            }
            try? png.write(to: out.appendingPathComponent("\(name).png"))
        }
        let cards = VStack(spacing: 10) {
            RecipeCard(report: mismatch!, recipe: zelda)
            RecipeCard(report: fine!, recipe: zelda)
            RecipeCard(report: shaderOnly!, recipe: zelda)
            RecipeCard(report: guessed!, recipe: nil)
        }
        let hints = VStack(alignment: .leading, spacing: 12) {
            RecipeHintRow(check: old, recipe: zelda)
            RecipeHintRow(check: right, recipe: zelda)
            RecipeHintRow(check: untagged, recipe: nil)
            RecipeHintRow(check: unknown, recipe: nil)
        }
        draw("cards-dark", cards, scheme: .dark)
        draw("cards-light", cards, scheme: .light)
        draw("hints-dark", hints, scheme: .dark)
        draw("controls-dark", ControlsContent(), scheme: .dark)
        draw("controls-light", ControlsContent(), scheme: .light)
    }
}

print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
