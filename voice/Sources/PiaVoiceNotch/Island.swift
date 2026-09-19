import SwiftUI

/// iOS system colours, dark variants.
public enum Palette {
    public static let red = Color(red: 1, green: 0.271, blue: 0.227)
    public static let green = Color(red: 0.196, green: 0.843, blue: 0.294)
    public static let orange = Color(red: 1, green: 0.624, blue: 0.039)
}

/// How the island moves. One spring for the shape, one crossfade for what is inside it — never two
/// springs fighting each other, and never a blur, which is what made the old open read as a smear.
public enum IslandMotion {
    /// The shape growing out of the notch and folding back into it.
    public static let morph = Animation.spring(response: 0.38, dampingFraction: 0.74)
    /// Content appearing inside a shape that is already the right size.
    public static let content = Animation.spring(response: 0.3, dampingFraction: 0.85)
    /// The island widening to make room for the cost, and closing again.
    public static let reveal = Animation.spring(response: 0.34, dampingFraction: 0.8)
}

/// The black shape.
///
/// - `notch`: flat top, concave joins that melt into the menu bar, convex bottom corners.
/// - `capsule`: a full pill, because on a screen with no notch there is nothing to melt into.
public struct IslandShape: Shape {
    public var inverseRadius: CGFloat
    public var notchHeight: CGFloat
    public var style: IslandStyle

    public init(inverseRadius: CGFloat, notchHeight: CGFloat = 0, style: IslandStyle = .notch) {
        self.inverseRadius = inverseRadius
        self.notchHeight = notchHeight
        self.style = style
    }

    /// Animating the two numbers together keeps the corners honest while the island grows.
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(inverseRadius, notchHeight) }
        set { inverseRadius = newValue.first; notchHeight = newValue.second }
    }

    public static func bottomRadius(forHeight height: CGFloat, notchHeight: CGFloat) -> CGFloat {
        guard notchHeight > 0 else { return min(max(height * 0.5, 12), 28) }
        let notch = notchHeight * 0.25
        return min(28, notch * height / notchHeight)
    }

    public func path(in rect: CGRect) -> Path {
        guard style == .notch else {
            return Path(roundedRect: rect, cornerRadius: min(rect.height, rect.width) / 2, style: .continuous)
        }
        let ir = min(inverseRadius, rect.width / 4)
        let r = min(Self.bottomRadius(forHeight: rect.height, notchHeight: notchHeight), (rect.width - 2 * ir) / 2)
        let left = rect.minX + ir, right = rect.maxX - ir
        let top = rect.minY, bottom = rect.maxY
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: top + ir), control: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: bottom - r))
        path.addQuadCurve(to: CGPoint(x: right - r, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: left + r, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - r), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left, y: top + ir))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: top), control: CGPoint(x: left, y: top))
        path.closeSubpath()
        return path
    }
}

/// The last couple of seconds of loudness, as Voice Memos draws them: thin vertical bars with rounded
/// caps, newest on the right, quiet moments left as dots rather than nothing.
public struct Waveform: View {
    public var samples: [Float]
    public var color: Color

    /// How many samples the model keeps. How many are *drawn* comes from the width it is given, so
    /// the waveform can be sized to match whatever sits on the other side of the notch.
    public static let capacity = 22
    static let pitch: CGFloat = 2.6
    static let barWidth: CGFloat = 1.6

    public init(samples: [Float], color: Color = Palette.red) {
        self.samples = samples
        self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            guard size.height > 0, size.width > 0 else { return }
            let count = max(1, Int(size.width / Self.pitch))
            // Newest sample at the right edge; a short recording starts at the right and fills leftwards.
            let padded = Array(repeating: Float(0), count: max(0, count - samples.count))
                + samples.suffix(count)
            for (index, sample) in padded.enumerated() {
                let loud = CGFloat(max(0, min(1, sample)))
                // A gentle curve: quiet speech still shows, loud speech doesn't clip to the ceiling.
                let fraction = 0.08 + 0.92 * pow(loud, 0.62)
                let height = max(Self.barWidth, fraction * size.height)
                let x = size.width - CGFloat(count - index) * Self.pitch + (Self.pitch - Self.barWidth) / 2
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: Self.barWidth, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: Self.barWidth / 2), with: .color(color))
            }
        }
    }
}

/// `0:05`, the way every Apple recording timer reads.
public struct ElapsedLabel: View {
    public var seconds: TimeInterval
    public var color: Color

    public init(seconds: TimeInterval, color: Color = Palette.red) {
        self.seconds = seconds
        self.color = color
    }

    public static func text(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    public var body: some View {
        Text(Self.text(seconds))
            .font(.system(size: 11.5, weight: .regular, design: .rounded).monospacedDigit())
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .lineLimit(1)
            .fixedSize()
    }
}

/// A thin ring that spins while the transcription comes back.
public struct Spinner: View {
    public var color: Color = .white
    public init(color: Color = .white) { self.color = color }

    public var body: some View {
        TimelineView(.animation) { timeline in
            let turns = timeline.date.timeIntervalSinceReferenceDate / 0.85
            Circle()
                .trim(from: 0.18, to: 1)
                .stroke(color.opacity(0.88), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(turns.truncatingRemainder(dividingBy: 1) * 360))
                .frame(width: 9, height: 9)
        }
    }
}
