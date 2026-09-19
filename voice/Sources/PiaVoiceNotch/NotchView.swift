import AppKit
import SwiftUI

/// The intent island: PIA's voice, alive for as long as the work's intent conversation lasts.
///
/// It is deliberately the same shape and the same two slots as the dictation island, and deliberately
/// a different colour, so a glance tells you which one is running. Dictation is red and counts a take;
/// the voice is white and counts a conversation.
///
/// Left: a dot for whether a session is open, and the time this conversation has been billed for.
/// Right: the live waveform — your voice, and the voice answering — but only while a session is open.
///
/// That last part is the whole design. GPT-Live bills by the second, silence included, so a session
/// opens when you speak and closes itself after a while of quiet. The island shows exactly that: wide
/// and moving while it costs money, narrow and breathing while it does not. You can tell what you are
/// paying for without reading a number.
///
/// The dot is the state: lit while a session is open, blue when Claude is holding something for you,
/// a quiet ring when it is asleep and there is nothing waiting.
///
/// One click wakes the island or puts it back to sleep. Double-click reveals the cost, as in dictation.
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

    /// The waveform is only drawn while a session is open; asleep, the side empties out, the way the
    /// dictation island empties while it thinks.
    private var trailingWidth: CGFloat {
        (model.connected ? Self.slotWidth : 14) + geometry.contentInset
    }

    /// The size the content is laid out at. It never changes while the voice speaks.
    private var restingWidth: CGFloat { leadingWidth + geometry.middleGap + trailingWidth }

    /// The size the *shape* breathes to. Rounded to whole points: a fractional frame makes SwiftUI
    /// re-rasterise everything inside it every frame, which is what made the clock shimmer.
    private var pulsedWidth: CGFloat { (restingWidth + 2 * NotchGeometry.lift.width * pulse).rounded() }
    private var pulsedHeight: CGFloat { (geometry.barHeight + NotchGeometry.lift.height * pulse).rounded() }

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
                .offset(x: alignmentOffset, y: geometry.topGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        // The pulse gets a short spring so it breathes with syllables instead of twitching.
        .animation(.spring(response: 0.19, dampingFraction: 0.72), value: model.level)
        .animation(.spring(response: 0.38, dampingFraction: 0.58), value: model.voiceSpeaking)
        .animation(IslandMotion.reveal, value: model.showCost)
        .animation(IslandMotion.morph, value: model.connected)
        .animation(IslandMotion.reveal, value: model.waiting)
    }

    /// The shape breathes behind content that is pinned to the resting size.
    ///
    /// Keeping the content out of the animating frame is the whole point: anything laid out inside a
    /// frame that is mid-spring gets re-measured on every frame, and text re-measured at fractional
    /// positions wobbles. The island can grow all it likes; the clock never hears about it.
    private var island: some View {
        Color.clear
            .frame(width: restingWidth, height: geometry.barHeight)
            .background(alignment: .top) {
                IslandShape(inverseRadius: geometry.inverseRadius, notchHeight: geometry.notchHeight, style: geometry.style)
                    .fill(Color(white: 0))
                    .shadow(color: .black.opacity(geometry.style == .capsule ? 0.32 : 0), radius: 7, y: 2)
                    .frame(width: pulsedWidth, height: pulsedHeight)
            }
            // Clipped to the resting shape: content can never spill past the curve, whatever it grows into.
            .overlay {
                content.clipShape(IslandShape(inverseRadius: geometry.inverseRadius,
                                              notchHeight: geometry.notchHeight, style: geometry.style))
            }
            .contentShape(Rectangle())
            .overlay(ClickCatcher(onClick: { model.onDotClick?() },
                                  onDoubleClick: { model.showCost.toggle() }))
    }

    private var content: some View {
        HStack(spacing: 0) {
                leading.frame(width: leadingWidth, alignment: .leading)
                Color.clear.frame(width: geometry.middleGap)
                Group {
                    if model.connected {
                        Waveform(samples: model.samples, color: .white.opacity(0.95))
                            .frame(width: Self.slotWidth, height: geometry.waveHeight)
                            .transition(.opacity.combined(with: .scale(scale: 0.7, anchor: .trailing)))
                    } else {
                        Color.clear.frame(width: 14)
                    }
                }
                // The inset is padding, not part of the slot: aligning to the slot's own trailing edge
                // would put the waveform right on the curve, which is where it ended up once already.
                .padding(.trailing, geometry.contentInset)
        }
        .frame(width: restingWidth, height: geometry.barHeight)
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
                AttentionLight(awake: model.connected, waiting: model.waiting)
                ElapsedLabel(seconds: model.elapsed, color: .white.opacity(model.connected ? 0.9 : 0.45))
                    .frame(width: Self.slotWidth, alignment: .leading)
            }
        }
        .padding(.leading, geometry.contentInset)
    }
}

/// The dot. Solid white while a session is open, solid blue while Claude is holding something for you,
/// and a quiet ring breathing when it is asleep with nothing to say.
public struct AttentionLight: View {
    public var awake: Bool
    public var waiting: Bool
    @State private var breathing = false

    public init(awake: Bool, waiting: Bool = false) {
        self.awake = awake
        self.waiting = waiting
    }

    private var filled: Bool { awake || waiting }
    private var colour: Color { waiting && !awake ? Palette.blue : .white }

    public var body: some View {
        ZStack {
            Circle().fill(colour.opacity(filled ? 0.95 : 0))
            Circle().strokeBorder(Color.white.opacity(filled ? 0 : 0.45), lineWidth: 1.1)
        }
        .frame(width: 7, height: 7)
        .frame(width: 9, height: 9)
        .shadow(color: colour.opacity(filled ? 0.6 : 0), radius: filled ? 3.5 : 0)
        // Asleep with something waiting, it breathes brighter: visible from the corner of your eye,
        // never the flashing of a notification.
        .opacity(filled && !waiting ? 1 : (breathing ? (waiting ? 1 : 0.65) : (waiting ? 0.55 : 0.3)))
        .animation(.easeInOut(duration: waiting ? 1.3 : 2.4).repeatForever(autoreverses: true), value: breathing)
        .animation(.easeInOut(duration: 0.45), value: filled)
        .onAppear { breathing = true }
    }
}
