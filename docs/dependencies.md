# Dependencies

## Rust Crates

### Core FFI

| Crate | Version | Purpose | PRD Reference |
|-------|---------|---------|---------------|
| `swift-bridge` | 0.1.x | Rust↔Swift FFI code generation. Generates Swift and C glue code from `#[swift_bridge::bridge]` module. | §10 — chosen over UniFFI for bidirectional call support |
| `swift-bridge-build` | 0.1.x | Build script integration. Runs code generation during `cargo build`. | §10 |

### Inference

| Crate | Version | Purpose | PRD Reference |
|-------|---------|---------|---------------|
| `whisper-rs` | 0.13.x | Rust bindings to whisper.cpp. Transitive: `whisper-cpp-sys`, Metal.framework, Accelerate.framework. | §9.3 — mature, Metal-accelerated, 115K downloads/month |

### Audio

| Crate | Version | Purpose | PRD Reference |
|-------|---------|---------|---------------|
| `cpal` | 0.15.x | Cross-platform audio I/O. Wraps Core Audio on macOS. Captures microphone input. | §11 — standard Rust audio crate |

### System Interaction

| Crate | Version | Purpose | PRD Reference |
|-------|---------|---------|---------------|
| `arboard` | 3.x | Cross-platform clipboard access. Read/write text to NSPasteboard. | §12.2 — clipboard + restore |
| `core-graphics` | 0.23.x | macOS Quartz Event Services. CGEvent.post for paste simulation, CGEventTap for hotkey capture. | §12.1, §12.2 |
| `core-foundation` | 0.10.x | macOS Core Foundation types. Required by core-graphics for CF types. | — |

### Configuration & Serialization

| Crate | Version | Purpose | PRD Reference |
|-------|---------|---------|---------------|
| `config` | 0.14.x | Layered configuration from TOML files + env vars. `config/default.toml` → `config/{env}.toml` → `AGENTTALK_*` env vars. | — |
| `serde` | 1.x | Serialization framework. Used by config crate and for state serialization. | — |
| `serde_json` | 1.x | JSON support for serde. | — |
| `toml` | 0.8.x | TOML support for config crate. | — |

### Error Handling

| Crate | Version | Purpose | PRD Reference |
|-------|---------|---------|---------------|
| `anyhow` | 1.x | Flexible error type for application code. `anyhow::Result<T>` for functions that can fail with varied errors. | — |
| `thiserror` | 2.x | Derive macro for custom error types. Used in library modules where structured errors matter. | — |

### Observability

| Crate | Version | Purpose | PRD Reference |
|-------|---------|---------|---------------|
| `tracing` | 0.1.x | Structured, async-aware logging framework. Spans, events, levels. | — |
| `tracing-subscriber` | 0.3.x | Log output subscribers. JSON format for file, pretty format for console. Env filter for runtime level control. | — |
| `tracing-appender` | 0.2.x | Non-blocking file writer. Avoids blocking inference on log I/O. | — |

### Model Management

| Crate | Version | Purpose | PRD Reference |
|-------|---------|---------|---------------|
| `reqwest` | 0.12.x | HTTP client. Downloads ggml model files from Hugging Face. Blocking mode used (no async). | — |
| `sha2` | 0.10.x | SHA-256 hashing. Verifies model file integrity after download. | — |
| `dirs` | 5.x | Platform-standard directories. Resolves `~/Library/Application Support/` on macOS. | — |

## Build Dependencies

| Crate | Version | Purpose | PRD Reference |
|-------|---------|---------|---------------|
| `swift-bridge-build` | 0.1.x | Build script codegen for swift-bridge FFI | §10 |

## Apple Frameworks

| Framework | Purpose | PRD Reference |
|-----------|---------|---------------|
| **SwiftUI** | Menu bar extra, floating panel, all UI | §7 |
| **AppKit** | NSApplication lifecycle, menu bar API, window management | §7 |
| **AVFoundation** | Microphone permission request and audio device enumeration | §11 |
| **Metal** | GPU acceleration for whisper.cpp inference | §9 |
| **CoreML** | Neural Engine encoder offload (deferred for fast-follow) | §9.3 |
| **Accelerate** | BLAS/LAPACK routines for whisper.cpp CPU fallback | — |
| **Carbon** | Legacy hotkey API (RegisterEventHotKey fallback) | §12.1 |
| **Core Graphics** | CGEvent API (auto-paste + hotkey) | §12 |

## Why NOT Included

| Candidate | Reason Excluded | PRD Reference |
|-----------|----------------|---------------|
| `tokio` | No async I/O needed. Audio is callback-driven (cpal thread). Inference is synchronous. | §7 |
| `UniFFI` | swift-bridge chosen for bidirectional call support (Rust→Swift callbacks). | §10 |
| `mlx-whisper` | No mature Rust binding. Python/Swift only. Would violate Rust-core architecture. | §9.2 |
| `silero-vad-rs` | VAD deferred to v1.1. Adds ONNX runtime dependency. | §11 |
| Vapor/Rocket web server | No server or network component. | §3 (no cloud) |
| `open-whisper` / other model crates | whisper-rs is the canonical Rust binding. No alternatives with comparable maturity. | §9.3 |
