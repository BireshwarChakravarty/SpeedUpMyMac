import SwiftUI
import BurnishCore

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(Module.groups.indices, id: \.self) { index in
                    if let title = Module.groups[index].0 {
                        Section(title) { rows(Module.groups[index].1) }
                    } else {
                        rows(Module.groups[index].1)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { MachineFooter().padding(12) }
        } detail: {
            ZStack(alignment: .bottom) {
                detail(for: model.selection ?? .smartScan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 8) {
                    if let offer = model.sentinelOffer { SentinelBanner(app: offer.app, leftovers: offer.leftovers) }
                    if let busy = model.busy { BusyOverlay(message: busy) }
                    if let status = model.status { StatusBanner(text: status, isError: model.statusIsError) }
                }
                .padding(18)
                .animation(.spring(duration: 0.3), value: model.busy)
                .animation(.spring(duration: 0.3), value: model.status)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { SudoToggle() }
        }
        .sheet(item: $model.receipt) { receipt in ReceiptSheet(receipt: receipt) }
    }

    @ViewBuilder
    private func rows(_ modules: [Module]) -> some View {
        ForEach(modules) { module in
            Label(module.title, systemImage: module.symbol).tag(module)
        }
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

/// The Sudo capsule in the toolbar. Disabled, with an explanation, on standard accounts.
struct SudoToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Toggle(isOn: model.sudoBinding) {
            Label("Sudo", systemImage: model.sudo ? "lock.open.fill" : "lock.shield")
        }
        .toggleStyle(.button)
        .tint(Theme.sudo)
        .disabled(!model.machine.isAdmin)
        .help(model.machine.isAdmin
              ? "Sudo mode: include system-level items. You'll authorize once per batch, and see the exact script first."
              : "\(model.machine.userName) is a standard account on this Mac, so Burnish cleans everything you own but can't touch system folders.")
    }
}

struct MachineFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "laptopcomputer").foregroundStyle(Theme.polish)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.machine.name).font(.caption.weight(.semibold)).lineLimit(1)
                Text("\(model.machine.chip) · \(model.machine.isAdmin ? "Admin" : "Standard")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .glassCard(cornerRadius: 12)
    }
}

/// Offer shown when an app is dragged to the Trash.
struct SentinelBanner: View {
    @Environment(AppModel.self) private var model
    var app: InstalledApp
    var leftovers: [Leftover]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.circle.fill").font(.title2).foregroundStyle(Theme.polish)
            VStack(alignment: .leading) {
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
            .buttonStyle(.polish)
        }
        .padding(14)
        .frame(maxWidth: 640)
        .glassCard(cornerRadius: 16)
    }
}

/// The receipt: nothing is removed without this.
struct ReceiptSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var receipt: Receipt
    @State private var showScript = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text(receipt.title).font(.title2.weight(.bold))
                    Text("\(receipt.lines.count) item(s) · \(Format.bytes(receipt.total))").foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.bytes(receipt.total)).font(Theme.heroSmall).foregroundStyle(Theme.polish)
            }
            if let note = receipt.note {
                Label(note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            }
            List(receipt.lines) { line in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.title).lineLimit(1)
                        if line.path.hasPrefix("/") { PathText(path: line.path) }
                    }
                    Spacer()
                    Text(line.destination).font(.caption)
                        .foregroundStyle(line.destination.contains("admin") ? Theme.sudo : .secondary)
                    SizeText(bytes: line.bytes).frame(width: 80, alignment: .trailing)
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 220)
            if let script = receipt.script {
                DisclosureGroup(isExpanded: $showScript) {
                    ScrollView {
                        Text(script.text).font(Theme.mono).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                    .padding(8)
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                } label: {
                    Label("Script that will run as administrator (\(script.lines.count) line\(script.lines.count == 1 ? "" : "s"))",
                          systemImage: "lock.shield").foregroundStyle(Theme.sudo)
                }
            }
            HStack {
                Text("Removals are logged in History.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(receipt.confirmTitle) {
                    let action = receipt.perform
                    dismiss()
                    Task { await action() }
                }
                .buttonStyle(.polish)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 640, height: 560)
    }
}
