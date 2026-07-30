//! Audio capture and preprocessing.
//!
//! Uses `cpal` to capture from the default microphone, resampling to
//! 16kHz mono f32 — the required input format for Whisper.
//!
//! Responsibilities:
//! - Device enumeration and selection
//! - Audio buffer capture via cpal callback
//! - Sample rate conversion (resampling to 16kHz)
//! - Channel reduction (stereo → mono)
//! - Buffer management for handoff to the inference layer
