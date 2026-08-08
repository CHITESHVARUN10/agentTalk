pub mod audio;
pub mod config;
pub mod hotkey;
pub mod inference;
pub mod model_manager;
pub mod state;
pub mod system;

use std::cell::RefCell;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};

use model_manager::{ModelManager, ModelState};
use state::{AppStateMachine, SessionPhase};

static APP: Mutex<Option<AppStateMachine>> = Mutex::new(None);
thread_local! {
    static AUDIO: RefCell<Option<audio::AudioCapture>> = const { RefCell::new(None) };
}
static INITIALIZED: AtomicBool = AtomicBool::new(false);

// ── Inference worker ─────────────────────────────────────────
// A dedicated long-lived thread owns the Whisper engine (WhisperContext is !Send).
// The watchdog thread sends Unload after idle; stop_recording sends Transcribe jobs.

/// Monotonic seconds of the last dictation activity. Bumped on start/stop/transcribe.
static LAST_ACTIVITY: AtomicU64 = AtomicU64::new(0);

enum InferenceJob {
    TranscribeChunk { samples: Vec<f32>, is_final: bool },
    ResetSession,
    Unload,
}

static INFERENCE_TX: OnceLock<mpsc::Sender<InferenceJob>> = OnceLock::new();

/// Shared with the chunker thread: stop signal when recording ends.
static CHUNKER_STOP_TX: Mutex<Option<mpsc::Sender<()>>> = Mutex::new(None);
/// Number of non-final chunks dispatched this session (for stop-path decisions).
static CHUNKS_SENT: AtomicU64 = AtomicU64::new(0);
/// Set when any chunk job failed — triggers whole-buffer re-transcribe at stop.
static CHUNK_FAILED: AtomicBool = AtomicBool::new(false);
/// Buffer length (samples) at the last chunk send — the final chunk starts here.
static LAST_CHUNK_END: AtomicU64 = AtomicU64::new(0);
/// Samples-per-second (16 kHz) — used by the chunker to size windows.
static SAMPLE_RATE: AtomicU64 = AtomicU64::new(16000);
/// Model path + thread count for engine creation (resolved once at init).
static MODEL_PATH: Mutex<Option<std::path::PathBuf>> = Mutex::new(None);
static N_THREADS: AtomicU64 = AtomicU64::new(4);
/// Live preview toggle (default from config `features.live_preview`).
static LIVE_PREVIEW: AtomicBool = AtomicBool::new(false);

fn with_app<F, R>(f: F) -> R
where
    F: FnOnce(&mut AppStateMachine) -> R,
{
    let mut guard = APP.lock().unwrap();
    let app = guard.as_mut().expect("Core not initialized");
    f(app)
}

fn with_audio<F, R>(f: F) -> R
where
    F: FnOnce(&mut Option<audio::AudioCapture>) -> R,
{
    AUDIO.with(|cell| f(&mut cell.borrow_mut()))
}

#[swift_bridge::bridge]
mod ffi {
    enum AppPhase {
        Idle,
        Preparing,
        Ready,
        Recording,
        Processing,
        TranscriptReady,
        Error,
    }

    enum ModelPhase {
        NotInstalled,
        Downloading,
        Verifying,
        Loading,
        Ready,
        Inference,
        Unloading,
        Error,
    }

    extern "Swift" {
        fn on_state_changed(phase: AppPhase, model: ModelPhase);
        fn on_transcript_ready(text: String);
        fn on_partial_transcript(text: String);
        fn on_error(message: String);
        fn on_download_progress(progress: f32, speed: String, remaining: String);
    }

    extern "Rust" {
        fn verify_bridge() -> String;
        fn initialize_core() -> bool;
        fn is_initialized() -> bool;
        fn start_recording() -> bool;
        fn stop_recording();
        fn get_transcript() -> String;
        fn copy_to_clipboard();
        fn paste_into_frontmost_app();
        fn dismiss_transcript();
        fn retry_recording();
        fn get_audio_level() -> f32;
        fn get_app_phase() -> AppPhase;
        fn get_model_phase() -> ModelPhase;
        fn get_download_progress() -> f32;
        fn get_download_speed() -> String;
        fn get_download_remaining() -> String;
        fn get_error_message() -> String;
        fn get_live_preview_enabled() -> bool;
        fn set_live_preview_enabled(enabled: bool);
    }
}

