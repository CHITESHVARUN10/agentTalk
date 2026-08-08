use core_foundation::base::TCFType;
use core_graphics::event::{CGEvent, CGEventTapLocation};
use core_graphics::event_source::CGEventSource;

pub fn paste_into_frontmost() -> anyhow::Result<()> {
    check_accessibility_permission()?;

    let source = CGEventSource::new(core_graphics::event_source::CGEventSourceStateID::Private)
        .map_err(|_| anyhow::anyhow!("Failed to create event source"))?;

    let cmd_down = CGEvent::new_keyboard_event(source.clone(), 55, true)
        .map_err(|_| anyhow::anyhow!("Failed to create Cmd key-down event"))?;
    let v_down = CGEvent::new_keyboard_event(source.clone(), 9, true)
        .map_err(|_| anyhow::anyhow!("Failed to create V key-down event"))?;
    let v_up = CGEvent::new_keyboard_event(source.clone(), 9, false)
        .map_err(|_| anyhow::anyhow!("Failed to create V key-up event"))?;
    let cmd_up = CGEvent::new_keyboard_event(source, 55, false)
        .map_err(|_| anyhow::anyhow!("Failed to create Cmd key-up event"))?;

    v_down.set_flags(core_graphics::event::CGEventFlags::CGEventFlagCommand);

    cmd_down.post(CGEventTapLocation::HID);
    v_down.post(CGEventTapLocation::HID);
    v_up.post(CGEventTapLocation::HID);
    cmd_up.post(CGEventTapLocation::HID);

    tracing::info!("Pasted into frontmost app");
    Ok(())
}

pub fn check_accessibility_permission() -> anyhow::Result<()> {
    tracing::info!("Accessibility permission check");
    Ok(())
}

pub fn open_accessibility_settings() -> std::io::Result<()> {
    std::process::Command::new("open")
        .args(["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"])
        .spawn()?;
    Ok(())
}

pub fn open_microphone_settings() -> std::io::Result<()> {
    std::process::Command::new("open")
        .args(["x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"])
        .spawn()?;
    Ok(())
}
