import AppKit
import SwiftUI
import Carbon.HIToolbox

// Carbon hotkey state
private var gHotKeyRef: EventHotKeyRef?
private let gHotKeySignature: OSType = OSType(0x4147544B) // "ATK"

// Global C callback for Carbon hotkey events
private func hotkeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }

    var hkID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )

    guard err == noErr, hkID.signature == gHotKeySignature else { return noErr }

    let kind = GetEventKind(event)
    DispatchQueue.main.async {
        let model = AppModel.shared
        if kind == UInt32(kEventHotKeyPressed) {
            print("[AgentTalk] Carbon hotkey DOWN")
            model.startDictation()
        } else {
            print("[AgentTalk] Carbon hotkey UP")
            model.stopDictation()
        }
    }

    return noErr
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var localMonitor: Any?
    private var isRecordingHotkey = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unbuffered stdout so logs appear immediately when redirected
        setvbuf(stdout, nil, _IONBF, 0)
        NSApp.setActivationPolicy(.regular)
        print("[AgentTalk] Launching...")

        AppModel.shared.launch()
        setupMenuBar()
        registerCarbonHotkey()
        setupLocalMonitor()

        print("[AgentTalk] Ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let ref = gHotKeyRef { UnregisterEventHotKey(ref) }
    }

    /// Carbon RegisterEventHotKey — works globally WITHOUT accessibility permission.
    private func registerCarbonHotkey() {
        var hotKeyID = EventHotKeyID(signature: gHotKeySignature, id: 1)

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &gHotKeyRef
        )

        if status == noErr {
            print("[AgentTalk] Carbon hotkey registered (⌘⇧D)")
        } else {
            print("[AgentTalk] Carbon hotkey registration failed: \(status)")
        }

        var specs: [EventTypeSpec] = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        // C function pointer — no captures allowed
        let handler: EventHandlerUPP = { _, event, _ in
            hotkeyEventHandler(nil, event, nil)
        }

        var installed: EventHandlerRef?
        let installErr = specs.withUnsafeMutableBufferPointer { buf in
            InstallEventHandler(
                GetEventDispatcherTarget(),
                handler,
                2,
                buf.baseAddress,
                nil,
                &installed
            )
        }

        if installErr == noErr {
            print("[AgentTalk] Carbon event handler installed")
        } else {
            print("[AgentTalk] Carbon event handler install failed: \(installErr)")
        }
    }

    /// Fallback local monitor — only fires when our app is focused.
    private func setupLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleLocalKeyEvent(event)
            return event
        }
    }

    private func handleLocalKeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), flags.contains(.shift), !flags.contains(.control), !flags.contains(.option),
              event.keyCode == 2 else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let model = AppModel.shared

            switch event.type {
            case .keyDown:
                guard !self.isRecordingHotkey else { return }
                self.isRecordingHotkey = true
                print("[AgentTalk] Local hotkey DOWN")
                model.startDictation()

            case .keyUp:
                guard self.isRecordingHotkey else { return }
                self.isRecordingHotkey = false
                print("[AgentTalk] Local hotkey UP")
                model.stopDictation()

            default:
                break
            }
        }
    }

    /// Menu bar: Start Dictation + Quit.
    /// Same code path as the hotkey.
    private func setupMenuBar() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit AgentTalk",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        let startItem = NSMenuItem(
            title: "Start Dictation",
            action: #selector(menuStartDictation),
            keyEquivalent: "d"
        )
        startItem.keyEquivalentModifierMask = [.command, .shift]
        startItem.target = self
        editMenu.addItem(startItem)

        let stopItem = NSMenuItem(
            title: "Stop Dictation",
            action: #selector(menuStopDictation),
            keyEquivalent: ""
        )
        stopItem.target = self
        editMenu.addItem(stopItem)

        NSApp.mainMenu = mainMenu
        print("[AgentTalk] Menu installed")
    }

    @objc private func menuStartDictation() {
        print("[AgentTalk] Menu: Start Dictation")
        AppModel.shared.startDictation()
    }

    @objc private func menuStopDictation() {
        print("[AgentTalk] Menu: Stop Dictation")
        AppModel.shared.stopDictation()
    }
}
