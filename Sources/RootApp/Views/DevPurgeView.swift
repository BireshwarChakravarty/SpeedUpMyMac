import SwiftUI
import RootCore

struct DevPurgeView: View {
    @Environment(AppModel.self) private var model

    private var selectedBytes: Int64 {
        model.artifacts.filter { model.selectedArtifacts.contains($0.path) }.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        ModuleScroll {
            HeroHeader(title: "Dev Purge", value: Format.bytes(selectedBytes),
                       caption: "node_modules, target, .build, Pods, venvs and friends in \(model.settings.purgeRoots.count) project roots",
                       symbol: "hammer") {
                HStack {
                    Button("Scan") { Task { await model.runPurgeScan() } }.disabled(model.busy != nil)
                    Button("Purge") { model.confirmPurge() }.buttonStyle(.tinted(.devPurge)).disabled(selectedBytes == 0 || model.busy != nil)
                }
            }
            let waiting = ProjectPurge.rootsNeedingAccess(model.settings.purgeRoots).filter { Paths.lexists(Paths.expand($0)) }
            if !waiting.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised").foregroundStyle(Theme.review)
                    Text("Skipped \(waiting.map(Paths.abbreviate).joined(separator: ", ")) so macOS doesn't stop to ask. Give Root Full Disk Access to include it.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings") { model.openFullDiskAccessSettings() }.controlSize(.small)
                }
                .padding(12)
                .surface()
            }
            InfoNote(text: "Projects touched in the last \(model.settings.purgeMinAgeDays) days are listed but not selected. Git-tracked folders are never touched. Toolchain caches (Homebrew, npm, Xcode…) live in Cleanup → Developer.")
            if model.artifacts.isEmpty {
                EmptyState(symbol: "shippingbox", title: "No build artifacts found",
                           message: "Add the folders where you keep code in Settings → Dev Purge roots.").card()
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(model.artifacts.enumerated()), id: \.element.id) { index, artifact in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { model.selectedArtifacts.contains(artifact.path) },
                                                     set: { on in
                                                         if on { model.selectedArtifacts.insert(artifact.path) } else { model.selectedArtifacts.remove(artifact.path) }
                                                     })).labelsHidden()
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text((artifact.project as NSString).lastPathComponent).fontWeight(.medium)
                                    Text(artifact.kind).font(.caption).foregroundStyle(.secondary)
                                    if artifact.recentlyActive { Chip(text: "active", color: Theme.review, symbol: "bolt.fill") }
                                }
                                PathText(path: artifact.path)
                            }
                            Spacer()
                            if let last = artifact.lastActivity {
                                Text(Format.relative(last)).font(.caption).foregroundStyle(.secondary)
                            }
                            SizeText(bytes: artifact.bytes).frame(width: 80, alignment: .trailing)
                        }
                        .padding(.vertical, 5)
                        .rowHover()
                        .reveal(index: index)
                    }
                }
                .card()
            }
        }
        .navigationTitle("Dev Purge")
        .task { if model.artifacts.isEmpty { await model.runPurgeScan() } }
    }
}
