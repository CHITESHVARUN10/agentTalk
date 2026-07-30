#!/usr/bin/env bash
set -euo pipefail

echo "Cleaning build artifacts..."

# Rust
echo "  → cargo clean"
cd rust-core && cargo clean && cd ..

# Swift
echo "  → Removing build/ directory"
rm -rf build/

# Xcode derived data
echo "  → Removing DerivedData"
rm -rf ~/Library/Developer/Xcode/DerivedData/AgentTalk-*

# Generated FFI files (preserve committed ones)
echo "  → Removing generated FFI files"
rm -f rust-core/generated/SwiftBridgeCore.swift
rm -f rust-core/generated/SwiftBridgeCore.h
rm -f rust-core/generated/agent-talk-core/agent-talk-core.swift
rm -f rust-core/generated/agent-talk-core/agent-talk-core.h
rm -f AgentTalk/Bridge/SwiftBridgeCore.swift
rm -f AgentTalk/Bridge/SwiftBridgeCore.h
rm -f AgentTalk/Bridge/agent-talk-core.swift
rm -f AgentTalk/Bridge/agent-talk-core.h

echo "Clean complete."
