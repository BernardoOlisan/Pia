import AppKit
import Observation
import SwiftUI

/// What the island shows while dictating. Updated on the main thread by the dictation session.
@Observable
public final class DictationModel {
    public enum Phase: Equatable { case hidden, recording, transcribing, done, failed }

    public var phase = Phase.hidden
    /// This month's dictation cost, live while recording: "$0.004". Hidden unless asked for.
    public var cost = "$0.000"
    /// Double-clicking the island shows the cost beside the waveform; double-clicking again hides it.
    public var showCost = false
    /// 0...1 microphone loudness, for the bar being drawn right now.
    public var level: Float = 0
    /// How long this dictation has been running.
    public var elapsed: TimeInterval = 0
    /// This take appends to the last one instead of replacing it. Shown as a "+" beside the clock.
    public var appending = false
    /// The last couple of seconds of loudness, oldest first.
    public var samples: [Float] = []
    /// One click stops the recording.
    public var onTap: (() -> Void)?

    public init() {}

    /// Called by the session on every tick.
    public func push(level: Float) {
        self.level = level
        samples.append(level)
        if samples.count > Waveform.capacity { samples.removeFirst(samples.count - Waveform.capacity) }
    }

    /// A new take starts clean, and that includes the cost: it is revealed for the take you are
    /// looking at, never left on for the next one.
    public func reset() {
        samples = []
        level = 0
        elapsed = 0
        showCost = false
        appending = false
    }
}

/// The dictation island, drawn the way Voice Memos draws a recording: the live waveform on one side of
/// the notch, the elapsed time on the other, both in red. The cost is not shown unless you ask for it.
public struct DictationView: View {
    @Bindable var model: DictationModel
    var stage: IslandStage

    /// Room for the widest side: the inset, the waveform, and the cost when it is revealed.
    public static let maxSideWidth: CGFloat = 20 + slotWidth + 7 + costWidth
    static let costWidth: CGFloat = 46
    /// The waveform and the clock are the same width, one each side of the notch.
    static let slotWidth: CGFloat = 38
    /// The "+" sits outside the clock's slot, so turning it on never squeezes the digits.
    static let plusWidth: CGFloat = 10

    public init(model: DictationModel, stage: IslandStage) {
        self.model = model
        self.stage = stage
    }

    private var geometry: NotchGeometry { stage.geometry }
    private var visible: Bool { model.phase != .hidden }
    private var costVisible: Bool { model.showCost && (model.phase == .recording || model.phase == .transcribing) }

    /// The side that holds the sound, and the side that holds the state.
    private var leadingWidth: CGFloat {
        guard visible else { return 0 }
        var width = geometry.contentInset
        if costVisible { width += Self.costWidth + 7 }
        width += model.phase == .recording ? Self.slotWidth : 14
        return width
    }

    private var trailingWidth: CGFloat {
        guard visible else { return 0 }
        var width = Self.slotWidth + geometry.contentInset
        if appendingVisible { width += Self.plusWidth }
        return width
    }

    private var appendingVisible: Bool { model.appending && model.phase == .recording }

    private var islandWidth: CGFloat {
        visible ? leadingWidth + geometry.middleGap + trailingWidth : geometry.foldedWidth
    }

