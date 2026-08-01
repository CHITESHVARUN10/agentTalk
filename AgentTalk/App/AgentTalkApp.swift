import SwiftUI

@main
struct AgentTalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("AgentTalk", systemImage: "mic.fill") {
            Button("Toggle Dictation (⌘⇧D)") {
                AppModel.shared.toggleDictation()
            }
            Divider()
            Button("Live Preview") {
                AppModel.shared.toggleLivePreview()
            }
            Divider()
            Text("Pill Position")
            Button("Default (Bottom)") {
                AppModel.shared.setDefaultPosition()
            }
            Button("Custom (Draggable)…") {
                AppModel.shared.startPositionPlacement()
            }
            Button("Cancel Placement") {
                AppModel.shared.cancelPositionPlacement()
            }
            Button("Reset Custom Position") {
                AppModel.shared.resetCustomPosition()
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
