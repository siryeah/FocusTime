import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let timerController: TimerController
    private let floatingTimerWindowController: FloatingTimerWindowController
    private let statusItem: NSStatusItem
    private var aboutWindow: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var pendingStatusUpdate: DispatchWorkItem?

    init(
        timerController: TimerController,
        floatingTimerWindowController: FloatingTimerWindowController
    ) {
        self.timerController = timerController
        self.floatingTimerWindowController = floatingTimerWindowController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        installObservers()
        let menu = NSMenu()
        menu.delegate = self
        populateMenu(menu)
        statusItem.menu = menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.configureStatusButton()
        }
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        statusItem.isVisible = true
        button.imagePosition = .imageLeft
        button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        button.attributedTitle = statusAttributedTitle
        button.image = menuBarLogoImage()
        button.toolTip = "专注时刻"
        statusItem.length = statusItemLength
    }

    private func installObservers() {
        timerController.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleStatusButtonUpdate()
            }
            .store(in: &cancellables)
    }

    private func scheduleStatusButtonUpdate() {
        pendingStatusUpdate?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateStatusButton()
        }
        pendingStatusUpdate = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func updateStatusButton() {
        statusItem.isVisible = true
        statusItem.length = statusItemLength
        statusItem.button?.attributedTitle = statusAttributedTitle
        statusItem.button?.image = menuBarLogoImage()
    }

    private var statusTitle: String {
        timerController.displayMode == .desktopOnly ? "" : timerController.formattedTime
    }

    private var statusAttributedTitle: NSAttributedString {
        NSAttributedString(
            string: statusTitle,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white
            ]
        )
    }

    private var statusItemLength: CGFloat {
        timerController.displayMode == .desktopOnly ? NSStatusItem.squareLength : 82
    }

    private var elapsedProgress: CGFloat {
        if timerController.isCompleted { return 1 }
        if timerController.state == .idle { return 0 }
        return min(max(1 - timerController.progress, 0), 1)
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let stateTitle: String
        switch timerController.state {
        case .idle:
            stateTitle = "准备专注 · \(timerController.formattedTime)"
        case .running:
            stateTitle = "专注中 · \(timerController.formattedTime)"
        case .paused:
            stateTitle = "已暂停 · \(timerController.formattedTime)"
        case .completed:
            stateTitle = "已完成 · 00:00"
        }
        let status = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        addPresetItem(minutes: 25, to: menu)
        addPresetItem(minutes: 30, to: menu)
        addPresetItem(minutes: 45, to: menu)
        menu.addItem(menuItem("自定义...", action: #selector(showPanel)))
        menu.addItem(.separator())

        let panelTitle = floatingTimerWindowController.presentation.isSettingsPanelOpen ? "隐藏设置面板" : "显示设置面板"
        menu.addItem(menuItem(panelTitle, action: #selector(showPanel)))
        menu.addItem(menuItem(timerController.isRunning ? "暂停专注" : "继续专注", action: #selector(startOrPause)))
        menu.addItem(menuItem("重置时间", action: #selector(resetTimer)))
        menu.addItem(.separator())

        let loginItem = menuItem("开机自启动", action: #selector(toggleLaunchAtLogin))
        loginItem.state = timerController.launchAtLogin ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(menuItem("关于专注时刻", action: #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出专注时刻", action: #selector(quitApp)))
    }

    private func addPresetItem(minutes: Int, to menu: NSMenu) {
        let item = menuItem("\(minutes) 分钟", action: #selector(selectPreset(_:)))
        item.tag = minutes
        item.state = timerController.durationMinutes == minutes ? .on : .off
        menu.addItem(item)
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        populateMenu(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populateMenu(menu)
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        timerController.setDuration(minutes: sender.tag)
    }

    @objc private func showPanel() {
        if floatingTimerWindowController.presentation.isSettingsPanelOpen {
            floatingTimerWindowController.closeSettingsPanel()
        } else {
            floatingTimerWindowController.showSettingsPanel()
        }
    }

    @objc private func startOrPause() {
        timerController.startOrPause()
    }

    @objc private func resetTimer() {
        timerController.reset()
    }

    @objc private func toggleLaunchAtLogin() {
        timerController.launchAtLogin.toggle()
    }

    @objc private func showAbout() {
        if let aboutWindow {
            NSApp.activate(ignoringOtherApps: true)
            aboutWindow.center()
            aboutWindow.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "关于专注时刻"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: AboutPanelView())
        panel.center()
        aboutWindow = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func ringImage(fillProgress: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 2.5, y: 2.5, width: 13, height: 13)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2
        let lineWidth: CGFloat = 2.3
        let baseAlpha: CGFloat = timerController.isCompleted && !timerController.completionPulse ? 0.18 : 0.50

        NSColor.white.withAlphaComponent(baseAlpha).setStroke()
        let basePath = NSBezierPath()
        basePath.lineWidth = lineWidth
        basePath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        basePath.stroke()

        guard fillProgress > 0.001 else {
            image.isTemplate = false
            return image
        }

        let startAngle: CGFloat = 90
        let endAngle = startAngle - fillProgress * 360
        NSColor.white.setStroke()
        let progressPath = NSBezierPath()
        progressPath.lineWidth = lineWidth
        progressPath.lineCapStyle = .round
        progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        progressPath.stroke()

        image.isTemplate = false
        return image
    }

    private func menuBarLogoImage() -> NSImage {
        if let image = NSImage(named: "MenuBarLogo") {
            image.isTemplate = false
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return ringImage(fillProgress: elapsedProgress)
    }
}

private struct AboutPanelView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)

            AboutIconView()
                .frame(width: 76, height: 76)

            Text("专注时刻")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, 18)

            Text("Focus Time")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 3)

            Text("版本 V1.0.0")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary.opacity(0.82))
                .padding(.top, 14)

            Text("创意：AI 产品经理四月")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary.opacity(0.82))
                .padding(.top, 5)

            Spacer(minLength: 22)
        }
        .frame(width: 360, height: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

private struct AboutIconView: View {
    var body: some View {
        Image(nsImage: aboutIconImage())
            .resizable()
            .scaledToFit()
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 5)
    }

    private func aboutIconImage() -> NSImage {
        if let aboutLogo = NSImage(named: "AboutLogo") {
            return aboutLogo
        }
        if let appIcon = NSImage(named: "AppIcon") {
            return appIcon
        }
        if let focusMark = NSImage(named: "FocusMarkBlue") {
            return focusMark
        }
        return NSApplication.shared.applicationIconImage
    }
}