fn phase_to_ffi(phase: SessionPhase) -> ffi::AppPhase {
    match phase {
        SessionPhase::Idle => ffi::AppPhase::Idle,
        SessionPhase::Preparing => ffi::AppPhase::Preparing,
        SessionPhase::Ready => ffi::AppPhase::Ready,
        SessionPhase::Recording => ffi::AppPhase::Recording,
        SessionPhase::Processing => ffi::AppPhase::Processing,
        SessionPhase::TranscriptReady => ffi::AppPhase::TranscriptReady,
        SessionPhase::Error => ffi::AppPhase::Error,
    }
}

fn model_to_ffi(state: ModelState) -> ffi::ModelPhase {
    match state {
        ModelState::NotInstalled => ffi::ModelPhase::NotInstalled,
        ModelState::Downloading => ffi::ModelPhase::Downloading,
        ModelState::Verifying => ffi::ModelPhase::Verifying,
        ModelState::Loading => ffi::ModelPhase::Loading,
        ModelState::Ready => ffi::ModelPhase::Ready,
        ModelState::Inference => ffi::ModelPhase::Inference,
        ModelState::Unloading => ffi::ModelPhase::Unloading,
        ModelState::Error => ffi::ModelPhase::Error,
    }
}

fn notify_state() {
    let (phase, model) = with_app(|app| (phase_to_ffi(app.phase), model_to_ffi(app.model_state)));
    ffi::on_state_changed(phase, model);
}

fn notify_error(msg: &str) {
    ffi::on_error(msg.to_string());
}

fn verify_bridge() -> String {
    "bridge ok".to_string()
}

fn initialize_core() -> bool {
    if INITIALIZED.swap(true, Ordering::SeqCst) {
        tracing::warn!("Core already initialized");
        return true;
    }

    // Init logging — without this, all tracing! macros are no-ops
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::level_filters::LevelFilter::DEBUG)
        .with_writer(std::io::stderr)
        .try_init();

    tracing::info!("AgentTalk core initializing");

    let config = config::AppConfig::load().unwrap_or_else(|e| {
        tracing::warn!("Failed to load config: {}, using defaults", e);
        config::AppConfig::default()
    });

    let state = AppStateMachine::new(config);
    *APP.lock().unwrap() = Some(state);

    tracing::info!("AgentTalk core initialized");

    // Resolve model path + engine params once for the inference worker.
    {
        let model_dir = with_app(|app| app.config.model.directory.clone());
        let home = dirs::home_dir().unwrap_or_default();
        let dir = model_dir.replacen("~/", &format!("{}/", home.display()), 1);
        let filename = with_app(|app| app.config.model.filename.clone());
        let path = std::path::PathBuf::from(dir).join(&filename);
        *MODEL_PATH.lock().unwrap() = Some(path);

        let threads = with_app(|app| app.config.inference.n_threads);
        N_THREADS.store(threads.max(1) as u64, Ordering::SeqCst);

        let rate = with_app(|app| app.config.audio.sample_rate);
        SAMPLE_RATE.store(rate as u64, Ordering::SeqCst);

        let preview = with_app(|app| app.config.features.live_preview);
        LIVE_PREVIEW.store(preview, Ordering::SeqCst);
    }

    // Dedicated inference thread — owns the Whisper engine for its lifetime.
    let (tx, rx) = mpsc::channel::<InferenceJob>();
    INFERENCE_TX.set(tx).ok();
    thread::spawn(move || inference_worker(rx));

    // Idle watchdog — unloads the model after idle_unload_seconds of no activity.
    let idle_seconds = with_app(|app| app.config.model.idle_unload_seconds);
    thread::spawn(move || idle_watchdog(idle_seconds));

    thread::spawn(|| {
        let mut mgr = match ModelManager::new() {
            Ok(m) => m,
            Err(e) => {
                tracing::error!("Failed to create model manager: {}", e);
                with_app(|app| {
                    app.model_state = ModelState::Error;
                    app.phase = SessionPhase::Error;
                });
                notify_state();
                return;
            }
        };

        if mgr.is_installed() {
            with_app(|app| {
                app.model_state = ModelState::Ready;
                app.phase = SessionPhase::Ready;
            });
            notify_state();
            return;
        }

        with_app(|app| {
            app.model_state = ModelState::Downloading;
            app.phase = SessionPhase::Preparing;
        });
        notify_state();

        let download_result = mgr.download_with_progress(|progress, speed, remaining| {
            with_app(|app| {
                app.set_download_progress(progress, speed.to_string(), remaining.to_string());
            });
            ffi::on_download_progress(progress, speed.to_string(), remaining.to_string());
        });

        with_app(|app| match download_result {
            Ok(()) => {
                app.model_state = ModelState::Ready;
                app.phase = SessionPhase::Ready;
            }
            Err(e) => {
                tracing::error!("Model download failed: {}", e);
                app.model_state = ModelState::Error;
                app.phase = SessionPhase::Error;
            }
        });
        notify_state();
    });

    true
}

