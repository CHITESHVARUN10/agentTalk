# Setup Guide

## Prerequisites

- **macOS 14.0+ (Sonoma or later)**
- **Xcode 16.0+** — [App Store](https://apps.apple.com/us/app/xcode/id497799835)
- **Rust** — [rustup.rs](https://rustup.rs)
- **Homebrew** — [brew.sh](https://brew.sh)
- **xcodegen** — `brew install xcodegen`

Verify installation:
```bash
xcodebuild -version
rustc --version
cargo --version
brew --version
xcodegen --version
```

## Quick Start

```bash
# Clone the repository
git clone <repo-url>
cd agentTalk

# One-command setup
./scripts/bootstrap.sh

# Build and run
make run
```

## Manual Setup

### 1. Install Rust toolchain components

```bash
rustup update stable
rustup component add rustfmt clippy
rustup target add aarch64-apple-darwin
```

### 2. Generate Xcode project

```bash
xcodegen generate --spec project.yml
```

This creates `AgentTalk.xcodeproj` from `project.yml`.

### 3. Build Rust core

```bash
cd rust-core
cargo build --release
cd ..
```

The first build downloads and compiles whisper.cpp (~5-10 minutes). Subsequent builds are incremental.

### 4. Build Swift app

```bash
xcodebuild -project AgentTalk.xcodeproj \
    -scheme AgentTalk \
    -configuration Release \
    build
```

The app binary is at `build/Release/AgentTalk.app`.

### 5. Download the Whisper model

```bash
./scripts/setup-model.sh
```

Downloads `ggml-large-v3-turbo.bin` (~1.5 GB) from Hugging Face to:
```
~/Library/Application Support/AgentTalk/models/
```

## Development Workflow

```bash
# Build everything
make build

# Run tests
make rust-test

# Lint
make rust-lint

# Format check
make rust-fmt

# Clean all artifacts
make clean

# Generate Xcode project (after project.yml changes)
make xcode
```

## Project Structure

```
agentTalk/
├── AgentTalk/              SwiftUI application
│   ├── App/                @main entry point + AppDelegate
│   ├── UI/                 Menu bar + floating panel
│   ├── Bridge/             swift-bridge generated files (gitignored)
│   └── Resources/          Asset catalog, Info.plist, entitlements
├── rust-core/              Rust static library
│   └── src/                Module tree (audio, inference, state, etc.)
├── config/                 TOML configuration (default, dev, release)
├── scripts/                Build and setup scripts
├── docs/                   Developer documentation
├── models/                 Whisper model storage (gitignored)
└── project.yml             xcodegen specification
```

## Troubleshooting

### "xcrun: error: unable to find utility xcodebuild"

Ensure Xcode is installed and the command line tools are selected:
```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### "cargo: command not found"

Install Rust via rustup:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Build fails with Metal/whisper.cpp linking errors

Ensure the `aarch64-apple-darwin` target is installed:
```bash
rustup target add aarch64-apple-darwin
```

### "whisper-rs build takes forever"

The first build compiles whisper.cpp from C source. This is expected and cached for subsequent builds. Opt-level for dependencies is set to 2 even in debug mode to keep rebuilds fast.
