import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AgentTalk] App launched — infrastructure phase")

        // Set activation policy: accessory = menu bar app (no dock icon)
        NSApp.setActivationPolicy(.accessory)
    }
}
