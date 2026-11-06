import SwiftUI
import SpruceCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SoundFX.enabledKey) private var soundOn = true

    var body: some View {
        @Bindable var model = model
        let module = model.selection ?? .smartScan
        ZStack {
            ModuleBackdrop(module: module)
            HStack(spacing: 0) {
                Sidebar()
                    .frame(width: 236)
                    .padding(8)
                VStack(spacing: 0) {
                    TopBar(module: module, soundOn: $soundOn)
                    ZStack {
                        detail(for: module)
                            .id(module)
                            .transition(.moduleSwap)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeOut(duration: 0.2), value: module)
                }
                .environment(\.pageModule, module)
            }
            VStack(spacing: 10) {
                Spacer()
                if let offer = model.sentinelOffer {
                    SentinelBanner(app: offer.app, leftovers: offer.leftovers).transition(.toast)
                }
                if let busy = model.busy, model.scanProgress == nil || module != .smartScan {
                    BusyOverlay(message: busy, progress: model.scanProgress).transition(.toast)
                }
                if let status = model.status {
                    StatusBanner(text: status, isError: model.statusIsError).transition(.toast)
                }
            }
            .padding(.bottom, 20)
            .padding(.leading, 252)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.busy)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.status)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.sentinelOffer?.app.path)

            if let celebration = model.celebration {
                CelebrationOverlay(celebration: celebration) {
                    withAnimation(.easeOut(duration: 0.3)) { model.celebration = nil }
                }
                .id(celebration.id)
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .background(WindowConfigurator())
        .buttonStyle(.quiet)
        .toggleStyle(.check)
        .sheet(item: $model.receipt) { receipt in ReceiptSheet(receipt: receipt) }
        .alert("Use Touch ID instead of your password?", isPresented: $model.showTouchIDOffer) {
            Button("Use Touch ID") { model.setTouchIDForAdmin(true) }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("When Spruce needs admin rights, it will ask for your fingerprint. So will sudo in Terminal. Setting this up needs your password one last time. You can change it in Settings.")
        }
        .onChange(of: model.receipt?.id) { _, id in if id != nil { SoundFX.shared.play(.whoosh) } }
        .onChange(of: model.sentinelOffer?.app.path) { _, path in if path != nil { SoundFX.shared.play(.success, haptic: .generic) } }
        .onAppear { AppDelegate.openMainWindow = { [openWindow] in openWindow(id: "main") } }
        .task { if let folder = AppModel.tourFolder { await model.runTour(folder) } }
    }

    @ViewBuilder
    private func detail(for module: Module) -> some View {
        switch module {
        case .smartScan: SmartScanView()
        case .cleanup: CleanupView()
        case .devPurge: DevPurgeView()
        case .uninstaller: UninstallerView()
        case .spaceLens: SpaceLensView()
        case .processes: ProcessesView()
        case .maintenance: MaintenanceView()
        case .startup: StartupView()
        case .tweaks: TweaksView()
        case .health: HealthView()
        case .fleet: FleetView()
        case .history: HistoryView()
        }
    }
}

/// The toolbar row: the page title on the left, sound and Admin on the right. Drags the window.
struct TopBar: View {
    var module: Module
    @Binding var soundOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(module.title)
                .font(.system(size: 15, weight: .semibold))
                .id(module)
                .transition(.opacity)
            Text(module.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .id("sub-\(module.rawValue)")
                .transition(.opacity)
            Spacer()
            Button {
                soundOn.toggle()
                if soundOn { SoundFX.shared.play(.toggleOn) }
            } label: {
                Image(systemName: soundOn ? "speaker.wave.2" : "speaker.slash")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 16)
            }
            .controlSize(.regular)
            .help(soundOn ? "Sound effects on" : "Sound effects off")
            .accessibilityLabel(soundOn ? "Mute sound effects" : "Turn on sound effects")
            SudoSwitch()
        }
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .frame(height: 52)
    }
}

/// Lets the window background drag the window, now that the title bar is hidden.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            AppDelegate.register(window)
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            if AppModel.tourFolder != nil, let screen = window.screen ?? NSScreen.main {
                window.setFrame(screen.visibleFrame, display: true)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Offer shown when an app is dragged to the Trash.
struct SentinelBanner: View {
    @Environment(AppModel.self) private var model
    var app: InstalledApp
    var leftovers: [Leftover]

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(app.name) left \(leftovers.count) file\(leftovers.count == 1 ? "" : "s") behind").font(.system(size: 13, weight: .semibold))
                Text(Format.bytes(leftovers.reduce(0) { $0 + $1.bytes })).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Not Now") { model.sentinelOffer = nil }
            Button("Review & Remove") {
                model.sentinelOffer = nil
                model.confirmOrphans(leftovers)
            }
            .buttonStyle(.brand)
        }
        .padding(12)
        .frame(maxWidth: 620)
        .glassCard(cornerRadius: 18)
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }
}

/// The receipt: nothing is removed without this.
struct ReceiptSheet: View {
    @Environment(\.dismiss) private var dismiss
    var receipt: Receipt
    @State private var showScript = false

    private var isUninstall: Bool { receipt.confirmTitle == "Remove Completely" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(receipt.title).font(.system(size: 20, weight: .semibold))
                    Text("\(receipt.lines.count) item\(receipt.lines.count == 1 ? "" : "s")").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                BigBytes(bytes: receipt.total, size: 30, duration: 0.8)
            }
            if let note = receipt.note {
                InfoNote(text: note, symbol: isUninstall ? "exclamationmark.triangle" : "info.circle")
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(receipt.lines.enumerated()), id: \.element.id) { index, line in
                        if index > 0 { RowDivider(inset: 16) }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.title).font(.system(size: 13)).lineLimit(1)
                                if line.path.hasPrefix("/") { PathText(path: line.path) }
                            }
                            Spacer()
                            Text(destination(line))
                                .font(.system(size: 12))
                                .foregroundStyle(line.destination.contains("admin") ? Theme.sudo : Color.secondary)
                            Text(line.bytes > 0 ? Format.bytes(line.bytes) : "")
                                .font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .trailing)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 9)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 120, maxHeight: 340)
            .fixedSize(horizontal: false, vertical: receipt.lines.count < 8)
            .surface()
            if let script = receipt.script {
                DisclosureGroup(isExpanded: $showScript) {
                    ScrollView {
                        Text(script.text).font(Theme.mono).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 130)
                    .padding(10)
                    .surface(cornerRadius: 8)
                } label: {
                    Label("Runs as administrator: \(script.lines.count) command\(script.lines.count == 1 ? "" : "s")", systemImage: "lock.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.sudo)
                }
            }
            HStack {
                Text("Every removal is logged in History.").font(.system(size: 12)).foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(receipt.confirmTitle) {
                    let action = receipt.perform
                    dismiss()
                    Task { await action() }
                }
                .buttonStyle(isUninstall ? PrimaryButtonStyle.danger : PrimaryButtonStyle.brand)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(Theme.base)
        .buttonStyle(.quiet)
    }

    private func destination(_ line: ReceiptLine) -> String {
        switch line.destination {
        case "Move to Trash": return "Trash"
        case "Delete": return "Delete"
        case "Delete as admin": return "Delete · admin"
        case "Clear as admin": return "Clear · admin"
        default: return line.destination
        }
    }
}
