import AppKit
import SwiftUI

/// The intent island: PIA's voice, alive for as long as the work's intent conversation lasts.
///
/// It is deliberately the same shape and the same two slots as the dictation island, and deliberately
/// a different colour, so a glance tells you which one is running. Dictation is red and counts a take;
/// the voice is white and counts a conversation.
///
/// Left: a dot for whether a session is open, and the time this conversation has been billed for.
/// Right: the live waveform — your voice, and the voice answering.
/// Double-click reveals the cost, exactly as it does for dictation. One click ends the voice.
public struct NotchView: View {
    @Bindable var model: NotchModel
    var stage: IslandStage

    public static let maxSideWidth: CGFloat = 20 + dotWidth + 6 + slotWidth + 7 + costWidth
    static let dotWidth: CGFloat = 9
    /// The waveform and the clock are the same width, one each side of the notch.
    static let slotWidth: CGFloat = 38
    static let costWidth: CGFloat = 44

    public init(model: NotchModel, stage: IslandStage) {
        self.model = model
        self.stage = stage
    }

    private var geometry: NotchGeometry { stage.geometry }

    private var leadingWidth: CGFloat {
        var width = geometry.contentInset + Self.dotWidth + 6 + Self.slotWidth
        if model.showCost { width += 7 + Self.costWidth }
        return width
    }

    private var trailingWidth: CGFloat { Self.slotWidth + geometry.contentInset }

    /// Resting width, plus the lift while the voice speaks, scaled by its real loudness.
    private var islandWidth: CGFloat {
        leadingWidth + geometry.middleGap + trailingWidth + 2 * NotchGeometry.lift.width * pulse
    }

    private var islandHeight: CGFloat { geometry.barHeight + NotchGeometry.lift.height * pulse }

    /// Only the voice's own sound lifts the island; your voice moves the bars and nothing else.
    private var pulse: CGFloat {
        model.voiceSpeaking ? CGFloat(min(1, max(0, model.level))) : 0
    }

    private var alignmentOffset: CGFloat {
        geometry.style == .notch ? (trailingWidth - leadingWidth) / 2 : 0
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            island
                .frame(width: islandWidth, height: islandHeight)
                .offset(x: alignmentOffset, y: geometry.topGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        // The pulse gets a short spring so it breathes with syllables instead of twitching.
        .animation(.spring(response: 0.19, dampingFraction: 0.72), value: model.level)
        .animation(.spring(response: 0.38, dampingFraction: 0.58), value: model.voiceSpeaking)
        .animation(IslandMotion.reveal, value: model.showCost)
    }

    private var island: some View {
        ZStack(alignment: .top) {
            IslandShape(inverseRadius: geometry.inverseRadius, notchHeight: geometry.notchHeight, style: geometry.style)
                .fill(Color(white: 0))
                .shadow(color: .black.opacity(geometry.style == .capsule ? 0.32 : 0), radius: 7, y: 2)
            HStack(spacing: 0) {
                leading.frame(width: leadingWidth, alignment: .leading)
                Color.clear.frame(width: geometry.middleGap)
                Waveform(samples: model.samples, color: .white.opacity(model.connected ? 0.95 : 0.45))
                    .frame(width: Self.slotWidth, height: geometry.waveHeight)
                    .frame(width: trailingWidth, alignment: .trailing)
                    .padding(.trailing, geometry.contentInset)
            }
            .frame(height: geometry.barHeight)
        }
        .clipShape(IslandShape(inverseRadius: geometry.inverseRadius, notchHeight: geometry.notchHeight, style: geometry.style))
        .contentShape(Rectangle())
        .overlay(ClickCatcher(onClick: { model.onDotClick?() },
                              onDoubleClick: { model.showCost.toggle() }))
    }

    @ViewBuilder private var leading: some View {
        HStack(spacing: 7) {
            if model.showCost {
                Text(model.cost)
                    .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.4))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: Self.costWidth, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            HStack(spacing: 6) {
                AttentionLight(awake: model.connected)
                ElapsedLabel(seconds: model.elapsed, color: .white.opacity(model.connected ? 0.9 : 0.45))
                    .frame(width: Self.slotWidth, alignment: .leading)
            }
        }
        .padding(.leading, geometry.contentInset)
    }
}

/// Is a session open. Solid and lit when connected; a hollow ring breathing when not.
public struct AttentionLight: View {
    public var awake: Bool
    @State private var breathing = false

    public init(awake: Bool) { self.awake = awake }

    public var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(awake ? 0.95 : 0))
            Circle().strokeBorder(Color.white.opacity(awake ? 0 : 0.45), lineWidth: 1.1)
        }
        .frame(width: 7, height: 7)
        .frame(width: 9, height: 9)
        .shadow(color: Color.white.opacity(awake ? 0.6 : 0), radius: awake ? 3.5 : 0)
        .opacity(awake ? 1 : (breathing ? 0.65 : 0.3))
        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathing)
        .animation(.easeInOut(duration: 0.45), value: awake)
        .onAppear { breathing = true }
    }
}
