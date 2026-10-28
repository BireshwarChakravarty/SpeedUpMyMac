import SwiftUI
import BurnishCore

/// "Always dark" in Settings: the aurora was designed for a night sky.
let alwaysDarkKey = "alwaysDark"

@main
struct BurnishApp: App {
    @State private var model = AppModel()
    @AppStorage(alwaysDarkKey) private var alwaysDark = true

    var body: some Scene {
        WindowGroup("Burnish", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1060, minHeight: 700)
                .preferredColorScheme(alwaysDark ? .dark : nil)
                .tint(Theme.azure)
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

        MenuBarExtra {
            MenuBarView().environment(model).preferredColorScheme(alwaysDark ? .dark : nil)
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings {
            SettingsView().environment(model).frame(width: 540)
        }
    }
}
