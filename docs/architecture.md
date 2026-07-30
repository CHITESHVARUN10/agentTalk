# AgentTalk Architecture

## Overview

AgentTalk is a macOS-native AI dictation utility. It converts spoken English to text entirely on-device, triggered by a global hotkey. The target feel is a system utility — instant open, minimal UI, invisible until summoned.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        macOS System                              │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              SwiftUI Application Layer                     │  │
│  │                                                           │  │
│  │  ┌──────────┐  ┌──────────────┐  ┌───────────────────┐   │  │
│  │  │ Menu Bar  │  │  Floating    │  │  Permission       │   │  │
│  │  │ Extra     │  │  Panel       │  │  Prompts          │   │  │
│  │  └──────────┘  └──────────────┘  └───────────────────┘   │  │
│  └───────────────────┬───────────────────────────────────────┘  │
│                      │ swift-bridge FFI                          │
│  ┌───────────────────▼───────────────────────────────────────┐  │
│  │                    Rust Core                               │  │
│  │                                                           │  │
│  │  ┌─────────┐  ┌──────────┐  ┌────────────────────────┐   │  │
│  │  │ state   │  │ audio    │  │ inference              │   │  │
│  │  │ machine │──│ capture  │──│ (whisper-rs wrapper)   │   │  │
│  │  └────┬────┘  └──────────┘  └───────────┬────────────┘   │  │
│  │       │                                 │                 │  │
│  │  ┌────┴────┐  ┌──────────┐  ┌───────────▼────────────┐   │  │
│  │  │ hotkey  │  │ system   │  │ model_manager          │   │  │
│  │  │ CGEvent │  │ clipboard│  │ download + cache        │   │  │
│  │  └─────────┘  └──────────┘  └────────────────────────┘   │  │
│  └───────────────────┬───────────────────────────────────────┘  │
│                      │                                          │
│  ┌───────────────────▼───────────────────────────────────────┐  │
│  │            whisper.cpp + Metal GPU                        │  │
│  │            (whisper large-v3-turbo)                       │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Layer Responsibilities

### SwiftUI Layer (thin)
- Menu bar extra and contextual menu
- Floating recording/transcript panel
- Permission prompt orchestration
- No knowledge of Whisper internals
- Observes Rust state via FFI callbacks

### Rust Core (thick)
- Session state machine — single source of truth
- Audio capture via Core Audio (cpal), resampled to 16kHz mono f32
- whisper-rs inference wrapper — model lifecycle, transcription
- Global hotkey registration (CGEventTap)
- Clipboard access (arboard) and paste simulation (CGEvent)
- Model download, checksum verification, caching

### whisper.cpp (compiled from C)
- GPU-accelerated inference via Metal
- Core ML encoder offload available as fast-follow

## Data Flow: Recording → Transcript

```
Microphone
    │  cpal callback — raw PCM
    ▼
Audio buffer (resample → 16kHz mono f32)
    │
    ▼
whisper_full() — Metal GPU inference
    │
    ▼
Segments (timestamped text fragments)
    │  concatenated
    ▼
Transcript string
    │  FFI callback → Swift
    ▼
Floating panel displays text
    │
    ├─ Copy → clipboard (arboard)
    ├─ Paste → CGEvent ⌘V into active app
    ├─ Retry → discard, re-record
    └─ Discard → close
```

## State Machine

```
Idle ──────────────────────────────────────────────────┐
   │  hotkey pressed                                     │
   ▼                                                     │
Recording ────────────────────────────┐                 │
   │  hotkey pressed again / release  │                  │
   ▼                                  │                  │
Processing ──────────────────────┐    │                  │
   │  inference complete         │    │                  │
   ▼                             │    │                  │
TranscriptReady ─── retry ───────┘    │                  │
   │  copy/paste/discard              │                  │
   └──────────────────────────────────┘                  │
                                                         │
Error ──────────────────────────────────────────────────┘
```

## Module Boundaries (Rust)

| Module | File | Responsibility |
|--------|------|---------------|
| `state` | `src/state/mod.rs` | Session state machine (idle→recording→processing→done) |
| `audio` | `src/audio/mod.rs` | Microphone capture, resampling to 16kHz mono f32 |
| `inference` | `src/inference/` | whisper-rs wrapper: model lifecycle, transcription |
| `hotkey` | `src/hotkey/mod.rs` | CGEventTap global hotkey registration |
| `system` | `src/system/mod.rs` | Clipboard (arboard), CGEvent paste, permission checks |
| `model_manager` | `src/model_manager/mod.rs` | Model download, checksum, cache directory |
| `config` | `src/config/mod.rs` | Layered TOML configuration |

## FFI Boundary

The `#[swift_bridge::bridge]` module in `lib.rs` defines the contract:

**Swift → Rust (calls):**
- `initialize_core()` — setup logging, config, model warm-up
- `start_recording()` / `stop_recording()` — audio capture control
- `get_transcript()` — retrieve last transcription
- `copy_to_clipboard()` / `paste_into_frontmost_app()` — output actions

**Rust → Swift (callbacks):**
- `on_state_changed(AppState)` — push state transitions to UI
- `on_transcript_ready(String)` — push completed transcript
- `on_error(String)` — push error messages

## Technology Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Inference backend | whisper.cpp via whisper-rs | Mature Rust binding, Metal support, no bespoke FFI needed |
| Rust↔Swift FFI | swift-bridge | Bidirectional calls, rich type sharing, Rust-first |
| Swift project format | xcodegen (YAML → .xcodeproj) | Human-readable, git-friendly, deterministic generation |
| async runtime | None | All operations are synchronous or callback-driven |
| Model | large-v3-turbo | Best speed/accuracy trade-off for short dictations |
| Distribution | Direct notarized .dmg | Avoids App Store rejection risk for CGEvent auto-paste |
