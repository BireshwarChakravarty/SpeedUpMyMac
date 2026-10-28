import SwiftUI
import RootCore

/// "Always dark" in Settings: the aurora was designed for a night sky.
let alwaysDarkKey = "alwaysDark"

@main
struct RootApp: App {
    @State private var model = AppModel()
    @AppStorage(alwaysDarkKey) private var alwaysDark = true

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

        MenuBarExtra {
            MenuBarView().environment(model).preferredColorScheme(alwaysDark ? .dark : nil)
        } label: {
            Image(systemName: "number")
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings {
            SettingsView().environment(model).frame(width: 540)
        }
    }
}
