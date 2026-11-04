import AppKit
import SwiftUI

/// The welcome window: what the Mac still needs, and one button that installs it.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showLog = false

    var body: some View {
        let onboarding = model.onboarding
        let status = onboarding.status
        let ready = status?.toolsReady == true

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ready ? L("NX Builder is ready") : L("Welcome to NX Builder"))
                        .font(.title2.weight(.semibold))
                    Text(ready
                         ? (status?.keys == true ? L("Everything is installed. Choose a game and build it.") : L("Everything is installed. Choose your prod.keys, then a game."))
                         : L("NX Builder installs the free tools nxnative needs, and nxnative itself. Your Mac's password is asked once. Xcode comes from the App Store; NX Builder sets it up when it is there."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(OnboardingStep.allCases) { step in
                        stepRow(step, onboarding)
                        if step != OnboardingStep.allCases.last { Divider().padding(.leading, 56) }
                    }
                }
                .padding(.vertical, 6)
            }

            VStack(alignment: .leading, spacing: 10) {
                if onboarding.waitingForXcode {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "bag").font(.title3).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Install Xcode in the App Store (Get, then Install). It is large and takes a while; NX Builder carries on by itself when it is done."))
                                .fixedSize(horizontal: false, vertical: true)
                            Button(L("Open the App Store")) { NSWorkspace.shared.open(Onboarding.xcodeAppStore) }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
                }
                if let fraction = onboarding.downloadFraction {
                    ProgressView(value: fraction)
                }
                if let failure = onboarding.failure {
                    Label(failure, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !onboarding.log.isEmpty {
                    DisclosureGroup(L("Details"), isExpanded: $showLog) {
                        LogView(lines: onboarding.log, height: 110...200)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

            Divider()

            HStack {
                if !onboarding.isRunning {
                    Button(ready ? L("Close") : L("Later")) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                if onboarding.isDetecting && status == nil { ProgressView().controlSize(.small) }
                primaryButton(onboarding, ready: ready)
            }
            .padding(16)
        }
        .frame(width: 660, height: 680)
        .task { await onboarding.refresh(settings: model.settings) }
    }

    @ViewBuilder private func stepRow(_ step: OnboardingStep, _ onboarding: Onboarding) -> some View {
        let state = onboarding.state(of: step)
        HStack(alignment: .top, spacing: 14) {
            Group {
                switch state {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .needed: Image(systemName: "circle").foregroundStyle(.secondary)
                case .running: ProgressView().controlSize(.small)
                case .waiting: Image(systemName: "hourglass").foregroundStyle(.blue)
                case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .font(.title3)
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(.headline)
                Text(step.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if step == .keys && state != .done && !onboarding.isRunning {
                Button(L("Choose…")) { chooseKeys() }.controlSize(.small)
            } else if state == .done {
                Text(L("Installed")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    @ViewBuilder private func primaryButton(_ onboarding: Onboarding, ready: Bool) -> some View {
        if onboarding.isRunning {
            Button(L("Stop")) { onboarding.cancel() }
        } else if ready && onboarding.status?.keys == true {
            Button(L("Start building")) { dismiss() }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        } else if ready {
            Button(L("Choose prod.keys …")) { chooseKeys() }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        } else {
            Button(onboarding.failure == nil ? L("Install") : L("Try again")) {
                Task {
                    await onboarding.install(settings: model.settings)
                    await model.recipes.reload(repo: model.settings.repoPath)
                    await model.checker.run(settings: model.settings)
                    await model.updates.check(repo: model.settings.repoPath)
                }
            }
            .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            .disabled(onboarding.status == nil || model.runner.isBusy || model.tasks.isRunning)
        }
    }

    private func chooseKeys() {
        if let path = FilePicker.file(message: L("Choose the prod.keys dumped from your own Switch."), startingAt: model.settings.keysPath) {
            model.settings.keysPath = path
            Task {
                await model.onboarding.refresh(settings: model.settings)
                await model.checker.run(settings: model.settings)
            }
        }
    }
}
