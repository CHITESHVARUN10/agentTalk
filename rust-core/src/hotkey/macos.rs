//! macOS hotkey — thin shim. Real Carbon RegisterEventHotKey lives in
//! AgentTalk/App/AppDelegate.swift. This file exists so hotkey/ can be
//! split by cfg without breaking imports.

pub use super::{HotkeyAction, HotkeyBridge, HotkeyCallback};
