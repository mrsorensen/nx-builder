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
                Link(L("Read the recipe"), destination: url).font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.12)))
    }

    private var name: String { recipe?.name ?? report.id }
    private var madeFor: String { recipe?.buildLabel ?? L("another version") }

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
        case .bad: L("No recipe for this game")
        case .warn: L("%@: wrong version for the recipe", "\(name)")
        case .ok, .info: L("Recipe: %@", "\(name)")
        }
    }

    private var detail: String {
        switch level {
        case .bad:
            return L("nxnative has no setup for this game (%@) yet. The script guesses one, and the app may not start.", "\(report.id)")
        case .warn:
            let yours = report.yourVersion ?? L("another version")
            return L("The recipe was made for %@, but you are building %@. Its fixes apply to that version only, so the game may misbehave or not start. Put the %@ update in the game folder and build again; what is already extracted is reused.", "\(madeFor)", "\(yours)", "\(madeFor)")
        case .info:
            return L("Made for %@. Every fix applies, but the folder lacks a version the recipe's shader tables were made from, so they are made from your files.", "\(madeFor)")
        case .ok:
            return L("Made for %@", "\(madeFor)")
                + (report.yourVersion.map { L(", and you are building %@. Every fix applies.", "\($0)") } ?? ".")
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
                    title: L("Recipe: ") + (recipe?.name ?? check.profileName ?? id),
                    detail: matchDetail)
            } else {
                row(icon: "exclamationmark.triangle.fill", color: .orange,
                    title: L("No recipe for %@", "\(id)"),
                    detail: L("nxnative has no setup for this game yet. The build guesses one, and the app may not start."))
            }
        } else {
            row(icon: "book.closed", color: .secondary,
                title: L("Recipe"),
                detail: L("The file names do not say which game this is. Which recipe is used, and whether the version fits, shows when the build starts."))
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
            return L("Made for %@, and the folder has that version.", "\(madeFor)")
        case false?:
            let newest = check.newestTag ?? L("another version")
            return L("Made for %@, but the folder's newest file is %@. Put the %@ update in the folder, or the recipe's fixes do not apply.", "\(madeFor)", "\(newest)", "\(madeFor)")
        case nil:
            return L("Made for %@. The file names do not give the version; it shows when the build starts.", "\(madeFor)")
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
                    Text(L("Games with a recipe in nxnative")).font(.title3.weight(.semibold))
                    Spacer()
                    Text(L("%@ games", "\(model.recipes.recipes.count)")).foregroundStyle(.secondary)
                }
                Text(L("The base game and update must be the version in the list, or the recipe's fixes do not apply. Double-click a game to read its recipe."))
                    .font(.caption).foregroundStyle(.secondary)
                TextField(L("Search by name or title ID"), text: $filter)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(16)

            Table(shown, selection: $selection) {
                TableColumn(L("Game"), value: \.name)
                    .width(min: 240, ideal: 340)
                TableColumn(L("Version")) { Text($0.buildLabel) }
                    .width(min: 90, ideal: 130, max: 170)
                TableColumn("Title ID") { Text($0.titleID).font(.system(.body, design: .monospaced)) }
                    .width(min: 140, ideal: 150, max: 160)
                TableColumn(L("Graphics"), value: \.graphics)
                    .width(min: 60, ideal: 70, max: 90)
            }
            .contextMenu(forSelectionType: Recipe.ID.self) { ids in
                if let id = ids.first, let url = model.recipes.recipe(id)?.noteURL {
                    Button(L("Read the recipe")) { NSWorkspace.shared.open(url) }
                }
            } primaryAction: { ids in
                if let id = ids.first, let url = model.recipes.recipe(id)?.noteURL { NSWorkspace.shared.open(url) }
            }

            HStack {
                if model.recipes.recipes.isEmpty {
                    Text(L("The games table was not found. Check the nxnative folder in Setup.")).font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Button(L("Close")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}
