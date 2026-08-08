//! System-level operations: clipboard access and auto-paste.

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
pub use macos::{check_accessibility_permission, open_accessibility_settings, open_microphone_settings, paste_into_frontmost};

#[cfg(target_os = "windows")]
mod windows;
#[cfg(target_os = "windows")]
pub use windows::{check_accessibility_permission, open_accessibility_settings, open_microphone_settings, paste_into_frontmost};

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub use stub::{check_accessibility_permission, open_accessibility_settings, open_microphone_settings, paste_into_frontmost};

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
mod stub {
    pub fn paste_into_frontmost() -> anyhow::Result<()> {
        anyhow::bail!("paste_into_frontmost not supported on this platform")
    }
    pub fn check_accessibility_permission() -> anyhow::Result<()> {
        Ok(())
    }
    pub fn open_accessibility_settings() -> std::io::Result<()> {
        Err(std::io::Error::new(std::io::ErrorKind::Unsupported, "not supported"))
    }
    pub fn open_microphone_settings() -> std::io::Result<()> {
        Err(std::io::Error::new(std::io::ErrorKind::Unsupported, "not supported"))
    }
}

pub fn copy_to_clipboard(text: &str) -> anyhow::Result<()> {
    let mut clipboard = arboard::Clipboard::new()
        .map_err(|e| anyhow::anyhow!("Failed to access clipboard: {}", e))?;

    clipboard.set_text(text).map_err(|e| anyhow::anyhow!("Failed to set clipboard text: {}", e))?;

    tracing::info!(chars = text.len(), "Copied to clipboard");
    Ok(())
}

pub fn get_clipboard() -> anyhow::Result<Option<String>> {
    let mut clipboard = arboard::Clipboard::new()
        .map_err(|e| anyhow::anyhow!("Failed to access clipboard: {}", e))?;

    match clipboard.get_text() {
        Ok(text) => Ok(Some(text)),
        Err(arboard::Error::ContentNotAvailable) => Ok(None),
        Err(e) => Err(anyhow::anyhow!("Clipboard read error: {}", e)),
    }
}

pub fn copy_with_backup(text: &str) -> anyhow::Result<Option<String>> {
    let previous = get_clipboard().unwrap_or(None);
    copy_to_clipboard(text)?;
    tracing::info!(saved = previous.as_ref().map_or(0, |s| s.len()), "Clipboard saved and updated");
    Ok(previous)
}

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
