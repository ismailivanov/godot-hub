extends Node
## Offline tests of the editor build picked for each OS and CPU architecture, with the
## real asset names of godot-builds releases from every era, and of host detection.


const GITHUB := preload("res://src/components/editors/remote/remote_editors_tree/sources/github.gd")

## Every OS and architecture pair with Godot editor builds, as "os/arch".
const PLATFORMS: Array[String] = [
	"linux/x86_64", "linux/x86_32", "linux/arm64", "linux/arm32",
	"windows/x86_64", "windows/x86_32", "windows/arm64",
	"macos/universal", "macos/arm64", "macos/x86_64",
]
## Words of asset names that are never a desktop editor.
const NEVER_PICKED: Array[String] = [
	"web_editor", "android", "server", "headless", "portable", "console", "export_templates",
]

var _failures := 0


func _ready() -> void:
	_test_suffix_lists()
	_test_picks_per_era()
	_test_never_picks_other_files()
	_test_fallbacks()
	_test_asset_labels()
	_test_platform_labels()
	_test_desktop_editor_assets()
	_test_mono_detection()
	_test_arch_from_uname()
	_test_linux_arch()
	_test_windows_arch()
	_test_host_platform()
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Editor platforms tests passed.")
	get_tree().quit()


func _test_suffix_lists() -> void:
	for platform in PLATFORMS:
		var parts := platform.split("/")
		_check(
			not GITHUB.platform_suffixes(parts[0], parts[1]).is_empty(),
			"Expected suffixes for %s" % platform,
		)
	var linux := GITHUB.platform_suffixes("linux", "x86_64")
	_check(linux[0] == "_linux.x86_64.zip", "Linux x86_64 should prefer its 4.x build")
	_check(
		linux.find("_x11.64.zip") < linux.find("_linux.x86_32.zip"),
		"64-bit builds of every era come before 32-bit fallbacks",
	)
	_check(
		GITHUB.platform_suffixes("macos", "arm64")
			== GITHUB.platform_suffixes("macos", "universal"),
		"Every Mac gets the same list: universal builds, then Intel ones under Rosetta",
	)
	_check(
		not GITHUB.platform_suffixes("macos", "universal").has("_osx32.zip"),
		"32-bit Mac builds do not run on macOS 10.15 and newer",
	)
	for unsupported: Array in [
		["FreeBSD", "x86_64"], ["linux", "riscv64"], ["windows", "ia64"], ["", ""],
	]:
		_check(
			GITHUB.platform_suffixes(unsupported[0] as String, unsupported[1] as String).is_empty(),
			"Expected no suffixes for %s" % [unsupported],
		)


