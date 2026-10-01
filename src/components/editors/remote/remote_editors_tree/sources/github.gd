@warning_ignore("redundant_await")
class_name RemoteEditorsTreeDataSourceGithub
extends RefCounted
## GitHub-based data source for remote editor releases.

# Endings of desktop editor files, lowercase, per platform. Standard builds use dots
# ("_linux.x86_64.zip"), .NET builds underscores ("_mono_linux_x86_64.zip"); Godot 3
# and older say x11 and osx, Godot 4.0 alpha1 to alpha14 "linux.64". Godot 1.0 to 4.x
# spellings, as published on godot-builds.
const _LINUX_X86_64_SUFFIXES: Array[String] = [
	"_linux.x86_64.zip", "_linux_x86_64.zip", "_x11.64.zip", "_x11_64.zip", "_linux.64.zip",
]
const _LINUX_X86_32_SUFFIXES: Array[String] = [
	"_linux.x86_32.zip", "_linux_x86_32.zip", "_x11.32.zip", "_x11_32.zip", "_linux.32.zip",
]
const _LINUX_ARM64_SUFFIXES: Array[String] = ["_linux.arm64.zip", "_linux_arm64.zip"]
const _LINUX_ARM32_SUFFIXES: Array[String] = ["_linux.arm32.zip", "_linux_arm32.zip"]
const _WINDOWS_X86_64_SUFFIXES: Array[String] = ["_win64.exe.zip", "_win64.zip"]
const _WINDOWS_X86_32_SUFFIXES: Array[String] = ["_win32.exe.zip", "_win32.zip"]
const _WINDOWS_ARM64_SUFFIXES: Array[String] = [
	"_windows_arm64.exe.zip", "_windows_arm64.zip",
]
const _MACOS_UNIVERSAL_SUFFIXES: Array[String] = ["_macos.universal.zip", "_osx.universal.zip"]
## 64-bit and fat (32 and 64-bit) Intel builds; Apple silicon runs them with Rosetta.
const _MACOS_INTEL_SUFFIXES: Array[String] = ["_osx.64.zip", "_osx64.zip", "_osx.fat.zip"]
## Godot 1.x and 2.0 Mac builds. macOS 10.15 and newer do not run 32-bit apps.
const _MACOS_X86_32_SUFFIXES: Array[String] = ["_osx32.zip"]
## Files with these words are not the desktop editor, whatever their ending.
const _NOT_EDITOR_WORDS: Array[String] = ["console", "portable", "headless", "server"]

## The detected platform, see [method host_platform].
static var _host_platform: Dictionary[String, String] = {}


static func channel_major_from_version_name(version_name: String) -> int:
	var trimmed := version_name.strip_edges()
	if trimmed.is_empty():
		return 0
	var head := trimmed.split(".")[0].split("-")[0]
	if head.is_valid_int():
		return int(head)
	return 0


static func channel_name_looks_prerelease(s: String) -> bool:
	var low := s.to_lower()
	for w: String in ["rc", "beta", "alpha", "dev", "fixup"]:
		if low.contains(w):
			return true
	return false


## Endings of the editor files [method host_platform] runs, best first.
static func platform_suffixes_current_os() -> Array[String]:
	var host := host_platform()
	return platform_suffixes(host["os"], host["arch"])


