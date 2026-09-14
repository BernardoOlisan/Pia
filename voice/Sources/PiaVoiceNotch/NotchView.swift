import AppKit
import SwiftUI

/// The island, from the old Pia (`Sources/PiaUI`): the notch shape, a dot and the cost on the left,
/// the voice meter on the right, and a small pulse while the voice speaks.
struct NotchView: View {
    @Bindable var model: NotchModel
    let geometry: NotchGeometry

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            island.frame(width: size.width, height: size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The window sits over the notch, which is outside the safe area; without this SwiftUI pushes the island down and out of view.
        .ignoresSafeArea()
        // The pulse gets a short spring so it breathes with syllables instead of twitching.
        .animation(.spring(response: 0.19, dampingFraction: 0.72), value: model.level)
        .animation(.spring(response: 0.38, dampingFraction: 0.58), value: model.voiceSpeaking)
    }

    /// Resting size, plus the lift while the voice speaks, scaled by its real loudness.
    var size: CGSize {
        var box = geometry.restingSize
        let pulse = model.voiceSpeaking ? CGFloat(min(1, max(0, model.level))) : 0
        box.width += 2 * NotchGeometry.lift.width * pulse
        box.height += NotchGeometry.lift.height * pulse
        return box
    }

    private var island: some View {
        ZStack(alignment: .top) {
            IslandShape(inverseRadius: geometry.inverseRadius, notchHeight: geometry.notchHeight)
                .fill(Color(white: 0))
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    AttentionLight(awake: model.connected)
                    Text(model.cost)
                        .font(Font.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(model.connected ? 0.85 : 0.45))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, NotchGeometry.inset)
                .contentShape(Rectangle())
                .onTapGesture { model.onDotClick?() }
                Color.clear.frame(width: geometry.notchWidth)
                VoiceMeter(level: model.level, speaking: model.voiceSpeaking, asleep: !model.connected)
                    .frame(width: NotchGeometry.meterWidth, height: NotchGeometry.meterHeight)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, NotchGeometry.inset)
            }
            .padding(.horizontal, geometry.inverseRadius)
            .frame(height: geometry.restingSize.height)
        }
        .clipShape(IslandShape(inverseRadius: geometry.inverseRadius, notchHeight: geometry.notchHeight))
    }
}

/// Left: is a session open. Solid and lit when connected; a hollow ring breathing when not.
struct AttentionLight: View {
    let awake: Bool
    @State private var breathing = false

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(awake ? 0.92 : 0))
            Circle().strokeBorder(Color.white.opacity(awake ? 0 : 0.45), lineWidth: 1.1)
        }
        .frame(width: 7, height: 7)
        .shadow(color: Color.white.opacity(awake ? 0.6 : 0), radius: awake ? 3.5 : 0)
        .opacity(awake ? 1 : (breathing ? 0.65 : 0.3))
        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathing)
        .animation(.easeInOut(duration: 0.45), value: awake)
        .onAppear { breathing = true }
    }
}

/// Right: five bars driven by real loudness, never a canned animation.
struct VoiceMeter: View {
    let level: Float
    let speaking: Bool
    let asleep: Bool
    @State private var breathing = false

    static let profile: [CGFloat] = [0.60, 1.0, 0.72, 0.92, 0.55]
    static let floorFraction: CGFloat = 0.14

    var heights: [CGFloat] {
        Self.profile.map { weight in
            asleep ? Self.floorFraction : min(1, max(Self.floorFraction, CGFloat(level) * weight))
        }
    }

    var body: some View {
        Canvas { context, size in
            let heights = self.heights
            let barWidth = size.width / CGFloat(heights.count)
            let inset = barWidth * 0.34
            for (index, fraction) in heights.enumerated() {
                let height = max(2, fraction * size.height)
                let rect = CGRect(x: CGFloat(index) * barWidth + inset / 2, y: (size.height - height) / 2,
                                  width: max(1, barWidth - inset), height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: rect.width / 2),
                             with: .color(Color.white.opacity(speaking ? 0.95 : 0.7)))
            }
        }
        .opacity(asleep ? (breathing ? 0.5 : 0.22) : 1)
        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathing)
        .animation(.easeInOut(duration: 0.45), value: asleep)
        .onAppear { breathing = true }
    }
}

/// The black shape: flat top, concave joins that melt into the menu bar, convex bottom corners.
struct IslandShape: Shape {
    let inverseRadius: CGFloat
    var notchHeight: CGFloat = 0

    static func bottomRadius(forHeight height: CGFloat, notchHeight: CGFloat) -> CGFloat {
        guard notchHeight > 0 else { return min(max(height * 0.5, 12), 28) }
        let notch = notchHeight * 0.25
        return min(28, notch * height / notchHeight)
    }

    func path(in rect: CGRect) -> Path {
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
