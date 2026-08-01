//! Layered configuration management.
//!
//! Loads configuration from multiple sources with precedence:
//! 1. `config/default.toml` — shipped with the app
//! 2. `config/{environment}.toml` — environment-specific overrides
//! 3. Environment variables (`AGENTTALK_*`) — runtime overrides

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSection {
    pub name: String,
    pub version: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelSection {
    pub directory: String,
    pub filename: String,
    pub auto_download: bool,
    pub idle_unload_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioSection {
    pub sample_rate: u32,
    pub channels: u8,
    pub max_duration_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InferenceSection {
    pub n_threads: i32,
    pub language: String,
    pub sampling: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HotkeySection {
    pub mechanism: String,
    pub modifiers: Vec<String>,
    pub key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PasteSection {
    pub auto_paste: bool,
    pub restore_clipboard: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoggingSection {
    pub level: String,
    pub file: String,
    pub format: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeaturesSection {
    pub vad_enabled: bool,
    pub coreml_enabled: bool,
}

impl AppConfig {
    pub fn load() -> anyhow::Result<Self> {
        let env = std::env::var("AGENTTALK_ENV").unwrap_or_else(|_| "development".into());

        let default_path = std::path::Path::new("config/default.toml");
        let env_filename = format!("config/{}.toml", env);
        let env_path = std::path::Path::new(&env_filename);

        let builder = config::Config::builder()
            .add_source(config::File::from(default_path).required(true));

        let builder = if env_path.exists() {
            builder.add_source(config::File::from(env_path).required(false))
        } else {
            tracing::warn!("Environment config not found: {:?}", env_path);
            builder
        };

        let cfg: AppConfig = builder
            .add_source(
                config::Environment::with_prefix("AGENTTALK")
                    .separator("__")
                    .ignore_empty(true),
            )
            .build()?
            .try_deserialize()?;

        tracing::info!(env = %env, "Configuration loaded");
        Ok(cfg)
    }

    pub fn default() -> Self {
        Self {
            app: AppSection {
                name: "AgentTalk".into(),
                version: "0.1.0".into(),
            },
            model: ModelSection {
                directory: "~/Library/Application Support/AgentTalk/models".into(),
                filename: "ggml-large-v3-turbo.bin".into(),
                auto_download: true,
                idle_unload_seconds: 360,
            },
            audio: AudioSection {
                sample_rate: 16000,
                channels: 1,
                max_duration_seconds: 300,
            },
            inference: InferenceSection {
                n_threads: 4,
                language: "en".into(),
                sampling: "greedy".into(),
            },
            hotkey: HotkeySection {
                mechanism: "cgeventtap".into(),
                modifiers: vec!["command".into(), "shift".into()],
                key: "d".into(),
            },
            paste: PasteSection {
                auto_paste: false,
                restore_clipboard: true,
            },
            logging: LoggingSection {
                level: "info".into(),
                file: "~/Library/Application Support/AgentTalk/logs/agenttalk.log".into(),
                format: "pretty".into(),
            },
            features: FeaturesSection {
                vad_enabled: false,
                coreml_enabled: false,
            },
        }
    }
}
