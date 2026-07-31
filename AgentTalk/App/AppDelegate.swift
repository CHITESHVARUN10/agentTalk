import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var eventMonitor: Any?
    private var isRecordingHotkey = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        print("[AgentTalk] Launching...")

        AppModel.shared.launch()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        print("[AgentTalk] Ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.command, .shift], event.keyCode == 2 else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let model = AppModel.shared

            switch event.type {
            case .keyDown:
                guard !self.isRecordingHotkey, model.phase == .Ready else { return }
                self.isRecordingHotkey = true
                model.handleHotkeyPress()

            case .keyUp:
                guard self.isRecordingHotkey, model.phase == .Recording else { return }
                self.isRecordingHotkey = false
                model.handleHotkeyRelease()

            default:
                break
            }
        }
    }
}
