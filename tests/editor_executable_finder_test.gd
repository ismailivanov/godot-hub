extends Node
## Tests [method RemoteEditorInstallControl.find_editor_executable] on the files of
## editor downloads for each platform and Godot era, listed like
## [method edir.list_recursive] lists an extracted archive.


## Where the listed archives are extracted.
const ROOT := "/home/user/.local/share/godot/app_userdata/GodotHub/versions/build"

var _failures := 0


func _ready() -> void:
	_test_linux_builds()
	_test_linux_dotnet_builds()
	_test_linux_choices()
	_test_windows_builds()
	_test_macos_builds()
	_test_nothing_to_install()
	_test_other_platforms()
	_test_versions_folder_names()
	_test_editor_names()
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Editor executable finder tests passed.")
	get_tree().quit()


func _test_linux_builds() -> void:
	for editor: String in [
		"Godot_v4.7.2-stable_linux.x86_64",
		"Godot_v4.8-dev6_linux.x86_64",
		"Godot_v4.7.2-stable_linux.arm64",
		"Godot_v4.7.2-stable_linux.arm32",
		"Godot_v4.7.2-stable_linux.x86_32",
		"Godot_v3.6.2-stable_x11.64",
		"Godot_v3.6.2-stable_x11.32",
		"Godot_v2.1.6-stable_x11.64",
	]:
		_check_found("Linux", [editor], editor)
	# A drag and drop keeps the dots of the archive name in the folder it fills.
	_check_found(
		"Linux",
		["Godot_v4.7.2-stable_linux.x86_64/", "Godot_v4.7.2-stable_linux.x86_64/Godot"],
		"",
	)
	_check_found(
		"Linux",
		[
			"Godot_v4.7.2-stable_linux.x86_64/",
			"Godot_v4.7.2-stable_linux.x86_64/Godot_v4.7.2-stable_linux.x86_64",
		],
		"Godot_v4.7.2-stable_linux.x86_64/Godot_v4.7.2-stable_linux.x86_64",
	)
	# Builds of other engines and custom builds have other names.
	_check_found("Linux", ["Redot_v4.3-stable_linux.x86_64"], "Redot_v4.3-stable_linux.x86_64")
	_check_found(
		"Linux", ["godot.linuxbsd.editor.x86_64"], "godot.linuxbsd.editor.x86_64"
	)


func _test_linux_dotnet_builds() -> void:
	var dev := "Godot_v4.8-dev6_mono_linux_x86_64/"
	_check_found(
		"Linux",
		[
			dev,
			dev + "Godot_v4.8-dev6_mono_linux.x86_64",
			dev + "GodotSharp/",
			dev + "GodotSharp/Api/",
			dev + "GodotSharp/Api/Release/",
			dev + "GodotSharp/Api/Release/GodotSharp.dll",
			dev + "GodotSharp/Api/Release/GodotSharp.xml",
			dev + "GodotSharp/Tools/",
			dev + "GodotSharp/Tools/Godot.NET.Sdk.4.8.0-dev.6.nupkg",
			# The .NET runtime is never the editor, whatever its files are named.
			dev + "GodotSharp/Tools/Godot.Tools.x86_64",
		],
		dev + "Godot_v4.8-dev6_mono_linux.x86_64",
	)
	_check_found(
		"Linux", [dev + "GodotSharp/", dev + "GodotSharp/Tools/Godot.Tools.x86_64"], ""
	)
	var arm := "Godot_v4.7.2-stable_mono_linux_arm64/"
	_check_found(
		"Linux",
		[
			arm,
			arm + "GodotSharp/",
			arm + "GodotSharp/Api/",
			arm + "GodotSharp/Api/Release/",
			arm + "GodotSharp/Api/Release/GodotSharp.dll",
			arm + "Godot_v4.7.2-stable_mono_linux.arm64",
		],
		arm + "Godot_v4.7.2-stable_mono_linux.arm64",
	)
	var old := "Godot_v3.6.2-stable_mono_x11_64/"
	_check_found(
		"Linux",
		[
			old,
			old + "Godot_v3.6.2-stable_mono_x11.64",
			old + "GodotSharp/",
			old + "GodotSharp/Mono/",
			old + "GodotSharp/Mono/lib/",
			old + "GodotSharp/Mono/lib/libmono-native.so",
			old + "GodotSharp/Mono/lib/mono/4.5/mcs.exe",
		],
		old + "Godot_v3.6.2-stable_mono_x11.64",
	)


