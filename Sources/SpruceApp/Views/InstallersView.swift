import SwiftUI
import SpruceCore

/// Old .dmg, .pkg, .xip and .iso files: what each one is, whether its app is already installed,
/// and how long it's been sitting there. Everything goes to the Trash.
struct InstallersView: View {
    @Environment(AppModel.self) private var model
    @State private var chosen = Set<String>()

    private var files: [InstallerFile] { model.installerFiles }
    private var chosenFiles: [InstallerFile] { files.filter { chosen.contains($0.path) } }

    var body: some View {
        ModuleScroll {
            if !model.installersScanned {
                start
            } else {
                HeroHeader(title: "Installers", value: Format.bytes(chosenFiles.reduce(0) { $0 + $1.bytes }),
                           caption: files.isEmpty ? "Nothing left behind" : "\(chosenFiles.count) of \(files.count) selected",
                           symbol: Module.installers.symbol) {
                    Button("Scan Again") { Task { await model.scanInstallers() } }.disabled(model.busy != nil)
                    Button("Move to Trash") { model.confirmInstallers(chosenFiles) }
                        .buttonStyle(.brand)
                        .disabled(chosenFiles.isEmpty || model.busy != nil)
                }
                if files.isEmpty {
                    EmptyState(symbol: "shippingbox", title: "No installers left behind",
                               message: "Downloads, Desktop, Documents, Mail downloads and the Shared folder have no .dmg, .pkg, .xip or .iso files.")
                        .card()
                } else {
                    InfoNote(text: "Pre-selected: installers for apps you already have, and anything older than a week. ISO images and mounted disk images are never pre-selected.")
                    list
                }
            }
        }
        .onChange(of: model.installerFiles) { _, found in
            chosen = Set(found.filter { $0.suggested() }.map(\.path))
        }
    }

    private var start: some View {
        VStack(spacing: 4) {
            ToolHero(module: .installers, title: "Installers",
                     subtitle: "Disk images and packages you've already used.") {
                Button("Scan") { Task { await model.scanInstallers() } }
                    .buttonStyle(.brand)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy != nil)
            }
            Text("Looks in Downloads, Desktop, Documents, Mail downloads and /Users/Shared. macOS may ask once for access to those folders.")
                .font(Theme.mono(11)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
        }
    }

    private var list: some View {
        let allPaths = Set(files.filter { !$0.mounted }.map(\.path))
        let allChosen = !allPaths.isEmpty && allPaths.isSubset(of: chosen)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Toggle(isOn: Binding(get: { allChosen }, set: { on in
                    withAnimation(Theme.snappy) { chosen = on ? allPaths : [] }
                })) {
                    Text(allChosen ? "Deselect All" : "Select All").fontWeight(.medium)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                Spacer()
                Text("\(files.count) found · \(Format.bytes(files.reduce(0) { $0 + $1.bytes }))")
                    .font(Theme.mono(11)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            RowDivider(inset: 0)
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                if index > 0 { RowDivider(inset: 38) }
                row(file).reveal(index: index)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .surface()
    }

    private func row(_ file: InstallerFile) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { chosen.contains(file.path) },
                                     set: { on in if on { chosen.insert(file.path) } else { chosen.remove(file.path) } }))
                .labelsHidden()
                .disabled(file.mounted)
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(file.name).font(Theme.sans(13, .medium)).lineLimit(1).truncationMode(.middle)
                    if let app = file.installedApp { Chip(text: "\(app) installed", color: Theme.safe, symbol: "checkmark") }
                    if file.mounted { Chip(text: "Mounted · eject it first", color: Theme.review, symbol: "eject") }
                }
                Text("\(location(file.path)) · \(age(file)) · \(file.kind.rawValue)")
                    .font(Theme.mono(11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            IconButton(symbol: "magnifyingglass", help: "Show in Finder") { model.reveal(file.path) }
            SizeText(bytes: file.bytes).frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .rowHover()
    }

    private func location(_ path: String) -> String {
        Paths.abbreviate((path as NSString).deletingLastPathComponent)
    }

    private func age(_ file: InstallerFile) -> String {
        guard let modified = file.modified else { return "date unknown" }
        return Format.relative(modified)
    }
}