fn is_initialized() -> bool {
    INITIALIZED.load(Ordering::SeqCst)
}

/// Long-lived inference thread. Owns the engine (thread-local) so the model
/// stays resident between transcriptions, and unloads on request.
fn inference_worker(rx: mpsc::Receiver<InferenceJob>) {
    thread_local! {
        static ENGINE: RefCell<Option<inference::engine::InferenceEngine>> = const { RefCell::new(None) };
    }

    tracing::info!("Inference worker started");

    // Session-scoped state: stitched transcript + last text for dedupe.
    let mut session_text = String::new();
    let mut last_tail: Option<String> = None;

    while let Ok(job) = rx.recv() {
        match job {
            InferenceJob::ResetSession => {
                tracing::info!("Reset session");
                session_text.clear();
                last_tail = None;
                ENGINE.with(|cell| {
                    if let Some(engine) = cell.borrow_mut().as_mut() {
                        engine.reset_decode_state();
                    }
                });
                CHUNKS_SENT.store(0, Ordering::SeqCst);
                CHUNK_FAILED.store(false, Ordering::SeqCst);
                LAST_CHUNK_END.store(0, Ordering::SeqCst);
            }
            InferenceJob::TranscribeChunk { samples, is_final } => {
                let start = Instant::now();
                tracing::info!(samples = samples.len(), is_final, "Chunk job received");

                let result = ENGINE.with(|cell| {
                    let mut cell = cell.borrow_mut();
                    if cell.is_none() {
                        tracing::info!("Creating inference engine (first use)");
                        let path = MODEL_PATH.lock().unwrap().clone();
                        let threads = N_THREADS.load(Ordering::SeqCst) as i32;
                        *cell = Some(inference::engine::InferenceEngine::new(
                            path.unwrap_or_default(),
                            threads,
                        ));
                    }
                    let engine = cell.as_mut().expect("engine just created");
                    engine.load()?;
                    engine.transcribe_chunk(&samples)
                });

                tracing::info!(elapsed_ms = start.elapsed().as_millis(), "Chunk job done");

                match result {
                    Ok(Some(new_text)) => {
                        // Stitch with dedupe: strip any duplicated tail/head.
                        let merged = dedupe_merge(last_tail.as_deref(), &new_text);
                        tracing::debug!(tail = ?last_tail, next = %new_text, merged = %merged, "dedupe");
                        stitch(&mut session_text, &merged);
                        // Keep a longer tail (≈12 words ≈ 4s) so the 2s overlap
                        // (≈6-9 words) is always fully covered by the dedupe.
                        last_tail = Some(last_words(&new_text, 12));
                        CHUNK_FAILED.store(false, Ordering::SeqCst);

                        // Live preview: push the growing transcript to Swift
                        // (only for non-final chunks; final goes via on_transcript_ready).
                        if !is_final && LIVE_PREVIEW.load(Ordering::SeqCst) {
                            ffi::on_partial_transcript(session_text.trim().to_string());
                        }
                    }
                    Ok(None) => {
                        // No new text this chunk (silence) — fine.
                        CHUNK_FAILED.store(false, Ordering::SeqCst);
                    }
                    Err(e) => {
                        tracing::error!(?e, "Chunk transcription failed");
                        CHUNK_FAILED.store(true, Ordering::SeqCst);
                    }
                }

                if is_final {
                    let final_text = session_text.trim().to_string();
                    tracing::info!(chars = final_text.len(), "Finalizing transcript");

                    with_app(|app| {
                        app.model_state = ModelState::Ready;
                        if final_text.is_empty() {
                            app.set_error("No speech detected".into());
                            notify_error("No speech detected");
                        } else {
                            app.set_transcript(final_text.clone());
                            ffi::on_transcript_ready(final_text);
                        }
                    });
                    notify_state();
                    LAST_ACTIVITY.store(now_secs(), Ordering::SeqCst);

                    // Reset session state for the next dictation.
                    session_text.clear();
                    last_tail = None;
                    CHUNKS_SENT.store(0, Ordering::SeqCst);
                    CHUNK_FAILED.store(false, Ordering::SeqCst);
                }
            }
            InferenceJob::Unload => {
                tracing::info!("Unload job received — freeing model RAM");
                ENGINE.with(|cell| {
                    if let Some(engine) = cell.borrow_mut().as_mut() {
                        engine.unload();
                    }
                });
            }
        }
    }

    tracing::info!("Inference worker exiting");
}

