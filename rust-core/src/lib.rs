pub mod audio;
pub mod config;
pub mod hotkey;
pub mod inference;
pub mod model_manager;
pub mod state;
pub mod system;

use std::cell::RefCell;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::thread;

use model_manager::{ModelManager, ModelState};
use state::{AppStateMachine, SessionPhase};

static APP: Mutex<Option<AppStateMachine>> = Mutex::new(None);
thread_local! {
    static AUDIO: RefCell<Option<audio::AudioCapture>> = const { RefCell::new(None) };
}
static INITIALIZED: AtomicBool = AtomicBool::new(false);

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
    let (phase, model) = with_app(|app| {
        (phase_to_ffi(app.phase), model_to_ffi(app.model_state))
    });
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

        with_app(|app| {
            match download_result {
                Ok(()) => {
                    app.model_state = ModelState::Ready;
                    app.phase = SessionPhase::Ready;
                }
                Err(e) => {
                    tracing::error!("Model download failed: {}", e);
                    app.model_state = ModelState::Error;
                    app.phase = SessionPhase::Error;
                }
            }
        });
        notify_state();
    });

    true
}

fn is_initialized() -> bool {
    INITIALIZED.load(Ordering::SeqCst)
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

    match audio::AudioCapture::start() {
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

    true
}

fn stop_recording() {
    // 1. Capture audio on the calling (main) thread — thread_local AUDIO lives here
    let samples = with_audio(|audio_opt| {
        audio_opt.take().map(|a| a.stop()).unwrap_or_default()
    });

    let needs_inference = with_app(|app| {
        match app.finish_recording() {
            Ok(_) => !samples.is_empty(),
            Err(e) => {
                app.set_error(format!("Stop recording error: {}", e));
                false
            }
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

    // 2. Transition to Processing — Swift renders the Transcribing pill immediately
    with_app(|app| {
        app.model_state = ModelState::Inference;
    });
    notify_state();

    // 3. Model path resolved on main thread
    let model_path = {
        let model_dir = with_app(|app| app.config.model.directory.clone());
        let home = dirs::home_dir().unwrap_or_default();
        let dir = model_dir.replacen("~/", &format!("{}/", home.display()), 1);
        let filename = with_app(|app| app.config.model.filename.clone());
        std::path::PathBuf::from(dir).join(&filename)
    };

    // 4. Inference on a dedicated thread — keeps main thread free for UI.
    //    Engine is thread_local to THIS thread, so the model stays resident
    //    across stops on the same thread.
    thread::spawn(move || {
        tracing::info!("Running inference on {} samples", samples.len());

        // First inference on this thread creates the engine; subsequent calls reuse it
        thread_local! {
            static ENGINE: RefCell<Option<inference::engine::InferenceEngine>> = const { RefCell::new(None) };
        }

        let result = ENGINE.with(|engine_cell| {
            let mut cell = engine_cell.borrow_mut();
            if cell.is_none() {
                tracing::info!("Creating inference engine (first use)");
                *cell = Some(inference::engine::InferenceEngine::new(model_path));
            }
            let engine = cell.as_mut().expect("engine just created");
            engine.load()?;
            engine.transcribe(&samples)
        });

        with_app(|app| {
            app.model_state = ModelState::Ready;
            match result {
                Ok(text) => {
                    if text.is_empty() {
                        app.set_error("No speech detected".into());
                        notify_error("No speech detected");
                    } else {
                        app.set_transcript(text.clone());
                        ffi::on_transcript_ready(text);
                    }
                }
                Err(e) => {
                    let msg = format!("Inference failed: {}", e);
                    tracing::error!("{}", msg);
                    app.set_error(msg.clone());
                    notify_error(&msg);
                }
            }
        });
        notify_state();
    });
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
