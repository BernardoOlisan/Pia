import AppKit
import Observation
import SwiftUI

/// What the notch shows while dictating. Updated on the main thread by the dictation session.
@Observable
public final class DictationModel {
    public enum Phase: Equatable { case hidden, recording, transcribing, done, failed }

    public var phase = Phase.hidden
    /// This month's dictation cost, live while recording: "$0.004".
    public var cost = "$0.000"
    /// 0...1 microphone loudness.
    public var level: Float = 0
    /// Clicking the island stops the recording.
    public var onTap: (() -> Void)?

    public init() {}
}

/// The same island as the intent, for dictation: it unfolds from the notch, a red dot breathes while it
/// records, a small ring spins while it transcribes, a green check when the text is in the clipboard.
struct DictationView: View {
    @Bindable var model: DictationModel
    let geometry: NotchGeometry

    static let leftContentWidth: CGFloat = 50

    private var visible: Bool { model.phase != .hidden }

    /// Folded into the notch when hidden. It never pulses: the island only grows with sound the computer plays
    /// (the AI's voice); your voice moves the bars and nothing else.
    var size: CGSize { visible ? geometry.restingSize : geometry.foldedSize }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            island
                .frame(width: size.width, height: size.height)
                // Without a notch there is nothing to fold into: fade instead.
                .opacity(visible || geometry.notchHeight > 0 ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.phase)
    }

    private var island: some View {
        ZStack(alignment: .top) {
            IslandShape(inverseRadius: geometry.inverseRadius, notchHeight: geometry.notchHeight)
                .fill(Color(white: 0))
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    StatusGlyph(phase: model.phase)
                    Text(model.cost)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(model.phase == .recording ? 0.9 : 0.6))
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, NotchGeometry.inset)
                Color.clear.frame(width: geometry.notchWidth)
                rightSide
                    .frame(width: NotchGeometry.meterWidth, height: NotchGeometry.meterHeight)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, NotchGeometry.inset)
            }
            .padding(.horizontal, geometry.inverseRadius)
            .frame(height: geometry.restingSize.height)
            .opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 3)
            .animation(.easeOut(duration: visible ? 0.28 : 0.12).delay(visible ? 0.1 : 0), value: visible)
        }
        .clipShape(IslandShape(inverseRadius: geometry.inverseRadius, notchHeight: geometry.notchHeight))
        .contentShape(Rectangle())
        .onTapGesture { model.onTap?() }
    }

    @ViewBuilder private var rightSide: some View {
        switch model.phase {
        case .transcribing:
            WaitingMeter()
        case .recording:
            VoiceMeter(level: model.level, speaking: true, asleep: false)
        default:
            VoiceMeter(level: 0, speaking: false, asleep: false)
        }
    }
}

/// iOS system colors, dark variants.
enum Palette {
    static let red = Color(red: 1, green: 0.271, blue: 0.227)
    static let green = Color(red: 0.196, green: 0.843, blue: 0.294)
    static let orange = Color(red: 1, green: 0.624, blue: 0.039)
}

/// Left: the state at a glance.
struct StatusGlyph: View {
    let phase: DictationModel.Phase

    var body: some View {
        ZStack {
            switch phase {
            case .hidden, .recording:
                RecordingDot().transition(.scale(scale: 0.3).combined(with: .opacity))
            case .transcribing:
                Spinner().transition(.scale(scale: 0.3).combined(with: .opacity))
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Palette.green)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            case .failed:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(Palette.orange)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: 10, height: 10)
    }
}

/// The red recording light, breathing slowly like the one iOS shows while recording.
struct RecordingDot: View {
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(Palette.red)
            .frame(width: 8, height: 8)
            .shadow(color: Palette.red.opacity(breathing ? 0.85 : 0.35), radius: breathing ? 4 : 1.5)
            .opacity(breathing ? 1 : 0.72)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: breathing)
            .onAppear { breathing = true }
    }
}

/// A thin ring that spins while the transcription comes back.
struct Spinner: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let turns = timeline.date.timeIntervalSinceReferenceDate / 0.85
            Circle()
                .trim(from: 0.18, to: 1)
                .stroke(Color.white.opacity(0.88), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(turns.truncatingRemainder(dividingBy: 1) * 360))
                .frame(width: 8.5, height: 8.5)
        }
    }
}

/// Right, while transcribing: the five bars ripple quietly instead of following the microphone.
struct WaitingMeter: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let count = VoiceMeter.profile.count
                let barWidth = size.width / CGFloat(count)
                let inset = barWidth * 0.34
                for index in 0..<count {
                    let wave = 0.5 + 0.5 * sin(t * 2 * .pi * 1.1 - Double(index) * 0.8)
                    let fraction = VoiceMeter.floorFraction + 0.32 * CGFloat(wave)
                    let height = max(2, fraction * size.height)
                    let rect = CGRect(x: CGFloat(index) * barWidth + inset / 2, y: (size.height - height) / 2,
                                      width: max(1, barWidth - inset), height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: rect.width / 2),
                                 with: .color(Color.white.opacity(0.55)))
                }
            }
        }
    }
}