fn stitch(session: &mut String, addition: &str) {
    if addition.is_empty() {
        return;
    }
    let addition = addition.trim();
    if addition.is_empty() {
        return;
    }
    if !session.is_empty() && !session.ends_with(' ') && !session.ends_with('\n') {
        session.push(' ');
    }
    session.push_str(addition);
}

fn norm_word(word: &str) -> String {
    let lower = word.to_ascii_lowercase();
    let trimmed = lower.trim_matches(|c: char| !c.is_alphanumeric());
    trimmed.to_string()
}

fn is_stopword(norm: &str) -> bool {
    matches!(
        norm,
        "the"
            | "a"
            | "an"
            | "and"
            | "or"
            | "so"
            | "but"
            | "of"
            | "to"
            | "in"
            | "on"
            | "is"
            | "it"
            | "we"
            | "you"
            | "for"
            | "as"
            | "at"
            | "be"
            | "are"
            | "was"
            | "by"
            | "with"
            | "that"
            | "this"
            | "from"
            | "have"
            | "has"
            | "had"
            | "will"
            | "would"
            | "can"
            | "do"
            | "does"
            | "did"
            | "not"
            | "no"
            | "if"
            | "then"
            | "okay"
            | "ok"
    )
}

/// Strips any duplicated tail of `prev` from the head of `next` (overlap dedupe).
///
/// The overlap window is ~2s of audio (~6-9 words), but whisper may
/// transcribe slightly more or fewer words of that overlap, and may insert
/// a leading filler word. So we search for the previous tail ANYWHERE in the
/// first few words of `next`, not just as an exact `starts_with` prefix.
fn dedupe_merge(prev_tail: Option<&str>, next: &str) -> String {
    let Some(tail) = prev_tail else {
        return next.trim().to_string();
    };
    let tail = tail.trim();
    let next = next.trim();
    if tail.is_empty() || next.is_empty() {
        return next.to_string();
    }

    let tail_words: Vec<&str> = tail.split_whitespace().collect();
    let next_words: Vec<&str> = next.split_whitespace().collect();
    if tail_words.is_empty() || next_words.is_empty() {
        return next.to_string();
    }

    let tail_norm: Vec<String> = tail_words.iter().map(|w| norm_word(w)).collect();
    let next_norm: Vec<String> = next_words.iter().map(|w| norm_word(w)).collect();

    // Exact prefix (normalized) — the common case with punctuation/case tolerance.
    // Check word-boundary: normalized tail words must equal the first N normalized next words.
    let tail_norm_filtered: Vec<&str> =
        tail_norm.iter().map(|s| s.as_str()).filter(|s| !s.is_empty()).collect();
    let next_norm_filtered: Vec<&str> =
        next_norm.iter().map(|s| s.as_str()).filter(|s| !s.is_empty()).collect();
    if !tail_norm_filtered.is_empty()
        && tail_norm_filtered.len() <= next_norm_filtered.len()
        && next_norm_filtered[..tail_norm_filtered.len()] == tail_norm_filtered[..]
    {
        let skip = tail_words.len();
        if skip >= next_words.len() {
            return String::new();
        }
        return next_words[skip..].join(" ");
    }

    let head_limit = next_words.len().min(12);

    // Search longest suffix of tail matching head of next at any small offset.
    // Normalized comparison; output slicing uses original words.
    for take in (1..=tail_words.len().min(12)).rev() {
        // Policy: require meaningful overlap length
        if take >= 3 {
            // ok
        } else if take == 2 {
            let a = tail_norm[tail_norm.len() - 2].as_str();
            let b = tail_norm[tail_norm.len() - 1].as_str();
            if a.is_empty() || b.is_empty() || is_stopword(a) || is_stopword(b) {
                continue;
            }
            if a.len() < 3 || b.len() < 3 {
                continue;
            }
        } else {
            // take == 1
            let w = tail_norm[tail_norm.len() - 1].as_str();
            if w.is_empty() || w.len() < 6 || is_stopword(w) {
                continue;
            }
            // Single-word dedupe only at head start (offset 0 or 1 for filler)
            // — handled via the start loop below (still offset-tolerant by 1).
        }

        let suffix_norm = &tail_norm[tail_norm.len() - take..];

        for start in 0..head_limit {
            if start + take > next_words.len() {
                break;
            }
            // For single-word, only allow offset 0 or 1
            if take == 1 && start > 1 {
                continue;
            }
            // For all, cap offset to 3 filler words
            if start > 3 {
                continue;
            }
            let window_norm = &next_norm[start..start + take];
            let matches = window_norm.iter().zip(suffix_norm.iter()).all(|(a, b)| {
                if a.is_empty() || b.is_empty() {
                    return false;
                }
                a == b
            });
            if matches {
                return next_words[start + take..].join(" ");
            }
        }
    }

    // No overlap detected — keep both (duplication is safer than data loss).
    next.to_string()
}

