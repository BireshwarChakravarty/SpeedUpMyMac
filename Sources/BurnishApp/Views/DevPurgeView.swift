import SwiftUI
import BurnishCore

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
                    Button("Purge") { model.confirmPurge() }.buttonStyle(.polish).disabled(selectedBytes == 0 || model.busy != nil)
                }
            }
            Label("Projects touched in the last \(model.settings.purgeMinAgeDays) days are listed but not selected. Git-tracked folders are never touched. Toolchain caches (Homebrew, npm, Xcode…) live in Cleanup → Developer.",
                  systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            if model.artifacts.isEmpty {
                EmptyState(symbol: "shippingbox", title: "No build artifacts found",
                           message: "Add the folders where you keep code in Settings → Dev Purge roots.").card()
            } else {
                VStack(spacing: 2) {
                    ForEach(model.artifacts) { artifact in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { model.selectedArtifacts.contains(artifact.path) },
                                                     set: { on in
                                                         if on { model.selectedArtifacts.insert(artifact.path) } else { model.selectedArtifacts.remove(artifact.path) }
                                                     })).labelsHidden()
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text((artifact.project as NSString).lastPathComponent).fontWeight(.medium)
                                    Text(artifact.kind).font(.caption).foregroundStyle(.secondary)
                                    if artifact.recentlyActive { RiskBadge(risk: .review) }
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
                    }
                }
                .card()
            }
        }
        .navigationTitle("Dev Purge")
        .task { if model.artifacts.isEmpty { await model.runPurgeScan() } }
    }
}