func _test_linux_choices() -> void:
	# Builds for two architectures: only the user knows which one runs here.
	_check_found(
		"Linux", ["Godot_v4.7.2-stable_linux.x86_64", "Godot_v4.7.2-stable_linux.arm64"], ""
	)
	# Files named Godot come first, then the ones closest to the root.
	_check_found(
		"Linux",
		["bin/", "bin/Godot_v4.7.2-stable_linux.x86_64", "tool.x86_64"],
		"bin/Godot_v4.7.2-stable_linux.x86_64",
	)
	_check_found(
		"Linux",
		["Godot_v4.7.2-stable_linux.x86_64", "extra/", "extra/Godot_v4.7.2-stable_linux.arm64"],
		"Godot_v4.7.2-stable_linux.x86_64",
	)
	# Data files are never the editor, nor the AppleDouble files of macOS archivers.
	_check_found(
		"Linux",
		[
			"Godot_v4.7.2-stable_linux.x86_64",
			"Godot_v4.7.2-stable_linux.pck",
			"libgodot.so",
			"__MACOSX/",
			"__MACOSX/Godot_v4.7.2-stable_linux.arm64",
			"._Godot_v4.7.2-stable_linux.arm64",
		],
		"Godot_v4.7.2-stable_linux.x86_64",
	)
	_check_found("Linux", ["__MACOSX/", "__MACOSX/Godot_v4.7.2-stable_linux.x86_64"], "")
	# A game exported for Linux is found too; installing it asks first.
	_check_found("Linux", ["MyGame.x86_64", "MyGame.pck"], "MyGame.x86_64")
	_check_found(
		"Linux",
		["MyGame.x86_64", "Redot_v4.3-stable_linux.x86_64"],
		"Redot_v4.3-stable_linux.x86_64",
	)


func _test_windows_builds() -> void:
	for editor: String in [
		"Godot_v4.7.2-stable_win64.exe",
		"Godot_v4.7.2-stable_win32.exe",
		"Godot_v4.7.2-stable_windows_arm64.exe",
		"Godot_v4.8-dev6_win64.exe",
	]:
		var console := editor.get_basename() + "_console.exe"
		_check_found("Windows", [editor, console], editor)
		_check_found("Windows", [console, editor], editor)
	_check_found("Windows", ["Godot_v3.6.2-stable_win64.exe"], "Godot_v3.6.2-stable_win64.exe")
	_check_found("Windows", ["GODOT.EXE"], "GODOT.EXE")

	var mono := "Godot_v4.7.2-stable_mono_win64/"
	_check_found(
		"Windows",
		[
			mono,
			mono + "Godot_v4.7.2-stable_mono_win64_console.exe",
			mono + "Godot_v4.7.2-stable_mono_win64.exe",
			mono + "GodotSharp/",
			mono + "GodotSharp/Api/",
			mono + "GodotSharp/Api/Release/",
			mono + "GodotSharp/Api/Release/GodotSharp.dll",
		],
		mono + "Godot_v4.7.2-stable_mono_win64.exe",
	)
	var old_mono := "Godot_v3.6.2-stable_mono_win64/"
	_check_found(
		"Windows",
		[
			old_mono,
			old_mono + "GodotSharp/",
			old_mono + "GodotSharp/Mono/",
			old_mono + "GodotSharp/Mono/bin/",
			old_mono + "GodotSharp/Mono/bin/Godot.Tools.exe",
			old_mono + "GodotSharp/Mono/lib/mono/4.5/csc.exe",
			old_mono + "Godot_v3.6.2-stable_mono_win64.exe",
		],
		old_mono + "Godot_v3.6.2-stable_mono_win64.exe",
	)
	# Only a console build: the user decides.
	_check_found("Windows", ["Godot_v4.7.2-stable_win64_console.exe"], "")
	_check_found("Windows", ["Godot_v4.7.2-stable_win64.exe", "Godot_v4.7.2-stable_win32.exe"], "")
	_check_found("Windows", ["Godot_v4.7.2-stable_linux.x86_64"], "")


