extends Node
## Offline tests of the release asset a Hub picks to update itself, for every platform and
## CPU architecture Godot Hub is released for, and of the files it expects inside them.


const UpdatePlatform = preload("res://src/services/update_platform.gd")

## Every asset a current release publishes: the ARM builds and the AppImages' .zsync files
## included. A .zsync file is update data for AppImageUpdate and is never picked as an update.
const RELEASE_ASSETS: Array[String] = [
	"GodotHub-Linux.zip",
	"GodotHub-Linux-arm64.zip",
	"GodotHub-Windows.zip",
	"GodotHub-Windows-arm64.zip",
	"GodotHub-macOS.zip",
	"GodotHub-x86_64.AppImage",
	"GodotHub-aarch64.AppImage",
	"GodotHub-x86_64.AppImage.zsync",
	"GodotHub-aarch64.AppImage.zsync",
	"Linux.zip",
	"Windows.zip",
	"SHA512-SUMS.txt",
]
## Every asset a release published before Godot Hub shipped ARM builds.
const X86_64_ONLY_RELEASE_ASSETS: Array[String] = [
	"GodotHub-Linux.zip",
	"GodotHub-Windows.zip",
	"GodotHub-macOS.zip",
	"GodotHub-x86_64.AppImage",
	"Linux.zip",
	"Windows.zip",
	"SHA512-SUMS.txt",
]
## Asset names, current and legacy, that hold builds for x86_64 CPUs only.
const X86_64_ASSETS: Array[String] = [
	"GodotHub-Linux.zip", "GodotHub-Windows.zip", "GodotHub-x86_64.AppImage",
	"Linux.zip", "LinuxX11.zip", "Linux.x86_64.zip", "Windows.zip", "Windows.Desktop.zip",
]
## Asset names that hold builds for arm64 CPUs only.
const ARM64_ASSETS: Array[String] = [
	"GodotHub-Linux-arm64.zip", "GodotHub-Windows-arm64.zip", "GodotHub-aarch64.AppImage",
]

var _failures := 0


func _ready() -> void:
	_test_x86_64_candidates()
	_test_arm64_candidates()
	_test_macos_candidates()
	_test_no_cross_architecture_candidates()
	_test_unsupported_targets()
	_test_default_architecture()
	_test_release_picks()
	_test_release_without_arm_builds()
	_test_linux_executable_names()
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Update assets tests passed.")
	get_tree().quit()


func _test_x86_64_candidates() -> void:
	_check_candidates("Windows", "x86_64", false, [
		"GodotHub-Windows.zip", "Windows.zip", "Windows.Desktop.zip",
	])
	_check_candidates("Windows", "x86_64", true, [
		"GodotHub-Windows.zip", "Windows.zip", "Windows.Desktop.zip",
	])
	_check_candidates("Linux", "x86_64", false, [
		"GodotHub-Linux.zip", "Linux.zip", "LinuxX11.zip", "Linux.x86_64.zip",
	])
	_check_candidates("Linux", "x86_64", true, ["GodotHub-x86_64.AppImage"])


func _test_arm64_candidates() -> void:
	_check_candidates("Windows", "arm64", false, ["GodotHub-Windows-arm64.zip"])
	_check_candidates("Windows", "arm64", true, ["GodotHub-Windows-arm64.zip"])
	_check_candidates("Linux", "arm64", false, ["GodotHub-Linux-arm64.zip"])
	_check_candidates("Linux", "arm64", true, ["GodotHub-aarch64.AppImage"])


func _test_macos_candidates() -> void:
	var universal: Array[String] = ["GodotHub-macOS.zip", "MacOS.zip", "macOS.zip", "Mac.zip"]
	for arch: String in ["x86_64", "arm64"]:
		_check_candidates("macOS", arch, false, universal)
		_check_candidates("macOS", arch, true, universal)


func _test_no_cross_architecture_candidates() -> void:
	for platform: String in ["Windows", "Linux"]:
		for prefer_appimage: bool in [false, true]:
			var x86_64 := UpdatePlatform.asset_candidates(platform, prefer_appimage, "x86_64")
			var arm64 := UpdatePlatform.asset_candidates(platform, prefer_appimage, "arm64")
			for asset_name in x86_64:
				_check(
					asset_name in X86_64_ASSETS,
					"%s is not an x86_64 build for %s" % [asset_name, platform],
				)
				_check(
					asset_name not in arm64,
					"%s is offered to both x86_64 and arm64 Hubs" % asset_name,
				)
			for asset_name in arm64:
				_check(
					asset_name in ARM64_ASSETS,
					"%s is not an arm64 build for %s" % [asset_name, platform],
				)


