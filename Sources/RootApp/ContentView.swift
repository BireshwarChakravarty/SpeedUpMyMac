import SwiftUI
import RootCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SoundFX.enabledKey) private var soundOn = true

    var body: some View {
        @Bindable var model = model
        let module = model.selection ?? .smartScan
        ZStack {
            AuroraBackground(module: module)
            HStack(spacing: 0) {
                Sidebar()
                    .frame(width: 236)
                    .padding(.leading, 10).padding(.vertical, 10)
                VStack(spacing: 0) {
                    TopBar(module: module, soundOn: $soundOn)
                    ZStack {
                        detail(for: module)
                            .id(module)
                            .transition(.moduleSwap)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(Theme.spring, value: module)
                }
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
            .padding(.bottom, 22)
            .padding(.leading, 246)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: model.busy)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: model.status)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: model.sentinelOffer?.app.path)

            if let celebration = model.celebration {
                CelebrationOverlay(celebration: celebration) {
                    withAnimation(.easeOut(duration: 0.35)) { model.celebration = nil }
                }
                .id(celebration.id)
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .background(WindowConfigurator())
        .buttonStyle(.glass)
        .toggleStyle(.check)
        .sheet(item: $model.receipt) { receipt in ReceiptSheet(receipt: receipt) }
        .onChange(of: model.receipt?.id) { _, id in if id != nil { SoundFX.shared.play(.whoosh) } }
        .task { if let folder = AppModel.tourFolder { await model.runTour(folder) } }
        .onChange(of: model.sentinelOffer?.app.path) { _, path in if path != nil { SoundFX.shared.play(.success, haptic: .generic) } }
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

/// Module title on the left; Sudo and sound on the right. Doubles as the window's drag handle.
struct TopBar: View {
    var module: Module
    @Binding var soundOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(module.title)
                    .font(Theme.title)
                    .contentTransition(.opacity)
                Text(module.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            .id(module)
            .transition(.opacity.combined(with: .offset(x: -8)))
            .animation(Theme.spring, value: module)
            Spacer()
            Button {
                soundOn.toggle()
                if soundOn { SoundFX.shared.play(.toggleOn) }
            } label: {
                Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 16)
            }
            .help(soundOn ? "Sound effects on" : "Sound effects off")
            SudoSwitch()
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

/// Lets the whole window background drag the window, now that the title bar is hidden.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            if AppModel.tourFolder != nil {
                window.setContentSize(NSSize(width: 1440, height: 900))
                window.center()
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
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 40, height: 40)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "trash.circle.fill").font(.system(size: 18)).foregroundStyle(.white, Theme.danger)
                        .offset(x: 4, y: 4)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("You trashed \(app.name)").font(.headline)
                Text("It left \(leftovers.count) file(s) behind · \(Format.bytes(leftovers.reduce(0) { $0 + $1.bytes }))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Not now") { model.sentinelOffer = nil }
            Button("Review & remove") {
                model.sentinelOffer = nil
                model.confirmOrphans(leftovers)
            }
            .buttonStyle(.brand)
        }
        .padding(14)
        .frame(maxWidth: 660)
        .glassCard(cornerRadius: 20)
    }
}

/// The receipt: nothing is removed without this.
struct ReceiptSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var receipt: Receipt
    @State private var showScript = false

    private var isUninstall: Bool { receipt.confirmTitle == "Remove Completely" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECEIPT").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
                    Text(receipt.title).font(Theme.title)
                    Text("\(receipt.lines.count) item(s)").foregroundStyle(.secondary)
                }
                Spacer()
                CountingBytes(bytes: receipt.total, duration: 0.9)
                    .font(Theme.heroSmall)
                    .foregroundStyle(Theme.brand)
            }
            if let note = receipt.note {
                InfoNote(text: note, symbol: isUninstall ? "exclamationmark.shield" : "info.circle")
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(receipt.lines.enumerated()), id: \.element.id) { index, line in
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: line))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(line.destination.contains("admin") ? Theme.sudo : Theme.leaf)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.title).lineLimit(1)
                                if line.path.hasPrefix("/") { PathText(path: line.path) }
                            }
                            Spacer()
                            Chip(text: line.destination, color: line.destination.contains("admin") ? Theme.sudo
                                 : line.destination == "Delete" ? Theme.risky : .secondary, symbol: nil)
                            if line.bytes > 0 { SizeText(bytes: line.bytes).frame(width: 80, alignment: .trailing) }
                            else { Spacer().frame(width: 80) }
                        }
                        .padding(.vertical, 5)
                        .rowHover()
                        .reveal(index: index, step: 0.02)
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(minHeight: 220)
            .glassCard(cornerRadius: 16)
            if let script = receipt.script {
                DisclosureGroup(isExpanded: $showScript) {
                    ScrollView {
                        Text(script.text).font(Theme.mono).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                    .padding(10)
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                } label: {
                    Label("Script that will run as administrator (\(script.lines.count) line\(script.lines.count == 1 ? "" : "s"))",
                          systemImage: "lock.shield").foregroundStyle(Theme.sudo)
                }
            }
            HStack {
                Label("Removals are logged in History.", systemImage: "clock.arrow.circlepath").font(.caption).foregroundStyle(.secondary)
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
        .frame(width: 680, height: 600)
        .background(AuroraBackground(module: model.selection ?? .smartScan, intensity: 0.6))
        .buttonStyle(.glass)
    }

    private func icon(for line: ReceiptLine) -> String {
        if line.path.hasPrefix("trace:") { return "wand.and.stars" }
        if line.title.hasSuffix(".app") { return "app.dashed" }
        return line.destination.contains("Trash") ? "trash" : "flame"
    }
}
