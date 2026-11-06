import SwiftUI
import RootCore

/// "Always dark" in Settings: the aurora was designed for a night sky.
let alwaysDarkKey = "alwaysDark"

@main
struct RootApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @AppStorage(alwaysDarkKey) private var alwaysDark = true

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        WindowGroup("Root", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 940, minHeight: 620)
                .preferredColorScheme(alwaysDark ? .dark : nil)
                .tint(Theme.leaf)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Smart Scan") {
                    model.selection = .smartScan
                    Task { await model.runSmartScan() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            CommandMenu("Go") {
                ForEach(Array(Module.allCases.enumerated()), id: \.element) { index, module in
                    Button(module.title) {
                        SoundFX.shared.play(.select)
                        withAnimation(Theme.spring) { model.selection = module }
                    }
                    .keyboardShortcut(index < 9 ? KeyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command) : nil)
                }
            }
        }

        SwiftUI.Settings {
            SettingsView().environment(model).frame(width: 540)
        }
    }
}

/// Clicking Root in the Dock brings its window back, whatever else is on screen. (SwiftUI's own
/// handling counted the menu bar panel as a visible window, so the Dock icon did nothing.) Opening
/// Root again from Finder or Launchpad sends the same "reopen" event.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The main windows SwiftUI has made, registered by `WindowConfigurator` (weak references).
    private static let windows = NSHashTable<NSWindow>.weakObjects()
    /// SwiftUI's `openWindow(id: "main")`, handed over by the first view that has it.
    static var openMainWindow: (() -> Void)?

    /// The app's one model, shared with the menu bar panel (which lives outside SwiftUI's scenes).
    static var model: AppModel?

    static func register(_ window: NSWindow) { windows.add(window) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let model = AppDelegate.model { StatusItemController.install(model: model) }
    }

    static var mainWindows: [NSWindow] { windows.allObjects }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let folder = AppModel.tourFolder {
            FileManager.default.createFile(atPath: (folder as NSString).appendingPathComponent("reopen-event"), contents: nil)
        }
        AppDelegate.showMainWindow()
        return false
    }

    /// Brings back the main window: un-minimizes or raises it, or opens a new one if it was closed.
    static func showMainWindow() {
        if let window = mainWindows.first(where: \.isVisible) ?? mainWindows.first(where: \.isMiniaturized) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        NSApp.activate()
    }
}
