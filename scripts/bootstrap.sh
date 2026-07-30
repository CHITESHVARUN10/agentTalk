#!/usr/bin/env bash
set -euo pipefail

echo "Bootstrapping AgentTalk development environment..."

# Verify prerequisites
command -v rustup >/dev/null 2>&1 || { echo "Install rustup: https://rustup.rs"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "Install Xcode from the App Store"; exit 1; }

# Install/update Rust toolchain
echo "Updating Rust toolchain..."
rustup update stable
rustup component add rustfmt clippy
rustup target add aarch64-apple-darwin

# Install xcodegen
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Installing xcodegen..."
    brew install xcodegen
fi

# Generate Xcode project
echo "Generating Xcode project..."
xcodegen generate --spec project.yml

# Fetch Rust dependencies (warm caches)
echo "Fetching Rust dependencies..."
cd rust-core && cargo fetch && cd ..

# Setup model
echo ""
./scripts/setup-model.sh

echo ""
echo "Bootstrap complete."
echo "Run 'make build' to build the project."
echo "Run 'make run' to build and launch."