## Endings of the editor files that run on [param os_name] ("linux", "windows" or
## "macos") with CPU [param arch] ("x86_64", "x86_32", "arm64" or "arm32"), best
## first: the native build, then builds the system also runs (32-bit x86 builds on
## 64-bit x86, x64 builds emulated on Windows on ARM, Intel builds on Apple silicon).
## Standard and .NET spellings of every Godot version are listed; use
## [method pick_platform_asset] to pick one. Empty for platforms without builds.
static func platform_suffixes(os_name: String, arch: String) -> Array[String]:
	var out: Array[String] = []
	match os_name:
		"linux":
			match arch:
				"x86_64":
					out.append_array(_LINUX_X86_64_SUFFIXES)
					out.append_array(_LINUX_X86_32_SUFFIXES)
				"x86_32":
					out.append_array(_LINUX_X86_32_SUFFIXES)
				"arm64":
					out.append_array(_LINUX_ARM64_SUFFIXES)
				"arm32":
					out.append_array(_LINUX_ARM32_SUFFIXES)
		"windows":
			match arch:
				"arm64":
					out.append_array(_WINDOWS_ARM64_SUFFIXES)
					out.append_array(_WINDOWS_X86_64_SUFFIXES)
					out.append_array(_WINDOWS_X86_32_SUFFIXES)
				"x86_64":
					out.append_array(_WINDOWS_X86_64_SUFFIXES)
					out.append_array(_WINDOWS_X86_32_SUFFIXES)
				"x86_32":
					out.append_array(_WINDOWS_X86_32_SUFFIXES)
		"macos":
			# Every Mac: universal builds, then Intel ones.
			out.append_array(_MACOS_UNIVERSAL_SUFFIXES)
			out.append_array(_MACOS_INTEL_SUFFIXES)
	return out


## The platform editor downloads are picked for, detected once: [code]{"os": "linux",
## "arch": "arm64"}[/code]. os is "linux", "windows", "macos", or the name of an OS
## without Godot builds ("FreeBSD"); arch is "x86_64", "x86_32", "arm64", "arm32",
## "universal" on macOS, or the name of an architecture without builds ("riscv64").
static func host_platform() -> Dictionary[String, String]:
	if _host_platform.is_empty():
		_host_platform = _detect_host_platform()
	return _host_platform


## Name of the [method host_platform] for messages, e.g. "Linux arm64".
static func host_platform_label() -> String:
	var host := host_platform()
	return platform_label(host["os"], host["arch"])


## Name of a platform for messages, e.g. "Linux arm64", "Windows x86_64" or "macOS".
static func platform_label(os_name: String, arch: String) -> String:
	match os_name:
		"linux":
			return ("Linux %s" % arch).strip_edges()
		"windows":
			return ("Windows %s" % arch).strip_edges()
		"macos":
			return "macOS"
	return ("%s %s" % [os_name, arch]).strip_edges()


## Name of the platform of editor file [param asset_name], e.g. "Linux arm64" or
## "macOS (universal)", or empty when it is not a desktop editor build.
static func platform_label_for_asset(asset_name: String) -> String:
	var low := asset_name.to_lower()
	# Some releases keep replaced builds as "OLD.Godot_v...".
	if not low.begins_with("godot_v"):
		return ""
	for word in _NOT_EDITOR_WORDS:
		if low.contains(word):
			return ""
	var labels := {
		"Linux x86_64": _LINUX_X86_64_SUFFIXES,
		"Linux x86_32": _LINUX_X86_32_SUFFIXES,
		"Linux arm64": _LINUX_ARM64_SUFFIXES,
		"Linux arm32": _LINUX_ARM32_SUFFIXES,
		"Windows x86_64": _WINDOWS_X86_64_SUFFIXES,
		"Windows x86_32": _WINDOWS_X86_32_SUFFIXES,
		"Windows arm64": _WINDOWS_ARM64_SUFFIXES,
		"macOS (universal)": _MACOS_UNIVERSAL_SUFFIXES,
		"macOS (Intel)": _MACOS_INTEL_SUFFIXES,
		"macOS x86_32": _MACOS_X86_32_SUFFIXES,
	}
	for label: String in labels:
		var suffixes: Array[String] = labels[label]
		if _ends_with_any(low, suffixes):
			return label
	return ""


## True when [param asset_name] is a desktop editor build for any platform, even one
## this OS does not run. Android builds, export templates, the web editor, sources and
## headless or server builds are not.
static func is_desktop_editor_asset(asset_name: String) -> bool:
	return not platform_label_for_asset(asset_name).is_empty()


## Godot's name of the CPU architecture [code]uname -m[/code] prints, e.g. "arm64"
## for "aarch64". Unknown machines keep their name, in lowercase.
static func arch_from_uname(machine: String) -> String:
	var low := machine.strip_edges().to_lower()
	match low:
		"x86_64", "amd64", "x64":
			return "x86_64"
		"aarch64", "arm64":
			return "arm64"
		"i386", "i486", "i586", "i686", "x86":
			return "x86_32"
	# armv6l, armv7l, and armv8l (32-bit programs on a 64-bit ARM CPU).
	if low.begins_with("arm"):
		return "arm32"
	return low


