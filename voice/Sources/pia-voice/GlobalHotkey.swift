import Carbon.HIToolbox
import Foundation
import PiaVoiceCore

/// A system-wide shortcut. Carbon's hot keys need no Accessibility permission and only see this one key combination.
@MainActor
final class GlobalHotkey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    nonisolated(unsafe) private static var action: (() -> Void)?

    /// Nil when the shortcut can't be registered (for example, another app already took it).
    init?(_ spec: HotkeySpec, action: @escaping () -> Void) {
        Self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotkey.action?() }
            return noErr
        }, 1, &pressed, nil, &handler)
        guard installed == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x5049_4156), id: 1) // "PIAV"
        let registered = RegisterEventHotKey(spec.keyCode, spec.modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        guard registered == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }
}
