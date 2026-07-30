//! System-level operations: clipboard access and auto-paste.
//!
//! Clipboard (`arboard`):
//! - Read/write text to the system clipboard
//! - Save and restore clipboard contents
//!
//! Auto-paste (`core-graphics` CGEvent):
//! - Simulate ⌘V in the frontmost application
//! - Track the active application before the hotkey fires
//!   to paste into the correct target
//! - Requires Accessibility permission (`kTCCServicePostEvent`)
//!
//! Permission (`core-foundation`):
//! - Check Accessibility trust status via `AXIsProcessTrusted()`
//! - Guide user through permission grant flow
