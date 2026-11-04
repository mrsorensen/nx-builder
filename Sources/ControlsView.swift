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
        .init(keys: ["W", "A", "S", "D"], button: L("Left stick"), note: L("Walk and run")),
        .init(keys: ["⇧", "← ↑ → ↓"], button: L("Right stick"), note: L("Camera: hold Shift and press an arrow key")),
        .init(keys: ["← ↑ → ↓"], button: "D-pad", note: L("The arrow keys alone")),
        .init(keys: ["F"], button: L("Press the left stick"), note: ""),
        .init(keys: ["G"], button: L("Press the right stick"), note: ""),
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
        .init(keys: [L("Space")], button: L("Shake the controller"), note: L("While you hold it")),
    ]
    static let window: [KeyBinding] = [
        .init(keys: [L("Mouse")], button: L("Touch screen"), note: L("Left mouse button")),
        .init(keys: ["⌃", "⌘", "F"], button: L("Full screen on/off"), note: ""),
        .init(keys: ["⌘", "Q"], button: L("Quit the game"), note: L("What the game has not saved is lost")),
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
            Text(L("The keyboard works without any setup while the game window is active (click it first). The keys go by their place on the keyboard and cannot be changed in nxnative."))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    group(L("Moving and camera"), KeyMap.moving)
                    group(L("Window"), KeyMap.window)
                }
                group(L("Buttons"), KeyMap.buttons)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Controllers")).font(.headline)
                Text(L("Xbox, PlayStation, Switch Pro and 8BitDo controllers work as soon as they are connected to the Mac (Bluetooth or cable), also while the game runs. The buttons go by position: right is A, bottom B, top X and left Y. On a Nintendo controller they follow the labels. The first controller is player 1 together with the keyboard; more controllers become more players. Hold the Home button for 2 seconds and press A to quit."))
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
            Text(L("Keyboard and controllers")).font(.title2.weight(.semibold))
                .padding([.top, .horizontal], 20)
            ScrollView {
                ControlsContent().padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button(L("Close")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 720, height: 640)
    }
}
