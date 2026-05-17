import AppKit
import Combine
import Foundation

enum TimerState: String, Codable {
    case idle
    case running
    case paused
    case completed
}

enum DisplayMode: String, CaseIterable, Identifiable, Codable {
    case menuBarOnly
    case desktopOnly
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBarOnly: "仅菜单栏"
        case .desktopOnly: "仅桌面"
        case .both: "同时显示"
        }
    }
}

enum TimerAccentColor: String, CaseIterable, Identifiable, Codable {
    case blue
    case orange
    case white
    case teal
    case yellow
    case green
    case purple
    case pink

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .blue: NSColor.systemBlue
        case .orange: NSColor(calibratedRed: 1.0, green: 0.34, blue: 0.13, alpha: 1.0)
        case .white: NSColor.white
        case .teal: NSColor.systemTeal
        case .yellow: NSColor.systemYellow
        case .green: NSColor.systemGreen
        case .purple: NSColor.systemPurple
        case .pink: NSColor.systemPink
        }
    }

    var panelTintColor: NSColor {
        switch self {
        case .white:
            NSColor(calibratedWhite: 1.0, alpha: 1.0)
        default:
            nsColor
        }
    }
}

@MainActor
final class TimerController: ObservableObject {
    static let defaultDurationMinutes = 25

    @Published private(set) var state: TimerState
    @Published var durationMinutes: Int {
        didSet {
            if oldValue != durationMinutes {
                remainingSeconds = durationMinutes * 60
                state = .idle
                save()
            }
        }
    }
    @Published var remainingSeconds: Int {
        didSet {
            save()
        }
    }
    @Published var accentColor: TimerAccentColor {
        didSet { save() }
    }
    @Published var displayMode: DisplayMode {
        didSet { save() }
    }
    @Published var isPinned: Bool {
        didSet { save() }
    }
    @Published var launchAtLogin: Bool {
        didSet { save() }
    }
    @Published var completionPulse: Bool = false

    private var timer: Timer?
    private var pulseTimer: Timer?
    private let defaults = UserDefaults.standard

    var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var progress: CGFloat {
        guard durationMinutes > 0 else { return 0 }
        return CGFloat(remainingSeconds) / CGFloat(durationMinutes * 60)
    }

    var isRunning: Bool { state == .running }
    var isCompleted: Bool { state == .completed }
    var isCountingState: Bool { state == .running || state == .paused || state == .completed }
    var canReset: Bool {
        isCountingState ||
            durationMinutes != Self.defaultDurationMinutes ||
            remainingSeconds != durationMinutes * 60
    }

    init() {
        let storedDuration = defaults.integer(forKey: AppSettings.durationMinutes)
        let initialDuration = storedDuration == 0 ? Self.defaultDurationMinutes : min(max(storedDuration, 1), 90)
        durationMinutes = initialDuration

        let storedRemaining = defaults.integer(forKey: AppSettings.remainingSeconds)
        remainingSeconds = storedRemaining == 0 ? initialDuration * 60 : min(max(storedRemaining, 0), initialDuration * 60)

        let accentRaw = defaults.string(forKey: AppSettings.accentColor) ?? TimerAccentColor.blue.rawValue
        accentColor = TimerAccentColor(rawValue: accentRaw) ?? .blue

        let displayRaw = defaults.string(forKey: AppSettings.displayMode) ?? DisplayMode.both.rawValue
        displayMode = DisplayMode(rawValue: displayRaw) ?? .both

        isPinned = defaults.bool(forKey: AppSettings.isPinned)
        launchAtLogin = defaults.bool(forKey: AppSettings.launchAtLogin)

        let stateRaw = defaults.string(forKey: AppSettings.timerState) ?? TimerState.idle.rawValue
        state = TimerState(rawValue: stateRaw) ?? .idle
        if state == .running {
            state = .paused
        }
        if remainingSeconds == 0 {
            state = .completed
            startCompletionPulse()
        }
    }

    func startOrPause() {
        if state == .completed {
            acknowledgeCompletion()
            return
        }

        if state == .running {
            pause()
        } else {
            start()
        }
    }

    func start() {
        guard remainingSeconds > 0 else {
            completeAndNotify()
            return
        }
        state = .running
        stopCompletionPulse()
        installTickTimer()
        save()
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        state = .paused
        save()
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        stopCompletionPulse()
        durationMinutes = Self.defaultDurationMinutes
        remainingSeconds = Self.defaultDurationMinutes * 60
        state = .idle
        save()
    }

    func setDuration(minutes: Int) {
        let clampedMinutes = min(max(minutes, 1), 90)
        guard durationMinutes != clampedMinutes else { return }
        durationMinutes = clampedMinutes
    }

    func completeAndNotify() {
        timer?.invalidate()
        timer = nil
        remainingSeconds = 0
        state = .completed
        NSSound(named: "Glass")?.play()
        startCompletionPulse()
        save()
    }

    func acknowledgeCompletion() {
        stopCompletionPulse()
        reset()
    }

    private func installTickTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.state == .running else { return }
                if self.remainingSeconds <= 1 {
                    self.completeAndNotify()
                } else {
                    self.remainingSeconds = max(0, self.remainingSeconds - 1)
                }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func startCompletionPulse() {
        pulseTimer?.invalidate()
        completionPulse = true
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.72, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.completionPulse.toggle()
            }
        }
        RunLoop.main.add(pulseTimer!, forMode: .common)
    }

    private func stopCompletionPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        completionPulse = false
    }

    private func save() {
        defaults.set(durationMinutes, forKey: AppSettings.durationMinutes)
        defaults.set(remainingSeconds, forKey: AppSettings.remainingSeconds)
        defaults.set(accentColor.rawValue, forKey: AppSettings.accentColor)
        defaults.set(displayMode.rawValue, forKey: AppSettings.displayMode)
        defaults.set(isPinned, forKey: AppSettings.isPinned)
        defaults.set(launchAtLogin, forKey: AppSettings.launchAtLogin)
        defaults.set(state.rawValue, forKey: AppSettings.timerState)
    }
}

enum AppSettings {
    static let durationMinutes = "durationMinutes"
    static let remainingSeconds = "remainingSeconds"
    static let accentColor = "accentColor"
    static let displayMode = "displayMode"
    static let isPinned = "isPinned"
    static let launchAtLogin = "launchAtLogin"
    static let windowFrame = "windowFrame"
    static let desktopWindowFrame = "desktopWindowFrame"
    static let settingsWindowFrame = "settingsWindowFrame"
    static let timerState = "timerState"
}
