use std::sync::Arc;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HotkeyAction {
    Pressed,
    Released,
}

pub type HotkeyCallback = Arc<dyn Fn(HotkeyAction) + Send + Sync>;

pub struct HotkeyBridge {
    on_press: HotkeyCallback,
    on_release: HotkeyCallback,
}

impl HotkeyBridge {
    pub fn new(on_press: HotkeyCallback, on_release: HotkeyCallback) -> Self {
        Self { on_press, on_release }
    }

    pub fn handle_press(&self) {
        tracing::info!("Hotkey pressed");
        (self.on_press)(HotkeyAction::Pressed);
    }

    pub fn handle_release(&self) {
        tracing::info!("Hotkey released");
        (self.on_release)(HotkeyAction::Released);
    }
}

#[cfg(target_os = "macos")]
pub mod macos;

#[cfg(target_os = "windows")]
pub mod windows;

/// Re-export for convenience
pub use HotkeyBridge as Hotkey;
