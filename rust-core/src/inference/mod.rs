//! Whisper inference wrapper.
//!
//! Manages the whisper model lifecycle and transcription pipeline.
//!
//! Responsibilities:
//! - Model loading and unloading
//! - Inference engine warm-up (pre-heat Metal pipeline)
//! - Running `whisper_full()` on audio buffers
//! - Segment extraction and text assembly
//! - Metal backend detection and capability reporting

pub mod engine;
