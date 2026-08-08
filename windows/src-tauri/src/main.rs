#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::{Emitter, Manager};

#[tauri::command]
fn get_audio_level() -> f32 {
    // Calls into rust-core via ffi_win / direct linkage
    // For in-process Tauri, we link agent-talk-core directly.
    // This stub is wired to the real core once the phase below is expanded.
    0.0
}

#[tauri::command]
fn get_app_phase() -> String {
    "Idle".into()
}

#[tauri::command]
fn copy_transcript() -> Result<(), String> {
    Ok(())
}

#[tauri::command]
fn dismiss_transcript() -> Result<(), String> {
    Ok(())
}

#[tauri::command]
fn retry_recording() -> Result<(), String> {
    Ok(())
}

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            // TODO: initialize rust-core (agenttalk_initialize_core),
            // register global hotkey Ctrl+Shift+D via windows::Win32 RegisterHotKey
            // on a hidden HWND, and emit agenttalk://state / transcript events.
            // Tray: Shell_NotifyIconW + TrackPopupMenuEx equivalent via tauri tray plugin.
            let _ = app.handle();
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_audio_level,
            get_app_phase,
            copy_transcript,
            dismiss_transcript,
            retry_recording
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
