import AppKit
import Carbon.HIToolbox

/// System-wide keyboard shortcuts via Carbon's RegisterEventHotKey, which needs no Accessibility
/// or Input Monitoring permission.
public final class HotKeyCenter {
    public struct Shortcut {
        public var keyCode: UInt32
        public var modifiers: UInt32
        public var display: String
        public var description: String
        public var action: () -> Void
    }

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?
    public private(set) var failed: [String] = []

    public init() {}

    deinit { unregisterAll() }

    /// ⌃⌥⌘ is unlikely to clash with other apps.
    public static let modifiers = UInt32(controlKey | optionKey | cmdKey)

    public static func standardShortcuts(warmer: @escaping () -> Void, cooler: @escaping () -> Void,
                                         toggle: @escaping () -> Void) -> [Shortcut] {
        [
            Shortcut(keyCode: UInt32(kVK_ANSI_Equal), modifiers: modifiers, display: "\u{2303}\u{2325}\u{2318}=", description: "5% warmer", action: warmer),
            Shortcut(keyCode: UInt32(kVK_ANSI_Minus), modifiers: modifiers, display: "\u{2303}\u{2325}\u{2318}-", description: "5% cooler", action: cooler),
            Shortcut(keyCode: UInt32(kVK_ANSI_0), modifiers: modifiers, display: "\u{2303}\u{2325}\u{2318}0", description: "Turn NightMode on or off", action: toggle),
        ]
    }

    public func register(_ shortcuts: [Shortcut]) {
        unregisterAll()
        installHandlerIfNeeded()
        for (index, shortcut) in shortcuts.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4E_4D_44_45), id: id) // 'NMDE'
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[id] = shortcut.action
            } else {
                failed.append(shortcut.display)
            }
        }
    }

    public func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
        failed.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { center.actions[hotKeyID.id]?() }
            return noErr
        }, 1, &spec, selfPointer, &handler)
    }
}
