import AppKit
import SwiftUI

struct FloatingTimerRootView: View {
    @ObservedObject var timer: TimerController
    @ObservedObject var presentation: FloatingTimerPresentation

    let onTogglePanel: () -> Void
    let onClosePanel: () -> Void
    let onPrimaryControl: () -> Void
    let onDoubleClickTimer: () -> Void
    let onReset: () -> Void

    var body: some View {
        ZStack {
            if presentation.isSettingsPanelOpen {
                SettingsPanelView(
                    timer: timer,
                    onClosePanel: onClosePanel,
                    onPrimaryControl: onPrimaryControl
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            } else {
                CollapsedTimerView(
                    timer: timer,
                    isHovered: presentation.isHovered,
                    onTogglePanel: onTogglePanel,
                    onPrimaryControl: onPrimaryControl,
                    onDoubleClickTimer: onDoubleClickTimer,
                    onReset: onReset
                )
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: presentation.isSettingsPanelOpen)
        .animation(.easeOut(duration: 0.18), value: presentation.isHovered)
    }
}

private struct CollapsedTimerView: View {
    @ObservedObject var timer: TimerController
    let isHovered: Bool
    let onTogglePanel: () -> Void
    let onPrimaryControl: () -> Void
    let onDoubleClickTimer: () -> Void
    let onReset: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fontSize = min(max(min(size.width / 4.25, size.height * (isHovered ? 0.42 : 0.56)), 30), 96)
            let glassInset = isHovered ? min(max(size.height * 0.055, 7), 12) : 0
            let accent = Color(nsColor: timer.accentColor.nsColor)

            ZStack {
                DragInteractionView()

                if isHovered {
                    LiquidGlassCard(cornerRadius: 24)
                        .padding(glassInset)
                        .transition(.opacity)
                }

                VStack(spacing: max(3, size.height * 0.03)) {
                    TimerDigitsView(
                        text: timer.formattedTime,
                        fontSize: fontSize,
                        weight: .medium,
                        accent: accent,
                        isGlass: true
                    )
                        .minimumScaleFactor(0.42)
                        .lineLimit(1)
                        .opacity(timer.isCompleted && !timer.completionPulse ? 0.42 : 1)

                    if isHovered {
                        HStack(spacing: 18) {
                            Button(action: onPrimaryControl) {
                                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)

                            Button(action: onReset) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!timer.canReset)
                            .opacity(timer.canReset ? 1 : 0.38)
                        }
                        .foregroundStyle(.secondary)
                        .frame(height: 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, isHovered ? 28 : 10)
                .padding(.vertical, isHovered ? 18 : 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                onTogglePanel()
            }
            .onTapGesture(count: 2) {
                onDoubleClickTimer()
            }
        }
    }
}

private struct SettingsPanelView: View {
    @ObservedObject var timer: TimerController
    let onClosePanel: () -> Void
    let onPrimaryControl: () -> Void

    var body: some View {
        ZStack {
            SettingsPanelBackground(accent: Color(nsColor: timer.accentColor.panelTintColor))

            VStack(spacing: 24) {
                header
                timerPreview
                timeSection
                colorSection
                displaySection
                controlRow
            }
            .padding(.horizontal, 30)
            .padding(.top, 54)
            .padding(.bottom, 28)
        }
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 610, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 3) {
                Text("专注时刻")
                    .font(.system(size: 21, weight: .semibold))
                Text("Focus Time")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()

                Button {
                    timer.isPinned.toggle()
                } label: {
                    Image(systemName: timer.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(timer.isPinned ? Color(nsColor: timer.accentColor.nsColor) : .primary)
            }
        }
        .frame(height: 44)
    }

    private var timerPreview: some View {
        VStack(spacing: 6) {
            TimerDigitsView(
                text: timer.formattedTime,
                fontSize: 82,
                weight: .medium,
                accent: Color(nsColor: timer.accentColor.nsColor),
                isGlass: false
            )
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text("剩余时间")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 116)
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("时间设置")

            TimeScaleControl(timer: timer)
                .frame(height: 70)
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("数字颜色")

            HStack {
                ForEach(Array(TimerAccentColor.allCases.enumerated()), id: \.element) { index, accent in
                    Button {
                        timer.accentColor = accent
                    } label: {
                        let isSelected = timer.accentColor == accent
                        Circle()
                            .fill(Color(nsColor: accent.nsColor))
                            .frame(width: 23, height: 23)
                            .shadow(color: Color(nsColor: accent.nsColor).opacity(accent == .white ? 0.12 : 0.24), radius: 8, x: 0, y: 2)
                            .overlay {
                                Circle()
                                    .stroke(.primary.opacity(accent == .white ? 0.12 : 0), lineWidth: 1)
                            }
                            .overlay {
                                Circle()
                                    .stroke(Color(nsColor: accent.nsColor), lineWidth: isSelected ? 3 : 0)
                                    .padding(-7)
                            }
                    }
                    .buttonStyle(.plain)

                    if index < TimerAccentColor.allCases.count - 1 {
                        Spacer(minLength: 16)
                    }
                }
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("显示模式")

            CapsuleSegmentedControl(
                selection: $timer.displayMode,
                accent: Color(nsColor: timer.accentColor.nsColor)
            )
        }
    }

    private var controlRow: some View {
        ZStack {
            Button {
                onPrimaryControl()
            } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .frame(width: 76, height: 76)
                    .contentShape(Circle())
            }
            .keyboardShortcut(.space, modifiers: .option)
            .buttonStyle(PlayCircleButtonStyle(accent: Color(nsColor: timer.accentColor.nsColor)))
            .help(timer.isRunning ? "暂停" : "开始播放")

            HStack {
                Spacer()

                Button {
                    timer.reset()
                } label: {
                    Label("重置", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(ResetPillButtonStyle())
                .disabled(!timer.canReset)
                .opacity(timer.canReset ? 1 : 0.42)
            }
        }
        .frame(height: 84)
    }

}

private struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary.opacity(0.78))
    }
}

