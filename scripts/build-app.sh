#!/bin/zsh
set -eu
HUB_PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HUB_BUILD_DIR="${TRAINING_HUB_BUILD_DIR:-$HUB_PROJECT_DIR/build}"
HUB_CACHE_DIR="${TRAINING_HUB_CACHE_DIR:-$HUB_BUILD_DIR/cache}"
HUB_CONFIG_DIR="${TRAINING_HUB_CONFIG_DIR:-$HUB_BUILD_DIR/config}"
HUB_OUTPUT_ZIP="$HUB_PROJECT_DIR/../GarHub.zip"
HUB_STAGE_DIR="$(mktemp -d /private/tmp/training-hub-package.XXXXXX)"
trap 'rm -rf "$HUB_STAGE_DIR"' EXIT
HUB_APP="$HUB_STAGE_DIR/GarHub.app"
export CLANG_MODULE_CACHE_PATH="$HUB_BUILD_DIR/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$HUB_BUILD_DIR/module-cache"
swift build --package-path "$HUB_PROJECT_DIR" --scratch-path "$HUB_BUILD_DIR" --cache-path "$HUB_CACHE_DIR" --config-path "$HUB_CONFIG_DIR" --disable-sandbox --build-system native -c release --product GarminTrainingHub
HUB_BIN_DIR="$(swift build --package-path "$HUB_PROJECT_DIR" --scratch-path "$HUB_BUILD_DIR" --cache-path "$HUB_CACHE_DIR" --config-path "$HUB_CONFIG_DIR" --disable-sandbox --build-system native -c release --show-bin-path)"
mkdir -p "$HUB_APP/Contents/MacOS" "$HUB_APP/Contents/Resources" "$HUB_APP/Contents/Frameworks"
cp "$HUB_BIN_DIR/GarminTrainingHub" "$HUB_APP/Contents/MacOS/GarminTrainingHub"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$HUB_APP/Contents/MacOS/GarminTrainingHub"
strip -S "$HUB_APP/Contents/MacOS/GarminTrainingHub"
xcrun swift-stdlib-tool --copy --scan-executable "$HUB_APP/Contents/MacOS/GarminTrainingHub" --platform macosx --destination "$HUB_APP/Contents/Frameworks" --sign -
for HUB_SIGNING_BACKUP in "$HUB_APP/Contents/Frameworks/"*.original(N); do
    rm -f "$HUB_SIGNING_BACKUP"
done
cp "$HUB_PROJECT_DIR/Resources/Info.plist" "$HUB_APP/Contents/Info.plist"
cp "$HUB_PROJECT_DIR/Resources/AppIcon.icns" "$HUB_APP/Contents/Resources/AppIcon.icns"
cp -R "$HUB_PROJECT_DIR/Resources/ThirdPartyLicenses" "$HUB_APP/Contents/Resources/"
xattr -cr "$HUB_APP"
codesign --force --sign - "$HUB_APP"
codesign --verify --deep --strict "$HUB_APP"
ditto -c -k --norsrc --keepParent "$HUB_APP" "$HUB_OUTPUT_ZIP"
echo "Built: $HUB_OUTPUT_ZIP"