/// Returns the last `n` words of `text`.
fn last_words(text: &str, n: usize) -> String {
    let words: Vec<&str> = text.split_whitespace().collect();
    let start = words.len().saturating_sub(n);
    words[start..].join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dedupe_exact_prefix() {
        let tail = "timeline and key";
        let next = "timeline and key milestones we need to hit";
        assert_eq!(dedupe_merge(Some(tail), next), "milestones we need to hit");
    }

    #[test]
    fn dedupe_long_overlap_more_than_3_words() {
        // Overlap is ~2s ≈ 6-9 words; the tail now keeps 12 words so the
        // full overlap must be stripped, not just the last 3.
        let tail = "the new project timeline and key milestones";
        let next = "timeline and key milestones we need to hit by the end of the week";
        assert_eq!(dedupe_merge(Some(tail), next), "we need to hit by the end of the week");
    }

    #[test]
    fn dedupe_with_leading_filler() {
        // whisper may re-segment and start the overlap with a filler word.
        let tail = "we have six weeks to deliver";
        let next = "so we have six weeks to deliver something tangible";
        assert_eq!(dedupe_merge(Some(tail), next), "something tangible");
    }

    #[test]
    fn dedupe_no_overlap_keeps_both() {
        let tail = "completely different sentence";
        let next = "something entirely new";
        assert_eq!(dedupe_merge(Some(tail), next), "something entirely new");
    }

    #[test]
    fn dedupe_filler_then_overlap_at_head() {
        // Filler word, then the overlap appears at the very start.
        let tail = "now we will discuss the action items";
        let next = "okay now we will discuss the action items each member needs";
        assert_eq!(dedupe_merge(Some(tail), next), "each member needs");
    }

    #[test]
    fn dedupe_common_word_inside_head_not_false_positive() {
        // "and" appears mid-head but NOT as a 3+ word overlap — must not cut.
        let tail = "we need to deliver the prototype";
        let next = "the design and engineering teams are aligned";
        assert_eq!(dedupe_merge(Some(tail), next), "the design and engineering teams are aligned");
    }

    #[test]
    fn last_words_keeps_n() {
        assert_eq!(last_words("a b c d e", 3), "c d e");
        assert_eq!(last_words("a b", 3), "a b");
    }

    // ── Paragraph reproduction (reported failures) ──

    #[test]
    fn dedupe_rushed_core_case_variant() {
        let tail = "the rust core remains the";
        let next = "The Rust core remains the rust code remain the same";
        // Normalized case-insensitive exact-prefix dedupe should strip overlap
        let merged = dedupe_merge(Some(tail), next);
        assert_eq!(merged, "rust code remain the same");
    }

    #[test]
    fn dedupe_windows_single_word_dupe() {
        let tail = "into the windows";
        let next = "windows and then with the help of";
        assert_eq!(dedupe_merge(Some(tail), next), "and then with the help of");
    }

    #[test]
    fn dedupe_punct_variant() {
        let tail = "into the windows.";
        let next = "windows and then we must be able";
        assert_eq!(dedupe_merge(Some(tail), next), "and then we must be able");
    }

    #[test]
    fn dedupe_of_of_single_stopword_not_deduped_via_merge() {
        // "of" is a stopword and too short for single-word dedupe — keep both.
        // The true "of of" dupe in the paragraph is better fixed by not
        // duplicating the 2s window textually; but single "of" must not false-positive.
        let tail = "with the help of";
        let next = "of that you the people can download";
        assert_eq!(dedupe_merge(Some(tail), next), "of that you the people can download");
    }

    #[test]
    fn dedupe_cpu_hammer_duplication() {
        let tail = "does not hammer the CPU";
        let next = "does not hammer the cpu or gpu usage";
        assert_eq!(dedupe_merge(Some(tail), next), "or gpu usage");
    }

    #[test]
    fn stitch_inserts_space() {
        let mut s = String::from("currently");
        stitch(&mut s, "we have being like the UI should look");
        assert_eq!(s, "currently we have being like the UI should look");
        assert!(!s.contains("currentlywe"));
    }

    #[test]
    fn stitch_paragraph_spacing_regression() {
        let mut s = String::new();
        stitch(&mut s, "the rust core remains the");
        stitch(&mut s, "the rust code remain the same");
        assert_eq!(s, "the rust core remains the the rust code remain the same");
        assert!(!s.contains("corethe"));
        let mut s2 = String::new();
        stitch(&mut s2, "currently");
        stitch(&mut s2, "we have being like the UI should look");
        assert_eq!(s2, "currently we have being like the UI should look");
        assert!(!s2.contains("currentlywe"));
        let mut s3 = String::new();
        stitch(&mut s3, "rushed core");
        stitch(&mut s3, "the rust code remain");
        assert_eq!(s3, "rushed core the rust code remain");
        assert!(!s3.contains("corethe"));
    }

    #[test]
    fn stitch_trim_and_empty() {
        let mut s = String::from("hello");
        stitch(&mut s, "   ");
        assert_eq!(s, "hello");
        stitch(&mut s, " world ");
        assert_eq!(s, "hello world");
    }
}

