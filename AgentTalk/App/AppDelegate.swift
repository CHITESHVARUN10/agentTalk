import AppKit
import SwiftUI
import Carbon.HIToolbox

// Carbon hotkey state
private var gHotKeyRef: EventHotKeyRef?
private let gHotKeySignature: OSType = OSType(0x4147544B) // "ATK"

// Held-state tracking — suppress auto-repeat
// The flag lives outside AppDelegate so the C callback can touch it.
// Only accessed from the main queue (all hotkey events hop there).
private var gHotkeyHeld = false

/// Resets the hotkey held-state. Called when a dictation cycle completes
/// (dismiss/close) so a stale held flag can't swallow the next press.
func resetHotkeyHeldState() {
    DispatchQueue.main.async {
        if gHotkeyHeld {
            print("[Hotkey] State reset (was held)")
        }
        gHotkeyHeld = false
    }
}

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
    let isPress = (kind == UInt32(kEventHotKeyPressed))

    DispatchQueue.main.async {
        let model = AppModel.shared

        if isPress {
            // Toggle ON the first key-down only.
            // Suppress auto-repeat presses while the key is held.
            guard !gHotkeyHeld else {
                print("[Hotkey] Ignored repeat press (already held)")
                return
            }
            gHotkeyHeld = true
            print("[Hotkey] DOWN — toggle dictation")
            model.toggleDictation()
        } else {
            // Release: clear the held flag, do NOT toggle.
            // A quick tap = start on DOWN, nothing on UP.
            // The next tap's DOWN toggles stop.
            gHotkeyHeld = false
            print("[Hotkey] UP — release (no toggle)")
        }
    }

    return noErr
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unbuffered stdout so logs appear immediately when redirected
        setvbuf(stdout, nil, _IONBF, 0)
        NSApp.setActivationPolicy(.regular)
        print("[AgentTalk] Launching...")

        AppModel.shared.launch()
        registerCarbonHotkey()

        print("[AgentTalk] Ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let ref = gHotKeyRef { UnregisterEventHotKey(ref) }
        gHotkeyHeld = false
    }

    /// Carbon RegisterEventHotKey — the SINGLE hotkey path.
    /// Works globally without accessibility permission.
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
}
