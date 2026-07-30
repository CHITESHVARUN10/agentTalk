//! Global hotkey registration via CGEventTap.
//!
//! Listens for the configured global keyboard shortcut and triggers
//! recording state transitions. Uses Quartz Event Services (CGEventTap)
//! for reliable event capture across all applications, including those
//! with custom-drawn views (terminals, IDEs).
//!
//! Requires Accessibility permission (`kTCCServicePostEvent`).
//!
//! Fallback: Carbon `RegisterEventHotKey` can be added later as an
//! opt-in alternative for users who prefer to avoid the Accessibility
//! permission prompt, though it may not fire reliably in certain apps.
