import Foundation

/// The app's language: English, or Norwegian when the Mac's first language is Norwegian (or the
/// player picks it). Decided once at launch; a change applies at the next start.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, norwegian
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: tr("Same as the Mac", "Samme som Macen")
        case .english: "English"
        case .norwegian: "Norsk"
        }
    }
}

enum L10n {
    static let defaultsKey = "appLanguage"

    static let norwegian: Bool = {
        switch AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system {
        case .english: return false
        case .norwegian: return true
        case .system:
            let first = Locale.preferredLanguages.first?.lowercased() ?? ""
            return first.hasPrefix("nb") || first.hasPrefix("no") || first.hasPrefix("nn")
        }
    }()
}

/// The English text, or its Norwegian translation when the app speaks Norwegian.
func tr(_ english: String, _ norwegian: String) -> String {
    L10n.norwegian ? norwegian : english
}
