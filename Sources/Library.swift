import AppKit
import Foundation
import Observation

/// A Mac app of a game, as `dm/mac/pack_app.py` packs it (its Info.plist has DMTitleID).
struct GameApp: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let version: String
    let titleID: String
    var id: String { path }

    var logFile: String { NSHomeDirectory() + "/Library/Logs/nxnative/\(titleID).log" }
    var dataFolder: String { NSHomeDirectory() + "/Library/Application Support/nxnative/\(titleID)" }

    /// The build folder the NSP script left beside the game files it was built from.
    func buildFolder(source: String?) -> String? {
        guard let source else { return nil }
        let folder = source + "/\(titleID)_build"
        return FileManager.default.fileExists(atPath: folder) ? folder : nil
    }
}

@MainActor @Observable
final class GameLibrary {
    private(set) var apps: [GameApp] = []
    private(set) var isScanning = false
    /// Bytes on disk of each build folder, filled in as they are measured.
    private(set) var buildSizes: [String: Int64] = [:]

    func refresh(known: [String]) async {
        isScanning = true
        apps = await Task.detached { Self.scan(known: known) }.value
        isScanning = false
    }

    func measure(_ folder: String) async {
        let size = await Task.detached { Self.allocatedSize(folder) }.value
        buildSizes[folder] = size
    }

    func forgetSize(_ folder: String) { buildSizes[folder] = nil }