## The real editor files of each era, for every platform: [Standard, .NET] after the
## era's name prefix, or "" for none.
func _test_picks_per_era() -> void:
	var full_4 := {
		"linux/x86_64": ["linux.x86_64.zip", "mono_linux_x86_64.zip"],
		"linux/x86_32": ["linux.x86_32.zip", "mono_linux_x86_32.zip"],
		"linux/arm64": ["linux.arm64.zip", "mono_linux_arm64.zip"],
		"linux/arm32": ["linux.arm32.zip", "mono_linux_arm32.zip"],
		"windows/x86_64": ["win64.exe.zip", "mono_win64.zip"],
		"windows/x86_32": ["win32.exe.zip", "mono_win32.zip"],
		"windows/arm64": ["windows_arm64.exe.zip", "mono_windows_arm64.zip"],
		"macos/universal": ["macos.universal.zip", "mono_macos.universal.zip"],
	}
	_check_era("Godot_v4.7.2-stable_", _assets_4_7_2(), full_4)
	_check_era("Godot_v4.8-dev6_", _assets_4_8_dev6(), full_4)

	# Linux ARM builds start with 4.2, Windows ARM builds with 4.3: x64 runs emulated.
	var no_windows_arm := full_4.duplicate()
	no_windows_arm["windows/arm64"] = ["win64.exe.zip", "mono_win64.zip"]
	_check_era("Godot_v4.2.2-stable_", _assets_4_2_2(), no_windows_arm)
	var no_arm := no_windows_arm.duplicate()
	no_arm["linux/arm64"] = ["", ""]
	no_arm["linux/arm32"] = ["", ""]
	_check_era("Godot_v4.0-stable_", _assets_4_0(), no_arm)
	# 4.0 alpha1 to alpha14 say "linux.64" and have no .NET builds.
	var godot_4_0_alpha := {}
	for platform: String in no_arm:
		var files: Array = no_arm[platform]
		godot_4_0_alpha[platform] = [files[0], ""]
	godot_4_0_alpha["linux/x86_64"] = ["linux.64.zip", ""]
	godot_4_0_alpha["linux/x86_32"] = ["linux.32.zip", ""]
	_check_era("Godot_v4.0-alpha13_", _assets_4_0_alpha13(), godot_4_0_alpha)

	var godot_3 := {
		"linux/x86_64": ["x11.64.zip", "mono_x11_64.zip"],
		"linux/x86_32": ["x11.32.zip", "mono_x11_32.zip"],
		"linux/arm64": ["", ""],
		"linux/arm32": ["", ""],
		"windows/x86_64": ["win64.exe.zip", "mono_win64.zip"],
		"windows/x86_32": ["win32.exe.zip", "mono_win32.zip"],
		"windows/arm64": ["win64.exe.zip", "mono_win64.zip"],
		"macos/universal": ["osx.universal.zip", "mono_osx.universal.zip"],
	}
	_check_era("Godot_v3.5.3-stable_", _assets_3_5_3(), godot_3)
	# 3.6 adds Linux ARM builds, without .NET.
	var godot_3_6 := godot_3.duplicate()
	godot_3_6["linux/arm64"] = ["linux.arm64.zip", ""]
	godot_3_6["linux/arm32"] = ["linux.arm32.zip", ""]
	_check_era("Godot_v3.6-stable_", _assets_3_6(), godot_3_6)
	var godot_3_2 := godot_3.duplicate()
	godot_3_2["macos/universal"] = ["osx.64.zip", "mono_osx.64.zip"]
	_check_era("Godot_v3.2.3-stable_", _assets_3_2_3(), godot_3_2)
	var godot_3_0_6 := godot_3.duplicate()
	godot_3_0_6["macos/universal"] = ["osx.fat.zip", "mono_osx.fat.zip"]
	_check_era("Godot_v3.0.6-stable_", _assets_3_0_6(), godot_3_0_6)
	# 3.0 spells its .NET Mac build without a dot and has no 32-bit .NET Linux build.
	var godot_3_0 := godot_3_0_6.duplicate()
	godot_3_0["macos/universal"] = ["osx.fat.zip", "mono_osx64.zip"]
	godot_3_0["linux/x86_32"] = ["x11.32.zip", ""]
	_check_era("Godot_v3.0-stable_", _assets_3_0(), godot_3_0)

	var godot_2 := {
		"linux/x86_64": ["x11.64.zip", ""],
		"linux/x86_32": ["x11.32.zip", ""],
		"linux/arm64": ["", ""],
		"linux/arm32": ["", ""],
		"windows/x86_64": ["win64.exe.zip", ""],
		"windows/x86_32": ["win32.exe.zip", ""],
		"windows/arm64": ["win64.exe.zip", ""],
		"macos/universal": ["osx.fat.zip", ""],
	}
	_check_era("Godot_v2.1.6-stable_", _assets_2_1_6(), godot_2)
	# 2.0 has a 32-bit Mac build only, and no 32-bit Linux one.
	var godot_2_0 := godot_2.duplicate()
	godot_2_0["macos/universal"] = ["", ""]
	godot_2_0["linux/x86_32"] = ["", ""]
	_check_era("Godot_v2.0_stable_", _assets_2_0(), godot_2_0)
	var godot_1_1 := godot_2.duplicate()
	godot_1_1["macos/universal"] = ["", ""]
	_check_era("Godot_v1.1_stable_", _assets_1_1(), godot_1_1)
	var godot_1_0 := godot_2.duplicate()
	godot_1_0["macos/universal"] = ["osx64.zip", ""]
	_check_era("Godot_v1.0_stable_", _assets_1_0(), godot_1_0)

	var nothing := {}
	for platform: String in full_4:
		nothing[platform] = ["", ""]
	_check_era("Godot_v4.8-dev7_", _assets_4_8_dev7(), nothing)


