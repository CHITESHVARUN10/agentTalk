#!/usr/bin/env bash
set -euo pipefail

echo "Building AgentTalk..."

# Build Rust static library (generates FFI files into rust-core/generated/)
echo "[1/2] Building Rust core..."
cd rust-core
cargo build --release
cd ..

# Copy generated FFI files into Bridge directory for Xcode compilation
echo "       Copying FFI files..."
mkdir -p AgentTalk/Bridge
cp rust-core/generated/SwiftBridgeCore.swift AgentTalk/Bridge/ 2>/dev/null || true
cp rust-core/generated/SwiftBridgeCore.h AgentTalk/Bridge/ 2>/dev/null || true
cp rust-core/generated/agent-talk-core/agent-talk-core.swift AgentTalk/Bridge/ 2>/dev/null || true
cp rust-core/generated/agent-talk-core/agent-talk-core.h AgentTalk/Bridge/ 2>/dev/null || true

# Build Swift app
echo "[2/2] Building Swift app..."
xcodebuild -project AgentTalk.xcodeproj \
    -scheme AgentTalk \
    -configuration Release \
    build 2>&1 | grep -E '(error:|warning:|BUILD)' || true

echo ""
echo "Build complete."
echo "App: build/Release/AgentTalk.app"
