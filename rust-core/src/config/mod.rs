//! Layered configuration management.
//!
//! Loads configuration from multiple sources with precedence:
//! 1. `config/default.toml` — shipped with the app
//! 2. `config/{environment}.toml` — environment-specific overrides
//! 3. Environment variables (`AGENTTALK_*`) — runtime overrides
//!
//! The environment is determined by `AGENTTALK_ENV` (defaults to "development").
//! Uses the `config` crate for TOML deserialization and layered merging.

use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct AppConfig {
    pub app: AppSection,
    pub model: ModelSection,
    pub audio: AudioSection,
    pub inference: InferenceSection,
    pub hotkey: HotkeySection,
    pub paste: PasteSection,
    pub logging: LoggingSection,
    pub features: FeaturesSection,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AppSection {
    pub name: String,
    pub version: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ModelSection {
    pub directory: String,
    pub filename: String,
    pub auto_download: bool,
    pub idle_unload_seconds: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AudioSection {
    pub sample_rate: u32,
    pub channels: u8,
    pub max_duration_seconds: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct InferenceSection {
    pub n_threads: i32,
    pub language: String,
    pub sampling: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct HotkeySection {
    pub mechanism: String,
    pub modifiers: Vec<String>,
    pub key: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PasteSection {
    pub auto_paste: bool,
    pub restore_clipboard: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct LoggingSection {
    pub level: String,
    pub file: String,
    pub format: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FeaturesSection {
    pub vad_enabled: bool,
    pub coreml_enabled: bool,
}

impl AppConfig {
    /// Load configuration from the layered sources.
    /// Not yet wired — returns defaults during infrastructure phase.
    pub fn load() -> anyhow::Result<Self> {
        todo!("Configuration loading — infrastructure phase")
    }
}
