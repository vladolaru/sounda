import AppKit
import Carbon.HIToolbox

final class KeyboardEscapeController {
    private let onQuit: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?

    init(onQuit: @escaping () -> Void) {
        self.onQuit = onQuit
    }

    func start() {
        guard hotKeyRef == nil, localMonitor == nil else {
            return
        }

        registerGlobalHotKey()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            if self.isEscapeHotkey(event) {
                self.quit()
                return nil
            }

            return event
        }
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }

        hotKeyRef = nil
        eventHandlerRef = nil
        localMonitor = nil
    }
}

private extension KeyboardEscapeController {
    static let hotKeySignature = OSType(0x534E_4441) // SNDA
    static let hotKeyID = UInt32(1)

    static let hotKeyHandler: EventHandlerUPP = { _, _, userData in
        guard let userData else {
            return noErr
        }

        let controller = Unmanaged<KeyboardEscapeController>
            .fromOpaque(userData)
            .takeUnretainedValue()
        controller.quit()
        return noErr
    }

    func registerGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handlerRef: EventHandlerRef?
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyHandler,
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )

        guard handlerStatus == noErr else {
            print("Sounda escape hatch warning: could not install keyboard handler (\(handlerStatus)).")
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID)
        var hotKeyRef: EventHotKeyRef?
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_Q),
            UInt32(cmdKey | optionKey | controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard hotKeyStatus == noErr else {
            RemoveEventHandler(handlerRef)
            print("Sounda escape hatch warning: could not register Control-Option-Command-Q (\(hotKeyStatus)).")
            return
        }

        self.eventHandlerRef = handlerRef
        self.hotKeyRef = hotKeyRef
    }

    func isEscapeHotkey(_ event: NSEvent) -> Bool {
        guard event.charactersIgnoringModifiers?.lowercased() == "q" else {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains([.command, .option, .control])
    }

    func quit() {
        DispatchQueue.main.async { [onQuit] in
            onQuit()
        }
    }
}