func _test_never_picks_other_files() -> void:
	var eras: Array[PackedStringArray] = [
		_assets_4_7_2(), _assets_4_8_dev6(), _assets_4_2_2(), _assets_4_0(),
		_assets_4_0_alpha13(), _assets_3_6(), _assets_3_5_3(), _assets_3_2_3(), _assets_3_0_6(),
		_assets_3_0(), _assets_2_1_6(), _assets_2_0(), _assets_1_1(), _assets_1_0(),
		_assets_4_8_dev7(),
	]
	for names in eras:
		var assets := _assets(names)
		for platform in PLATFORMS:
			var parts := platform.split("/")
			var suffixes := GITHUB.platform_suffixes(parts[0], parts[1])
			for mono: bool in [false, true]:
				var picked := GITHUB.pick_platform_asset(assets, suffixes, mono)
				if picked == null:
					continue
				for word in NEVER_PICKED:
					_check(
						not picked.name.to_lower().contains(word),
						"%s picked %s" % [platform, picked.name],
					)


func _test_fallbacks() -> void:
	# A 64-bit system runs 32-bit builds when there is nothing else.
	var only_32 := _assets(PackedStringArray([
		"Godot_v1.0_stable_x11.32.zip", "Godot_v1.0_stable_win32.exe.zip",
	]))
	_check_pick(only_32, "linux", "x86_64", false, "Godot_v1.0_stable_x11.32.zip")
	_check_pick(only_32, "windows", "x86_64", false, "Godot_v1.0_stable_win32.exe.zip")
	_check_pick(only_32, "windows", "arm64", false, "Godot_v1.0_stable_win32.exe.zip")
	# ARM Linux runs neither x86 builds nor the other ARM width.
	var only_x86 := _assets(PackedStringArray([
		"Godot_v4.0-stable_linux.x86_64.zip", "Godot_v4.0-stable_linux.x86_32.zip",
	]))
	_check_pick(only_x86, "linux", "arm64", false, "")
	_check_pick(only_x86, "linux", "arm32", false, "")
	var only_arm64 := _assets(PackedStringArray(["Godot_v4.3-stable_linux.arm64.zip"]))
	_check_pick(only_arm64, "linux", "arm32", false, "")
	_check_pick(only_arm64, "linux", "x86_64", false, "")
	# A 32-bit system never gets a 64-bit build.
	var only_64 := _assets(PackedStringArray([
		"Godot_v4.0-stable_linux.x86_64.zip", "Godot_v4.0-stable_win64.exe.zip",
	]))
	_check_pick(only_64, "linux", "x86_32", false, "")
	_check_pick(only_64, "windows", "x86_32", false, "")