func _test_macos_builds() -> void:
	for app: String in ["Godot.app", "Godot_mono.app"]:
		_check_found(
			"macOS",
			[
				app + "/",
				app + "/Contents/",
				app + "/Contents/Info.plist",
				app + "/Contents/MacOS/",
				app + "/Contents/MacOS/Godot",
				app + "/Contents/Resources/",
				app + "/Contents/Resources/GodotSharp/",
				app + "/Contents/Resources/GodotSharp/Tools/",
				# Helper apps inside the bundle are deeper than the bundle.
				app + "/Contents/Helpers/",
				app + "/Contents/Helpers/Godot Helper.app/",
			],
			app,
		)
	_check_found("macOS", ["Godot.app/", "Godot_mono.app/"], "")
	# Only folders are app bundles.
	_check_found("macOS", ["Godot.app"], "")
	_check_found("macOS", ["__MACOSX/", "__MACOSX/._Godot.app/", "Godot.app/"], "Godot.app")
	_check_found("macOS", ["Godot_v4.7.2-stable_win64.exe"], "")


func _test_nothing_to_install() -> void:
	for os_name: String in ["Linux", "Windows", "macOS"]:
		_check_found(os_name, [], "")
		_check_found(os_name, ["README.txt", "data/", "data/editor.pck"], "")


func _test_other_platforms() -> void:
	_check_found("FreeBSD", ["Godot_v4.7.2-stable_linux.x86_64"], "")
	_check_found("Android", ["Godot.app/", "Godot_v4.7.2-stable_win64.exe"], "")


## Only the folders of the archive are looked at, not those the versions folder is in.
func _test_versions_folder_names() -> void:
	for root: String in [
		"/home/user/GodotSharp/versions/build",
		"/Volumes/__MACOSX/versions/build",
		"C:/Users/user/GodotSharp/versions/build",
		"user://versions/build",
		"/build",
	]:
		_check_found(
			"Linux",
			["Godot_v4.7.2-stable_linux.x86_64", "GodotSharp/", "GodotSharp/Godot.x86_64"],
			"Godot_v4.7.2-stable_linux.x86_64",
			root,
		)
		var win := "Godot_v4.7.2-stable_win64.exe"
		_check_found("Windows", [win, "GodotSharp/", "GodotSharp/Godot.exe"], win, root)
		_check_found("macOS", ["Godot.app/", "Godot.app/Contents/"], "Godot.app", root)


func _test_editor_names() -> void:
	for path: String in [
		"Godot_v4.7.2-stable_linux.x86_64",
		"/versions/build/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64.exe",
		"/versions/build/Godot.app",
		"/versions/build/Godot_mono.app",
		"/versions/build/GODOT.EXE",
		"godot.linuxbsd.editor.x86_64",
		"Redot_v4.3-stable_linux.x86_64",
	]:
		_check(
			RemoteEditorInstallControl.is_named_like_editor(path),
			"%s should be named like an editor" % path,
		)
	for path: String in [
		"/versions/build/MyGame.x86_64",
		"/versions/godot/MyGame.exe",
		"/versions/build/MyGame.app",
		"",
	]:
		_check(
			not RemoteEditorInstallControl.is_named_like_editor(path),
			"%s should not be named like an editor" % path,
		)


## Checks that [param os_name] finds [param expected] (relative to [param root], or
## nothing when empty) in [param entries] listed in [param root], given in that order and
## reversed. Entries ending with a slash are folders.
func _check_found(os_name: String, entries: Array, expected: String, root := ROOT) -> void:
	var listing := _listing(entries, root)
	var want := "" if expected.is_empty() else root.path_join(expected)
	var got := RemoteEditorInstallControl.find_editor_executable(listing, os_name)
	_check(got == want, "%s in %s: expected \"%s\", got \"%s\"" % [os_name, entries, want, got])
	listing.reverse()
	got = RemoteEditorInstallControl.find_editor_executable(listing, os_name)
	_check(got == want, "%s in reversed %s: expected \"%s\", got \"%s\"" % [
		os_name, entries, want, got,
	])


func _listing(entries: Array, root: String) -> Array[edir.DirListResult]:
	var result: Array[edir.DirListResult] = []
	for entry: String in entries:
		var is_dir := entry.ends_with("/")
		result.append(edir.DirListResult.new(root.path_join(entry.trim_suffix("/")), is_dir))
	return result


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
