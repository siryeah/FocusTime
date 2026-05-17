import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingTimerPresentation: ObservableObject {
    @Published var isHovered = false
    @Published var isDesktopTimerVisible = true
    @Published var isSettingsPanelOpen = false
}

@MainActor
final class FloatingTimerWindowController: NSObject {
    let presentation = FloatingTimerPresentation()

    private let timerController: TimerController
    private let panel: FocusTimerPanel
    private var cancellables = Set<AnyCancellable>()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var hoverPollingTimer: Timer?
    private var settingsPanelCanDismissOnResign = false

    init(timerController: TimerController) {
        self.timerController = timerController

        let savedFrameString = UserDefaults.standard.string(forKey: AppSettings.desktopWindowFrame)
            ?? UserDefaults.standard.string(forKey: AppSettings.windowFrame)
        let savedFrame = savedFrameString.map(NSRectFromString)
        let initialFrame = FloatingTimerWindowController.initialFrame(savedFrame: savedFrame)

        panel = FocusTimerPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init()

        configurePanel()
        installContentView()
        panel.delegate = self
        installObservers()
        installMouseMonitors()
        installHoverPolling()
    }

    func showPanel() {
        guard timerController.displayMode != .menuBarOnly else { return }
        presentation.isDesktopTimerVisible = true
        if !presentation.isSettingsPanelOpen {
            setWindowChromeVisible(false)
        }
        ensureFrameIsVisible()
        panel.setIsVisible(true)
        panel.orderFrontRegardless()
        updateWindowInteractivity()
    }

    func hidePanel() {
        presentation.isSettingsPanelOpen = false
        presentation.isDesktopTimerVisible = false
        panel.orderOut(nil)
    }

    func showSettingsPanel() {
        persistDesktopFrame()
        presentation.isHovered = true
        presentation.isSettingsPanelOpen = true
        settingsPanelCanDismissOnResign = false
        setWindowChromeVisible(true)
        ensureFrameIsVisible()
        panel.setIsVisible(true)
        NSApp.activate(ignoringOtherApps: true)
        resizeForExpandedPanel()
        panel.makeKeyAndOrderFront(nil)
        updateWindowInteractivity()
    }

    func toggleExpanded() {
        if timerController.isCompleted {
            timerController.acknowledgeCompletion()
            return
        }
        if presentation.isSettingsPanelOpen {
            closeSettingsPanel()
        } else {
            showSettingsPanel()
        }
    }

    func closeSettingsPanel() {
        persistSettingsFrame()
        presentation.isSettingsPanelOpen = false
        settingsPanelCanDismissOnResign = false
        setWindowChromeVisible(false)
        if timerController.displayMode == .menuBarOnly {
            presentation.isDesktopTimerVisible = false
            panel.orderOut(nil)
            updateWindowInteractivity()
            return
        }
        presentation.isDesktopTimerVisible = true
        restoreCollapsedPanelFrame()
        updateWindowInteractivity()
    }

    func revealForLaunch(expanded: Bool = false) {
        guard timerController.displayMode != .menuBarOnly else { return }
        presentation.isHovered = true
        showPanel()
        if expanded {
            presentation.isSettingsPanelOpen = true
            setWindowChromeVisible(true)
            NSApp.activate(ignoringOtherApps: true)
            resizeForExpandedPanel()
            panel.makeKeyAndOrderFront(nil)
            updateWindowInteractivity()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            guard !self.presentation.isSettingsPanelOpen else { return }
            self.presentation.isHovered = self.panel.frame.contains(NSEvent.mouseLocation)
            self.updateWindowInteractivity()
        }
    }

    func applyDisplayMode(_ displayMode: DisplayMode) {
        switch displayMode {
        case .menuBarOnly:
            presentation.isDesktopTimerVisible = false
            if !presentation.isSettingsPanelOpen {
                panel.orderOut(nil)
            }
        case .desktopOnly, .both:
            presentation.isDesktopTimerVisible = true
            showPanel()
        }
    }

    func persistFrame() {
        if presentation.isSettingsPanelOpen {
            persistSettingsFrame()
        } else {
            persistDesktopFrame()
        }
    }

