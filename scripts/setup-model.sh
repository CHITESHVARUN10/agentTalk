#!/usr/bin/env bash
set -euo pipefail

MODEL_DIR="${HOME}/Library/Application Support/AgentTalk/models"
MODEL_FILE="${MODEL_DIR}/ggml-large-v3-turbo.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"

# Update this after first download by running:
#   shasum -a 256 ggml-large-v3-turbo.bin
EXPECTED_SHA256=""

mkdir -p "${MODEL_DIR}"

if [ -f "${MODEL_FILE}" ]; then
    echo "Model already exists at ${MODEL_FILE}"

    if [ -n "${EXPECTED_SHA256}" ]; then
        ACTUAL=$(shasum -a 256 "${MODEL_FILE}" | cut -d' ' -f1)
        if [ "${ACTUAL}" != "${EXPECTED_SHA256}" ]; then
            echo ""
            echo "WARNING: Checksum mismatch!"
            echo "  Expected: ${EXPECTED_SHA256}"
            echo "  Got:      ${ACTUAL}"
            echo ""
            echo "Re-downloading..."
            rm "${MODEL_FILE}"
        else
            echo "Checksum verified."
            exit 0
        fi
    else
        echo "Checksum verification skipped (EXPECTED_SHA256 not set)."
        CURRENT=$(shasum -a 256 "${MODEL_FILE}" | cut -d' ' -f1)
        echo "Current SHA256: ${CURRENT}"
        echo "Update EXPECTED_SHA256 in this script once verified."
        exit 0
    fi
fi

echo "Downloading whisper large-v3-turbo model (~1.5 GB)..."
echo "URL: ${MODEL_URL}"
curl -L --progress-bar -o "${MODEL_FILE}" "${MODEL_URL}"

echo ""
echo "Download complete."
COMPUTED=$(shasum -a 256 "${MODEL_FILE}" | cut -d' ' -f1)
echo "SHA256: ${COMPUTED}"

if [ -n "${EXPECTED_SHA256}" ]; then
    if [ "${COMPUTED}" = "${EXPECTED_SHA256}" ]; then
        echo "Checksum verified."
    else
        echo ""
        echo "ERROR: Checksum mismatch!"
        echo "  Expected: ${EXPECTED_SHA256}"
        echo "  Got:      ${COMPUTED}"
        rm "${MODEL_FILE}"
        exit 1
    fi
else
    echo ""
    echo "Update EXPECTED_SHA256 in this script and in rust-core/src/model_manager/mod.rs:"
    echo "  EXPECTED_SHA256=\"${COMPUTED}\""
fi
