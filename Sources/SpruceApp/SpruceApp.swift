import SwiftUI
import SpruceCore

/// "Always dark" in Settings: Spruce is designed dark-first, and every page also works in light mode.
let alwaysDarkKey = "alwaysDark"
/// "Hide from the Dock when the window is closed": Spruce then lives in the menu bar only, and
/// comes back to the Dock whenever its window is open. On by default.
let menuBarOnlyKey = "menuBarOnlyWhenClosed"

@main
struct SpruceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @AppStorage(alwaysDarkKey) private var alwaysDark = true

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        WindowGroup("Spruce", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 940, minHeight: 620)
                .preferredColorScheme(alwaysDark ? .dark : nil)
                .tint(Theme.spruce)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands {
            // About shows "Version 2.1.1" only: an empty build version drops the "(…)" after it.
            CommandGroup(replacing: .appInfo) {
                Button("About Spruce") { AppDelegate.showAbout() }
            }
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
            // Same theme as the main window: dark when "Always use the dark theme" is on, warm ground, Spruce accents.
            SettingsView().environment(model).frame(width: 540)
                .scrollContentBackground(.hidden)
                .background(Theme.base)
                .preferredColorScheme(alwaysDark ? .dark : nil)
                .tint(Theme.spruce)
        }
    }
}

/// Clicking Spruce in the Dock (or Open Spruce in the menu bar panel) brings its window back, whatever else is on screen. (SwiftUI's own
/// handling counted the menu bar panel as a visible window, so the Dock icon did nothing.) Opening
/// Spruce again from Finder or Launchpad sends the same "reopen" event.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The main windows SwiftUI has made, registered by `WindowConfigurator` (weak references).
    private static let windows = NSHashTable<NSWindow>.weakObjects()
    /// SwiftUI's `openWindow(id: "main")`, handed over by the first view that has it.
    static var openMainWindow: (() -> Void)?
    /// SwiftUI's `openSettings()`, handed over the same way (the CI tour opens Settings with it).
    static var openSettingsWindow: (() -> Void)?

    /// The app's one model, shared with the menu bar panel (which lives outside SwiftUI's scenes).
    static var model: AppModel?

    static func register(_ window: NSWindow) {
        windows.add(window)
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [menuBarOnlyKey: true])
        if let model = AppDelegate.model { StatusItemController.install(model: model) }
        MetricsMonitor.shared.start()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let closing = note.object as? NSWindow
            MainActor.assumeIsolated { AppDelegate.updateDockIcon(closing: closing) }
        }
    }

    /// Windows that count as "Spruce is open": the main window and Settings. The menu bar panel,
    /// popovers and the status item's own window don't.
    private static func isAppWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled) && (window.isVisible || window.isMiniaturized)
    }

    /// Shows Spruce in the Dock while one of its windows is open. When the last one closes and
    /// "Hide from the Dock when the window is closed" is on, it steps back to the menu bar only.
    static func updateDockIcon(closing: NSWindow? = nil) {
        let open = NSApp.windows.contains { $0 !== closing && isAppWindow($0) }
        let menuBarOnly = UserDefaults.standard.bool(forKey: menuBarOnlyKey)
        let policy: NSApplication.ActivationPolicy = (open || !menuBarOnly) ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    static var mainWindows: [NSWindow] { windows.allObjects }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let folder = AppModel.tourFolder {
            FileManager.default.createFile(atPath: (folder as NSString).appendingPathComponent("reopen-event"), contents: nil)
        }
        AppDelegate.showMainWindow()
        return false
    }

    static func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.version: ""])
        NSApp.activate()
    }

    /// Brings back the main window: un-minimizes or raises it, or opens a new one if it was closed.
    static func showMainWindow() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        if let window = mainWindows.first(where: \.isVisible) ?? mainWindows.first(where: \.isMiniaturized) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        NSApp.activate()
    }
}
