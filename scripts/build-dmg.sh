#!/bin/zsh
set -eu

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_zip="$project_dir/../GarHub.zip"
if [[ ! -f "$app_zip" ]]; then
  echo 'Run zsh scripts/build-app.sh first.' >&2
  exit 1
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/volume"
ditto -x -k "$app_zip" "$stage/volume"
app="$stage/volume/GarHub.app"
codesign --verify --deep --strict "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
archs="$(lipo -archs "$app/Contents/MacOS/GarminTrainingHub")"
archs="${archs// /-}"
ln -s /Applications "$stage/volume/Applications"
name="GarHub-$version-$archs.dmg"
hdiutil create -volname 'GarHub' -srcfolder "$stage/volume" -format UDZO "$stage/$name"
hdiutil verify "$stage/$name"
mv -f "$stage/$name" "$project_dir/../$name"
printf 'Built %s\n' "$project_dir/../$name"
