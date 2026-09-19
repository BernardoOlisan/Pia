import Carbon.HIToolbox
import Foundation
import PiaVoiceCore

/// The system-wide shortcuts. Carbon's hot keys need no Accessibility permission and only see the
/// exact key combinations registered here.
///
/// There are two: the take that replaces what is in the clipboard, and the take that appends to it.
/// Carbon hands the handler the id of the key that was pressed, so one handler serves both.
@MainActor
final class GlobalHotkey {
    private var registered: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    nonisolated(unsafe) private static var actions: [UInt32: () -> Void] = [:]

    /// The shortcuts another app already owns. They are skipped, not fatal: one of two is still useful.
    private(set) var rejected: [HotkeySpec] = []

    /// Nil when the event handler can't be installed, or when no shortcut at all could be registered.
    init?(_ bindings: [(spec: HotkeySpec, action: () -> Void)]) {
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let which = id.id
            DispatchQueue.main.async { GlobalHotkey.actions[which]?() }
            return noErr
        }, 1, &pressed, nil, &handler)
        guard installed == noErr else { return nil }

        for (index, binding) in bindings.enumerated() {
            let number = UInt32(index + 1)
            let id = EventHotKeyID(signature: OSType(0x5049_4156), id: number) // "PIAV"
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(binding.spec.keyCode, binding.spec.modifiers, id,
                                   GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                Self.actions[number] = binding.action
                registered.append(ref)
            } else {
                rejected.append(binding.spec)
            }
        }

        guard !registered.isEmpty else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }
}
