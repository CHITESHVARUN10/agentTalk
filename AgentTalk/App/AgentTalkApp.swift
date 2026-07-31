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
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