func _test_unsupported_targets() -> void:
	for arch: String in ["x86_32", "arm32", "rv64", "ppc64", "wasm32", ""]:
		for platform: String in ["Windows", "Linux"]:
			_check_candidates(platform, arch, false, [])
			_check_candidates(platform, arch, true, [])
	for platform: String in ["Android", "iOS", "Web", "FreeBSD", ""]:
		_check_candidates(platform, "x86_64", false, [])
		_check_candidates(platform, "arm64", false, [])


func _test_default_architecture() -> void:
	var arch := Engine.get_architecture_name()
	for platform: String in ["Windows", "Linux", "macOS"]:
		for prefer_appimage: bool in [false, true]:
			_check(
				UpdatePlatform.asset_candidates(platform, prefer_appimage)
					== UpdatePlatform.asset_candidates(platform, prefer_appimage, arch),
				"%s candidates should default to the Hub's own CPU (%s)" % [platform, arch],
			)
	_check(
		UpdatePlatform.asset_candidates("Linux") == UpdatePlatform.asset_candidates("Linux", false),
		"Zip installs are the default on Linux",
	)
	_check(
		UpdatePlatform.linux_executable_name() == UpdatePlatform.linux_executable_name(arch),
		"The Linux executable name should default to the Hub's own CPU (%s)" % arch,
	)


func _test_release_picks() -> void:
	var release := _release(RELEASE_ASSETS)
	_check_picks(release, "Windows", "x86_64", false, ["GodotHub-Windows.zip", "Windows.zip"])
	_check_picks(release, "Windows", "arm64", false, ["GodotHub-Windows-arm64.zip"])
	_check_picks(release, "Linux", "x86_64", false, ["GodotHub-Linux.zip", "Linux.zip"])
	_check_picks(release, "Linux", "x86_64", true, ["GodotHub-x86_64.AppImage"])
	_check_picks(release, "Linux", "arm64", false, ["GodotHub-Linux-arm64.zip"])
	_check_picks(release, "Linux", "arm64", true, ["GodotHub-aarch64.AppImage"])
	for arch: String in ["x86_64", "arm64"]:
		_check_picks(release, "macOS", arch, false, ["GodotHub-macOS.zip"])
	_check(
		not _release(["SHA512-SUMS.txt"]).assets[0].is_godots_bin_for_current_platform(),
		"The checksum list is never an update",
	)


func _test_release_without_arm_builds() -> void:
	var release := _release(X86_64_ONLY_RELEASE_ASSETS)
	_check_picks(release, "Windows", "arm64", false, [])
	_check_picks(release, "Linux", "arm64", false, [])
	_check_picks(release, "Linux", "arm64", true, [])
	_check_picks(release, "Linux", "x86_64", false, ["GodotHub-Linux.zip", "Linux.zip"])
	_check_picks(release, "macOS", "arm64", false, ["GodotHub-macOS.zip"])


func _test_linux_executable_names() -> void:
	_check(
		UpdatePlatform.linux_executable_name("x86_64") == "GodotHub.x86_64",
		"x86_64 Linux zips hold GodotHub.x86_64",
	)
	_check(
		UpdatePlatform.linux_executable_name("arm64") == "GodotHub.arm64",
		"arm64 Linux zips hold GodotHub.arm64",
	)


func _check_candidates(
	platform: String, arch: String, prefer_appimage: bool, expected: Array[String]
) -> void:
	var actual := UpdatePlatform.asset_candidates(platform, prefer_appimage, arch)
	_check(
		actual == expected,
		"%s/%s (AppImage: %s) should update from %s, got %s" % [
			platform, arch, prefer_appimage, expected, actual,
		],
	)


func _check_picks(
	release: GodotsReleases.Release,
	platform: String,
	arch: String,
	prefer_appimage: bool,
	expected: Array[String],
) -> void:
	var picked: Array[String] = []
	for asset in release.assets:
		if asset.is_godots_bin_for(platform, arch, prefer_appimage):
			picked.append(asset.name)
	_check(
		picked == expected,
		"%s/%s (AppImage: %s) should match %s in the release, got %s" % [
			platform, arch, prefer_appimage, expected, picked,
		],
	)


func _release(asset_names: Array[String]) -> GodotsReleases.Release:
	var assets: Array[Dictionary] = []
	for asset_name in asset_names:
		assets.append({
			"name": asset_name,
			"browser_download_url": "https://example.invalid/%s" % asset_name,
		})
	return GodotsReleases.Release.new({
		"name": "Godot Hub v1.3.0",
		"tag_name": "v1.3.0",
		"draft": false,
		"prerelease": false,
		"assets": assets,
	})


func _check(condition: bool, message: String) -> void:
	if condition: return
	_failures += 1
	push_error(message)
