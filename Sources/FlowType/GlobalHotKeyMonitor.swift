import AppKit
import Carbon

package enum GlobalHotKeyAction: Equatable {
    case localDictation
    case agentRewrite
}

package struct GlobalHotKeyShortcut: Equatable {
    package let identifier: UInt32
    package let keyCode: UInt32
    package let modifiers: UInt32
    package let action: GlobalHotKeyAction

    package static let localDictation = GlobalHotKeyShortcut(
        identifier: 1,
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        action: .localDictation
    )
    package static let agentRewrite = GlobalHotKeyShortcut(
        identifier: 2,
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey | shiftKey),
        action: .agentRewrite
    )
}

@MainActor
final class GlobalHotKeyMonitor {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private let shortcuts: [UInt32: GlobalHotKeyShortcut]
    private let action: (GlobalHotKeyAction) -> Void

    init(
        shortcuts: [GlobalHotKeyShortcut] = [
            .localDictation,
            .agentRewrite,
        ],
        action: @escaping (GlobalHotKeyAction) -> Void
    ) {
        self.shortcuts = Dictionary(
            uniqueKeysWithValues: shortcuts.map { ($0.identifier, $0) }
        )
        self.action = action
        install()
    }

    deinit {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func install() {
        for shortcut in shortcuts.values {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: OSType(0x464C4F57),
                id: shortcut.identifier
            )
            if RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            ) == noErr,
            let hotKeyRef {
                hotKeyRefs.append(hotKeyRef)
            }
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return noErr }
                let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(context).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                guard GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                ) == noErr else {
                    return noErr
                }
                Task { @MainActor in
                    monitor.performAction(for: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandler
        )
    }

    private func performAction(for identifier: UInt32) {
        guard let shortcut = shortcuts[identifier] else { return }
        action(shortcut.action)
    }
}
