import AppKit
import SwiftUI

/// The recipe a running or finished build uses, and whether the version fits it.
struct RecipeCard: View {
    let report: RecipeReport
    let recipe: Recipe?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let url = recipe?.noteURL, !report.provisional {
                Link(tr("Read the recipe", "Les oppskriften"), destination: url).font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.12)))
    }

    private var name: String { recipe?.name ?? report.id }
    private var madeFor: String { recipe?.buildLabel ?? tr("another version", "en annen versjon") }

    private enum Level { case ok, info, warn, bad }

    private var level: Level {
        if report.provisional { return .bad }
        if report.versionMismatch { return .warn }
        if report.derivedReason != nil { return .info }
        return .ok
    }

    private var icon: String {
        switch level {
        case .ok: "checkmark.seal.fill"
        case .info: "info.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .bad: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch level {
        case .ok: .green
        case .info: .blue
        case .warn: .orange
        case .bad: .red
        }
    }

    private var title: String {
        switch level {
        case .bad: tr("No recipe for this game", "Ingen oppskrift for dette spillet")
        case .warn: tr("\(name): wrong version for the recipe", "\(name): feil versjon for oppskriften")
        case .ok, .info: tr("Recipe: \(name)", "Oppskrift: \(name)")
        }
    }

    private var detail: String {
        switch level {
        case .bad:
            return tr("nxnative has no setup for this game (\(report.id)) yet. The script guesses one, and the app may not start.",
                      "nxnative har ikke laget et oppsett for spillet (\(report.id)) ennå. Skriptet gjetter et, og appen starter kanskje ikke.")
        case .warn:
            let yours = report.yourVersion ?? tr("another version", "en annen versjon")
            return tr("The recipe was made for \(madeFor), but you are building \(yours). Its fixes apply to that version only, so the game may misbehave or not start. Put the \(madeFor) update in the game folder and build again; what is already extracted is reused.",
                      "Oppskriften er laget for \(madeFor), men du bygger \(yours). Rettelsene i oppskriften gjelder bare den versjonen, så spillet kan få feil eller ikke starte. Legg oppdateringen \(madeFor) i spillmappen og bygg på nytt; det som alt er pakket ut, gjenbrukes.")
        case .info:
            return tr("Made for \(madeFor). Every fix applies, but the folder lacks a version the recipe's shader tables were made from, so they are made from your files.",
                      "Laget for \(madeFor). Alle rettelsene brukes, men mappen mangler en versjon oppskriftens shadertabeller ble laget fra, så de lages fra filene du har.")
        case .ok:
            return tr("Made for \(madeFor)", "Laget for \(madeFor)")
                + (report.yourVersion.map { tr(", and you are building \($0). Every fix applies.", ", og du bygger \($0). Alle rettelsene brukes.") } ?? ".")
        }
    }
}

/// Before a build: what the file names say about the recipe.
struct RecipeHintRow: View {
    let check: RecipePrecheck
    let recipe: Recipe?

    var body: some View {
        if let id = check.titleID {
            if check.hasProfile || recipe != nil {
                row(icon: matchIcon, color: matchColor,
                    title: tr("Recipe: ", "Oppskrift: ") + (recipe?.name ?? check.profileName ?? id),
                    detail: matchDetail)
            } else {
                row(icon: "exclamationmark.triangle.fill", color: .orange,
                    title: tr("No recipe for \(id)", "Ingen oppskrift for \(id)"),
                    detail: tr("nxnative has no setup for this game yet. The build guesses one, and the app may not start.",
                               "nxnative har ikke laget et oppsett for dette spillet ennå. Bygget gjetter et, og appen starter kanskje ikke."))
            }
        } else {
            row(icon: "book.closed", color: .secondary,
                title: tr("Recipe", "Oppskrift"),
                detail: tr("The file names do not say which game this is. Which recipe is used, and whether the version fits, shows when the build starts.",
                           "Filnavnene sier ikke hvilket spill det er. Hvilken oppskrift som brukes, og om versjonen stemmer, ser du når bygget starter."))
        }
    }

    private var madeFor: String {
        recipe?.buildLabel ?? check.builds.map(\.display).joined(separator: ", ")
    }

    private var matchIcon: String {
        switch check.versionMatches {
        case true?: "checkmark.seal.fill"
        case false?: "exclamationmark.triangle.fill"
        case nil: "book.closed"
        }
    }

    private var matchColor: Color {
        switch check.versionMatches {
        case true?: .green
        case false?: .orange
        case nil: .secondary
        }
    }

    private var matchDetail: String {
        switch check.versionMatches {
        case true?:
            return tr("Made for \(madeFor), and the folder has that version.", "Laget for \(madeFor), og mappen har den versjonen.")
        case false?:
            let newest = check.newestTag ?? tr("another version", "en annen versjon")
            return tr("Made for \(madeFor), but the folder's newest file is \(newest). Put the \(madeFor) update in the folder, or the recipe's fixes do not apply.",
                      "Laget for \(madeFor), men mappens nyeste fil er \(newest). Legg oppdateringen \(madeFor) i mappen, ellers gjelder ikke rettelsene i oppskriften.")
        case nil:
            return tr("Made for \(madeFor). The file names do not give the version; it shows when the build starts.",
                      "Laget for \(madeFor). Filnavnene sier ikke versjonen; det ser du når bygget starter.")
        }
    }

    private func row(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Every game nxnative has a recipe for, with the version it needs.
struct RecipeListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""
    @State private var selection: Recipe.ID?

    private var shown: [Recipe] {
        let all = model.recipes.recipes
        guard !filter.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(filter) || $0.titleID.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tr("Games with a recipe in nxnative", "Spill med oppskrift i nxnative")).font(.title3.weight(.semibold))
                    Spacer()
                    Text(tr("\(model.recipes.recipes.count) games", "\(model.recipes.recipes.count) spill")).foregroundStyle(.secondary)
                }
                Text(tr("The base game and update must be the version in the list, or the recipe's fixes do not apply. Double-click a game to read its recipe.",
                        "Grunnspillet og oppdateringen må være versjonen i listen, ellers gjelder ikke rettelsene i oppskriften. Dobbeltklikk på et spill for å lese oppskriften."))
                    .font(.caption).foregroundStyle(.secondary)
                TextField(tr("Search by name or title ID", "Søk etter navn eller title ID"), text: $filter)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(16)

            Table(shown, selection: $selection) {
                TableColumn(tr("Game", "Spill"), value: \.name)
                    .width(min: 240, ideal: 340)
                TableColumn(tr("Version", "Versjon")) { Text($0.buildLabel) }
                    .width(min: 90, ideal: 130, max: 170)
                TableColumn("Title ID") { Text($0.titleID).font(.system(.body, design: .monospaced)) }
                    .width(min: 140, ideal: 150, max: 160)
                TableColumn(tr("Graphics", "Grafikk"), value: \.graphics)
                    .width(min: 60, ideal: 70, max: 90)
            }
            .contextMenu(forSelectionType: Recipe.ID.self) { ids in
                if let id = ids.first, let url = model.recipes.recipe(id)?.noteURL {
                    Button(tr("Read the recipe", "Les oppskriften")) { NSWorkspace.shared.open(url) }
                }
            } primaryAction: { ids in
                if let id = ids.first, let url = model.recipes.recipe(id)?.noteURL { NSWorkspace.shared.open(url) }
            }

            HStack {
                if model.recipes.recipes.isEmpty {
                    Text(tr("The games table was not found. Check the nxnative folder in Setup.", "Fant ikke spilltabellen. Sjekk nxnative-mappen under Oppsett.")).font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Button(tr("Close", "Lukk")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}