/// Chunker thread — every `chunk_seconds` of new audio, copies the last
/// `chunk_seconds + overlap` window from the recording buffer and sends it
/// to the inference worker as a non-final chunk.
fn chunker_thread(stop_rx: mpsc::Receiver<()>, chunk_seconds: u64, overlap_seconds: u64) {
    if chunk_seconds == 0 {
        tracing::info!("Chunker disabled (chunk_seconds = 0)");
        return;
    }

    tracing::info!(chunk_seconds, overlap_seconds, "Chunker started");

    let rate = SAMPLE_RATE.load(Ordering::SeqCst);
    let window = (chunk_seconds + overlap_seconds) as usize * rate as usize;

    loop {
        // Wait for the stop signal OR the chunk interval — whichever comes first.
        let chunk_duration = Duration::from_secs(chunk_seconds);
        let stop_wait = stop_rx.recv_timeout(chunk_duration);
        if stop_wait.is_ok() {
            tracing::info!("Chunker stopped");
            break;
        }

        // Chunk interval elapsed (recv_timeout returned Err(Timeout)).
        let is_recording = with_app(|app| app.phase == SessionPhase::Recording);

        if !is_recording {
            // Not recording anymore — exit.
            tracing::info!("Chunker exiting (not recording)");
            break;
        }

        // Copy the last `window` samples from the ACTIVE buffer (non-destructive).
        // The buffer Arc is registered globally at capture start — the chunker
        // thread reads it directly, NOT via the main-thread thread_local.
        let (chunk, buf_len) = audio::tail_active(window);

        if chunk.is_empty() {
            tracing::debug!("Chunker: empty window, skipping");
            continue;
        }

        CHUNKS_SENT.fetch_add(1, Ordering::SeqCst);
        // The final chunk must start AFTER the audio this chunk covered.
        // `buf_len` is the buffer length at snapshot time = end of this window.
        // (Do NOT subtract the window — that would re-cover already-decoded
        // audio and corrupt the persistent decode state → data loss.)
        LAST_CHUNK_END.store(buf_len, Ordering::SeqCst);
        if let Some(tx) = INFERENCE_TX.get() {
            let _ = tx.send(InferenceJob::TranscribeChunk { samples: chunk, is_final: false });
            bump_activity();
        }
    }
}

