//! Global hotkey via CGEventTap.
//!
//! The CGEventTap is registered on the Swift side (more natural for macOS apps).
//! This module provides the Rust-side callbacks that the tap invokes.

use std::sync::Arc;

/// Callback type for hotkey press/release
pub type HotkeyCallback = Arc<dyn Fn(HotkeyAction) + Send + Sync>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HotkeyAction {
    Pressed,
    Released,
}

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