## The architecture of a Linux system: [param machine] as [code]uname -m[/code]
## prints it, else [param engine_arch], the Hub's own. A 32-bit Hub on a 64-bit kernel
## of the same family means a 32-bit system (like Raspberry Pi OS with its 64-bit
## kernel), where 64-bit editors do not run.
static func linux_arch(machine: String, engine_arch: String) -> String:
	var kernel := arch_from_uname(machine)
	var own := engine_arch.strip_edges().to_lower()
	if kernel.is_empty():
		return own
	if (kernel == "arm64" and own == "arm32") or (kernel == "x86_64" and own == "x86_32"):
		return own
	return kernel


## The architecture of a Windows system, from its PROCESSOR_ARCHITEW6432,
## PROCESSOR_ARCHITECTURE and PROCESSOR_IDENTIFIER environment variables, else
## [param engine_arch], the Hub's own. A 32-bit Hub finds the system's in
## PROCESSOR_ARCHITEW6432. An x64 Hub emulated on Windows on ARM sees "AMD64", but the
## identifier still names the ARM CPU.
static func windows_arch(
	architew6432: String, architecture: String, identifier: String, engine_arch: String
) -> String:
	var native := architew6432.strip_edges().to_upper()
	if native.is_empty():
		native = architecture.strip_edges().to_upper()
	if native == "ARM64" or identifier.strip_edges().to_upper().begins_with("ARM"):
		return "arm64"
	match native:
		"AMD64", "X64", "EM64T":
			return "x86_64"
		"X86":
			return "x86_32"
	return engine_arch.strip_edges().to_lower()


static func _detect_host_platform() -> Dictionary[String, String]:
	var result: Dictionary[String, String] = {}
	var engine_arch := Engine.get_architecture_name()
	if OS.has_feature("macos"):
		result["os"] = "macos"
		result["arch"] = "universal"
	elif OS.has_feature("windows"):
		result["os"] = "windows"
		result["arch"] = windows_arch(
			OS.get_environment("PROCESSOR_ARCHITEW6432"),
			OS.get_environment("PROCESSOR_ARCHITECTURE"),
			OS.get_environment("PROCESSOR_IDENTIFIER"),
			engine_arch,
		)
	elif OS.has_feature("linux"):
		# The kernel's architecture: an x86_64 Hub may run emulated on an ARM machine.
		var output: Array = []
		var machine := ""
		if OS.execute("uname", ["-m"], output) == 0 and not output.is_empty():
			machine = str(output[0])
		result["os"] = "linux"
		result["arch"] = linux_arch(machine, engine_arch)
	else:
		result["os"] = OS.get_name()
		result["arch"] = engine_arch
	return result


static func _ends_with_any(low_name: String, suffixes: Array[String]) -> bool:
	for suffix in suffixes:
		if low_name.ends_with(suffix):
			return true
	return false


static func _asset_is_mono(asset_name: String) -> bool:
	var low := asset_name.to_lower()
	return ".mono." in low or "_mono_" in low or low.ends_with(".mono.zip")


## Returns the desktop editor of [param assets] with the first of [param suffixes] (see
## [method platform_suffixes]), the .NET build when [param want_mono] is true, or null.
static func pick_platform_asset(
	assets: Array[GodotAsset], suffixes: Array[String], want_mono: bool
) -> GodotAsset:
	for suffix in suffixes:
		for asset in assets:
			var low := asset.name.to_lower()
			if not low.ends_with(suffix.to_lower()):
				continue
			if _asset_is_mono(low) != want_mono or not is_desktop_editor_asset(low):
				continue
			return asset
	return null


static func pick_platform_stable_asset(assets: Array[GodotAsset], suffixes: Array[String]) -> GodotAsset:
	return pick_platform_asset(assets, suffixes, false)


