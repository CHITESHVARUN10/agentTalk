pub mod audio;
pub mod config;
pub mod hotkey;
pub mod inference;
pub mod model_manager;
pub mod state;
pub mod system;

use tracing::info;

#[swift_bridge::bridge]
mod ffi {
    enum AppState {
        Idle,
        Recording,
        Processing,
        TranscriptReady,
        Error,
    }

    extern "Rust" {
        fn verify_bridge() -> String;
        fn initialize_core() -> bool;
        fn get_app_state() -> AppState;
        fn start_recording() -> bool;
        fn stop_recording() -> Vec<u8>;
        fn get_transcript() -> String;
        fn copy_to_clipboard();
        fn paste_into_frontmost_app();
    }

    extern "Swift" {
        fn on_state_changed(state: AppState);
        fn on_transcript_ready(text: String);
        fn on_error(message: String);
    }
}

fn verify_bridge() -> String {
    "bridge ok".to_string()
}

fn initialize_core() -> bool {
    info!("AgentTalk core initializing");
    info!("AgentTalk core initialized");
    true
}

fn get_app_state() -> ffi::AppState {
    ffi::AppState::Idle
}

fn start_recording() -> bool {
    info!("Recording started");
    true
}

fn stop_recording() -> Vec<u8> {
    info!("Recording stopped");
    Vec::new()
}

fn get_transcript() -> String {
    String::new()
}

fn copy_to_clipboard() {
    info!("Copied to clipboard");
}

fn paste_into_frontmost_app() {
    info!("Pasted into frontmost app");
}