    nonisolated static func scan(known: [String]) -> [GameApp] {
        let fm = FileManager.default
        var candidates = known
        for folder in ["/Applications", NSHomeDirectory() + "/Applications"] {
            let names = (try? fm.contentsOfDirectory(atPath: folder)) ?? []
            candidates += names.filter { $0.hasSuffix(".app") }.map { folder + "/" + $0 }
        }
        var seen = Set<String>()
        var apps: [GameApp] = []
        for path in candidates where seen.insert(path).inserted {
            guard let app = read(path) else { continue }
            apps.append(app)
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    nonisolated static func read(_ path: String) -> GameApp? {
        guard let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any],
              let titleID = info["DMTitleID"] as? String else { return nil }
        let name = info["CFBundleDisplayName"] as? String
            ?? info["CFBundleName"] as? String
            ?? (path.lastPathComponent as NSString).deletingPathExtension
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        return GameApp(path: path, name: name, version: version, titleID: titleID)
    }

    /// The space a folder takes on disk.
    nonisolated static func allocatedSize(_ folder: String) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

enum GameFileRole: Sendable {
    case base, update, dlc, nup, dump, unknown
}

/// A file in the game folder that the build script reads.
struct GameFile: Identifiable, Sendable {
    let path: String
    let name: String
    let size: Int64
    let role: GameFileRole
    /// The [v<N>] tag in the name, if any.
    let version: String?
    var id: String { path }

    var needsKeys: Bool { role != .nup && role != .dump }

    var label: String {
        let kind: String
        switch role {
        case .base: kind = L("Base game")
        case .update: kind = L("Update")
        case .dlc: kind = "DLC"
        case .nup: kind = "NUP"
        case .dump: kind = L("Extracted game")
        case .unknown: kind = ""
        }
        guard let version, version != "v0", role != .dlc else { return kind }
        return kind.isEmpty ? version : "\(kind) \(version)"
    }

    var symbol: String {
        switch role {
        case .dlc: "puzzlepiece.extension"
        case .update: "arrow.up.circle"
        default: "shippingbox"
        }
    }

    static let extensions: Set<String> = ["nsp", "xci", "nsz", "xcz", "nup"]
    /// The files that need prod.keys and a folder of their own (a .nup can be given as it is).
    static let packageExtensions: Set<String> = ["nsp", "xci", "nsz", "xcz"]

    /// A file named as the usual dump tools name them.
    nonisolated static func named(_ name: String, path: String = "", size: Int64 = 0) -> GameFile {
        let (role, version) = guess(name)
        return GameFile(path: path.isEmpty ? "/" + name : path, name: name, size: size, role: role, version: version)
    }

    /// A folder that holds only game files and what builds leave beside them, so a file in it can be
    /// built through the folder. Home, Downloads, Desktop and Documents never count.
    nonisolated static func isGameFolder(_ folder: String) -> Bool {
        let home = NSHomeDirectory()
        let shared = [home, home + "/Downloads", home + "/Desktop", home + "/Documents"]
        let standard = URL(fileURLWithPath: folder).standardizedFileURL.path
        if shared.contains(where: { URL(fileURLWithPath: $0).standardizedFileURL.path == standard }) { return false }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return false }
        let onlyGameFiles = names.allSatisfy { name in
            let ext = (name as NSString).pathExtension.lowercased()
            return name.hasPrefix(".") || extensions.contains(ext) || ext == "app" || name.hasSuffix("_build")
                || name.hasSuffix("_survey") || name.hasSuffix(".partial")
        }
        guard onlyGameFiles else { return false }
        // Several packages must name one game (base, update, DLC); a folder of many games is shared.
        let packages = names.filter { packageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        return packages.count <= 1 || baseTitleID(scan(folder)) != nil
    }

    /// The base game's title ID (its profile's ID) from the files' names, when they name one game:
    /// …000 is the base game, …800 its update, and a DLC is the base + 0x1000 + its index.
    nonisolated static func baseTitleID(_ files: [GameFile]) -> String? {
        var ids = Set<UInt64>()
        for file in files {
            let upper = file.name.uppercased()
            guard let r = upper.range(of: #"0[0-9A-F]{15}"#, options: .regularExpression),
                  let tid = UInt64(upper[r], radix: 16) else { continue }
            let low = tid & 0xFFF
            ids.insert(low == 0 ? tid : low == 0x800 ? tid & ~0xFFF : (tid & ~0xFFF) &- 0x1000)
        }
        guard ids.count == 1, let id = ids.first else { return nil }
        return String(format: "%016llX", id)
    }

    /// A folder name for a game file: its name without [title ID], [version] or (region) tags.
    nonisolated static func folderName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let clean = stem
            .replacingOccurrences(of: #"\s*[\[\(][^\]\)]*[\]\)]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_.")))
        return clean.isEmpty ? stem : clean
    }

    /// The game files in a folder (or the one .nup file given), with a guess at what each is.
    nonisolated static func scan(_ path: String) -> [GameFile] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard !path.isEmpty, fm.fileExists(atPath: path, isDirectory: &isDir) else { return [] }
        let urls: [URL]
        if isDir.boolValue {
            urls = ((try? fm.contentsOfDirectory(at: URL(fileURLWithPath: path),
                                                 includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])) ?? [])
        } else {
            urls = [URL(fileURLWithPath: path)]
        }
        var files: [GameFile] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if extensions.contains(ext) {
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                if ext == "nup" {
                    files.append(GameFile(path: url.path, name: url.lastPathComponent, size: size, role: .nup, version: nil))
                } else {
                    files.append(named(url.lastPathComponent, path: url.path, size: size))
                }
            } else if url.lastPathComponent == "base",
                      (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                files.append(GameFile(path: url.path, name: "base/", size: 0, role: .dump, version: nil))
            }
        }
        return files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Base game, update or DLC from the usual file names: [BASE] / [UPD] / [DLC] tags, or the
    /// title ID (…000 base, …800 update, anything else DLC). Only a hint; the script reads the files.
    nonisolated static func guess(_ name: String) -> (GameFileRole, String?) {
        let upper = name.uppercased()
        var role = GameFileRole.unknown
        if upper.contains("[DLC]") { role = .dlc }
        else if upper.contains("[UPD]") || upper.contains("UPDATE") { role = .update }
        else if upper.contains("[BASE]") { role = .base }
        else if let r = upper.range(of: #"0[0-9A-F]{15}"#, options: .regularExpression) {
            switch upper[r].suffix(3) {
            case "000": role = .base
            case "800": role = .update
            default: role = .dlc
            }
        }
        let version = name.range(of: #"\[v\d+\]"#, options: .regularExpression).map { String(name[$0].dropFirst().dropLast()) }
        return (role, version)
    }
}