static func download_target_from_version_hint(version_hint: String, require_mono := false) -> Dictionary:
	var parsed := VersionHint.parse(version_hint)
	if not parsed.is_valid or parsed.version.is_empty():
		return {}
	return {
		"version": parsed.version,
		"release": parsed.stage,
		"mono": require_mono or parsed.is_mono,
	}


static func async_editor_download_for_this_os(
	version_hint: String, require_mono := false
) -> Dictionary:
	var target := download_target_from_version_hint(version_hint, require_mono)
	if target.is_empty():
		return {}
	var suffixes := platform_suffixes_current_os()
	if suffixes.is_empty():
		return {}
	var asset_src := GithubAssetSourceDefault.new()
	var assets := await asset_src.async_load(
		target["version"] as String, target["release"] as String
	)
	var picked := pick_platform_asset(assets, suffixes, target["mono"] as bool)
	if picked == null:
		return {}
	return {
		"url": picked.browser_download_url,
		"file_name": picked.file_name,
		"version_label": "%s-%s" % [target["version"], target["release"]],
	}


static func _asset_platform_sort_rank(asset: GodotAsset, suffixes: Array[String]) -> int:
	var low := asset.name.to_lower()
	var is_mono := _asset_is_mono(low)
	var is_platform := _ends_with_any(low, suffixes)
	if is_platform and not is_mono:
		return 0
	if is_platform and is_mono:
		return 1
	if not is_platform and not is_mono:
		return 2
	return 3


static func sort_assets_prefer_current_platform(assets: Array[GodotAsset]) -> Array[GodotAsset]:
	var sorted := assets.duplicate()
	var suffixes := platform_suffixes_current_os()
	sorted.sort_custom(func(a: GodotAsset, b: GodotAsset) -> bool:
		return _asset_platform_sort_rank(a, suffixes) < _asset_platform_sort_rank(b, suffixes)
	)
	return sorted


static func candidate_stable_versions_newest_first(vlist: Array[GithubVersion]) -> Array[GithubVersion]:
	var four_plus: Array[GithubVersion] = []
	var rest: Array[GithubVersion] = []
	for v in vlist:
		if v.flavor.strip_edges() != "stable":
			continue
		if channel_major_from_version_name(v.name) >= 4:
			four_plus.append(v)
		else:
			rest.append(v)
	var ranked: Array[GithubVersion] = four_plus if not four_plus.is_empty() else rest
	ranked.sort_custom(func(a: GithubVersion, b: GithubVersion) -> bool:
		var va := VersionHint.version_or_nothing(a.name)
		var vb := VersionHint.version_or_nothing(b.name)
		return va.naturalcasecmp_to(vb) > 0
	)
	return ranked


static func async_latest_stable_editor_download_for_this_os() -> Dictionary:
	var vsrc := GithubVersionSourceParseYml.new(YmlSourceGithub.new(), GithubAssetSourceDefault.new())
	var versions := await vsrc.async_load()
	var ranked := candidate_stable_versions_newest_first(versions)
	var asset_src := GithubAssetSourceDefault.new()
	var sfx := platform_suffixes_current_os()
	if sfx.is_empty():
		return {}
	for candidate in ranked:
		var assets := await asset_src.async_load(candidate.name, "stable")
		if assets.is_empty():
			continue
		var picked: GodotAsset = pick_platform_stable_asset(assets, sfx)
		if picked != null:
			return {
				"url": picked.browser_download_url,
				"file_name": picked.file_name,
				"version_label": candidate.name,
			}
	return {}