func _test_asset_labels() -> void:
	var labels := {
		"Godot_v4.7.2-stable_linux.x86_64.zip": "Linux x86_64",
		"Godot_v4.7.2-stable_mono_linux_x86_64.zip": "Linux x86_64",
		"Godot_v3.6-stable_x11.64.zip": "Linux x86_64",
		"Godot_v3.6-stable_mono_x11_64.zip": "Linux x86_64",
		"Godot_v3.6-stable_x11.32.zip": "Linux x86_32",
		"Godot_v4.7.2-stable_mono_linux_x86_32.zip": "Linux x86_32",
		"Godot_v4.0-alpha13_linux.64.zip": "Linux x86_64",
		"Godot_v4.0-alpha13_linux.32.zip": "Linux x86_32",
		"Godot_v4.7.2-stable_linux.arm64.zip": "Linux arm64",
		"Godot_v4.7.2-stable_mono_linux_arm64.zip": "Linux arm64",
		"Godot_v3.6-stable_linux.arm32.zip": "Linux arm32",
		"Godot_v4.7.2-stable_win64.exe.zip": "Windows x86_64",
		"Godot_v4.7.2-stable_mono_win64.zip": "Windows x86_64",
		"Godot_v4.7.2-stable_win32.exe.zip": "Windows x86_32",
		"Godot_v4.7.2-stable_windows_arm64.exe.zip": "Windows arm64",
		"Godot_v4.7.2-stable_mono_windows_arm64.zip": "Windows arm64",
		"Godot_v4.7.2-stable_macos.universal.zip": "macOS (universal)",
		"Godot_v3.6-stable_mono_osx.universal.zip": "macOS (universal)",
		"Godot_v3.2.3-stable_osx.64.zip": "macOS (Intel)",
		"Godot_v3.0-stable_mono_osx64.zip": "macOS (Intel)",
		"Godot_v3.0.6-stable_osx.fat.zip": "macOS (Intel)",
		"Godot_v4.7.2-stable_web_editor.zip": "",
		"Godot_v4.7.2-stable_android_editor.apk": "",
		"Godot_v3.6-stable_linux_server.64.zip": "",
		"Godot_v3.2.3-stable_mono_linux_headless_64.zip": "",
		"Godot_v1.1_stable_x11_portable.64.zip": "",
		"godot-4.7.2-stable.tar.xz": "",
	}
	for asset_name: String in labels:
		var expected: String = labels[asset_name]
		var label := GITHUB.platform_label_for_asset(asset_name)
		_check(
			label == expected,
			"Wrong label of %s: got \"%s\", expected \"%s\"" % [asset_name, label, expected],
		)


func _test_platform_labels() -> void:
	var labels := {
		["linux", "x86_64"]: "Linux x86_64",
		["linux", "arm64"]: "Linux arm64",
		["windows", "arm64"]: "Windows arm64",
		["windows", "x86_32"]: "Windows x86_32",
		["macos", "universal"]: "macOS",
		["macos", "arm64"]: "macOS",
		["FreeBSD", "x86_64"]: "FreeBSD x86_64",
		["linux", "riscv64"]: "Linux riscv64",
	}
	for key: Array in labels:
		var expected: String = labels[key]
		var label := GITHUB.platform_label(key[0] as String, key[1] as String)
		_check(label == expected, "Wrong label of %s: %s" % [key, label])


func _test_desktop_editor_assets() -> void:
	for asset_name in _assets_4_7_2():
		var expected := (
			asset_name.ends_with(".zip")
			and not asset_name.contains("web_editor")
			and not asset_name.contains("android")
			and not asset_name.contains("symbols")
		)
		_check(
			GITHUB.is_desktop_editor_asset(asset_name) == expected,
			"Wrong desktop editor check of %s" % asset_name,
		)
	for asset_name in _assets_4_8_dev7():
		_check(not GITHUB.is_desktop_editor_asset(asset_name), "%s is no editor" % asset_name)
	# Platforms without a Godot Hub pick still count as editor builds.
	_check(GITHUB.is_desktop_editor_asset("Godot_v2.0_stable_osx32.zip"), "osx32 is an editor")
	# Some releases, like 3.6.2, also keep replaced builds as "OLD.Godot_v...".
	_check(
		not GITHUB.is_desktop_editor_asset("OLD.Godot_v3.6.2-stable_x11.64.zip"),
		"OLD. builds are no editor downloads",
	)
	var assets: Array[GITHUB.GodotAsset] = []
	for asset_name: String in [
		"OLD.Godot_v3.6.2-stable_x11.64.zip", "Godot_v3.6.2-stable_x11.64.zip"
	]:
		assets.append(GITHUB.GodotAsset.new({"name": asset_name}))
	var picked := GITHUB.pick_platform_asset(
		assets, GITHUB.platform_suffixes("linux", "x86_64"), false
	)
	_check(
		picked != null and picked.name == "Godot_v3.6.2-stable_x11.64.zip",
		"Picked an OLD. build listed first",
	)


