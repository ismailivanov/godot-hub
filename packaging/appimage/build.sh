#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
	echo "Usage: APPIMAGETOOL=/path/to/appimagetool $0 <GodotHub.x86_64> <output.AppImage>" >&2
	exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
binary=$(realpath "$1")
output=$(realpath -m "$2")
appimagetool=${APPIMAGETOOL:-appimagetool}
work_dir=$(mktemp -d)
app_dir="$work_dir/GodotHub.AppDir"
trap 'rm -rf "$work_dir"' EXIT

install -Dm755 "$binary" "$app_dir/usr/bin/GodotHub"
install -Dm644 "$script_dir/GodotHub.desktop" \
	"$app_dir/usr/share/applications/GodotHub.desktop"
install -Dm644 "$project_dir/assets/logo/logo.svg" \
	"$app_dir/usr/share/icons/hicolor/scalable/apps/godothub.svg"
ln -s usr/bin/GodotHub "$app_dir/AppRun"
ln -s usr/share/applications/GodotHub.desktop "$app_dir/GodotHub.desktop"
ln -s usr/share/icons/hicolor/scalable/apps/godothub.svg "$app_dir/godothub.svg"
ln -s godothub.svg "$app_dir/.DirIcon"

mkdir -p "$(dirname "$output")"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$appimagetool" "$app_dir" "$output"
