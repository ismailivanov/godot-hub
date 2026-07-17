extends RefCounted
## Pure platform-specific helpers shared by release selection and update installation.

const LINUX_UPDATE_SCRIPT := """#!/bin/sh
pid="$1"
current_exe="$2"
new_exe="$3"
update_dir="$4"
while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
old_exe="${current_exe}.old"
rm -f "$old_exe"
mv "$current_exe" "$old_exe" || exit 1
if mv "$new_exe" "$current_exe"; then
	chmod +x "$current_exe"
	nohup "$current_exe" >/dev/null 2>&1 &
	rm -f "$old_exe"
	rm -rf "$update_dir"
else
	mv "$old_exe" "$current_exe"
	exit 1
fi
"""


static func appimage_path(environment_path: String) -> String:
	if OS.has_feature("linux") and FileAccess.file_exists(environment_path):
		return environment_path.simplify_path()
	return ""


static func asset_candidates(platform: String, prefer_appimage := false) -> Array[String]:
	if platform == "Windows":
		return ["GodotHub-Windows.zip", "Windows.zip", "Windows.Desktop.zip"]
	if platform == "macOS":
		return ["GodotHub-macOS.zip", "MacOS.zip", "macOS.zip", "Mac.zip"]
	if platform == "Linux":
		if prefer_appimage:
			return ["GodotHub-x86_64.AppImage"]
		return ["GodotHub-Linux.zip", "Linux.zip", "LinuxX11.zip", "Linux.x86_64.zip"]
	return []
