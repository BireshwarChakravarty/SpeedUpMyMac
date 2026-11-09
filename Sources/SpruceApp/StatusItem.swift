import AppKit
import SwiftUI
import SpruceCore

/// Spruce's menu bar item. A click opens a floating panel that stays open while you work in other
/// apps, so you can drag an app into it from Finder. SwiftUI's MenuBarExtra closes the moment
/// Finder is clicked, which made that impossible. You can also drop an app straight on the icon.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate, NSDraggingDestination {
    static private(set) var shared: StatusItemController?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private var panel: SprucePanel?
    /// The point under the menu bar icon the panel hangs from, so it grows downwards.
    private var anchorTop: CGFloat = 0

    static func install(model: AppModel) {
        shared = StatusItemController(model: model)
    }

    private init(model: AppModel) {
        self.model = model
        super.init()
        guard let button = item.button else { return }
        button.image = StatusItemController.menuBarImage()
        button.target = self
        button.action = #selector(toggle)
        // The status item's own window forwards drag events to its delegate.
        button.window?.registerForDraggedTypes([.fileURL])
        button.window?.delegate = self
    }

    var isShown: Bool { panel?.isVisible ?? false }

    @objc func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let host = panel.contentView?.subviews.first { panel.setContentSize(host.fittingSize) }
        if let button = item.button, let window = button.window {
            let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
            anchorTop = icon.minY - 6
            let size = panel.frame.size
            var x = icon.midX - size.width / 2
            if let screen = window.screen?.visibleFrame { x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8) }
            panel.setFrameOrigin(NSPoint(x: x, y: anchorTop - size.height))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        item.button?.highlight(true)
        Task { if model.health == nil { await model.refreshHealth() } }
    }

    func hide() {
        panel?.orderOut(nil)
        item.button?.highlight(false)
    }

    private func makePanel() -> SprucePanel {
        let panel = SprucePanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let dark = UserDefaults.standard.object(forKey: alwaysDarkKey) as? Bool ?? true
        if dark { panel.appearance = NSAppearance(named: .darkAqua) }

        // Real glass: the desktop and windows behind blur through, with rounded corners.
        let glass = NSVisualEffectView()
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.maskImage = StatusItemController.roundedMask(radius: 22)

        let root = MenuBarView(close: { [weak self] in self?.hide() })
            .environment(model)
            .preferredColorScheme(dark ? .dark : nil)
            .tint(Theme.spruce)
            .fixedSize()
            .onGeometryChange(for: CGSize.self, of: \.size) { [weak self] size in self?.fit(size) }
        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            host.topAnchor.constraint(equalTo: glass.topAnchor),
            host.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        panel.contentView = glass
        panel.setContentSize(host.fittingSize)
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.hide() }
        return panel
    }

    /// A stretchable rounded-rectangle mask for the glass.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// The menu bar icon: the app icon's four stacked bars as a template image, so macOS tints it.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { rect in
            NSColor.black.setFill()
            for (index, width) in [CGFloat(5.5), 9.5, 13.5, 17.5].enumerated() {
                let bar = NSRect(x: rect.midX - width / 2, y: 0.8 + CGFloat(index) * 4.1, width: width, height: 2.8)
                NSBezierPath(roundedRect: bar, xRadius: 1.4, yRadius: 1.4).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Spruce"
        return image
    }

    /// Sizes the panel to its content, hanging from the menu bar as the content grows or shrinks.
    private func fit(_ size: CGSize) {
        guard let panel, size.width > 0, size.height > 0 else { return }
        var frame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin.x = panel.frame.minX
        frame.origin.y = (anchorTop > 0 ? anchorTop : panel.frame.maxY) - frame.height
        panel.setFrame(frame, display: true, animate: false)
        panel.invalidateShadow()
    }

    /// For the CI tour's log.
    var panelDescription: String {
        guard let panel else { return "no panel" }
        return "visible=\(panel.isVisible) frame=\(NSStringFromRect(panel.frame)) screen=\(NSStringFromRect(panel.screen?.frame ?? .zero))"
    }

    // MARK: Dropping an app on the menu bar icon

    private func droppedApp(_ sender: NSDraggingInfo) -> URL? {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first { $0.pathExtension == "app" }
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard droppedApp(sender) != nil else { return [] }
        item.button?.highlight(true)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        if !isShown { item.button?.highlight(false) }
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedApp(sender) else { return false }
        show()
        Task { await model.quickScan(url.path) }
        return true
    }
}

/// A floating panel that closes on Esc and can take keyboard focus without activating Spruce.
final class SprucePanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
