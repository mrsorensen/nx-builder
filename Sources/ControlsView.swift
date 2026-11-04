import SwiftUI

/// The keys and controllers a game app built by nxnative takes on the Mac. The key map is the host's
/// (dm/host/front_mac.m, `key_bit` and `on_key`): physical key positions, so it is the same on a
/// Norwegian keyboard. nxnative has no setting to change it.
struct KeyBinding: Identifiable {
    let keys: [String]
    let button: String
    let note: String
    var id: String { button }
}

enum KeyMap {
    static let moving: [KeyBinding] = [
        .init(keys: ["W", "A", "S", "D"], button: tr("Left stick", "Venstre stikke"), note: tr("Walk and run", "Gå og løp")),
        .init(keys: ["⇧", "← ↑ → ↓"], button: tr("Right stick", "Høyre stikke"), note: tr("Camera: hold Shift and press an arrow key", "Kamera: hold Shift og trykk en piltast")),
        .init(keys: ["← ↑ → ↓"], button: "D-pad", note: tr("The arrow keys alone", "Piltastene alene")),
        .init(keys: ["F"], button: tr("Press the left stick", "Trykk venstre stikke"), note: ""),
        .init(keys: ["G"], button: tr("Press the right stick", "Trykk høyre stikke"), note: ""),
    ]
    static let buttons: [KeyBinding] = [
        .init(keys: ["J"], button: "A", note: ""),
        .init(keys: ["K"], button: "B", note: ""),
        .init(keys: ["U"], button: "X", note: ""),
        .init(keys: ["I"], button: "Y", note: ""),
        .init(keys: ["Q"], button: "L", note: ""),
        .init(keys: ["E"], button: "R", note: ""),
        .init(keys: ["Z"], button: "ZL", note: ""),
        .init(keys: ["C"], button: "ZR", note: ""),
        .init(keys: ["⏎"], button: "+", note: "Return"),
        .init(keys: ["⇥"], button: "−", note: "Tab"),
        .init(keys: [tr("Space", "Mellomrom")], button: tr("Shake the controller", "Rist kontrolleren"), note: tr("While you hold it", "Mens du holder den inne")),
    ]
    static let window: [KeyBinding] = [
        .init(keys: [tr("Mouse", "Mus")], button: tr("Touch screen", "Berøringsskjerm"), note: tr("Left mouse button", "Venstre museknapp")),
        .init(keys: ["⌃", "⌘", "F"], button: tr("Full screen on/off", "Fullskjerm av/på"), note: ""),
        .init(keys: ["⌘", "Q"], button: tr("Quit the game", "Avslutt spillet"), note: tr("What the game has not saved is lost", "Det spillet ikke har lagret, går tapt")),
    ]
}

struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, label.count > 2 ? 8 : 0)
            .frame(minWidth: 28, minHeight: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.tertiary))
            .shadow(color: .black.opacity(0.15), radius: 0, y: 1)
    }
}

struct ControlsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tr("The keyboard works without any setup while the game window is active (click it first). The keys go by their place on the keyboard and cannot be changed in nxnative.",
                    "Tastaturet virker uten oppsett når spillvinduet er aktivt (klikk i det først). Tastene følger plassen på tastaturet og kan ikke endres i nxnative."))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    group(tr("Moving and camera", "Bevegelse og kamera"), KeyMap.moving)
                    group(tr("Window", "Vindu"), KeyMap.window)
                }
                group(tr("Buttons", "Knapper"), KeyMap.buttons)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Controllers", "Kontroller")).font(.headline)
                Text(tr("Xbox, PlayStation, Switch Pro and 8BitDo controllers work as soon as they are connected to the Mac (Bluetooth or cable), also while the game runs. The buttons go by position: right is A, bottom B, top X and left Y. On a Nintendo controller they follow the labels. The first controller is player 1 together with the keyboard; more controllers become more players. Hold the Home button for 2 seconds and press A to quit.",
                        "Xbox-, PlayStation-, Switch Pro- og 8BitDo-kontrollere virker med en gang de er koblet til Macen (Bluetooth eller kabel), også mens spillet kjører. Knappene følger plassering: høyre er A, nederst B, øverst X og venstre Y. På en Nintendo-kontroller følger de det som står på knappene. Den første kontrolleren er spiller 1 sammen med tastaturet; flere kontrollere blir flere spillere. Hold Home-knappen i 2 sekunder og trykk A for å avslutte."))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func group(_ title: String, _ rows: [KeyBinding]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(rows) { row in
                    GridRow {
                        HStack(spacing: 4) {
                            ForEach(Array(row.keys.enumerated()), id: \.offset) { index, key in
                                if index > 0 && row.keys.count > 1 && (row.keys[0] == "⇧" || row.keys[0] == "⌃" || row.keys[0] == "⌘") {
                                    Text("+").font(.caption).foregroundStyle(.tertiary)
                                }
                                KeyCap(label: key)
                            }
                        }
                        .gridColumnAlignment(.trailing)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.button)
                            if !row.note.isEmpty {
                                Text(row.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// The controls as a sheet.
struct ControlsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("Keyboard and controllers", "Tastatur og kontroller")).font(.title2.weight(.semibold))
                .padding([.top, .horizontal], 20)
            ScrollView {
                ControlsContent().padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button(tr("Close", "Lukk")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 720, height: 640)
    }
}