/// Polls LAST_ACTIVITY; sends Unload when the model has been idle too long.
fn idle_watchdog(idle_seconds: u64) {
    if idle_seconds == 0 {
        tracing::info!("Idle watchdog disabled (idle_unload_seconds = 0)");
        return;
    }

    tracing::info!(idle_seconds, "Idle watchdog started");

    loop {
        thread::sleep(Duration::from_secs(30));

        let idle_for = now_secs().saturating_sub(LAST_ACTIVITY.load(Ordering::SeqCst));
        if idle_for > idle_seconds {
            tracing::info!(idle_for, "Model idle — unloading");
            if let Some(tx) = INFERENCE_TX.get() {
                let _ = tx.send(InferenceJob::Unload);
            }
            // Don't spam: reset the clock so we only unload again after another full idle period
            LAST_ACTIVITY.store(now_secs(), Ordering::SeqCst);
        }
    }
}

fn now_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn bump_activity() {
    LAST_ACTIVITY.store(now_secs(), Ordering::SeqCst);
}

fn start_recording() -> bool {
    with_app(|app| {
        if let Err(e) = app.begin_recording() {
            let msg = format!("Failed to start recording: {}", e);
            app.set_error(msg.clone());
            notify_error(&msg);
            return false;
        }
        ffi::on_state_changed(phase_to_ffi(app.phase), model_to_ffi(app.model_state));
        true
    });
    bump_activity();

    let max_seconds = with_app(|app| app.config.audio.max_duration_seconds);

    match audio::AudioCapture::start(max_seconds) {
        Ok(capture) => {
            with_audio(|a| *a = Some(capture));
        }
        Err(e) => {
            tracing::error!("Failed to start audio: {}", e);
            with_app(|app| {
                app.set_error(format!("Audio error: {}", e));
            });
            notify_error(&format!("Audio error: {}", e));
            return false;
        }
    }

    // Fresh session for the inference worker (clear decode state + counters).
    if let Some(tx) = INFERENCE_TX.get() {
        let _ = tx.send(InferenceJob::ResetSession);
    }
    CHUNKS_SENT.store(0, Ordering::SeqCst);
    CHUNK_FAILED.store(false, Ordering::SeqCst);

    // Spawn the chunker for live transcription during this recording.
    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    *CHUNKER_STOP_TX.lock().unwrap() = Some(stop_tx);
    let (chunk_seconds, overlap_seconds) = with_app(|app| {
        (app.config.audio.chunk_seconds as u64, app.config.audio.chunk_overlap_seconds as u64)
    });
    thread::spawn(move || chunker_thread(stop_rx, chunk_seconds, overlap_seconds));

    true
}