func _test_mono_detection() -> void:
	for asset_name: String in [
		"Godot_v4.7.2-stable_mono_linux_x86_64.zip", "Godot_v3.6-stable_mono_x11_64.zip",
		"Godot_v3.2.3-stable_mono_osx.64.zip", "Godot_v3.0-stable_mono_osx64.zip",
		"Godot_v3.0.6-stable_mono_win32.zip",
	]:
		_check(GITHUB._asset_is_mono(asset_name), "%s is a .NET build" % asset_name)
	for asset_name: String in [
		"Godot_v4.7.2-stable_linux.x86_64.zip", "Godot_v3.6-stable_x11.64.zip",
		"Godot_v3.2.3-stable_osx.64.zip", "Godot_v1.0_stable_osx64.zip",
	]:
		_check(not GITHUB._asset_is_mono(asset_name), "%s is a Standard build" % asset_name)


func _test_arch_from_uname() -> void:
	var cases := {
		"x86_64\n": "x86_64",
		"amd64": "x86_64",
		"aarch64": "arm64",
		"arm64": "arm64",
		"armv7l": "arm32",
		"armv8l": "arm32",
		"armv6l": "arm32",
		"i686": "x86_32",
		"i386": "x86_32",
		" I586 ": "x86_32",
		"riscv64": "riscv64",
		"": "",
	}
	for machine: String in cases:
		var expected: String = cases[machine]
		var arch := GITHUB.arch_from_uname(machine)
		_check(
			arch == expected,
			"uname %s should be %s, got %s" % [machine.c_escape(), expected, arch],
		)


func _test_linux_arch() -> void:
	var cases := [
		["x86_64", "x86_64", "x86_64"],
		# An x86_64 Hub emulated on an ARM machine (FEX, box64) still gets ARM builds.
		["aarch64", "x86_64", "arm64"],
		# A 32-bit Hub on a 64-bit kernel: a 32-bit system, like Raspberry Pi OS 32-bit.
		["aarch64", "arm32", "arm32"],
		["x86_64", "x86_32", "x86_32"],
		["armv7l", "arm32", "arm32"],
		# No uname: the Hub's own architecture.
		["", "arm64", "arm64"],
		["", "x86_64", "x86_64"],
		["riscv64", "rv64", "riscv64"],
	]
	for case: Array in cases:
		var expected: String = case[2]
		var arch := GITHUB.linux_arch(case[0] as String, case[1] as String)
		_check(
			arch == expected,
			"Linux %s with a %s Hub should be %s, got %s" % [case[0], case[1], expected, arch],
		)


func _test_windows_arch() -> void:
	var intel := "Intel64 Family 6 Model 154 Stepping 3, GenuineIntel"
	var amd := "AMD64 Family 25 Model 33 Stepping 0, AuthenticAMD"
	var qualcomm := "ARMv8 (64-bit) Family 8 Model D4B Revision   0, Qualcomm Technologies Inc"
	var cases := [
		["", "AMD64", intel, "x86_64", "x86_64"],
		["", "AMD64", amd, "x86_64", "x86_64"],
		# An x64 Hub emulated on Windows on ARM sees AMD64; the CPU is still ARM.
		["", "AMD64", qualcomm, "x86_64", "arm64"],
		["", "ARM64", qualcomm, "arm64", "arm64"],
		# A 32-bit Hub on 64-bit Windows: PROCESSOR_ARCHITEW6432 has the system's.
		["AMD64", "x86", intel, "x86_32", "x86_64"],
		["ARM64", "x86", qualcomm, "x86_32", "arm64"],
		["", "x86", "x86 Family 6 Model 15 Stepping 13, GenuineIntel", "x86_32", "x86_32"],
		# No environment: the Hub's own architecture.
		["", "", "", "x86_64", "x86_64"],
	]
	for case: Array in cases:
		var expected: String = case[4]
		var arch := GITHUB.windows_arch(
			case[0] as String, case[1] as String, case[2] as String, case[3] as String
		)
		_check(
			arch == expected,
			"Windows %s should be %s, got %s" % [case.slice(0, 4), expected, arch],
		)


