/// Swift-side implementations of functions that Rust calls back into.
/// These are declared as `extern "Swift"` in the Rust FFI module.
/// Each is annotated with @_cdecl and must match the C calling convention.

func on_state_changed(state: AppState) {
    print("[AgentTalk] State changed: \(state)")
    // TODO: push to SwiftUI @State / @Observable model
}

func on_transcript_ready(text: RustString) {
    print("[AgentTalk] Transcript ready: \(text.toString())")
    // TODO: display in floating panel
}

func on_error(message: RustString) {
    print("[AgentTalk] Error: \(message.toString())")
    // TODO: show error in UI
}
