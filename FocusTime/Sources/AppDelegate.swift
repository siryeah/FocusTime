import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var timerController: TimerController!
    private var floatingTimerWindowController: FloatingTimerWindowController!
    private var statusBarController: StatusBarController!
    private var shortcutController: GlobalShortcutController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        timerController = TimerController()
        timerController.launchAtLogin = LoginItemController.isEnabled
        makeDebugLaunchVisibleIfNeeded()

        floatingTimerWindowController = FloatingTimerWindowController(timerController: timerController)
        installStatusBarControllerIfNeeded()

        shortcutController = GlobalShortcutController { [weak self] in
            self?.timerController.startOrPause()
        }

        timerController.$launchAtLogin
            .dropFirst()
            .removeDuplicates()
            .sink { enabled in
                LoginItemController.setEnabled(enabled)
            }
            .store(in: &cancellables)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.floatingTimerWindowController.applyDisplayMode(self.timerController.displayMode)
            #if DEBUG
            self.floatingTimerWindowController.showSettingsPanel()
            #else
            self.floatingTimerWindowController.revealForLaunch()
            #endif
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        floatingTimerWindowController.persistFrame()
    }

    private func installStatusBarControllerIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.statusBarController = StatusBarController(
                timerController: self.timerController,
                floatingTimerWindowController: self.floatingTimerWindowController
            )
        }
    }

    private func makeDebugLaunchVisibleIfNeeded() {
        #if DEBUG
        NSLog(
            "FocusTime debug launch: displayMode=%@",
            timerController.displayMode.rawValue
        )
        #endif
    }
}
