import AppKit
import Carbon

/// Global show/hide hotkey via Carbon `RegisterEventHotKey`.
/// Chosen deliberately over an event tap: Carbon hotkeys need NO
/// Accessibility permission, so the user never sees a permission prompt
/// just to summon their notes (register §6.2).
///
/// Default: Control + Option + Command + Space.
final class HotKeyManager {

    static let shared = HotKeyManager()

    var onToggle: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    func register() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onToggle?()
            return noErr
        }, 1, &eventType, selfPointer, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x534E5453), id: 1) // 'SNTS'
        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        let status = RegisterEventHotKey(UInt32(kVK_Space), modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            // Non-fatal: sliver, menu-bar icon and reopen still summon the
            // panel. Logged so a taken/conflicting combo is diagnosable
            // instead of the hotkey silently doing nothing.
            print("SilverNotes: hotkey registration failed with OSStatus \(status) — ⌃⌥⌘Space may be taken by another app")
            hotKeyRef = nil
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
    }
}
