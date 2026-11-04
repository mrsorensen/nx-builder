import Foundation

/// The app's language. The texts are written in English in the code; each other language is a file,
/// `Localizations/<code>.json`, that maps the English text to its translation (placeholders %@, or
/// %1$@ %2$@ … where a translation puts them in another order). Decided once at launch: a change in
/// Setup applies at the next start.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en, nb, de, fr, es
    case ptBR = "pt-BR"
    case ja
    case zhHans = "zh-Hans"
    var id: String { rawValue }

    /// Each language by its own name, as language menus show them.
    var label: String {
        switch self {
        case .system: L("Same as the Mac")
        case .en: "English"
        case .nb: "Norsk"
        case .de: "Deutsch"
        case .fr: "Français"
        case .es: "Español"
        case .ptBR: "Português (Brasil)"
        case .ja: "日本語"
        case .zhHans: "简体中文"
        }
    }

    /// A stored choice; "english" and "norwegian" are the values of the first version.
    init(stored: String?) {
        switch stored {
        case "english": self = .en
        case "norwegian": self = .nb
        default: self = AppLanguage(rawValue: stored ?? "") ?? .system
        }
    }

    /// The language for the Mac's preferred languages: the first one the app has, else English.
    static func matching(_ preferred: [String]) -> AppLanguage {
        for tag in preferred.map({ $0.lowercased() }) {
            if tag.hasPrefix("en") { return .en }
            if tag.hasPrefix("nb") || tag.hasPrefix("no") || tag.hasPrefix("nn") { return .nb }
            if tag.hasPrefix("de") { return .de }
            if tag.hasPrefix("fr") { return .fr }
            if tag.hasPrefix("es") { return .es }
            if tag.hasPrefix("pt") { return .ptBR }
            if tag.hasPrefix("ja") { return .ja }
            if tag.hasPrefix("zh-hans") || tag.hasPrefix("zh-cn") || tag.hasPrefix("zh-sg") { return .zhHans }
        }
        return .en
    }
}

enum L10n {
    static let defaultsKey = "appLanguage"

    /// The language in use for this run.
    static let language: AppLanguage = {
        let chosen = AppLanguage(stored: UserDefaults.standard.string(forKey: defaultsKey))
        return chosen == .system ? AppLanguage.matching(Locale.preferredLanguages) : chosen
    }()

    static let table: [String: String] = load(language)

    /// The translations of a language, from the app bundle (Contents/Resources/Localizations), or the
    /// project's Localizations folder for the test and snapshot tools run from it.
    static func load(_ language: AppLanguage) -> [String: String] {
        guard language != .en, language != .system else { return [:] }
        let name = "Localizations/\(language.rawValue).json"
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent(name)) }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(name))
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let table = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                return table
            }
        }
        return [:]
    }

    /// Fills %@, %1$@, %2$@ … with the arguments, and %% with %.
    static func format(_ template: String, _ args: [String]) -> String {
        guard !args.isEmpty else { return template }
        var out = "", next = 0
        var i = template.startIndex
        while i < template.endIndex {
            let c = template[i]
            guard c == "%", let j = template.index(i, offsetBy: 1, limitedBy: template.endIndex), j < template.endIndex else {
                out.append(c); i = template.index(after: i); continue
            }
            if template[j] == "%" { out.append("%"); i = template.index(after: j); continue }
            if template[j] == "@" {
                out += next < args.count ? args[next] : ""
                next += 1
                i = template.index(after: j); continue
            }
            // %n$@
            var k = j, digits = ""
            while k < template.endIndex, template[k].isNumber { digits.append(template[k]); k = template.index(after: k) }
            if !digits.isEmpty, k < template.endIndex, template[k] == "$",
               let at = template.index(k, offsetBy: 1, limitedBy: template.endIndex), at < template.endIndex, template[at] == "@",
               let n = Int(digits) {
                out += n >= 1 && n <= args.count ? args[n - 1] : ""
                i = template.index(after: at); continue
            }
            out.append(c); i = template.index(after: i)
        }
        return out
    }
}

/// The text in the app's language. `key` is the English text, with %@ where each argument goes.
func L(_ key: String, _ args: String...) -> String {
    L10n.format(L10n.table[key] ?? key, args)
}