private struct TimerDigitsView: View {
    let text: String
    let fontSize: CGFloat
    let weight: Font.Weight
    let accent: Color
    let isGlass: Bool

    var body: some View {
        if isGlass {
            ZStack {
                digitText
                    .foregroundStyle(accent.opacity(0.36))
                    .offset(x: 0.85, y: 1.0)
                    .mask(digitText)

                digitText
                    .foregroundStyle(.white.opacity(0.16))
                    .offset(x: -0.55, y: -0.65)
                    .mask(digitText)

                LinearGradient(
                    colors: [
                        .white.opacity(0.16),
                        .clear,
                        accent.opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .mask(digitText)
                .blendMode(.screen)

                digitText
                    .foregroundStyle(accent)
            }
            .overlay {
                digitText
                    .strokeLike(color: .white.opacity(0.10), offset: CGSize(width: -0.25, height: -0.3))
            }
            .shadow(color: .black.opacity(0.12), radius: 1.3, x: 0, y: 0.7)
            .shadow(color: accent.opacity(0.14), radius: 2.0, x: 0, y: 0)
            .accessibilityLabel(text)
        } else {
            digitText
                .foregroundStyle(accent)
                .shadow(color: .black.opacity(0.16), radius: 2.5, x: 0, y: 1)
                .shadow(color: accent.opacity(0.12), radius: 5, x: 0, y: 1)
        }
    }

    private var digitText: some View {
        Text(text)
            .font(.system(size: fontSize, weight: weight, design: .rounded))
            .monospacedDigit()
    }
}

private extension View {
    func strokeLike(color: Color, offset: CGSize) -> some View {
        ZStack {
            self.offset(x: offset.width, y: offset.height).foregroundStyle(color)
            self.offset(x: -offset.width, y: -offset.height).foregroundStyle(color.opacity(0.45))
        }
        .mask(self)
    }
}

private struct TimeScaleControl: View {
    @ObservedObject var timer: TimerController

    private let labels = [1, 15, 25, 45, 60, 75, 90]

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let accent = Color(nsColor: timer.accentColor.nsColor)
            let selectedX = position(for: timer.durationMinutes, width: width)

            ZStack(alignment: .topLeading) {
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.34))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.primary.opacity(0.06), lineWidth: 0.7)
                    )
                    .frame(height: 44)
                    .position(x: width / 2, y: 23)

                ForEach(labels, id: \.self) { value in
                    Button {
                        timer.setDuration(minutes: value)
                    } label: {
                        Text("\(value)m")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary.opacity(timer.durationMinutes == value ? 0 : 0.46))
                            .frame(width: 58, height: 44)
                    }
                    .buttonStyle(.plain)
                    .position(x: position(for: value, width: width), y: 23)
                }

                Capsule(style: .continuous)
                    .fill(accent.opacity(0.13))
                    .background {
                        Capsule(style: .continuous)
                            .fill(.regularMaterial)
                    }
                    .glassEffect(.clear.tint(accent.opacity(0.12)).interactive(), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(accent.opacity(0.20), lineWidth: 0.8)
                    )
                    .shadow(color: accent.opacity(0.18), radius: 10, x: 0, y: 3)
                    .frame(width: 70, height: 44)
                    .overlay {
                        Text("\(timer.durationMinutes)m")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    .position(x: selectedX, y: 23)

                tickMarks(width: width, accent: accent)
                    .position(x: width / 2, y: 57)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        timer.setDuration(minutes: minute(at: value.location.x, width: width))
                    }
            )
        }
    }

    private func tickMarks(width: CGFloat, accent: Color) -> some View {
        let total = 42
        return HStack(spacing: 0) {
            ForEach(0...total, id: \.self) { index in
                let ratio = CGFloat(index) / CGFloat(total)
                let minute = 1 + Int(round(ratio * 89))
                Rectangle()
                    .fill(abs(minute - timer.durationMinutes) <= 1 ? accent : Color.primary.opacity(index.isMultiple(of: 7) ? 0.22 : 0.12))
                    .frame(width: 1, height: index.isMultiple(of: 7) ? 10 : 4)

                if index != total {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: max(width - 64, 1), height: 12)
    }

    private func position(for minute: Int, width: CGFloat) -> CGFloat {
        let ratio = CGFloat(min(max(minute, 1), 90) - 1) / 89
        return 35 + ratio * max(width - 70, 1)
    }

    private func minute(at x: CGFloat, width: CGFloat) -> Int {
        let availableWidth = max(width - 70, 1)
        let ratio = min(max((x - 35) / availableWidth, 0), 1)
        return min(max(Int(round(1 + ratio * 89)), 1), 90)
    }
}

private struct PlayCircleButtonStyle: ButtonStyle {
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(accent)
            .background {
                Circle()
                    .fill(.regularMaterial)
                    .glassEffect(.clear.tint(accent.opacity(0.08)).interactive(), in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
                    .shadow(color: accent.opacity(0.14), radius: 12, x: 0, y: 2)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

private struct ResetPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary.opacity(0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.primary.opacity(0.06), lineWidth: 0.7)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct SettingsPanelBackground: View {
    var accent: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)

            LinearGradient(
                colors: [
                    accent.opacity(0.10),
                    Color.white.opacity(0.05),
                    accent.opacity(0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct CapsuleSegmentedControl: View {
    @Binding var selection: DisplayMode
    var accent: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DisplayMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 14, weight: selection == mode ? .semibold : .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(selection == mode ? accent : .primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if selection == mode {
                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.15))
                            .background {
                                Capsule(style: .continuous)
                                    .fill(.regularMaterial)
                            }
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(accent.opacity(0.24), lineWidth: 0.9)
                            )
                            .shadow(color: accent.opacity(0.16), radius: 10, x: 0, y: 3)
                            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                }

                if mode != DisplayMode.allCases.last {
                    Divider()
                        .frame(height: 19)
                        .opacity(selection == mode ? 0 : 0.32)
                }
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity)
        .background {
            Capsule(style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.28))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.primary.opacity(0.06), lineWidth: 0.7)
                )
        }
    }
}
private struct LiquidGlassCard: View {
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(.clear)
            .glassEffect(
                .clear.tint(Color.white.opacity(0.03)).interactive(),
                in: shape
            )
            .clipShape(shape)
            .contentShape(shape)
    }
}