func _test_host_platform() -> void:
	var host := GITHUB.host_platform()
	_check(host.has("os") and host.has("arch"), "Expected os and arch, got %s" % host)
	_check(GITHUB.host_platform() == host, "The host is detected once")
	if OS.has_feature("linux"):
		_check(host["os"] == "linux", "Expected linux, got %s" % host)
		_check(
			host["arch"] in ["x86_64", "x86_32", "arm64", "arm32"]
				or GITHUB.platform_suffixes(host["os"], host["arch"]).is_empty(),
			"Unexpected Linux arch %s" % host,
		)
	elif OS.has_feature("windows"):
		_check(host["os"] == "windows", "Expected windows, got %s" % host)
	elif OS.has_feature("macos"):
		_check(host == {"os": "macos", "arch": "universal"}, "Expected a universal Mac")
	_check(
		GITHUB.platform_suffixes_current_os()
			== GITHUB.platform_suffixes(host["os"], host["arch"]),
		"platform_suffixes_current_os() should follow the detected host",
	)
	_check(
		GITHUB.host_platform_label() == GITHUB.platform_label(host["os"], host["arch"]),
		"Expected the host label from the detected host",
	)
	print("Host platform: %s (%s)" % [host, GITHUB.host_platform_label()])


## Checks the picks of [param expected] ("os/arch" to [Standard, .NET] after
## [param prefix]) in [param names]. "macos/universal" also covers other Macs.
func _check_era(prefix: String, names: PackedStringArray, expected: Dictionary) -> void:
	var assets := _assets(names)
	var cases := expected.duplicate()
	cases["macos/arm64"] = expected["macos/universal"]
	cases["macos/x86_64"] = expected["macos/universal"]
	for platform: String in cases:
		var parts := platform.split("/")
		var files: Array = cases[platform]
		for i in 2:
			var tail: String = files[i]
			var file := "" if tail.is_empty() else prefix + tail
			_check_pick(assets, parts[0], parts[1], i == 1, file)


func _check_pick(
	assets: Array[RemoteEditorsTreeDataSourceGithub.GodotAsset],
	os_name: String,
	arch: String,
	mono: bool,
	expected: String,
) -> void:
	var suffixes := GITHUB.platform_suffixes(os_name, arch)
	var picked := GITHUB.pick_platform_asset(assets, suffixes, mono)
	var got := picked.name if picked != null else ""
	_check(
		got == expected,
		"%s/%s %s: got \"%s\", expected \"%s\"" % [
			os_name, arch, ".NET" if mono else "Standard", got, expected,
		],
	)


func _assets(names: PackedStringArray) -> Array[RemoteEditorsTreeDataSourceGithub.GodotAsset]:
	var result: Array[RemoteEditorsTreeDataSourceGithub.GodotAsset] = []
	for asset_name in names:
		result.append(GITHUB.GodotAsset.new({
			"name": asset_name,
			"browser_download_url": "https://example.com/" + asset_name,
		}))
	return result


func _check(condition: bool, message: String) -> void:
	if condition: return
	_failures += 1
	push_error(message)


# Asset names of godot-builds releases, as published on GitHub.

func _assets_4_7_2() -> PackedStringArray:
	return _prefixed("Godot_v4.7.2-stable_", [
		"android_debug.perfetto.apk", "android_editor.aab", "android_editor.apk",
		"android_editor_horizonos.apk", "android_editor_picoos.apk",
		"android_release.perfetto.apk", "android_source.perfetto.zip", "export_templates.tpz",
		"linux.arm32.zip", "linux.arm64.zip", "linux.x86_32.zip", "linux.x86_64.zip",
		"macos.universal.zip", "mono_export_templates.tpz", "mono_linux_arm32.zip",
		"mono_linux_arm64.zip", "mono_linux_x86_32.zip", "mono_linux_x86_64.zip",
		"mono_macos.universal.zip", "mono_win32.zip", "mono_win64.zip",
		"mono_windows_arm64.zip", "web_editor.zip", "win32.exe.zip", "win64.exe.zip",
		"windows_arm64.exe.zip",
	]) + PackedStringArray([
		"godot-4.7.2-stable.tar.xz", "godot-4.7.2-stable.tar.xz.sha256",
		"godot-lib.4.7.2.stable.mono.template_release.aar",
		"godot-lib.4.7.2.stable.template_release.aar",
		"Godot_native_debug_symbols.4.7.2.stable.editor.android.zip",
		"Godot_native_debug_symbols.4.7.2.stable.template_release.android.zip",
		"SHA512-SUMS.txt",
	])