    /// The island is centred on the notch, not on itself, so the wider side grows outwards.
    private var alignmentOffset: CGFloat {
        geometry.style == .notch ? (trailingWidth - leadingWidth) / 2 : 0
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            island
                .frame(width: islandWidth, height: geometry.barHeight)
                .offset(x: alignmentOffset, y: geometry.topGap)
                // A notch island folds into the notch. A capsule has nothing to fold into, so it
                // drops in and lifts away instead.
                .scaleEffect(visible || geometry.style == .notch ? 1 : 0.8, anchor: .top)
                .opacity(visible || geometry.style == .notch ? 1 : 0)
                .offset(y: visible || geometry.style == .notch ? 0 : -6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(IslandMotion.morph, value: model.phase)
        .animation(IslandMotion.reveal, value: costVisible)
        .animation(IslandMotion.reveal, value: appendingVisible)
    }

    private var island: some View {
        ZStack(alignment: .top) {
            IslandShape(inverseRadius: geometry.inverseRadius, notchHeight: geometry.notchHeight, style: geometry.style)
                .fill(Color(white: 0))
                .shadow(color: .black.opacity(geometry.style == .capsule ? 0.32 : 0), radius: 7, y: 2)
            HStack(spacing: 0) {
                leading.frame(width: leadingWidth, alignment: .leading)
                Color.clear.frame(width: geometry.middleGap)
                trailing.frame(width: trailingWidth, alignment: .trailing)
            }
            .frame(height: geometry.barHeight)
            .opacity(visible ? 1 : 0)
            .animation(IslandMotion.content, value: visible)
        }
        .clipShape(IslandShape(inverseRadius: geometry.inverseRadius, notchHeight: geometry.notchHeight, style: geometry.style))
        .contentShape(Rectangle())
        .overlay(ClickCatcher(onClick: { model.onTap?() },
                              onDoubleClick: { model.showCost.toggle() }))
    }

    /// The sound side.
    @ViewBuilder private var leading: some View {
        HStack(spacing: 7) {
            if costVisible {
                Text(model.cost)
                    .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.4))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: Self.costWidth, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            if model.phase == .recording {
                Waveform(samples: model.samples, color: Palette.red)
                    .frame(width: Self.slotWidth, height: geometry.waveHeight)
                    .transition(.opacity.combined(with: .scale(scale: 0.7, anchor: .leading)))
            } else {
                Color.clear.frame(width: 14)
            }
        }
        .padding(.leading, geometry.contentInset)
    }

    /// The state side.
    @ViewBuilder private var trailing: some View {
        ZStack(alignment: .trailing) {
            switch model.phase {
            case .recording:
                // "+ 0:07": this take is being added to what you already said.
                HStack(spacing: 3) {
                    if appendingVisible {
                        Text("+")
                            .font(.system(size: 11.5, weight: .regular, design: .rounded))
                            .foregroundStyle(Palette.red)
                            .fixedSize()
                            .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .trailing)))
                    }
                    ElapsedLabel(seconds: model.elapsed)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            case .transcribing:
                Spinner().transition(.opacity.combined(with: .scale(scale: 0.5)))
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Palette.green)
                    .transition(.opacity.combined(with: .scale(scale: 0.5)))
            case .failed:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10.5, weight: .heavy))
                    .foregroundStyle(Palette.orange)
                    .transition(.opacity.combined(with: .scale(scale: 0.5)))
            case .hidden:
                Color.clear
            }
        }
        .padding(.trailing, geometry.contentInset)
    }

}

/// One click and two clicks, told apart properly.
///
/// SwiftUI fires a single tap even when a second one is on its way, and here a single click stops the
/// recording — so a double click would end the dictation before it ever showed the cost. AppKit can
/// make the single wait for the double to fail, which is exactly what is needed.
struct ClickCatcher: NSViewRepresentable {
    var onClick: () -> Void
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let double = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.double(_:)))
        double.numberOfClicksRequired = 2
        let single = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.single(_:)))
        single.numberOfClicksRequired = 1
        single.delaysPrimaryMouseButtonEvents = false
        view.addGestureRecognizer(double)
        view.addGestureRecognizer(single)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onClick = onClick
        context.coordinator.onDoubleClick = onDoubleClick
    }

    func makeCoordinator() -> Coordinator { Coordinator(onClick: onClick, onDoubleClick: onDoubleClick) }

    final class Coordinator: NSObject {
        var onClick: () -> Void
        var onDoubleClick: () -> Void
        private var pending: DispatchWorkItem?

        init(onClick: @escaping () -> Void, onDoubleClick: @escaping () -> Void) {
            self.onClick = onClick
            self.onDoubleClick = onDoubleClick
        }

        @objc func single(_ sender: NSClickGestureRecognizer) {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onClick() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        }

        @objc func double(_ sender: NSClickGestureRecognizer) {
            pending?.cancel()
            pending = nil
            onDoubleClick()
        }
    }
}
