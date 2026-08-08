# AgentTalk Windows

Additive port — `AgentTalk/` (macOS) stays untouched.

## Stack

- **Rust core** `rust-core/` with `cfg(target_os)` + features `metal` (macOS default) / `vulkan` (Windows default) / `cuda` (optional NVIDIA). `crate-type = ["staticlib","cdylib"]` so Windows can link `agent_talk_core.lib` or `dll`.
- **Frontend** Tauri 2 (Rust + WebView2). Not Electron: uses OS WebView2 (Edge), ~20–40 MB idle, shared GPU, ~10 MB installer overhead vs Electron ~150 MB. C++ WinUI alternative is documented in the plan if you prefer native C++; Tauri scaffold is cheaper to iterate and reuses the Rust core in-process.
- **Audio** `cpal` WASAPI with fallback `supported_input_configs()` → resample to 16kHz mono (see `rust-core/src/audio/mod.rs`).
- **Hotkey** `RegisterHotKey` Ctrl+Shift+D (`windows::Win32::UI::Input::KeyboardAndMouse`) — global, no admin. `1409 ERROR_HOTKEY_ALREADY_REGISTERED` surfaces for rebinding. Hold-to-talk via `WH_KEYBOARD_LL` if needed.
- **Paste** `SendInput` Ctrl+V (UIPI: elevated targets silently drop it → fallback copy-only). Clipboard via `arboard` (`clipboard-win`).
- **HUD** `WS_EX_TOPMOST|WS_EX_LAYERED|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE` layered window, `Shell_NotifyIconW` tray, `MonitorFromWindow` multi-mon. Sizes mirror macOS: Recording 240×44 (400×120 live preview) / Processing 240×44 / TranscriptReady 300×170 / Error 300×120.
- **Installer** Inno Setup 6 `.iss` → `dist/AgentTalk-0.1.0-x64-setup.exe`. Model not bundled; first launch downloads `ggml-large-v3-turbo.bin` to `%APPDATA%\AgentTalk\models`.

## Build

```powershell
# Windows (PowerShell)
.\scripts\package-windows.ps1              # release + installer
.\scripts\package-windows.ps1 -NoInstaller # just rust + tauri build
```

Rust cross-check from macOS:

```bash
cargo check --manifest-path rust-core/Cargo.toml --features vulkan
cargo test --manifest-path rust-core/Cargo.toml
```

## Signing

```powershell
.\scripts\sign-windows.ps1 -Identity "CN=..."
```

CI adds a `windows-latest` job (see `.github/workflows/release.yml` next).

## Project map

- `windows/src/` — Tauri frontend (HTML/CSS/JS) mirroring `AgentTalk/UI/Panel/RecordingPillView.swift`
- `windows/src-tauri/` — Tauri config + Rust glue calling `rust-core` `ffi_win` `extern "C"`
- `windows/installer/installer.iss` — Inno Setup