func _assets_4_8_dev6() -> PackedStringArray:
	return _prefixed("Godot_v4.8-dev6_", [
		"android_editor.aab", "android_editor.apk", "export_templates.tpz", "linux.arm32.zip",
		"linux.arm64.zip", "linux.x86_32.zip", "linux.x86_64.zip", "macos.universal.zip",
		"mono_export_templates.tpz", "mono_linux_arm32.zip", "mono_linux_arm64.zip",
		"mono_linux_x86_32.zip", "mono_linux_x86_64.zip", "mono_macos.universal.zip",
		"mono_win32.zip", "mono_win64.zip", "mono_windows_arm64.zip", "web_editor.zip",
		"win32.exe.zip", "win64.exe.zip", "windows_arm64.exe.zip",
	])


## Android builds, export templates and sources only: no desktop editor was published.
func _assets_4_8_dev7() -> PackedStringArray:
	return _prefixed("Godot_v4.8-dev7_", [
		"android_debug.perfetto.apk", "android_editor.aab", "android_editor.apk",
		"android_editor_horizonos.apk", "android_editor_picoos.apk",
		"android_release.perfetto.apk", "android_source.perfetto.zip", "export_templates.tpz",
		"mono_export_templates.tpz",
	]) + PackedStringArray([
		"godot-4.8-dev7.tar.xz", "godot-lib.4.8.dev7.template_release.aar",
		"Godot_native_debug_symbols.4.8.dev7.editor.android.zip", "SHA512-SUMS.txt",
	])


func _assets_4_2_2() -> PackedStringArray:
	return _prefixed("Godot_v4.2.2-stable_", [
		"android_editor.aab", "android_editor.apk", "export_templates.tpz", "linux.arm32.zip",
		"linux.arm64.zip", "linux.x86_32.zip", "linux.x86_64.zip", "macos.universal.zip",
		"mono_export_templates.tpz", "mono_linux_arm32.zip", "mono_linux_arm64.zip",
		"mono_linux_x86_32.zip", "mono_linux_x86_64.zip", "mono_macos.universal.zip",
		"mono_win32.zip", "mono_win64.zip", "web_editor.zip", "win32.exe.zip", "win64.exe.zip",
	])


func _assets_4_0() -> PackedStringArray:
	return _prefixed("Godot_v4.0-stable_", [
		"export_templates.tpz", "linux.x86_32.zip", "linux.x86_64.zip", "macos.universal.zip",
		"mono_export_templates.tpz", "mono_linux_x86_32.zip", "mono_linux_x86_64.zip",
		"mono_macos.universal.zip", "mono_win32.zip", "mono_win64.zip", "web_editor.zip",
		"win32.exe.zip", "win64.exe.zip",
	])


## The 4.0 alphas before alpha15 name their Linux builds "linux.64" and "linux.32".
func _assets_4_0_alpha13() -> PackedStringArray:
	return _prefixed("Godot_v4.0-alpha13_", [
		"android_editor.apk", "export_templates.tpz", "linux.32.zip", "linux.64.zip",
		"macos.universal.zip", "win32.exe.zip", "win64.exe.zip",
	]) + PackedStringArray([
		"godot-4.0-alpha13.tar.xz", "godot-4.0-alpha13.tar.xz.sha256",
		"godot-lib.4.0.alpha13.release.aar", "README.txt",
	])


func _assets_3_6() -> PackedStringArray:
	return _prefixed("Godot_v3.6-stable_", [
		"android_editor.aab", "android_editor.apk", "export_templates.tpz", "linux.arm32.zip",
		"linux.arm64.zip", "linux_headless.64.zip", "linux_server.64.zip",
		"mono_export_templates.tpz", "mono_linux_headless_64.zip", "mono_linux_server_64.zip",
		"mono_osx.universal.zip", "mono_win32.zip", "mono_win64.zip", "mono_x11_32.zip",
		"mono_x11_64.zip", "osx.universal.zip", "web_editor.zip", "win32.exe.zip",
		"win64.exe.zip", "x11.32.zip", "x11.64.zip",
	])


