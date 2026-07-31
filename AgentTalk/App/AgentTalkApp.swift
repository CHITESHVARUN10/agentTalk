import SwiftUI

@main
struct AgentTalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("AgentTalk", systemImage: "mic.fill") {
            Button("Start Dictation") {
                AppModel.shared.startDictation()
            }
            Button("Stop Dictation") {
                AppModel.shared.stopDictation()
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
