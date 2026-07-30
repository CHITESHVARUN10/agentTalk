/// Session state machine.
///
/// The single source of truth for the dictation session lifecycle:
///
/// ```text
/// Idle → Recording → Processing → TranscriptReady → Idle
///                                       ↓
///                                     Error → Idle
/// ```
///
/// The state machine is owned by the Rust core and observed by
/// the SwiftUI layer via FFI callbacks (`on_state_changed`).
/// The UI never mutates state directly — it calls into Rust APIs
/// (`start_recording`, `stop_recording`) which drive transitions.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionState {
    Idle,
    Recording,
    Processing,
    TranscriptReady,
    Error,
}

pub struct StateMachine {
    // state: SessionState,
    // transcript: Option<String>,
    // recording_buffer: Option<Vec<f32>>,
}
