/// whisper-rs context and state management.
///
/// Wraps `WhisperContext` from whisper-rs, providing a higher-level
/// API for model lifecycle and inference.
///
/// Supports both whole-buffer transcription (`transcribe`) and live
/// incremental transcription (`transcribe_chunk`) with a persistent
/// `WhisperState` that carries context across chunks.
///
/// Optimized for short dictation: English only, greedy sampling,
/// no timestamps, no translation, no language detection.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

pub struct InferenceEngine {
    model_path: PathBuf,
    context: Option<Arc<Mutex<whisper_rs::WhisperContext>>>,
    // Persistent decode state — carries context across chunks. !Send, owned
    // by the inference worker thread (same thread that owns the engine).
    decode_state: Option<whisper_rs::WhisperState>,
    // Number of segments extracted from decode_state so far.
    extracted_segments: i32,
    state: InferenceState,
    n_threads: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InferenceState {
    NotLoaded,
    Loading,
    Warming,
    Ready,
    Running,
    Error,
}

impl InferenceEngine {
    pub fn new(model_path: PathBuf, n_threads: i32) -> Self {
        Self {
            model_path,
            context: None,
            decode_state: None,
            extracted_segments: 0,
            state: InferenceState::NotLoaded,
            n_threads,
        }
    }

    pub fn load(&mut self) -> anyhow::Result<()> {
        if self.context.is_some() {
            tracing::info!("Model already loaded");
            return Ok(());
        }

        self.state = InferenceState::Loading;
        tracing::info!(model = %self.model_path.display(), "Loading whisper model");

        let start = std::time::Instant::now();

        if !self.model_path.exists() {
            anyhow::bail!("Model file not found: {}", self.model_path.display());
        }

        let ctx = whisper_rs::WhisperContext::new_with_params(
            self.model_path.to_str().unwrap(),
            whisper_rs::WhisperContextParameters {
                use_gpu: true,
                ..Default::default()
            },
        )?;

        let elapsed = start.elapsed();
        tracing::info!(duration_ms = elapsed.as_millis(), "Model loaded");

        self.context = Some(Arc::new(Mutex::new(ctx)));

        // Warm up
        self.state = InferenceState::Warming;
        self.warmup()?;

        self.state = InferenceState::Ready;
        Ok(())
    }

    fn warmup(&mut self) -> anyhow::Result<()> {
        let silence = vec![0.0f32; 16000];
        if let Ok(text) = self.transcribe_core(&silence) {
            tracing::info!(output = %text.trim(), "Warmup complete");
        }
        Ok(())
    }

    /// Whole-buffer transcription (fallback / warmup / short recordings).
    pub fn transcribe(&mut self, samples: &[f32]) -> anyhow::Result<String> {
        if self.context.is_none() {
            anyhow::bail!("Model not loaded");
        }

        self.state = InferenceState::Running;
        let start = std::time::Instant::now();
        let duration = samples.len() as f32 / 16000.0;

        tracing::info!(samples = samples.len(), duration_secs = %duration, "Starting inference");

        let result = self.transcribe_core(samples);

        let elapsed = start.elapsed();

        match &result {
            Ok(text) => {
                let rtf = elapsed.as_secs_f64() / duration as f64;
                tracing::info!(elapsed_ms = elapsed.as_millis(), rtf = %rtf, chars = text.len(), "Inference complete");
                self.state = InferenceState::Ready;
            }
            Err(e) => {
                self.state = InferenceState::Error;
                tracing::error!(?e, "Inference failed");
            }
        }

        result
    }

    /// Live chunk transcription with a persistent decode state.
    ///
    /// Returns `Some(new_text)` with ONLY the segments produced by this chunk
    /// (previous chunks' segments are skipped via `extracted_segments`).
    /// Returns `None` when the chunk produced no new text.
    pub fn transcribe_chunk(&mut self, samples: &[f32]) -> anyhow::Result<Option<String>> {
        let ctx = self
            .context
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Context not loaded"))?
            .clone();

        // Persistent state carries context across chunks (no_context = false).
        if self.decode_state.is_none() {
            tracing::info!("Creating persistent decode state");
            let ctx_guard = ctx.lock().unwrap();
            self.decode_state = Some(ctx_guard.create_state()?);
            self.extracted_segments = 0;
        }

        let mut params = whisper_rs::FullParams::new(whisper_rs::SamplingStrategy::Greedy { best_of: 1 });
        params.set_n_threads(self.n_threads);
        params.set_language(Some("en"));
        params.set_no_context(false); // carry context from previous chunks
        params.set_no_timestamps(true);

        self.state = InferenceState::Running;
        let start = std::time::Instant::now();

        let state = self.decode_state.as_mut().expect("state just created");
        state.full(params, samples)?;

        let total = state.full_n_segments()?;
        let mut new_text = String::new();
        let mut new_count = 0;

        for i in self.extracted_segments..total {
            if let Ok(seg_text) = state.full_get_segment_text(i) {
                new_text.push_str(&seg_text);
                new_count += 1;
            }
        }
        self.extracted_segments = total;

        let elapsed = start.elapsed();
        tracing::info!(
            elapsed_ms = elapsed.as_millis(),
            new_segments = new_count,
            new_chars = new_text.len(),
            "Chunk transcribed"
        );

        self.state = InferenceState::Ready;

        let trimmed = new_text.trim().to_string();
        if trimmed.is_empty() {
            Ok(None)
        } else {
            Ok(Some(trimmed))
        }
    }

    /// Drop the persistent decode state — start a fresh session.
    pub fn reset_decode_state(&mut self) {
        if self.decode_state.is_some() {
            tracing::info!("Resetting decode state");
            self.decode_state = None;
            self.extracted_segments = 0;
        }
    }

    fn transcribe_core(&self, samples: &[f32]) -> anyhow::Result<String> {
        let ctx = self
            .context
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Context not loaded"))?;
        let ctx = ctx.lock().unwrap();

        let mut params = whisper_rs::FullParams::new(whisper_rs::SamplingStrategy::Greedy { best_of: 1 });
        params.set_n_threads(self.n_threads);
        params.set_language(Some("en"));

        let mut state = ctx.create_state()?;

        state.full(params, samples)?;

        let segment_count = state.full_n_segments()?;
        let mut transcript = String::new();

        for i in 0..segment_count {
            if let Ok(seg_text) = state.full_get_segment_text(i) {
                transcript.push_str(&seg_text);
            }
        }

        Ok(transcript.trim().to_string())
    }

    pub fn is_loaded(&self) -> bool {
        matches!(self.state, InferenceState::Ready | InferenceState::Running)
    }

    pub fn state(&self) -> InferenceState {
        self.state
    }

    pub fn unload(&mut self) {
        tracing::info!("Unloading model");
        self.decode_state = None;
        self.extracted_segments = 0;
        self.context = None;
        self.state = InferenceState::NotLoaded;
    }
}
