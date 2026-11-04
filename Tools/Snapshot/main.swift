// Draws NX Builder's pages into PNG files without showing anything on screen: the views are hosted in a
// window that is never ordered in, and AppKit draws them into a bitmap. For checking the real screens
// headlessly and for README screenshots. Run by snapshot.sh.
import AppKit
import SwiftUI

/// The welcome window without its .task, which would detect this Mac's real state.
struct OnboardingPreview: View {
    var body: some View { OnboardingView() }
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)   // no Dock icon, never active

@MainActor func snapshot<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool) async {
    let host = NSHostingView(rootView: view.environment(AppModel.shared).frame(width: size.width, height: size.height))
    host.frame = CGRect(origin: .zero, size: size)
    host.wantsLayer = true
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = host.appearance
    window.backgroundColor = NSColor(white: dark ? 0.12 : 0.93, alpha: 1)   // fixed: a dynamic colour resolves to the Mac's own appearance here
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    try? await Task.sleep(for: .seconds(2))   // suspends, so the views' .task and refreshes run on the main actor
    host.layoutSubtreeIfNeeded()
    host.display()
    let scale: CGFloat = 2
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { print("FAIL \(name)"); return }
    ctx.scaleBy(x: scale, y: scale)
    (window.backgroundColor ?? .black).setFill()
    ctx.setFillColor((window.backgroundColor ?? .black).cgColor)
    ctx.fill(CGRect(origin: .zero, size: size))
    // The layer tree has what SwiftUI draws itself; AppKit-drawn controls are in it too once displayed.
    if let layer = host.layer {
        ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
        layer.render(in: ctx)
    }
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + "/\(name).png"))
    print("wrote \(name).png")
}

let model = AppModel.shared
if let game = ProcessInfo.processInfo.environment["NXB_GAME"] { model.settings.gamePath = game }
await model.recipes.reload(repo: model.settings.repoPath)
await model.checker.run(settings: model.settings)
await model.library.refresh(known: [])
await model.updates.check(repo: model.settings.repoPath)
let dark = ProcessInfo.processInfo.environment["NXB_LIGHT"] == nil
await snapshot("setup", NavigationStack { SetupView() }, size: CGSize(width: 860, height: 1000), dark: dark)
await snapshot("build", NavigationStack { BuildView(showSetup: {}) }, size: CGSize(width: 860, height: 900), dark: dark)
await snapshot("library", NavigationStack { LibraryView(showBuild: {}) }, size: CGSize(width: 860, height: 520), dark: dark)
await snapshot("recipes", RecipeListView(), size: CGSize(width: 760, height: 560), dark: dark)
// The welcome window on a Mac that has nothing yet, waiting for Xcode from the App Store.
var fresh = OnboardingStatus()
fresh.missingFormulas = ["zstd", "glslang", "uv"]
model.onboarding.preview(fresh, active: .xcode, waitingForXcode: true)
await snapshot("onboarding", OnboardingPreview(), size: CGSize(width: 660, height: 680), dark: dark)
