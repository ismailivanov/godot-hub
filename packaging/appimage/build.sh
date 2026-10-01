#!/bin/sh
set -eu

# APPIMAGE_ARCH picks the AppImage architecture (x86_64 or aarch64, default x86_64).
# APPIMAGE_RUNTIME optionally points to the type2 runtime for that architecture;
# without it, appimagetool fetches the runtime itself.
if [ "$#" -ne 2 ]; then
	echo "Usage: APPIMAGETOOL=/path/to/appimagetool [APPIMAGE_ARCH=x86_64|aarch64]" \
		"[APPIMAGE_RUNTIME=/path/to/runtime] $0 <GodotHub binary> <output.AppImage>" >&2
	exit 2
fi

arch=${APPIMAGE_ARCH:-x86_64}
case "$arch" in
	x86_64 | aarch64) ;;
	*)
		echo "Unsupported APPIMAGE_ARCH: $arch (expected x86_64 or aarch64)" >&2
		exit 2
		;;
esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
binary=$(realpath "$1")
output=$(realpath -m "$2")
appimagetool=${APPIMAGETOOL:-appimagetool}
runtime=${APPIMAGE_RUNTIME:-}
if [ -n "$runtime" ]; then
	runtime=$(realpath "$runtime")
fi
work_dir=$(mktemp -d)
app_dir="$work_dir/GodotHub.AppDir"
trap 'rm -rf "$work_dir"' EXIT

install -Dm755 "$binary" "$app_dir/usr/bin/GodotHub"
install -Dm644 "$script_dir/GodotHub.desktop" \
	"$app_dir/usr/share/applications/GodotHub.desktop"
app_version=$(sed -n 's/^config\/version="\([^"]*\)"$/\1/p' "$project_dir/project.godot")
if [ -z "$app_version" ]; then
	echo "Could not read application version from project.godot" >&2
	exit 1
fi
sed -i "s/@APP_VERSION@/$app_version/" \
	"$app_dir/usr/share/applications/GodotHub.desktop"
install -Dm644 "$project_dir/assets/logo/logo.svg" \
	"$app_dir/usr/share/icons/hicolor/scalable/apps/godothub.svg"
ln -s usr/bin/GodotHub "$app_dir/AppRun"
ln -s usr/share/applications/GodotHub.desktop "$app_dir/GodotHub.desktop"
ln -s usr/share/icons/hicolor/scalable/apps/godothub.svg "$app_dir/godothub.svg"
ln -s godothub.svg "$app_dir/.DirIcon"

mkdir -p "$(dirname "$output")"
if [ -n "$runtime" ]; then
	ARCH=$arch APPIMAGE_EXTRACT_AND_RUN=1 "$appimagetool" --runtime-file "$runtime" \
		"$app_dir" "$output"
else
	ARCH=$arch APPIMAGE_EXTRACT_AND_RUN=1 "$appimagetool" "$app_dir" "$output"
fi
