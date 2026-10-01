extends RefCounted
## Pure platform-specific helpers shared by release selection and update installation.

## Values of [method Engine.get_architecture_name] that Godot Hub is released for.
const ARCH_X86_64 := "x86_64"
const ARCH_ARM64 := "arm64"
## Name of the AppImage copied into the update directory. The update script moves it over
## the running AppImage, so it does not need to carry the architecture.
const STAGED_APPIMAGE_NAME := "GodotHub.AppImage"
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


## Returns the path of the AppImage this Hub runs from, or an empty string.
static func running_appimage_path() -> String:
	return appimage_path(OS.get_environment("APPIMAGE"))


static func stage_appimage(downloaded_path: String, update_dir: String) -> String:
	var staged_path := update_dir.path_join(STAGED_APPIMAGE_NAME)
	if DirAccess.copy_absolute(downloaded_path, staged_path) != OK:
		return ""
	return staged_path


## Returns the release asset names a Hub running on [param platform] ([method OS.get_name])
## and [param arch] ([method Engine.get_architecture_name]) can update itself from, in
## order of preference. A Hub only ever gets assets built for its own CPU, except on macOS
## where the single universal build serves every Mac. Empty when no build matches.
static func asset_candidates(
	platform: String, prefer_appimage := false, arch := Engine.get_architecture_name()
) -> Array[String]:
	if platform == "macOS":
		return ["GodotHub-macOS.zip", "MacOS.zip", "macOS.zip", "Mac.zip"]
	if arch == ARCH_X86_64:
		if platform == "Windows":
			return ["GodotHub-Windows.zip", "Windows.zip", "Windows.Desktop.zip"]
		if platform == "Linux":
			if prefer_appimage:
				return ["GodotHub-x86_64.AppImage"]
			return ["GodotHub-Linux.zip", "Linux.zip", "LinuxX11.zip", "Linux.x86_64.zip"]
	elif arch == ARCH_ARM64:
		if platform == "Windows":
			return ["GodotHub-Windows-arm64.zip"]
		if platform == "Linux":
			if prefer_appimage:
				return ["GodotHub-aarch64.AppImage"]
			return ["GodotHub-Linux-arm64.zip"]
	return []


## Returns the name of the Linux executable inside the release zip for [param arch].
static func linux_executable_name(arch := Engine.get_architecture_name()) -> String:
	if arch == ARCH_ARM64:
		return "GodotHub.arm64"
	return "GodotHub.x86_64"