func _assets_3_5_3() -> PackedStringArray:
	return _prefixed("Godot_v3.5.3-stable_", [
		"export_templates.tpz", "linux_headless.64.zip", "linux_server.64.zip",
		"mono_export_templates.tpz", "mono_linux_headless_64.zip", "mono_linux_server_64.zip",
		"mono_osx.universal.zip", "mono_win32.zip", "mono_win64.zip", "mono_x11_32.zip",
		"mono_x11_64.zip", "osx.universal.zip", "web_editor.zip", "win32.exe.zip",
		"win64.exe.zip", "x11.32.zip", "x11.64.zip",
	])


func _assets_3_2_3() -> PackedStringArray:
	return _prefixed("Godot_v3.2.3-stable_", [
		"changelog_authors.txt", "changelog_chrono.txt", "export_templates.tpz",
		"linux_headless.64.zip", "linux_server.64.zip", "mono_export_templates.tpz",
		"mono_linux_headless_64.zip", "mono_linux_server_64.zip", "mono_osx.64.zip",
		"mono_win32.zip", "mono_win64.zip", "mono_x11_32.zip", "mono_x11_64.zip", "osx.64.zip",
		"win32.exe.zip", "win64.exe.zip", "x11.32.zip", "x11.64.zip",
	])


func _assets_3_0_6() -> PackedStringArray:
	return _prefixed("Godot_v3.0.6-stable_", [
		"changelog.txt", "export_templates.tpz", "linux_headless.64.zip", "linux_server.64.zip",
		"mono_export_templates.tpz", "mono_osx.fat.zip", "mono_win32.zip", "mono_win64.zip",
		"mono_x11_32.zip", "mono_x11_64.zip", "osx.fat.zip", "win32.exe.zip", "win64.exe.zip",
		"x11.32.zip", "x11.64.zip",
	])


func _assets_3_0() -> PackedStringArray:
	return _prefixed("Godot_v3.0-stable_", [
		"export_templates.tpz", "mono_export_templates.tpz", "mono_osx64.zip", "mono_win32.zip",
		"mono_win64.zip", "mono_x11_64.zip", "osx.fat.zip", "win32.exe.zip", "win64.exe.zip",
		"x11.32.zip", "x11.64.zip",
	])


func _assets_2_1_6() -> PackedStringArray:
	return _prefixed("Godot_v2.1.6-stable_", [
		"changelog.txt", "export_templates.tpz", "linux_server.64.zip", "osx.fat.zip",
		"win32.exe.zip", "win64.exe.zip", "x11.32.zip", "x11.64.zip",
	])


func _assets_2_0() -> PackedStringArray:
	return _prefixed("Godot_v2.0_stable_", [
		"better_collada.zip", "demos.zip", "export_templates.tpz", "linux_server.64.zip",
		"osx32.zip", "win32.exe.zip", "win64.exe.zip", "x11.64.zip",
	])


func _assets_1_1() -> PackedStringArray:
	return _prefixed("Godot_v1.1_stable_", [
		"better_collada.zip", "changelog.txt", "demos.zip", "export_templates.tpz",
		"linux_server.64.zip", "linux_server_portable.64.zip", "osx32.zip", "win32.exe.zip",
		"win64.exe.zip", "x11.32.zip", "x11.64.zip", "x11_portable.32.zip",
		"x11_portable.64.zip",
	])


func _assets_1_0() -> PackedStringArray:
	return _prefixed("Godot_v1.0_stable_", [
		"export_templates.tpz", "linux_server.64.zip", "osx64.zip", "win32.exe.zip",
		"win32_fixed.exe.zip", "win64.exe.zip", "x11.32.zip", "x11.64.zip",
	])


func _prefixed(prefix: String, tails: Array[String]) -> PackedStringArray:
	var result := PackedStringArray()
	for tail in tails:
		result.append(prefix + tail)
	return result
