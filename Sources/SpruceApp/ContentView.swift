import SwiftUI
import SpruceCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SoundFX.enabledKey) private var soundOn = true

    var body: some View {
        @Bindable var model = model
        let module = model.selection ?? .smartScan
        ZStack {
            ModuleBackdrop(module: module)
            HStack(spacing: 0) {
                Sidebar()
                    .padding(.leading, 10).padding(.vertical, 10)
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
            .padding(.leading, 92)
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
        .foregroundStyle(Theme.text)
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
        .onAppear {
            AppDelegate.openMainWindow = { [openWindow] in openWindow(id: "main") }
            AppDelegate.openSettingsWindow = { [openSettings] in openSettings() }
        }
        .task { if let folder = AppModel.tourFolder { await model.runTour(folder) } }
    }

    @ViewBuilder
    private func detail(for module: Module) -> some View {
        switch module {
        case .smartScan: SmartScanView()
        case .status: StatusView()
        case .cleanup: CleanupView()
        case .devPurge: DevPurgeView()
        case .installers: InstallersView()
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

/// The toolbar row: the group's pages as pill tabs on the left, sound and Admin on the right.
/// Drags the window.
struct TopBar: View {
    var module: Module
    @Binding var soundOn: Bool
    @Environment(AppModel.self) private var model
    @Namespace private var namespace

    var body: some View {
        let group = RailGroup.of(module)
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 2) {
                ForEach(group.modules) { page in
                    let selected = page == module
                    Button {
                        guard !selected else { return }
                        SoundFX.shared.play(.select)
                        withAnimation(Theme.spring) { model.selection = page }
                    } label: {
                        HStack(spacing: 6) {
                            Text(page.title.lowercased())
                            if let badge = badge(for: page) {
                                Text(badge).foregroundStyle(selected ? Theme.onInverse.opacity(0.6) : Theme.text.opacity(0.45))
                                    .contentTransition(.numericText())
                            }
                        }
                        .font(Theme.mono(13, selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Theme.onInverse : Theme.text.opacity(0.72))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background {
                            if selected {
                                Capsule().fill(Theme.inverse).matchedGeometryEffect(id: "tab", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Theme.chipFill))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .animation(Theme.spring, value: module)
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
        .padding(.leading, 22)
        .padding(.trailing, 20)
        .frame(height: 60)
    }

    /// Live counts beside a tab's name.
    private func badge(for page: Module) -> String? {
        switch page {
        case .cleanup:
            guard let scan = model.scan else { return nil }
            let bytes = scan.bytes(maxRisk: .safe)
            return bytes > 0 ? Format.bytes(bytes) : nil
        case .devPurge:
            let bytes = model.artifacts.filter { !$0.recentlyActive }.reduce(0) { $0 + $1.bytes }
            return bytes > 0 ? Format.bytes(bytes) : nil
        case .maintenance:
            let n = model.smart?.recommendedTasks.count ?? 0
            return n > 0 ? "\(n)" : nil
        case .startup:
            let n = model.smart?.suspiciousStartupItems.count ?? 0
            return n > 0 ? "\(n)" : nil
        case .fleet:
            return model.fleet.count > 1 ? "\(model.fleet.count)" : nil
        default:
            return nil
        }
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
            Image(nsImage: FileIcon.image(app.path)).resizable().frame(width: 36, height: 36)
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
                if receipt.total > 0 { BigBytes(bytes: receipt.total, size: 30, duration: 0.8) }
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
                        Text(script.text).font(Theme.code).textSelection(.enabled)
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
                Text("Everything Spruce does is logged in Activity.").font(.system(size: 12)).foregroundStyle(.tertiary)
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
