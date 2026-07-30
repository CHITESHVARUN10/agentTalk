#!/usr/bin/env bash
set -euo pipefail

./scripts/build.sh

echo ""
echo "Launching AgentTalk..."
open build/Release/AgentTalk.app