private struct PlainSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.sliderType = .linear
        slider.numberOfTickMarks = 0
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
        nsView.minValue = range.lowerBound
        nsView.maxValue = range.upperBound
        if abs(nsView.doubleValue - value) > 0.5 {
            nsView.doubleValue = value
        }
    }

    final class Coordinator: NSObject {
        @Binding var value: Double

        init(value: Binding<Double>) {
            _value = value
        }

        @MainActor @objc func changed(_ sender: NSSlider) {
            value = sender.doubleValue
        }
    }
}

private struct DragInteractionView: NSViewRepresentable {
    func makeNSView(context: Context) -> DragInteractionNSView {
        DragInteractionNSView()
    }

    func updateNSView(_ nsView: DragInteractionNSView, context: Context) {
    }
}

private final class DragInteractionNSView: NSView {
    override func mouseDragged(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private extension View {
    func digitGlass(isEnabled: Bool, accent: Color) -> some View {
        modifier(DigitGlassModifier(isEnabled: isEnabled, accent: accent))
    }

    func sectionGlass() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 0.6)
                    )
            }
    }
}

private struct DigitGlassModifier: ViewModifier {
    var isEnabled: Bool
    var accent: Color

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .glassEffect(
                    .clear.tint(accent.opacity(0.14)).interactive(false),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        } else {
            content
        }
    }
}

private struct PresetButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color.white.opacity(0.12))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

private struct PrimaryControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct SecondaryControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.12))
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.6)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
