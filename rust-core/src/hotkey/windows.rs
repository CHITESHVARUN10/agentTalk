//! Windows global hotkey via RegisterHotKey + hidden message window.
//!
//! Toggle semantics match macOS: Ready → Recording → Processing.
//! Carbon on macOS gives press+release; RegisterHotKey only gives WM_HOTKEY
//! on press. For hold-to-talk we also support WH_KEYBOARD_LL if needed.

use super::{HotkeyAction, HotkeyCallback};
use std::sync::Arc;

pub struct WindowsHotkey {
    on_press: HotkeyCallback,
    on_release: HotkeyCallback,
}

impl WindowsHotkey {
    pub fn new(on_press: HotkeyCallback, on_release: HotkeyCallback) -> Self {
        Self { on_press, on_release }
    }

    pub fn handle_hotkey(&self) {
        tracing::info!("Windows hotkey pressed (WM_HOTKEY)");
        (self.on_press)(HotkeyAction::Pressed);
    }

    #[allow(dead_code)]
    pub fn handle_release(&self) {
        tracing::info!("Windows hotkey released");
        (self.on_release)(HotkeyAction::Released);
    }
}

/// Register Ctrl+Shift+D as a global hotkey on the given HWND.
/// Returns Ok(()) or Err with GetLastError. 1409 = ERROR_HOTKEY_ALREADY_REGISTERED.
#[cfg(target_os = "windows")]
pub fn register_hotkey(hwnd: windows::Win32::Foundation::HWND, id: i32) -> anyhow::Result<()> {
    use windows::Win32::UI::Input::KeyboardAndMouse::{RegisterHotKey, HOT_KEY_MODIFIERS, MOD_CONTROL, MOD_SHIFT, VIRTUAL_KEY};

    let modifiers = MOD_CONTROL | MOD_SHIFT;
    let vk = 0x44u32; // D
    let ok = unsafe { RegisterHotKey(hwnd, id, modifiers, vk) };
    if ok.as_bool() {
        tracing::info!(id, "Windows hotkey registered (Ctrl+Shift+D)");
        Ok(())
    } else {
        let err = std::io::Error::last_os_error();
        let code = err.raw_os_error().unwrap_or(-1);
        if code == 1409 {
            tracing::warn!("Hotkey already registered (1409) — suggest rebinding");
        }
        anyhow::bail!("RegisterHotKey failed: {err} (code {code})")
    }
}

#[cfg(target_os = "windows")]
pub fn unregister_hotkey(hwnd: windows::Win32::Foundation::HWND, id: i32) {
    use windows::Win32::UI::Input::KeyboardAndMouse::UnregisterHotKey;
    unsafe {
        let _ = UnregisterHotKey(hwnd, id);
    }
}
