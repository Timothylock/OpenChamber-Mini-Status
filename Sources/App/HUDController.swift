import AppKit
import Combine
import SwiftUI

/// Owns the floating panel: placement, drag, hover fade and opening a chat.
final class HUDController: NSObject {
    private let store: SessionStore
    private let preferences: Preferences
    private let defaults: UserDefaults
    private let onSettings: () -> Void
    private let logger = Log.window

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var fittedHeight: CGFloat = 0
    private var resizeTimer: Timer?
    private var preferenceCancellable: AnyCancellable?

    private static let originKey = "windowOrigin"

    init(
        store: SessionStore,
        preferences: Preferences,
        defaults: UserDefaults = .standard,
        onSettings: @escaping () -> Void
    ) {
        self.store = store
        self.preferences = preferences
        self.defaults = defaults
        self.onSettings = onSettings
        super.init()
    }

    func start() {
        store.start()
        buildPanel()
        restorePosition()
        resizeToFit()
        panel?.orderFrontRegardless()

        let timer = Timer(timeInterval: Config.refreshInterval, repeats: true) { [weak self] _ in
            self?.resizeToFit()
        }
        RunLoop.main.add(timer, forMode: .common)
        resizeTimer = timer

        preferenceCancellable = preferences.$fadeOnHover
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard !enabled else { return }
                self?.setHovering(false)
            }
    }

    func stop() {
        store.stop()
        resizeTimer?.invalidate()
        resizeTimer = nil
    }

    // MARK: panel

    private func buildPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Config.windowWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.alphaValue = Config.restAlpha

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = Config.cornerRadius
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        panel.contentView = blur

        let root = HUDView(store: store, onSelect: { [weak self] session in
            self?.open(session)
        })
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: Config.cornerRadius, style: .continuous))
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { [weak self] _ in
                    self?.dragToPointer()
                }
                .onEnded { [weak self] _ in
                    self?.endDrag()
                }
        )
        .onHover { [weak self] inside in
            self?.setHovering(inside)
        }
        .contextMenu {
            Button("Settings…") { self.onSettings() }
            Divider()
            Button("Reset position") { self.resetPosition() }
            Button("Refresh") { self.store.refresh() }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }

        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        blur.addSubview(hosting)

        self.panel = panel
        self.hostingView = hosting
    }

    private func setHovering(_ inside: Bool) {
        guard let panel else { return }
        let fades = preferences.fadeOnHover
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = inside && fades ? Config.hoverAlpha : Config.restAlpha
        }
    }

    // MARK: placement

    /// The gesture's translation is measured inside the window, which moves with the drag,
    /// so it reads about half the pointer travel. Tracking the pointer on screen avoids that.
    private func dragToPointer() {
        guard let panel else { return }
        let pointer = NSEvent.mouseLocation
        if dragStartMouse == nil {
            dragStartMouse = pointer
            dragStartOrigin = panel.frame.origin
        }
        guard let startMouse = dragStartMouse, let startOrigin = dragStartOrigin else { return }
        panel.setFrameOrigin(NSPoint(
            x: startOrigin.x + (pointer.x - startMouse.x),
            y: startOrigin.y + (pointer.y - startMouse.y)
        ))
        panel.invalidateShadow()
    }

    private func endDrag() {
        guard let panel else { return }
        defaults.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
        dragStartMouse = nil
        dragStartOrigin = nil
    }

    private func restorePosition() {
        guard let panel else { return }
        if let stored = defaults.string(forKey: Self.originKey) {
            let saved = NSPointFromString(stored)
            if let screen = NSScreen.screens.first(where: { $0.visibleFrame.insetBy(dx: -40, dy: -40).contains(saved) }) {
                panel.setFrameOrigin(clamp(saved, to: screen, height: panel.frame.height))
                return
            }
        }
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - panel.frame.width - Config.edgeInset,
            y: visible.minY + Config.edgeInset
        )
        panel.setFrameOrigin(origin)
    }

    func resetPosition() {
        defaults.removeObject(forKey: Self.originKey)
        dragStartMouse = nil
        dragStartOrigin = nil
        restorePosition()
        resizeToFit(force: true)
    }

    private func clamp(_ origin: NSPoint, to screen: NSScreen, height: CGFloat) -> NSPoint {
        let visible = screen.visibleFrame
        return NSPoint(
            x: min(max(origin.x, visible.minX + 4), visible.maxX - Config.windowWidth - 4),
            y: min(max(origin.y, visible.minY + 4), visible.maxY - height - 4)
        )
    }

    /// Keeps the window glued to whichever vertical edge it sits nearer, so rows growing
    /// never push it off the screen.
    private func resizeToFit(force: Bool = false) {
        guard let panel, let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        guard fitting.height > 1 else { return }
        guard force || abs(fitting.height - fittedHeight) > 0.5 else { return }
        fittedHeight = fitting.height

        var frame = panel.frame
        let bottom = frame.minY
        let top = frame.maxY
        frame.size = NSSize(width: Config.windowWidth, height: fitting.height)

        let screen = panel.screen ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            let nearerBottom = (frame.midY - visible.minY) < (visible.maxY - frame.midY)
            frame.origin.y = nearerBottom ? bottom : top - fitting.height
            frame.origin = clamp(frame.origin, to: screen, height: fitting.height)
        }

        panel.setFrame(frame, display: true)
        hostingView.frame = NSRect(x: 0, y: 0, width: Config.windowWidth, height: fitting.height)
        defaults.set(NSStringFromPoint(frame.origin), forKey: Self.originKey)
    }

    // MARK: selection

    private func open(_ session: ChatSession) {
        store.acknowledge(session.id)
        guard let url = Config.chatURL(sessionID: session.id) else { return }

        if !NSWorkspace.shared.open(url) {
            logger.info("deep link refused, launching OpenChamber instead")
            let application = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: Config.openChamberBundleIdentifier
            )
            if let application {
                NSWorkspace.shared.openApplication(
                    at: application,
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }
        }
        NSRunningApplication
            .runningApplications(withBundleIdentifier: Config.openChamberBundleIdentifier)
            .first?
            .activate(options: [])
    }
}
