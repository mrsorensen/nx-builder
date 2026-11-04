import Foundation

/// The app was called NX Bygger (bundle ID local.nxbygger) before its first release. Its settings and
/// its Python environment move over once, so nobody has to set it up again.
enum Migration {
    static let doneKey = "migratedFromNXBygger"
    static let oldDomain = "local.nxbygger"
    static let oldSupport = NSHomeDirectory() + "/Library/Application Support/NX Bygger"
    static let keys = ["repoPath", "keysPath", "gamePath", "destination", "customDestPath", "language", "allowOtherMetal",
                       "seenShaders", "notify", L10n.defaultsKey, "knownApps", "appSources"]

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        for key in keys where defaults.object(forKey: key) == nil {
            // Only the old app's own domain, not the global one.
            if let value = CFPreferencesCopyAppValue(key as CFString, oldDomain as CFString) {
                defaults.set(value, forKey: key)
            }
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: oldSupport) && !fm.fileExists(atPath: AppPaths.support) {
            try? fm.moveItem(atPath: oldSupport, toPath: AppPaths.support)
        }
    }
}
