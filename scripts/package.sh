#!/usr/bin/env bash
# Package AgentTalk into a distributable DMG.
#
# Usage:
#   ./scripts/package.sh              # release build + DMG (ad-hoc signed)
#   ./scripts/package.sh --sign       # sign with Developer ID if available
#   ./scripts/package.sh --skip-build # package existing build/Release app
#
# Output: dist/AgentTalk-<version>-<arch>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="0.1.0"
ARCH="$(uname -m)"                    # arm64 or x86_64
SIGN=false
SKIP_BUILD=false
for arg in "$@"; do
    case "$arg" in
        --sign) SIGN=true ;;
        --skip-build) SKIP_BUILD=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

APP_NAME="AgentTalk"
APP_DIR="$ROOT/build/Release/$APP_NAME.app"
DIST_DIR="$ROOT/dist"
DMG_NAME="AgentTalk-${VERSION}-${ARCH}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

# Detect Developer ID identity (optional). Without it we ad-hoc sign.
SIGN_IDENTITY="${AGENTTALK_SIGN_IDENTITY:-}"
if [ "$SIGN" = true ] && [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/{print $2; exit}')
    if [ -z "$SIGN_IDENTITY" ]; then
        echo "WARNING: --sign requested but no Developer ID Application identity found." >&2
        echo "         Falling back to ad-hoc signing (Gatekeeper will warn users)." >&2
        SIGN=false
    fi
fi

# ── Build ──────────────────────────────────────────────────
if [ "$SKIP_BUILD" = false ]; then
    echo "==> Building release app..."
    ./scripts/build.sh
fi

if [ ! -d "$APP_DIR" ]; then
    echo "ERROR: $APP_DIR not found. Run ./scripts/build.sh first." >&2
    exit 1
fi

# ── Sign ───────────────────────────────────────────────────
# Entitlements file (cleaned for release: no get-task-allow).
ENTITLEMENTS="$ROOT/AgentTalk/AgentTalk.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    SIGN_FLAGS=(--entitlements "$ENTITLEMENTS")
else
    SIGN_FLAGS=()
fi

if [ "$SIGN" = true ]; then
    echo "==> Signing with Developer ID: $SIGN_IDENTITY"
    codesign --force --deep --options runtime --timestamp \
        "${SIGN_FLAGS[@]}" \
        --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    echo "==> Ad-hoc signing (internally consistent; Gatekeeper will still warn)"
    codesign --force --deep "${SIGN_FLAGS[@]}" --sign - "$APP_DIR"
fi

# Verify signature + entitlements
codesign --verify --deep --strict "$APP_DIR" \
    || { echo "ERROR: codesign verify failed" >&2; exit 1; }
echo "==> Signature verified: $(codesign -dv "$APP_DIR" 2>&1 | grep -E 'Signature=')"

# ── DMG ────────────────────────────────────────────────────
echo "==> Creating DMG..."
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

STAGING_DIR="$(mktemp -d)"
STAGING_APP="$STAGING_DIR/$APP_NAME.app"
cp -R "$APP_DIR" "$STAGING_APP"

# Symlink to /Applications for drag-to-install
ln -s /Applications "$STAGING_DIR/Applications"

# License/readme on the volume (optional)
if [ -f README.md ]; then
    cp README.md "$STAGING_DIR/README.md" 2>/dev/null || true
fi

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo ""
echo "==> Package complete: $DMG_PATH"
if [ "$SIGN" = false ]; then
    echo ""
    echo "NOTE: This DMG is ad-hoc signed (not Developer ID). Users will need to:"
    echo "  - Right-click the app → Open, or"
    echo "  - Run: xattr -dr com.apple.quarantine /Applications/AgentTalk.app"
    echo "Sign with a Developer ID Application cert for Gatekeeper-clean installs:"
    echo "  AGENTTALK_SIGN_IDENTITY='<identity>' ./scripts/package.sh --sign"
fi
