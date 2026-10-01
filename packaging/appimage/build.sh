#!/bin/sh
set -eu

# APPIMAGE_ARCH picks the AppImage architecture (x86_64 or aarch64, default x86_64).
# APPIMAGE_RUNTIME optionally points to the type2 runtime for that architecture;
# without it, appimagetool fetches the runtime itself.
# APPIMAGE_UPDATE_INFO overrides the update information embedded in the AppImage; an empty
# value embeds none. By default it points to GodotHub-<arch>.AppImage.zsync in the latest
# GitHub release, and <output>.zsync is written next to the AppImage for that release.
if [ "$#" -ne 2 ]; then
	echo "Usage: APPIMAGETOOL=/path/to/appimagetool [APPIMAGE_ARCH=x86_64|aarch64]" \
		"[APPIMAGE_RUNTIME=/path/to/runtime] [APPIMAGE_UPDATE_INFO=...]" \
		"$0 <GodotHub binary> <output.AppImage>" >&2
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

# The AppStream component ID; the desktop file and the AppStream metadata are named after it.
app_id=io.github.ismailivanov.GodotHub
update_info=${APPIMAGE_UPDATE_INFO-"gh-releases-zsync|ismailivanov|godot-hub|latest|GodotHub-$arch.AppImage.zsync"}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
binary=$(realpath "$1")
output=$(realpath -m "$2")
output_dir=$(dirname "$output")
appimagetool=${APPIMAGETOOL:-appimagetool}
case "$appimagetool" in
	*/*) appimagetool=$(realpath "$appimagetool") ;;
esac
runtime=${APPIMAGE_RUNTIME:-}
if [ -n "$runtime" ]; then
	runtime=$(realpath "$runtime")
fi
work_dir=$(mktemp -d)
app_dir="$work_dir/GodotHub.AppDir"
trap 'rm -rf "$work_dir"' EXIT

app_version=$(sed -n 's/^config\/version="\([^"]*\)"$/\1/p' "$project_dir/project.godot")
if [ -z "$app_version" ]; then
	echo "Could not read application version from project.godot" >&2
	exit 1
fi
# The release date is the day (UTC) of the commit being built, so rebuilding a release
# gives the same metadata; outside a git checkout it is today.
release_date=$(TZ=UTC git -C "$project_dir" log -1 --format=%cd \
	--date=format-local:%Y-%m-%d 2>/dev/null || true)
if [ -z "$release_date" ]; then
	release_date=$(date -u +%Y-%m-%d)
fi

# Installs <source> as <destination>, with the version and release date filled in.
install_template() {
	install -Dm644 "$1" "$2"
	sed -i -e "s/@APP_VERSION@/$app_version/g" -e "s/@RELEASE_DATE@/$release_date/g" "$2"
}

install -Dm755 "$binary" "$app_dir/usr/bin/GodotHub"
install_template "$script_dir/$app_id.desktop" \
	"$app_dir/usr/share/applications/$app_id.desktop"
install_template "$script_dir/$app_id.appdata.xml" \
	"$app_dir/usr/share/metainfo/$app_id.appdata.xml"
install -Dm644 "$project_dir/assets/logo/logo.svg" \
	"$app_dir/usr/share/icons/hicolor/scalable/apps/godothub.svg"
ln -s usr/bin/GodotHub "$app_dir/AppRun"
ln -s "usr/share/applications/$app_id.desktop" "$app_dir/$app_id.desktop"
ln -s usr/share/icons/hicolor/scalable/apps/godothub.svg "$app_dir/godothub.svg"
ln -s godothub.svg "$app_dir/.DirIcon"

# appimagetool's own AppStream check looks the screenshots up online, so it fails without
# network access or before new screenshots are pushed. Check the metadata offline instead.
if command -v appstreamcli >/dev/null 2>&1; then
	appstreamcli validate-tree --no-net "$app_dir"
else
	echo "appstreamcli not found, skipping the AppStream metadata check" >&2
fi

set -- --no-appstream
if [ -n "$runtime" ]; then
	set -- "$@" --runtime-file "$runtime"
fi
if [ -n "$update_info" ]; then
	set -- "$@" --updateinformation "$update_info"
fi

mkdir -p "$output_dir"
rm -f "$output.zsync"
# zsyncmake writes the .zsync file into the working directory, so build from the output's.
(
	cd "$output_dir"
	ARCH=$arch APPIMAGE_EXTRACT_AND_RUN=1 "$appimagetool" "$@" "$app_dir" "$output"
)

if [ -n "$update_info" ] && [ ! -s "$output.zsync" ]; then
	echo "appimagetool did not write $output.zsync (is zsyncmake missing?)" >&2
	exit 1
fi