    private func configurePanel() {
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = false
        panel.minSize = NSSize(width: 220, height: 96)
        panel.maxSize = NSSize(width: 640, height: 780)
        panel.level = windowLevel(isPinned: timerController.isPinned)
        panel.ignoresMouseEvents = !timerController.isPinned
        panel.isReleasedWhenClosed = false
        setWindowChromeVisible(false)
        clearWindowBacking()
    }

    private func installContentView() {
        let rootView = FloatingTimerRootView(
            timer: timerController,
            presentation: presentation,
            onTogglePanel: { [weak self] in self?.toggleExpanded() },
            onClosePanel: { [weak self] in self?.closeSettingsPanel() },
            onPrimaryControl: { [weak self] in self?.performPrimaryControlFromSettings() },
            onDoubleClickTimer: { [weak self] in self?.timerController.startOrPause() },
            onReset: { [weak self] in self?.timerController.reset() }
        )

        let hostingView = TransparentHostingView(rootView: rootView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        clearWindowBacking()
    }

    private func installObservers() {
        timerController.$displayMode
            .removeDuplicates()
            .sink { [weak self] displayMode in
                self?.applyDisplayMode(displayMode)
            }
            .store(in: &cancellables)

        timerController.$isPinned
            .removeDuplicates()
            .sink { [weak self] isPinned in
                guard let self else { return }
                self.panel.level = self.windowLevel(isPinned: isPinned)
                if isPinned {
                    self.panel.collectionBehavior.insert(.fullScreenAuxiliary)
                }
                self.updateWindowInteractivity()
            }
            .store(in: &cancellables)

        presentation.$isHovered
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateWindowInteractivity()
            }
            .store(in: &cancellables)

        presentation.$isSettingsPanelOpen
            .removeDuplicates()
            .sink { [weak self] isOpen in
                guard let self else { return }
                self.panel.hasShadow = isOpen
            }
            .store(in: &cancellables)
    }

