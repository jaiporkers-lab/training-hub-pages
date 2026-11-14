#!/bin/zsh
set -eu
HUB_PREVIEW_PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
export TRAINING_HUB_INFO_PLIST="$HUB_PREVIEW_PROJECT/Resources/AI-Preview-Info.plist"
export TRAINING_HUB_OUTPUT_ZIP="${TRAINING_HUB_AI_PREVIEW_ZIP:-$HUB_PREVIEW_PROJECT/../GarHub-AI-Preview.zip}"
export TRAINING_HUB_BUNDLE_NAME="GarHub AI Preview.app"
zsh "$HUB_PREVIEW_PROJECT/scripts/build-app.sh"
