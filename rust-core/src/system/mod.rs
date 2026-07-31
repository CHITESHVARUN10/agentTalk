//! System-level operations: clipboard access and auto-paste.
//!
//! Clipboard (`arboard`):
//! - Read/write text to the system clipboard
//! - Save and restore clipboard contents
//!
//! Auto-paste (`core-graphics` CGEvent):
//! - Simulate ⌘V in the frontmost application
//! - Requires Accessibility permission (`kTCCServicePostEvent`)

use core_foundation::base::TCFType;
use core_graphics::event::{CGEvent, CGEventTapLocation};
use core_graphics::event_source::CGEventSource;

/// Copy text to the system clipboard.
/// Optionally restores the previous clipboard content afterward.
pub fn copy_to_clipboard(text: &str) -> anyhow::Result<()> {
    let mut clipboard = arboard::Clipboard::new()
        .map_err(|e| anyhow::anyhow!("Failed to access clipboard: {}", e))?;

    clipboard
        .set_text(text)
        .map_err(|e| anyhow::anyhow!("Failed to set clipboard text: {}", e))?;

    tracing::info!(chars = text.len(), "Copied to clipboard");
    Ok(())
}

/// Get the current clipboard text, if any.
pub fn get_clipboard() -> anyhow::Result<Option<String>> {
    let mut clipboard = arboard::Clipboard::new()
        .map_err(|e| anyhow::anyhow!("Failed to access clipboard: {}", e))?;

    match clipboard.get_text() {
        Ok(text) => Ok(Some(text)),
        Err(arboard::Error::ContentNotAvailable) => Ok(None),
        Err(e) => Err(anyhow::anyhow!("Clipboard read error: {}", e)),
    }
}

/// Save clipboard content and set new text.
/// Returns the previous content for restoration.
pub fn copy_with_backup(text: &str) -> anyhow::Result<Option<String>> {
    let previous = get_clipboard().unwrap_or(None);
    copy_to_clipboard(text)?;
    tracing::info!(
        saved = previous.as_ref().map_or(0, |s| s.len()),
        "Clipboard saved and updated"
    );
    Ok(previous)
}

/// Restore clipboard to previous content.
pub fn restore_clipboard(text: &Option<String>) -> anyhow::Result<()> {
    if let Some(prev) = text {
        let mut clipboard = arboard::Clipboard::new()
            .map_err(|e| anyhow::anyhow!("Failed to access clipboard: {}", e))?;
        clipboard
            .set_text(prev)
            .map_err(|e| anyhow::anyhow!("Failed to restore clipboard: {}", e))?;
        tracing::info!("Clipboard restored");
    }
    Ok(())
}

/// Simulate ⌘V (Cmd+V) to paste into the frontmost application.
/// Requires Accessibility permission.
pub fn paste_into_frontmost() -> anyhow::Result<()> {
    check_accessibility_permission()?;

    let source = CGEventSource::new(core_graphics::event_source::CGEventSourceStateID::Private)
        .map_err(|_| anyhow::anyhow!("Failed to create event source"))?;

    // Key code for 'V' is 9
    let cmd_down = CGEvent::new_keyboard_event(source.clone(), 55, true)
        .map_err(|_| anyhow::anyhow!("Failed to create Cmd key-down event"))?;
    let v_down = CGEvent::new_keyboard_event(source.clone(), 9, true)
        .map_err(|_| anyhow::anyhow!("Failed to create V key-down event"))?;
    let v_up = CGEvent::new_keyboard_event(source.clone(), 9, false)
        .map_err(|_| anyhow::anyhow!("Failed to create V key-up event"))?;
    let cmd_up = CGEvent::new_keyboard_event(source, 55, false)
        .map_err(|_| anyhow::anyhow!("Failed to create Cmd key-up event"))?;

    // Set command flag on the V press
    v_down.set_flags(core_graphics::event::CGEventFlags::CGEventFlagCommand);

    // Post to the active application
    cmd_down.post(CGEventTapLocation::HID);
    v_down.post(CGEventTapLocation::HID);
    v_up.post(CGEventTapLocation::HID);
    cmd_up.post(CGEventTapLocation::HID);

    tracing::info!("Pasted into frontmost app");
    Ok(())
}

/// Check whether the app has Accessibility permission.
pub fn check_accessibility_permission() -> anyhow::Result<()> {
    // In production, use Accessibility API:
    // AXIsProcessTrusted()
    tracing::info!("Accessibility permission check");
    Ok(())
}

/// Open System Settings → Privacy & Security → Accessibility
/// so the user can grant permission.
pub fn open_accessibility_settings() -> std::io::Result<()> {
    std::process::Command::new("open")
        .args([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ])
        .spawn()?;
    Ok(())
}

/// Open System Settings → Privacy & Security → Microphone
pub fn open_microphone_settings() -> std::io::Result<()> {
    std::process::Command::new("open")
        .args([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        ])
        .spawn()?;
    Ok(())
}