class GithubVersion:
	var name: String
	var flavor: String
	var releases: Array[String] = []
	## Date of the flavor build as written in versions.yml, e.g. "18 August 2026".
	var release_date: String
	## godotengine.org path of the flavor build's release notes, e.g. "/article/...".
	var release_notes: String
	## Major version this build is featured for, e.g. "4". Empty when not featured.
	var featured: String
	var _assets_src: GithubAssetSource
	var _release_infos: Dictionary[String, GithubReleaseInfo] = {}
	
	## Returns the versions.yml metadata of [param release_name]: the flavor or one of
	## [member releases]. Fields are empty when the source has none.
	func get_release_info(release_name: String) -> GithubReleaseInfo:
		if release_name == flavor:
			return GithubReleaseInfo.new(flavor, release_date, release_notes, featured)
		if _release_infos.has(release_name):
			return _release_infos[release_name]
		return GithubReleaseInfo.new(release_name)
	
	## Appends a release after the ones already listed, keeping its metadata.
	func add_release(info: GithubReleaseInfo) -> void:
		releases.append(info.name)
		_release_infos[info.name] = info
	
	func get_flavor_release() -> GodotRelease:
		return GodotRelease.new(name, flavor, _assets_src)
	
	func get_recent_releases() -> Array[GodotRelease]:
		var result: Array[GodotRelease] = []
		for r in releases:
			result.append(GodotRelease.new(name, r, _assets_src))
		return result


## versions.yml metadata of one build: a version's flavor or one of its releases.
class GithubReleaseInfo:
	var name: String
	## Date as written in versions.yml, e.g. "3 August 2026".
	var release_date: String
	## godotengine.org path of the release notes, e.g. "/article/...". May be empty.
	var release_notes: String
	## Major version this build is featured for, e.g. "4". Empty when not featured.
	var featured: String
	
	func _init(
		p_name: String, p_release_date: String = "", p_release_notes: String = "",
		p_featured: String = ""
	) -> void:
		name = p_name
		release_date = p_release_date
		release_notes = p_release_notes
		featured = p_featured


class GodotRelease:
	var name: String
	var _version: String
	var _assets_src: GithubAssetSource
	
	func _init(version: String, name: String, assets_src: GithubAssetSource) -> void:
		self.name = name
		_assets_src = assets_src
		_version = version
	
	func is_stable() -> bool:
		return name == "stable"
	
	func async_load_assets() -> Array[GodotAsset]:
		@warning_ignore("redundant_await")
		return await _assets_src.async_load(_version, name)


class GodotAsset:
	var _json: Dictionary
	
	var name: String:
		get: return _json.get("name", "")
	
	var file_name: String:
		get: return browser_download_url.get_file()
	
	var browser_download_url: String:
		get: return _json.get("browser_download_url", "")
	
	var is_zip: bool:
		get: return name.get_extension() == "zip"
	
	## Download size in bytes from the release json, or 0 when unknown.
	var size: int:
		get:
			# JSON numbers parse as floats.
			var bytes: float = _json.get("size", 0.0)
			return int(bytes)
	
	func _init(json: Dictionary) -> void:
		_json = json


class GithubVersionSource:
	func async_load(errors: Array[String] = []) -> Array[GithubVersion]:
		return []


class GithubAssetSource:
	func async_load(version: String, release: String) -> Array[GodotAsset]:
		return []


class GithubAssetSourceDefault extends GithubAssetSource:
	const url = "https://api.github.com/repos/godotengine/godot-builds/releases/tags/%s"
	
	func async_load(version: String, release: String) -> Array[GodotAsset]:
		var tag := "%s-%s" % [version, release]
		var response := await _async_http_get(url % tag)
		var result: Array[GodotAsset] = []
		# Failed requests have an empty body; treat anything but an object as no assets.
		var json: Variant = utils.response_to_json(response)
		if not json is Dictionary:
			return result
		for asset_json: Dictionary in (json as Dictionary).get('assets', []):
			result.append(GodotAsset.new(asset_json))
		return result
	
	func _async_http_get(request_url: String) -> Array:
		return await HttpClient.async_http_get(
			request_url,
			["Accept: application/vnd.github.v3+json"]
		)


class GithubAssetSourceFileJson extends GithubAssetSource:
	var _file_path: String
	
	func _init(file_path: String) -> void:
		_file_path = file_path
	
	func async_load(version: String, release: String) -> Array[GodotAsset]:
		var json: Dictionary = JSON.parse_string(FileAccess.open(_file_path, FileAccess.READ).get_as_text())
		var result: Array[GodotAsset] = []
		for asset_json: Dictionary in json.get('assets', []):
			result.append(GodotAsset.new(asset_json))
		return result