fn stop_recording() {
    // 1. Stop the chunker first — no more mid-recording jobs after this point.
    if let Some(stop_tx) = CHUNKER_STOP_TX.lock().unwrap().take() {
        let _ = stop_tx.send(());
    }

    // 2. Capture audio on the calling (main) thread — thread_local AUDIO lives here
    let samples = with_audio(|audio_opt| audio_opt.take().map(|a| a.stop()).unwrap_or_default());

    let needs_inference = with_app(|app| match app.finish_recording() {
        Ok(_) => !samples.is_empty(),
        Err(e) => {
            app.set_error(format!("Stop recording error: {}", e));
            false
        }
    });

    if !needs_inference {
        notify_state();
        with_app(|app| {
            if let Some(msg) = &app.error_message.clone() {
                notify_error(msg);
            }
        });
        return;
    }

    // 3. Transition to Processing — Swift renders the Transcribing pill immediately
    with_app(|app| {
        app.model_state = ModelState::Inference;
    });
    notify_state();
    bump_activity();

    // 4. Decide the final job:
    //    - Any chunk failed → reset decode state and re-transcribe the WHOLE
    //      buffer (no data loss; state must not carry stale chunks).
    //    - Chunks were sent → send only the tail AFTER the last chunk's end.
    //    - No chunks (recording < chunk_seconds) → whole buffer, as before.
    let chunks_sent = CHUNKS_SENT.load(Ordering::SeqCst);
    let chunk_failed = CHUNK_FAILED.load(Ordering::SeqCst);

    let (final_samples, need_reset) = if chunk_failed || chunks_sent == 0 {
        tracing::info!(chunk_failed, chunks_sent, "Whole-buffer final (fallback)");
        (samples, true)
    } else {
        let overlap_seconds = with_app(|app| app.config.audio.chunk_overlap_seconds as u64);
        let overlap_samples =
            (overlap_seconds as usize) * (SAMPLE_RATE.load(Ordering::SeqCst) as usize);
        let raw_start = LAST_CHUNK_END.load(Ordering::SeqCst) as usize;
        let start_at = raw_start.saturating_sub(overlap_samples);
        tracing::info!(
            chunks_sent,
            raw_start,
            start_at,
            overlap_samples,
            "Tail final with overlap"
        );
        (samples[start_at.min(samples.len())..].to_vec(), false)
    };

    if let Some(tx) = INFERENCE_TX.get() {
        if need_reset {
            let _ = tx.send(InferenceJob::ResetSession);
        }
        let _ = tx.send(InferenceJob::TranscribeChunk { samples: final_samples, is_final: true });
    } else {
        tracing::error!("Inference worker not initialized");
        with_app(|app| {
            app.set_error("Inference worker not initialized".into());
        });
        notify_state();
    }
}

fn get_transcript() -> String {
    with_app(|app| app.transcript.clone().unwrap_or_default())
}

fn copy_to_clipboard() {
    let text = with_app(|app| app.transcript.clone());

    let text = match text {
        Some(t) => t,
        None => {
            notify_error("No transcript to copy");
            return;
        }
    };

    // Plain copy — no previous-clipboard save.
    // Restoring old content later would overwrite the transcript in
    // clipboard managers (pushing it to second position).
    match system::copy_to_clipboard(&text) {
        Ok(()) => {}
        Err(e) => {
            notify_error(&format!("Clipboard copy failed: {}", e));
        }
    }
}

fn paste_into_frontmost_app() {
    match system::paste_into_frontmost() {
        Ok(()) => {}
        Err(e) => {
            tracing::error!("Paste failed: {}", e);
            notify_error("Paste failed - check Accessibility permission");
        }
    }
}

fn dismiss_transcript() {
    with_app(|app| {
        // No clipboard restore — the copied transcript stays the newest entry.
        app.dismiss();
    });
    notify_state();
}

fn retry_recording() {
    with_app(|app| app.retry());
    notify_state();
}

fn get_audio_level() -> f32 {
    with_audio(|a| a.as_ref().map(|cap| cap.current_level()).unwrap_or(0.0))
}

fn get_app_phase() -> ffi::AppPhase {
    with_app(|app| phase_to_ffi(app.phase))
}

fn get_model_phase() -> ffi::ModelPhase {
    with_app(|app| model_to_ffi(app.model_state))
}

fn get_download_progress() -> f32 {
    with_app(|app| app.download_progress)
}

fn get_download_speed() -> String {
    with_app(|app| app.download_speed.clone())
}

fn get_download_remaining() -> String {
    with_app(|app| app.download_remaining.clone())
}

fn get_error_message() -> String {
    with_app(|app| app.error_message.clone().unwrap_or_default())
}

fn get_live_preview_enabled() -> bool {
    LIVE_PREVIEW.load(Ordering::SeqCst)
}

fn set_live_preview_enabled(enabled: bool) {
    LIVE_PREVIEW.store(enabled, Ordering::SeqCst);
    tracing::info!(enabled, "Live preview toggled");
}
