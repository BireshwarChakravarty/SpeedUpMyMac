import SwiftUI
import BurnishCore

@main
struct BurnishApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Burnish", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Smart Scan") { Task { await model.runSmartScan() } }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings {
            SettingsView().environment(model).frame(width: 520)
        }
    }
}