class GithubVersionSourceFileJson extends GithubVersionSource:
	var _file_path: String
	var _assets_src: GithubAssetSource
	
	func _init(file_path: String, assets_src: GithubAssetSource) -> void:
		_file_path = file_path
		_assets_src = assets_src
	
	func async_load(errors: Array[String] = []) -> Array[GithubVersion]:
		var json: Array = JSON.parse_string(FileAccess.open(_file_path, FileAccess.READ).get_as_text())
		var result: Array[GithubVersion] = []
		for el: Dictionary in json:
			var version := GithubVersion.new()
			version._assets_src = _assets_src
			version.name = el.name
			version.flavor = el.flavor
			for release: Dictionary in el.get('releases', []):
				version.releases.append(release.name)
			result.append(version)
		return result


class YmlSource:
	func async_load(errors: Array[String]=[]) -> String:
		return ""


class YmlSourceFile extends YmlSource:
	var _file_path: String
	
	func _init(file_path: String) -> void:
		_file_path = file_path
	
	func async_load(errors: Array[String]=[]) -> String:
		var text := FileAccess.open(_file_path, FileAccess.READ).get_as_text() 
		return text


class YmlSourceGithub extends YmlSource:
	const url = "https://raw.githubusercontent.com/godotengine/godot-website/master/_data/versions.yml"
	func async_load(errors: Array[String]=[]) -> String:
		var response := HttpClient.Response.new(await HttpClient.async_http_get(url))
		var info := response.to_response_info(url)
		if info.error_text:
			errors.append(info.error_text)
		var text := response.get_string_from_utf8()
		return text


class GithubVersionSourceParseYml extends GithubVersionSource:
	var _src: YmlSource
	var _assets_src: GithubAssetSource
	
	var _version_regex := RegEx.create_from_string('(?m)^-[\\s\\S]*?(?=^-|\\Z)')
	var _name_regex := RegEx.create_from_string('(?m)\\sname:\\s"(?<name>[^"]+)"$')
	var _flavor_regex := RegEx.create_from_string('(?m)\\sflavor:\\s"(?<flavor>[^"]+)"$')
	## One "key: value" line, value quoted or not. Leading "- " is part of the indent.
	var _field_regex := RegEx.create_from_string(
		'(?m)^[ \\t-]*(?<key>[a-z_]+):[ \\t]*"?(?<value>[^"\\r\\n]*)"?[ \\t\\r]*$'
	)
	
	func _init(src: YmlSource, assets_src: GithubAssetSource) -> void:
		_src = src
		_assets_src = assets_src
	
	func async_load(errors: Array[String] = []) -> Array[GithubVersion]:
		@warning_ignore("redundant_await")
		var yml := await _src.async_load(errors)
		var result: Array[GithubVersion] = []
		var versions := _version_regex.search_all(yml)
		for version_result in versions:
			var version_string := version_result.get_string()
			var name_results := _name_regex.search_all(version_string)
			var flavor_result := _flavor_regex.search(version_string)
			if len(name_results) == 0 or flavor_result == null:
				continue
			var version := GithubVersion.new()
			version._assets_src = _assets_src
			version.name = name_results[0].get_string("name")
			version.flavor = flavor_result.get_string("flavor")
			# The version's own fields sit before its first release.
			var own := _release_info(version_string, name_results, 0)
			version.release_date = own.release_date
			version.release_notes = own.release_notes
			version.featured = own.featured
			for i in range(1, len(name_results)):
				version.add_release(_release_info(version_string, name_results, i))
			result.append(version)
		return result
	
	## Reads the fields between name [param index] and the next name in [param text].
	func _release_info(text: String, names: Array[RegExMatch], index: int) -> GithubReleaseInfo:
		var info := GithubReleaseInfo.new(names[index].get_string("name"))
		var end := names[index + 1].get_start() if index + 1 < names.size() else text.length()
		for field in _field_regex.search_all(text, names[index].get_start(), end):
			var value := field.get_string("value").strip_edges()
			match field.get_string("key"):
				"release_date": info.release_date = value
				"release_notes": info.release_notes = value
				"featured": info.featured = value
		return info
