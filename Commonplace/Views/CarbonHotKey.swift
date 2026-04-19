import AppKit
import Carbon.HIToolbox

/// System-wide hotkey backed by Carbon's `RegisterEventHotKey`.
///
/// Unlike `NSEvent.addGlobalMonitorForEvents`, this fires in every app context
/// without requiring Accessibility or Input Monitoring permission — critical
/// for a menu-bar-only app that has no windows on first launch.
final class CarbonHotKey {
    private let id: UInt32
    private var ref: EventHotKeyRef?

    private static var nextID: UInt32 = 1
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var eventHandlerInstalled = false

    /// `keyCode` uses `kVK_ANSI_*` values. `modifiers` uses Carbon modifier
    /// bits (`cmdKey`, `controlKey`, `optionKey`, `shiftKey`). Returns nil
    /// if the combo is already owned by another process.
    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        Self.installEventHandlerIfNeeded()

        let id = Self.nextID
        Self.nextID += 1

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let ref = hotKeyRef else {
            CaptureLog.warning("[CarbonHotKey] RegisterEventHotKey failed (status=\(status))")
            return nil
        }

        self.id = id
        self.ref = ref
        Self.handlers[id] = handler
    }

    func unregister() {
        if let ref = ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        Self.handlers.removeValue(forKey: id)
    }

    deinit { unregister() }

    // 'CMMP' — unique-ish app signature so we don't collide with other libs.
    private static let signature: OSType = {
        let chars: [UInt8] = [0x43, 0x4D, 0x4D, 0x50]
        return (OSType(chars[0]) << 24) | (OSType(chars[1]) << 16) | (OSType(chars[2]) << 8) | OSType(chars[3])
    }()

    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event = event else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return noErr }
                CarbonHotKey.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}
