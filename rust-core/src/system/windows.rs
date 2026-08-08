#[cfg(target_os = "windows")]
use windows::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP, VIRTUAL_KEY, VK_CONTROL,
};

pub fn paste_into_frontmost() -> anyhow::Result<()> {
    #[cfg(not(target_os = "windows"))]
    {
        tracing::info!("paste_into_frontmost: no-op on non-Windows host (testing)");
        return Ok(());
    }

    #[cfg(target_os = "windows")]
    {
        // Ctrl+V via SendInput (foreground window receives it). UIPI: if the
        // foreground window is elevated (admin) and we are not, SendInput is
        // silently dropped unless the app manifest has uiAccess=true and is
        // signed + in a secure location. Caller should fall back to copy-only.
        unsafe {
            let mut inputs = [
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VK_CONTROL,
                            wScan: 0,
                            dwFlags: Default::default(),
                            time: 0,
                            wVkExtraInfo: 0,
                        },
                    },
                },
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VIRTUAL_KEY(0x56),
                            wScan: 0,
                            dwFlags: Default::default(),
                            time: 0,
                            wVkExtraInfo: 0,
                        },
                    },
                },
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VIRTUAL_KEY(0x56),
                            wScan: 0,
                            dwFlags: KEYEVENTF_KEYUP,
                            time: 0,
                            wVkExtraInfo: 0,
                        },
                    },
                },
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VK_CONTROL,
                            wScan: 0,
                            dwFlags: KEYEVENTF_KEYUP,
                            time: 0,
                            wVkExtraInfo: 0,
                        },
                    },
                },
            ];
            let sent = SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
            if sent != inputs.len() as u32 {
                anyhow::bail!("SendInput only sent {sent}/{} events", inputs.len());
            }
        }
        tracing::info!("Pasted into frontmost app (Ctrl+V via SendInput)");
        Ok(())
    }
}

pub fn check_accessibility_permission() -> anyhow::Result<()> {
    // No TCC on Windows; paste may still be blocked by UIPI if target is elevated.
    tracing::info!("Windows: no accessibility permission check needed");
    Ok(())
}

pub fn open_accessibility_settings() -> std::io::Result<()> {
    // Closest Windows equivalent: Privacy → Microphone
    std::process::Command::new("cmd")
        .args(["/C", "start", "ms-settings:privacy-microphone"])
        .spawn()?;
    Ok(())
}

pub fn open_microphone_settings() -> std::io::Result<()> {
    std::process::Command::new("cmd")
        .args(["/C", "start", "ms-settings:privacy-microphone"])
        .spawn()?;
    Ok(())
}