    private func installMouseMonitors() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            self?.updateHoverState()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] _ in
            self?.updateHoverState()
        }
    }

    private func installHoverPolling() {
        hoverPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateHoverState()
            }
        }
        RunLoop.main.add(hoverPollingTimer!, forMode: .common)
    }

    private func updateHoverState() {
        guard timerController.displayMode != .menuBarOnly else { return }
        let mouseLocation = NSEvent.mouseLocation
        let inside = panel.frame.insetBy(dx: -3, dy: -3).contains(mouseLocation)
        if presentation.isHovered != inside {
            presentation.isHovered = inside
            panel.hasShadow = presentation.isSettingsPanelOpen
        }
        updateWindowInteractivity()
    }

    private func updateWindowInteractivity() {
        let acceptsMouse = timerController.isPinned || presentation.isHovered || presentation.isSettingsPanelOpen
        panel.ignoresMouseEvents = !acceptsMouse
    }

    private func resizeForExpandedPanel() {
        var frame = panel.frame
        let oldCenter = NSPoint(x: frame.midX, y: frame.midY)
        if let savedFrame = savedFrame(forKey: AppSettings.settingsWindowFrame) {
            frame = savedFrame
        } else {
            frame.size = NSSize(width: max(frame.width, 520), height: max(frame.height, 610))
            frame.origin = NSPoint(x: oldCenter.x - frame.width / 2, y: oldCenter.y - frame.height / 2)
        }
        frame = clampedToVisibleArea(frame)
        panel.setFrame(frame, display: true, animate: true)
    }

    private func resizeForCollapsedPanel() {
        var frame = panel.frame
        let oldCenter = NSPoint(x: frame.midX, y: frame.midY)
        frame.size = NSSize(width: 320, height: presentation.isHovered ? 150 : 134)
        frame.origin = NSPoint(x: oldCenter.x - frame.width / 2, y: oldCenter.y - frame.height / 2)
        frame = clampedToVisibleArea(frame)
        panel.setFrame(frame, display: true, animate: true)
    }

    private func restoreCollapsedPanelFrame() {
        guard let savedFrame = savedFrame(forKey: AppSettings.desktopWindowFrame) else {
            resizeForCollapsedPanel()
            return
        }
        panel.setFrame(clampedToVisibleArea(savedFrame), display: true, animate: true)
    }

    private func setStandardWindowButtonsVisible(_ visible: Bool) {
        panel.standardWindowButton(.closeButton)?.isHidden = !visible
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = !visible
        panel.standardWindowButton(.zoomButton)?.isHidden = !visible
    }

    private func setWindowChromeVisible(_ visible: Bool) {
        if visible {
            panel.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            panel.backgroundColor = .clear
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.titlebarSeparatorStyle = .none
            panel.hasShadow = true
        } else {
            panel.styleMask = [.borderless, .resizable]
            panel.backgroundColor = .clear
            panel.hasShadow = false
        }
        panel.isMovableByWindowBackground = !visible
        panel.isOpaque = false
        setStandardWindowButtonsVisible(visible)
        clearWindowBacking()
    }

    private func clearWindowBacking() {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.isOpaque = false
        panel.contentView?.superview?.wantsLayer = true
        panel.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.superview?.layer?.isOpaque = false
    }

    private func persistDesktopFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: AppSettings.desktopWindowFrame)
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: AppSettings.windowFrame)
    }

    private func persistSettingsFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: AppSettings.settingsWindowFrame)
    }

    private func savedFrame(forKey key: String) -> NSRect? {
        guard let frameString = UserDefaults.standard.string(forKey: key) else { return nil }
        let frame = NSRectFromString(frameString)
        guard !frame.isEmpty else { return nil }
        guard NSScreen.screens.contains(where: { allowedFrame(for: $0).intersects(frame) }) else { return nil }
        return frame
    }

    private func performPrimaryControlFromSettings() {
        let wasRunning = timerController.isRunning
        timerController.startOrPause()
        if !wasRunning, timerController.isRunning {
            closeSettingsPanel()
        }
    }

    private func ensureFrameIsVisible() {
        let visibleFrames = NSScreen.screens.map { allowedFrame(for: $0) }
        guard !visibleFrames.contains(where: { $0.intersects(panel.frame) }) else { return }
        panel.setFrame(Self.initialFrame(savedFrame: nil), display: true)
    }

    private static func initialFrame(savedFrame: NSRect?) -> NSRect {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        if let savedFrame, !savedFrame.isEmpty, visibleFrames.contains(where: { $0.intersects(savedFrame) }) {
            return savedFrame
        }

        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 340, height: 132)
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY + visibleFrame.height * 0.08,
            width: size.width,
            height: size.height
        )
    }

    private func clampedToVisibleArea(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first(where: { allowedFrame(for: $0).intersects(frame) }) ?? NSScreen.main
        guard let screen else { return frame }
        let allowedBounds = allowedFrame(for: screen)

        var clampedFrame = frame
        let margin: CGFloat = timerController.isPinned ? 0 : 24
        if clampedFrame.maxX > allowedBounds.maxX - margin {
            clampedFrame.origin.x = allowedBounds.maxX - margin - clampedFrame.width
        }
        if clampedFrame.minX < allowedBounds.minX + margin {
            clampedFrame.origin.x = allowedBounds.minX + margin
        }
        if clampedFrame.maxY > allowedBounds.maxY - margin {
            clampedFrame.origin.y = allowedBounds.maxY - margin - clampedFrame.height
        }
        if clampedFrame.minY < allowedBounds.minY + margin {
            clampedFrame.origin.y = allowedBounds.minY + margin
        }
        return clampedFrame
    }

    private func allowedFrame(for screen: NSScreen) -> NSRect {
        timerController.isPinned ? screen.frame : screen.visibleFrame
    }

    private func windowLevel(isPinned: Bool) -> NSWindow.Level {
        isPinned ? .screenSaver : .normal
    }
}

final class FocusTimerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}

extension FloatingTimerWindowController: NSWindowDelegate {
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor in
            self.closeSettingsPanel()
        }
        return false
    }

    nonisolated func windowDidBecomeKey(_ notification: Notification) {
        Task { @MainActor in
            self.settingsPanelCanDismissOnResign = true
        }
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            guard self.settingsPanelCanDismissOnResign else { return }
            guard self.presentation.isSettingsPanelOpen else { return }
            self.closeSettingsPanel()
        }
    }

    nonisolated func windowDidResize(_ notification: Notification) {
        Task { @MainActor in
            self.persistFrame()
        }
    }

    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            self.persistFrame()
        }
    }
}
