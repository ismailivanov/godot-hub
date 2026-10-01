extends Node
## Offline EditorCatalog tests: tabs, ordering, badges, search, variants per platform,
## availability, shared requests, the nearest available build and installs.


const VERSIONS_YML := "res://tests/assets/editor_catalog_versions.yml"
const RELEASE_JSON := "res://tests/assets/editor_catalog_release.json"
const LEGACY_VERSIONS_YML := "res://tests/assets/godot_versions.yml"
const RELEASE_URL_PREFIX := (
	"https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/"
)
## Files of a Godot 4.3+ release after "Godot_v<tag>_": every desktop platform.
const ALL_PLATFORMS_FILES: Array[String] = [
	"android_editor.apk", "export_templates.tpz", "linux.arm32.zip", "linux.arm64.zip",
	"linux.x86_32.zip", "linux.x86_64.zip", "macos.universal.zip", "mono_linux_arm64.zip",
	"mono_linux_x86_64.zip", "mono_macos.universal.zip", "mono_win64.zip",
	"mono_windows_arm64.zip", "web_editor.zip", "win32.exe.zip", "win64.exe.zip",
	"windows_arm64.exe.zip",
]
## Files of a Godot 4.0 release: no ARM builds.
const NO_ARM_FILES: Array[String] = [
	"export_templates.tpz", "linux.x86_32.zip", "linux.x86_64.zip", "macos.universal.zip",
	"mono_linux_x86_64.zip", "mono_macos.universal.zip", "mono_win64.zip", "web_editor.zip",
	"win32.exe.zip", "win64.exe.zip",
]
## Files of Godot 4.8 dev7 as first published: no desktop editor at all.
const NO_EDITOR_FILES: Array[String] = [
	"android_editor.aab", "android_editor.apk", "android_source.perfetto.zip",
	"export_templates.tpz", "mono_export_templates.tpz",
]
## Files of Godot 3.6: Linux ARM builds, x11 and osx names.
const GODOT_3_6_FILES: Array[String] = [
	"linux.arm64.zip", "linux_server.64.zip", "mono_x11_64.zip", "osx.universal.zip",
	"win64.exe.zip", "x11.64.zip",
]
## Files of Godot 3.5: no ARM builds.
const GODOT_3_5_FILES: Array[String] = [
	"linux_server.64.zip", "mono_x11_64.zip", "osx.universal.zip", "win64.exe.zip",
	"x11.64.zip",
]

var _failures := 0


func _ready() -> void:
	await _test_yml_metadata()
	_test_asset_size()
	_test_default_catalog()
	await _test_tabs()
	await _test_search()
	await _test_ordering_and_channels()
	await _test_variants()
	await _test_variants_per_platform()
	await _test_availability()
	await _test_shared_requests()
	await _test_nearest_available()
	await _test_nearest_newer()
	await _test_is_installed()
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Editor catalog tests passed.")
	get_tree().quit()


func _test_yml_metadata() -> void:
	var versions := await _versions(VERSIONS_YML)
	var stable := _find_version(versions, "4.7.2")
	_check(stable != null, "Expected 4.7.2 in the catalog fixture")
	if stable != null:
		_check(stable.flavor == "stable", "Expected 4.7.2 to be stable")
		_check(stable.release_date == "18 August 2026", "Wrong 4.7.2 release date")
		_check(
			stable.release_notes == "/article/maintenance-release-godot-4-7-2/",
			"Wrong 4.7.2 release notes",
		)
		_check(stable.featured == "4", "Expected 4.7.2 to be featured for Godot 4")
		_check(
			PackedStringArray(stable.releases) == PackedStringArray(["rc1"]),
			"Expected 4.7.2 releases to stay a list of names",
		)
		var rc := stable.get_release_info("rc1")
		_check(rc.name == "rc1", "Wrong release info name")
		_check(rc.release_date == "3 August 2026", "Wrong 4.7.2 rc1 release date")
		_check(
			rc.release_notes == "/article/release-candidate-godot-4-7-2-rc-1/",
			"Wrong 4.7.2 rc1 release notes",
		)
		_check(rc.featured.is_empty(), "A release must not inherit the version's featured flag")
		var flavor := stable.get_release_info("stable")
		_check(flavor.release_date == "18 August 2026", "Flavor info should use version fields")
		_check(flavor.featured == "4", "Flavor info should carry the featured flag")
		var unknown := stable.get_release_info("rc9")
		_check(
			unknown.name == "rc9" and unknown.release_date.is_empty(),
			"Unknown releases should give empty metadata",
		)

	var patch := _find_version(versions, "4.7.1")
	if patch != null:
		_check(patch.featured.is_empty(), "featured must not leak into the next version")

	var dev := _find_version(versions, "4.8")
	_check(dev != null, "Expected 4.8 in the catalog fixture")
	if dev != null:
		_check(dev.flavor == "dev7", "Expected 4.8 flavor dev7")
		_check(dev.releases.size() == 6, "Expected six older 4.8 dev releases")
		_check(
			dev.get_release_info("dev7").release_date == "29 September 2026",
			"Wrong 4.8 dev7 release date",
		)
		_check(
			dev.get_release_info("dev1").release_notes
				== "/article/dev-snapshot-godot-4-8-dev-1/",
			"Wrong 4.8 dev1 release notes",
		)

	# The older fixture indents releases with tabs.
	var legacy := await _versions(LEGACY_VERSIONS_YML)
	_check(not legacy.is_empty(), "Expected versions from the legacy fixture")
	if not legacy.is_empty():
		_check(
			legacy[0].name == "4.2" and legacy[0].flavor == "beta1",
			"Legacy fixture should still parse name and flavor",
		)
		_check(legacy[0].releases[0] == "dev6", "Legacy fixture should still list releases")
		_check(
			legacy[0].get_release_info("dev6").release_date == "3 October 2023",
			"Expected per-release dates from tab-indented releases",
		)
	var legacy_featured := _find_version(legacy, "4.1.2")
	if legacy_featured != null:
		_check(legacy_featured.featured == "4", "Expected 4.1.2 featured in the legacy fixture")


func _test_asset_size() -> void:
	var from_json := RemoteEditorsTreeDataSourceGithub.GodotAsset.new(
		{"name": "a.zip", "size": 1234.0}
	)
	_check(from_json.size == 1234, "Expected the asset size from the release json")
	var from_int := RemoteEditorsTreeDataSourceGithub.GodotAsset.new({"size": 99})
	_check(from_int.size == 99, "Expected an integer asset size")
	var unknown := RemoteEditorsTreeDataSourceGithub.GodotAsset.new({"name": "a.zip"})
	_check(unknown.size == 0, "Expected size 0 when the json has none")


func _test_default_catalog() -> void:
	var catalog := EditorCatalog.default()
	_check(catalog != null, "Expected a default catalog")
	if catalog != null:
		_check(
			catalog.entries(EditorCatalog.TAB_OFFICIAL).is_empty(),
			"Expected no entries before async_load",
		)


func _test_tabs() -> void:
	var catalog := _catalog(RemoteEditorsTreeDataSourceGithub.YmlSourceFile.new(VERSIONS_YML))
	_check(
		catalog.entries(EditorCatalog.TAB_ARCHIVE).is_empty(),
		"Expected no entries before async_load",
	)
	var errors: Array[String] = []
	await catalog.async_load(errors)
	_check(errors.is_empty(), "Unexpected load errors: %s" % [errors])

	# Godot 1.x and 2.x are only in the Archive.
	var official := catalog.entries(EditorCatalog.TAB_OFFICIAL)
	_check_names(official, [
		"Godot 4.7.2", "Godot 4.6.3", "Godot 4.5.2", "Godot 4.4.1", "Godot 4.3",
		"Godot 4.2.2", "Godot 3.6.3", "Godot 3.5.3",
	], "official")
	# One recommended build: the newest featured major.
	var recommended := official.filter(
		func(e: EditorCatalog.CatalogEntry) -> bool: return e.recommended
	)
	_check_names(recommended, ["Godot 4.7.2"], "recommended")
	var featured := official.filter(
		func(e: EditorCatalog.CatalogEntry) -> bool: return not e.featured.is_empty()
	)
	_check_names(featured, ["Godot 4.7.2", "Godot 3.6.3"], "featured")
	var latest_3 := _find_entry(official, "3.6.3", "stable")
	if latest_3 != null:
		_check(latest_3.featured == "3", "Expected 3.6.3 featured for Godot 3")
		_check(not latest_3.recommended, "An older featured major is not recommended")
	if not official.is_empty():
		var newest := official[0]
		_check(newest.version == "4.7.2", "Wrong newest official version")
		_check(newest.release == "stable", "Wrong newest official release")
		_check(newest.channel == EditorCatalog.CHANNEL_STABLE, "Wrong newest official channel")
		_check(newest.release_date == "18 August 2026", "Wrong newest official date")
		_check(
			newest.release_notes_url
				== "https://godotengine.org/article/maintenance-release-godot-4-7-2/",
			"Expected an absolute release notes url, got %s" % newest.release_notes_url,
		)

	var prerelease := catalog.entries(EditorCatalog.TAB_PRERELEASE)
	_check_names(prerelease, [
		"Godot 4.8 dev7", "Godot 4.8 dev6", "Godot 4.8 dev5", "Godot 4.8 dev4",
		"Godot 4.8 dev3", "Godot 4.8 dev2", "Godot 4.8 dev1", "Godot 3.7 dev1",
	], "pre-release")
	for entry in prerelease:
		_check(
			entry.channel == EditorCatalog.CHANNEL_DEV,
			"Expected dev channel: %s" % entry.display_name,
		)
		_check(not entry.recommended, "Pre-releases are never recommended")
	if prerelease.size() > 1:
		_check(
			prerelease[0].version == "4.8" and prerelease[0].release == "dev7",
			"Wrong newest pre-release",
		)
		_check(prerelease[1].release_date == "15 September 2026", "Wrong 4.8 dev6 date")
		_check(
			prerelease[1].release_notes_url
				== "https://godotengine.org/article/dev-snapshot-godot-4-8-dev-6/",
			"Wrong 4.8 dev6 release notes url",
		)

	var archive := catalog.entries(EditorCatalog.TAB_ARCHIVE)
	_check_names(archive, [
		"Godot 4.7.2", "Godot 4.7.1", "Godot 4.7", "Godot 4.6.3", "Godot 4.6.2",
		"Godot 4.6.1", "Godot 4.6", "Godot 4.5.2", "Godot 4.5.1", "Godot 4.5",
		"Godot 4.4.1", "Godot 4.4", "Godot 4.3", "Godot 4.2.2", "Godot 4.2.1", "Godot 4.2",
		"Godot 3.6.3", "Godot 3.6.2", "Godot 3.6.1", "Godot 3.6", "Godot 3.5.3",
		"Godot 2.1.6", "Godot 2.0.4.1", "Godot 2.0.4", "Godot 1.0",
	], "archive")
	for i in range(1, archive.size()):
		_check(archive[i - 1].sort_key > archive[i].sort_key, "Expected descending sort keys")

	_check(catalog.entries(99).is_empty(), "Expected no entries for an unknown tab")

	# Refresh replaces the entries instead of appending.
	await catalog.async_load(errors)
	_check(
		catalog.entries(EditorCatalog.TAB_ARCHIVE).size() == archive.size(),
		"Reloading must not duplicate entries",
	)


func _test_search() -> void:
	var catalog := _catalog(RemoteEditorsTreeDataSourceGithub.YmlSourceFile.new(VERSIONS_YML))
	var errors: Array[String] = []
	await catalog.async_load(errors)
	_check_names(
		catalog.entries(EditorCatalog.TAB_ARCHIVE, "4.7"),
		["Godot 4.7.2", "Godot 4.7.1", "Godot 4.7"],
		"archive search 4.7",
	)
	_check_names(
		catalog.entries(EditorCatalog.TAB_OFFICIAL, "  GODOT 3."),
		["Godot 3.6.3", "Godot 3.5.3"],
		"case-insensitive official search",
	)
	_check_names(
		catalog.entries(EditorCatalog.TAB_PRERELEASE, "DEV6"),
		["Godot 4.8 dev6"],
		"pre-release search",
	)
	_check(
		catalog.entries(EditorCatalog.TAB_ARCHIVE, "zzz").is_empty(),
		"Expected no match for zzz",
	)
	# Searches match from the start of a word: "6.3" is inside 4.6.3 and 3.6.3.
	_check(
		catalog.entries(EditorCatalog.TAB_ARCHIVE, "6.3").is_empty(),
		"A search should not match the middle of a version",
	)
	_check_names(
		catalog.entries(EditorCatalog.TAB_ARCHIVE, "3.6"),
		["Godot 3.6.3", "Godot 3.6.2", "Godot 3.6.1", "Godot 3.6"],
		"archive search 3.6",
	)
	_check(
		catalog.entries(EditorCatalog.TAB_OFFICIAL, "   ").size()
			== catalog.entries(EditorCatalog.TAB_OFFICIAL).size(),
		"A blank search should not filter",
	)


func _test_ordering_and_channels() -> void:
	var yml_src := YmlSourceText.new(_synthetic_yml(), "fetch failed")
	var catalog := _catalog(yml_src)
	var errors: Array[String] = []
	await catalog.async_load(errors)
	_check(
		PackedStringArray(errors) == PackedStringArray(["fetch failed"]),
		"Expected source errors to reach the caller",
	)

	var official := catalog.entries(EditorCatalog.TAB_OFFICIAL)
	_check_names(official, ["Godot 4.10", "Godot 4.9.1", "Godot 4.1"], "numeric ordering")
	if official.size() == 3:
		_check(official[0].recommended, "Expected 4.10 recommended")
		_check(not official[1].recommended, "Expected 4.9.1 not recommended")
		_check(
			official[2].release_notes_url == "https://example.com/notes/4.1",
			"Absolute release notes urls should stay as they are",
		)

	var prerelease := catalog.entries(EditorCatalog.TAB_PRERELEASE)
	_check_names(prerelease, [
		"Godot 5.0 rc2", "Godot 5.0 rc1", "Godot 5.0 beta3", "Godot 5.0 alpha1",
		"Godot 5.0 dev2",
	], "release order")
	var channels := PackedStringArray()
	for entry in prerelease:
		channels.append(entry.channel)
	_check(
		channels == PackedStringArray(["rc", "rc", "beta", "alpha", "dev"]),
		"Wrong channels: %s" % channels,
	)
	if prerelease.size() == 5:
		_check(not prerelease[0].recommended, "A featured pre-release is not recommended")
		_check(prerelease[0].release_notes_url.is_empty(), "Empty notes should give no url")
		_check(prerelease[1].release_date == "1 March 2027", "Wrong 5.0 rc1 date")
		_check(prerelease[2].release_date.is_empty(), "Expected no 5.0 beta3 date")


func _test_variants() -> void:
	var assets := FixtureAssetSource.new()
	var catalog := EditorCatalog.new(
		RemoteEditorsTreeDataSourceGithub.GithubVersionSourceParseYml.new(
			RemoteEditorsTreeDataSourceGithub.YmlSourceFile.new(VERSIONS_YML), assets
		),
		assets,
	)
	# The same results on every OS the tests run on.
	catalog.use_platform("linux", "x86_64")
	var errors: Array[String] = []
	await catalog.async_load(errors)
	var sizes := _fixture_sizes()
	var suffixes := RemoteEditorsTreeDataSourceGithub.platform_suffixes("linux", "x86_64")

	var stable := _find_entry(catalog.entries(EditorCatalog.TAB_OFFICIAL), "4.7.2", "stable")
	_check(stable != null, "Expected the 4.7.2 entry")
	if stable == null:
		return
	var variant_errors: Array[String] = []
	var variants := await catalog.async_variants(stable, variant_errors)
	_check(variants.size() == 2, "Expected Standard and .NET variants")
	_check(variant_errors.is_empty(), "Unexpected variant errors: %s" % [variant_errors])
	if variants.size() == 2:
		var standard := variants[0]
		var mono := variants[1]
		_check(not standard.mono and mono.mono, "Expected Standard first, then .NET")
		for variant in variants:
			_check(variant.available, "Expected an available variant")
			_check(
				suffixes.any(func(s: String) -> bool: return variant.file_name.ends_with(s)),
				"Expected a file for this OS, got %s" % variant.file_name,
			)
			_check(
				variant.url == RELEASE_URL_PREFIX + variant.file_name,
				"Wrong download url: %s" % variant.url,
			)
			var fixture_size: int = sizes.get(variant.file_name, -1)
			_check(
				variant.size_bytes > 0 and variant.size_bytes == fixture_size,
				"Wrong size for %s" % variant.file_name,
			)
			_check(not variant.platform_label.is_empty(), "Expected a platform label")
		_check(not standard.file_name.containsn("mono"), "Standard picked a Mono file")
		_check(mono.file_name.containsn("mono"), ".NET picked a non-Mono file")
		_check(
			standard.file_name == "Godot_v4.7.2-stable_linux.x86_64.zip",
			"Wrong Linux standard file: %s" % standard.file_name,
		)
		_check(standard.size_bytes == 77860424, "Wrong Linux standard size")
		_check(standard.platform_label == "Linux x86_64", "Wrong Linux label")
		_check(
			mono.file_name == "Godot_v4.7.2-stable_mono_linux_x86_64.zip",
			"Wrong Linux .NET file: %s" % mono.file_name,
		)
		_check(mono.size_bytes == 107698034, "Wrong Linux .NET size")
		_check(mono.platform_label == "Linux x86_64", "Wrong Linux .NET label")
	_check(
		catalog.entry_availability(stable) == EditorCatalog.Availability.AVAILABLE,
		"Expected 4.7.2 available after loading its files",
	)

	# Found assets are cached: the GitHub API is rate limited.
	await catalog.async_variants(stable)
	_check(assets.loaded_tags.count("4.7.2-stable") == 1, "Expected cached 4.7.2 assets")

	var prerelease := catalog.entries(EditorCatalog.TAB_PRERELEASE)
	var standard_only := _find_entry(prerelease, "4.8", "dev6")
	if standard_only != null:
		var partial_errors: Array[String] = []
		var partial := await catalog.async_variants(standard_only, partial_errors)
		_check(partial.size() == 2, "Expected two variants for 4.8 dev6")
		_check(partial_errors.is_empty(), "A release with some files is not an error")
		if partial.size() == 2:
			_check(partial[0].available, "Expected Standard 4.8 dev6")
			_check(not partial[1].available, "Expected no .NET 4.8 dev6")
			_check(
				partial[1].url.is_empty() and partial[1].size_bytes == 0,
				"A missing variant has no url or size",
			)
			_check(
				partial[1].platform_label == partial[0].platform_label,
				"A missing variant still names this platform",
			)

	var missing := _find_entry(prerelease, "4.8", "dev7")
	if missing != null:
		var missing_errors: Array[String] = []
		var none := await catalog.async_variants(missing, missing_errors)
		_check(
			none.size() == 2 and not none[0].available and not none[1].available,
			"Expected no variants without assets",
		)
		_check(
			missing_errors.size() == 1,
			"A release without files should report an error, like a failed request",
		)
		_check(
			catalog.entry_availability(missing) == EditorCatalog.Availability.LOAD_FAILED,
			"A release without files is a failed load",
		)
		# Empty results may be network errors, so they are fetched again.
		await catalog.async_variants(missing)
		_check(assets.loaded_tags.count("4.8-dev7") == 2, "Empty assets must not be cached")

	# Refresh drops cached assets too.
	await catalog.async_load(errors)
	await catalog.async_variants(stable)
	_check(assets.loaded_tags.count("4.7.2-stable") == 2, "Expected refresh to clear the cache")


## The 4.7.2 release has a Standard and a .NET build for every desktop platform.
func _test_variants_per_platform() -> void:
	var assets := FixtureAssetSource.new()
	var catalog := EditorCatalog.new(
		RemoteEditorsTreeDataSourceGithub.GithubVersionSourceParseYml.new(
			RemoteEditorsTreeDataSourceGithub.YmlSourceFile.new(VERSIONS_YML), assets
		),
		assets,
	)
	var errors: Array[String] = []
	await catalog.async_load(errors)
	var stable := _find_entry(catalog.entries(EditorCatalog.TAB_OFFICIAL), "4.7.2", "stable")
	if stable == null:
		_check(false, "Expected the 4.7.2 entry")
		return
	var sizes := _fixture_sizes()
	var cases := {
		["linux", "x86_64"]: ["linux.x86_64.zip", "mono_linux_x86_64.zip", "Linux x86_64"],
		["linux", "x86_32"]: ["linux.x86_32.zip", "mono_linux_x86_32.zip", "Linux x86_32"],
		["linux", "arm64"]: ["linux.arm64.zip", "mono_linux_arm64.zip", "Linux arm64"],
		["linux", "arm32"]: ["linux.arm32.zip", "mono_linux_arm32.zip", "Linux arm32"],
		["windows", "x86_64"]: ["win64.exe.zip", "mono_win64.zip", "Windows x86_64"],
		["windows", "x86_32"]: ["win32.exe.zip", "mono_win32.zip", "Windows x86_32"],
		["windows", "arm64"]: [
			"windows_arm64.exe.zip", "mono_windows_arm64.zip", "Windows arm64",
		],
		["macos", "universal"]: [
			"macos.universal.zip", "mono_macos.universal.zip", "macOS (universal)",
		],
	}
	for platform: Array in cases:
		catalog.use_platform(platform[0] as String, platform[1] as String)
		var expected: Array = cases[platform]
		var variants := await catalog.async_variants(stable)
		for i in variants.size():
			var variant := variants[i]
			var file_name := "Godot_v4.7.2-stable_" + str(expected[i])
			_check(
				variant.available and variant.file_name == file_name,
				"%s: expected %s, got %s" % [platform, file_name, variant.file_name],
			)
			var label: String = expected[2]
			_check(
				variant.platform_label == label,
				"%s: wrong label %s" % [platform, variant.platform_label],
			)
			var fixture_size: int = sizes.get(file_name, -1)
			_check(variant.size_bytes == fixture_size, "%s: wrong size" % file_name)
		_check(
			catalog.entry_availability(stable) == EditorCatalog.Availability.AVAILABLE,
			"%s: expected 4.7.2 available" % [platform],
		)
	# Assets are cached across platforms: one request for all of them.
	_check(assets.loaded_tags.count("4.7.2-stable") == 1, "Expected one 4.7.2 request")


func _test_availability() -> void:
	var assets := MapAssetSource.new({
		"4.8-dev7": NO_EDITOR_FILES,
		"4.8-dev6": ALL_PLATFORMS_FILES,
		"4.0-stable": NO_ARM_FILES,
		"3.6-stable": GODOT_3_6_FILES,
	})
	var catalog := _availability_catalog(assets, "linux", "x86_64")
	var errors: Array[String] = []
	await catalog.async_load(errors)
	var changed: Array[String] = []
	catalog.availability_changed.connect(func(entry: EditorCatalog.CatalogEntry) -> void:
		changed.append(entry.tag())
	)
	var prerelease := catalog.entries(EditorCatalog.TAB_PRERELEASE)
	var archive := catalog.entries(EditorCatalog.TAB_ARCHIVE)
	var dev7 := _find_entry(prerelease, "4.8", "dev7")
	var godot_4_0 := _find_entry(archive, "4.0", "stable")
	if dev7 == null or godot_4_0 == null:
		_check(false, "Expected 4.8 dev7 and 4.0 in the availability fixture")
		return
	_check(
		catalog.entry_availability(dev7) == EditorCatalog.Availability.UNKNOWN,
		"Nothing is known before the release files load",
	)
	_check(catalog.platform_label() == "Linux x86_64", "Wrong pinned platform label")

	# Android builds and export templates only, like 4.8 dev7 when it came out.
	var dev7_errors: Array[String] = []
	var none := await catalog.async_variants(dev7, dev7_errors)
	_check(dev7_errors.is_empty(), "A release with files is not a failed load")
	_check(
		none.size() == 2 and not none[0].available and not none[1].available,
		"Expected no editor of 4.8 dev7",
	)
	for variant in none:
		_check(variant.platform_label == "Linux x86_64", "Missing builds name this platform")
	_check(
		catalog.entry_availability(dev7) == EditorCatalog.Availability.NO_EDITOR_BUILDS,
		"Expected no editor builds for 4.8 dev7, got %d" % catalog.entry_availability(dev7),
	)
	_check(
		PackedStringArray(changed) == PackedStringArray(["4.8-dev7"]),
		"Expected one change for 4.8 dev7: %s" % [changed],
	)
	await catalog.async_variants(dev7)
	_check(changed.size() == 1, "The same availability again is no change")
	_check(
		assets.loaded_tags.count("4.8-dev7") == 2,
		"Files without editor builds are loaded again: Godot may publish them any time",
	)

	await catalog.async_variants(godot_4_0)
	_check(
		catalog.entry_availability(godot_4_0) == EditorCatalog.Availability.AVAILABLE,
		"4.0 runs on Linux x86_64",
	)

	# Godot 4.0 has no Linux ARM builds.
	catalog.use_platform("linux", "arm64")
	_check(catalog.platform_label() == "Linux arm64", "Wrong label after use_platform")
	_check(
		catalog.entry_availability(godot_4_0) == EditorCatalog.Availability.UNKNOWN,
		"Another platform forgets what was known",
	)
	var arm_variants := await catalog.async_variants(godot_4_0)
	_check(
		catalog.entry_availability(godot_4_0) == EditorCatalog.Availability.NOT_FOR_PLATFORM,
		"Expected 4.0 not for Linux arm64",
	)
	_check(
		arm_variants.size() == 2 and arm_variants[0].platform_label == "Linux arm64",
		"Missing builds name the pinned platform",
	)
	await catalog.async_variants(dev7)
	_check(
		catalog.entry_availability(dev7) == EditorCatalog.Availability.NO_EDITOR_BUILDS,
		"No editor builds is the same on every platform",
	)
	_check(assets.loaded_tags.count("4.0-stable") == 1, "Platform changes keep the files")

	# Windows on ARM runs the x64 build of 4.0.
	catalog.use_platform("windows", "arm64")
	var emulated := await catalog.async_variants(godot_4_0)
	_check(
		catalog.entry_availability(godot_4_0) == EditorCatalog.Availability.AVAILABLE,
		"Windows on ARM runs x64 builds",
	)
	if emulated.size() == 2:
		_check(
			emulated[0].file_name == "Godot_v4.0-stable_win64.exe.zip"
				and emulated[0].platform_label == "Windows x86_64",
			"Expected the x64 build named as such, got %s (%s)" % [
				emulated[0].file_name, emulated[0].platform_label,
			],
		)

	# No files: a failed request, tried again next time.
	catalog.use_platform("linux", "x86_64")
	var dev2 := _find_entry(prerelease, "4.8", "dev2")
	var failed_errors: Array[String] = []
	await catalog.async_variants(dev2, failed_errors)
	_check(failed_errors.size() == 1, "A failed load reports an error")
	_check(
		catalog.entry_availability(dev2) == EditorCatalog.Availability.LOAD_FAILED,
		"Expected a failed load for 4.8 dev2",
	)
	assets.files["4.8-dev2"] = ALL_PLATFORMS_FILES
	await catalog.async_variants(dev2)
	_check(
		catalog.entry_availability(dev2) == EditorCatalog.Availability.AVAILABLE,
		"A retry after a failed load finds the files",
	)

	# Builds without editors yet are forgotten on request, e.g. when the modal opens.
	await catalog.async_variants(dev7)
	changed.clear()
	catalog.forget_no_editor_builds()
	_check(
		catalog.entry_availability(dev7) == EditorCatalog.Availability.UNKNOWN,
		"Expected dev7 forgotten",
	)
	_check(
		catalog.entry_availability(dev2) == EditorCatalog.Availability.AVAILABLE,
		"Only builds without editors are forgotten",
	)
	_check(
		PackedStringArray(changed) == PackedStringArray(["4.8-dev7"]),
		"Forgetting should report dev7 only: %s" % [changed],
	)
	assets.files["4.8-dev7"] = ALL_PLATFORMS_FILES
	await catalog.async_variants(dev7)
	_check(
		catalog.entry_availability(dev7) == EditorCatalog.Availability.AVAILABLE,
		"Editors published since are found on the next check",
	)

	# Refresh forgets availability too.
	await catalog.async_load(errors)
	var reloaded := _find_entry(catalog.entries(EditorCatalog.TAB_PRERELEASE), "4.8", "dev7")
	_check(
		reloaded != null
			and catalog.entry_availability(reloaded) == EditorCatalog.Availability.UNKNOWN,
		"Refresh should forget availability",
	)


func _test_nearest_available() -> void:
	var assets := MapAssetSource.new({
		"4.8-dev7": NO_EDITOR_FILES,
		"4.8-dev6": ALL_PLATFORMS_FILES,
	})
	var catalog := _availability_catalog(assets, "linux", "x86_64")
	var errors: Array[String] = []
	await catalog.async_load(errors)
	var tab := EditorCatalog.TAB_PRERELEASE
	var dev7 := _find_entry(catalog.entries(tab), "4.8", "dev7")
	await catalog.async_variants(dev7)
	var nearest := await catalog.async_nearest_available(dev7, tab)
	_check(nearest != null and nearest.tag() == "4.8-dev6", "Expected 4.8 dev6 for dev7")
	_check(
		PackedStringArray(assets.loaded_tags) == PackedStringArray(["4.8-dev7", "4.8-dev6"]),
		"Expected one request for dev6, got %s" % [assets.loaded_tags],
	)
	# Known builds cost no request.
	nearest = await catalog.async_nearest_available(dev7, tab)
	_check(nearest != null and nearest.tag() == "4.8-dev6", "Expected dev6 again")
	_check(assets.loaded_tags.size() == 2, "A known available build needs no request")

	# At most MAX_NEAREST_CHECKS requests per search: dev6 to dev4 have no ARM builds.
	assets = MapAssetSource.new({
		"4.8-dev7": NO_EDITOR_FILES,
		"4.8-dev6": NO_ARM_FILES,
		"4.8-dev5": NO_ARM_FILES,
		"4.8-dev4": NO_ARM_FILES,
		"4.8-dev3": NO_ARM_FILES,
		"4.8-dev2": ALL_PLATFORMS_FILES,
	})
	catalog = _availability_catalog(assets, "linux", "arm64")
	await catalog.async_load(errors)
	dev7 = _find_entry(catalog.entries(tab), "4.8", "dev7")
	nearest = await catalog.async_nearest_available(dev7, tab)
	_check(
		nearest == null,
		"Expected no build within %d checks" % EditorCatalog.MAX_NEAREST_CHECKS,
	)
	_check(
		PackedStringArray(assets.loaded_tags)
			== PackedStringArray(["4.8-dev6", "4.8-dev5", "4.8-dev4"]),
		"Expected requests for dev6, dev5 and dev4 only, got %s" % [assets.loaded_tags],
	)
	var dev5 := _find_entry(catalog.entries(tab), "4.8", "dev5")
	_check(
		catalog.entry_availability(dev5) == EditorCatalog.Availability.NOT_FOR_PLATFORM,
		"Checked builds keep their availability for the list",
	)
	# Checked builds are free, so the next search goes further.
	nearest = await catalog.async_nearest_available(dev7, tab)
	_check(nearest != null and nearest.tag() == "4.8-dev2", "Expected dev2 on the next search")
	_check(assets.loaded_tags.size() == 5, "Expected requests for dev3 and dev2")
	# A build without this platform's editor looks at newer builds only: dev5's are
	# dev6 (no ARM build either) and dev7 (no editor builds), not the older dev2.
	nearest = await catalog.async_nearest_available(dev5, tab)
	_check(nearest == null, "Expected no newer build for dev5, got %s" % [nearest])
	_check(
		assets.loaded_tags.size() == 6 and assets.loaded_tags[-1] == "4.8-dev7",
		"Expected one request, for dev7: %s" % [assets.loaded_tags],
	)

	# The search stops before a request once nobody waits for it, e.g. after Back.
	assets = MapAssetSource.new({
		"4.8-dev7": NO_EDITOR_FILES,
		"4.8-dev6": NO_ARM_FILES,
		"4.8-dev5": ALL_PLATFORMS_FILES,
	})
	catalog = _availability_catalog(assets, "linux", "arm64")
	await catalog.async_load(errors)
	dev7 = _find_entry(catalog.entries(tab), "4.8", "dev7")
	var asked: Array[int] = [0]
	var is_wanted := func() -> bool:
		asked[0] += 1
		return asked[0] == 1
	nearest = await catalog.async_nearest_available(dev7, tab, is_wanted)
	_check(nearest == null, "A search nobody waits for finds nothing")
	_check(
		PackedStringArray(assets.loaded_tags) == PackedStringArray(["4.8-dev6"]),
		"Expected the search to stop after dev6, got %s" % [assets.loaded_tags],
	)

	# Never another major: 3.6 runs here, but is no stand-in for 4.0.
	assets = MapAssetSource.new({"4.0-stable": NO_EDITOR_FILES, "3.6-stable": GODOT_3_6_FILES})
	catalog = _availability_catalog(assets, "linux", "x86_64")
	await catalog.async_load(errors)
	var godot_4_0 := _find_entry(catalog.entries(EditorCatalog.TAB_ARCHIVE), "4.0", "stable")
	await catalog.async_variants(godot_4_0)
	nearest = await catalog.async_nearest_available(godot_4_0, EditorCatalog.TAB_ARCHIVE)
	_check(nearest == null, "Expected no build of another major")
	_check(not assets.loaded_tags.has("3.6-stable"), "Other majors are not requested")
	var godot_3_6 := _find_entry(catalog.entries(EditorCatalog.TAB_ARCHIVE), "3.6", "stable")
	await catalog.async_variants(godot_3_6)
	_check(
		catalog.entry_availability(godot_3_6) == EditorCatalog.Availability.AVAILABLE,
		"3.6 has a Linux x86_64 build",
	)

	# A failed request stops the search: the next ones would fail too.
	assets = MapAssetSource.new({
		"4.8-dev7": NO_EDITOR_FILES,
		"4.8-dev5": ALL_PLATFORMS_FILES,
	})
	catalog = _availability_catalog(assets, "linux", "x86_64")
	await catalog.async_load(errors)
	dev7 = _find_entry(catalog.entries(tab), "4.8", "dev7")
	nearest = await catalog.async_nearest_available(dev7, tab)
	_check(nearest == null, "Expected no build after a failed request")
	_check(
		PackedStringArray(assets.loaded_tags) == PackedStringArray(["4.8-dev6"]),
		"Expected one request",
	)


## Godot only adds platforms over time, so a build without this platform's editor is
## offered the nearest newer build of its major: Linux arm64 builds start with 4.2.
func _test_nearest_newer() -> void:
	var assets := MapAssetSource.new({
		"4.2-stable": ALL_PLATFORMS_FILES,
		"4.1.4-stable": NO_ARM_FILES,
		"4.0-stable": NO_ARM_FILES,
		"3.6-stable": GODOT_3_6_FILES,
		"3.5-stable": GODOT_3_5_FILES,
	})
	var yml := "\n".join([
		'- name: "4.2"',
		'  flavor: "stable"',
		'',
		'- name: "4.1.4"',
		'  flavor: "stable"',
		'',
		'- name: "4.0"',
		'  flavor: "stable"',
		'',
		'- name: "3.6"',
		'  flavor: "stable"',
		'',
		'- name: "3.5"',
		'  flavor: "stable"',
		'',
	])
	var catalog := _catalog_of(yml, assets, "linux", "arm64")
	var errors: Array[String] = []
	await catalog.async_load(errors)
	var tab := EditorCatalog.TAB_ARCHIVE
	var godot_4_1_4 := _find_entry(catalog.entries(tab), "4.1.4", "stable")
	var godot_4_0 := _find_entry(catalog.entries(tab), "4.0", "stable")
	var godot_3_5 := _find_entry(catalog.entries(tab), "3.5", "stable")
	await catalog.async_variants(godot_4_1_4)
	_check(
		catalog.entry_availability(godot_4_1_4) == EditorCatalog.Availability.NOT_FOR_PLATFORM,
		"4.1.4 has no Linux arm64 build",
	)
	var nearest := await catalog.async_nearest_available(godot_4_1_4, tab)
	_check(nearest != null and nearest.tag() == "4.2-stable", "Expected 4.2 for 4.1.4")
	_check(
		PackedStringArray(assets.loaded_tags)
			== PackedStringArray(["4.1.4-stable", "4.2-stable"]),
		"Older builds lack the platform too: not requested, got %s" % [assets.loaded_tags],
	)
	# The closest newer build first; checked builds cost no request.
	await catalog.async_variants(godot_4_0)
	nearest = await catalog.async_nearest_available(godot_4_0, tab)
	_check(nearest != null and nearest.tag() == "4.2-stable", "Expected 4.2 for 4.0")
	_check(assets.loaded_tags.size() == 3, "Expected no request but 4.0's own")
	# 3.6 added Linux ARM builds to Godot 3, and 4.x is no stand-in for 3.5.
	await catalog.async_variants(godot_3_5)
	nearest = await catalog.async_nearest_available(godot_3_5, tab)
	_check(nearest != null and nearest.tag() == "3.6-stable", "Expected 3.6 for 3.5")
	assets.files["3.6-stable"] = GODOT_3_5_FILES
	await catalog.async_load(errors)
	godot_3_5 = _find_entry(catalog.entries(tab), "3.5", "stable")
	await catalog.async_variants(godot_3_5)
	nearest = await catalog.async_nearest_available(godot_3_5, tab)
	_check(nearest == null, "Expected no build of another major for 3.5")
	_check(
		assets.loaded_tags.count("4.2-stable") == 1 and assets.loaded_tags[-1] == "3.6-stable",
		"Expected a request for 3.6 only: %s" % [assets.loaded_tags],
	)

	# Nothing is built for this OS: no requests for a search that cannot succeed.
	catalog.use_platform("FreeBSD", "x86_64")
	var requests := assets.loaded_tags.size()
	await catalog.async_variants(godot_3_5)
	nearest = await catalog.async_nearest_available(godot_3_5, tab)
	_check(nearest == null, "Expected no build for FreeBSD")
	_check(assets.loaded_tags.size() == requests, "Expected no request for FreeBSD")


## Callers asking for the same release files at the same time share one request.
func _test_shared_requests() -> void:
	var assets := MapAssetSource.new({
		"4.8-dev7": NO_EDITOR_FILES,
		"4.8-dev6": ALL_PLATFORMS_FILES,
	})
	assets.delay_frames = 2
	var catalog := _availability_catalog(assets, "linux", "x86_64")
	var errors: Array[String] = []
	await catalog.async_load(errors)
	var tab := EditorCatalog.TAB_PRERELEASE
	var dev7 := _find_entry(catalog.entries(tab), "4.8", "dev7")
	var dev6 := _find_entry(catalog.entries(tab), "4.8", "dev6")
	# Like a search still loading dev6 when page 2 asks for it.
	catalog.async_variants(dev6)
	var variants := await catalog.async_variants(dev6)
	_check(
		variants.size() == 2 and variants[0].available,
		"The waiting caller should get the files",
	)
	_check(assets.loaded_tags.count("4.8-dev6") == 1, "Expected one shared request for dev6")
	catalog.async_variants(dev7)
	await catalog.async_variants(dev7)
	_check(assets.loaded_tags.count("4.8-dev7") == 1, "Expected one shared request for dev7")
	_check(
		catalog.entry_availability(dev7) == EditorCatalog.Availability.NO_EDITOR_BUILDS,
		"The shared request should still set the availability",
	)
	# Done requests are not shared: files without editor builds are loaded again.
	await catalog.async_variants(dev7)
	_check(assets.loaded_tags.count("4.8-dev7") == 2, "Expected a new request for dev7")


func _test_is_installed() -> void:
	var catalog := _catalog(RemoteEditorsTreeDataSourceGithub.YmlSourceFile.new(VERSIONS_YML))
	var errors: Array[String] = []
	await catalog.async_load(errors)
	var archive := catalog.entries(EditorCatalog.TAB_ARCHIVE)
	var prerelease := catalog.entries(EditorCatalog.TAB_PRERELEASE)

	var redot := _editor("Redot v4.6.3 stable", "/editors/redot")
	redot.engine_brand = EditorEngineBrand.REDOT
	var custom := _editor("My editor", "/editors/custom")
	custom.version_hint = "4.5.2-stable"
	var editors: Array[LocalEditors.Item] = [
		_editor("Godot v4.7.2 stable", "/editors/stable"),
		_editor("Godot v4.8 dev7 mono", "/editors/mono"),
		redot,
		custom,
	]
	var cases := {
		["4.7.2", "stable"]: true,
		["4.7", "stable"]: false,
		["4.7.1", "stable"]: false,
		["4.6.3", "stable"]: false,
		["4.5.2", "stable"]: true,
		["4.8", "dev7"]: true,
		["4.8", "dev6"]: false,
	}
	for key: Array in cases:
		var version: String = key[0]
		var release: String = key[1]
		var expected: bool = cases[key]
		var list: Array[EditorCatalog.CatalogEntry] = (
			archive if release == "stable" else prerelease
		)
		var entry := _find_entry(list, version, release)
		_check(entry != null, "Missing entry %s-%s" % [version, release])
		if entry == null:
			continue
		_check(
			catalog.is_installed(entry, editors) == expected,
			"Expected installed=%s for %s-%s" % [expected, version, release],
		)
	if not archive.is_empty():
		var no_editors: Array[LocalEditors.Item] = []
		_check(not catalog.is_installed(archive[0], no_editors), "Nothing is installed")
	for editor in editors:
		editor.free()


func _catalog(yml_src: RemoteEditorsTreeDataSourceGithub.YmlSource) -> EditorCatalog:
	var assets := FixtureAssetSource.new()
	return EditorCatalog.new(
		RemoteEditorsTreeDataSourceGithub.GithubVersionSourceParseYml.new(yml_src, assets),
		assets,
	)


## A catalog of 4.8 dev7 to dev2, 4.0 and 3.6 whose release files come from
## [param assets], picking builds for [param os_name] and [param arch].
func _availability_catalog(
	assets: MapAssetSource, os_name: String, arch: String
) -> EditorCatalog:
	var yml := "\n".join([
		'- name: "4.8"',
		'  flavor: "dev7"',
		'  releases:',
		'    - name: "dev6"',
		'    - name: "dev5"',
		'    - name: "dev4"',
		'    - name: "dev3"',
		'    - name: "dev2"',
		'',
		'- name: "4.0"',
		'  flavor: "stable"',
		'',
		'- name: "3.6"',
		'  flavor: "stable"',
		'',
	])
	return _catalog_of(yml, assets, os_name, arch)


## A catalog of the versions in [param yml] whose release files come from
## [param assets], picking builds for [param os_name] and [param arch].
func _catalog_of(
	yml: String, assets: MapAssetSource, os_name: String, arch: String
) -> EditorCatalog:
	var catalog := EditorCatalog.new(
		RemoteEditorsTreeDataSourceGithub.GithubVersionSourceParseYml.new(
			YmlSourceText.new(yml), assets
		),
		assets,
	)
	catalog.use_platform(os_name, arch)
	return catalog


func _versions(path: String) -> Array[RemoteEditorsTreeDataSourceGithub.GithubVersion]:
	var src := RemoteEditorsTreeDataSourceGithub.GithubVersionSourceParseYml.new(
		RemoteEditorsTreeDataSourceGithub.YmlSourceFile.new(path),
		FixtureAssetSource.new(),
	)
	var errors: Array[String] = []
	return await src.async_load(errors)


func _find_version(
	versions: Array[RemoteEditorsTreeDataSourceGithub.GithubVersion], version_name: String
) -> RemoteEditorsTreeDataSourceGithub.GithubVersion:
	for version in versions:
		if version.name == version_name:
			return version
	return null


func _find_entry(
	entries: Array[EditorCatalog.CatalogEntry], version: String, release: String
) -> EditorCatalog.CatalogEntry:
	for entry in entries:
		if entry.version == version and entry.release == release:
			return entry
	return null


func _fixture_sizes() -> Dictionary[String, int]:
	var result: Dictionary[String, int] = {}
	var json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RELEASE_JSON))
	for asset: Dictionary in json.get("assets", []):
		var size: float = asset.get("size", 0.0)
		result[str(asset.get("name", ""))] = int(size)
	return result


func _synthetic_yml() -> String:
	# Out of order on purpose, with every channel and some missing fields.
	return "\n".join([
		'- name: "4.1"',
		'  flavor: "stable"',
		'  release_date: "6 July 2023"',
		'  release_notes: "https://example.com/notes/4.1"',
		'',
		'- name: "5.0"',
		'  flavor: "rc2"',
		'  release_date: "2 March 2027"',
		'  release_notes: ""',
		'  featured: "5"',
		'  releases:',
		'    - name: "rc1"',
		'      release_date: "1 March 2027"',
		'    - name: "beta3"',
		'    - name: "alpha1"',
		'    - name: "dev2"',
		'',
		'- name: "4.10"',
		'  flavor: "stable"',
		'  featured: "4"',
		'',
		'- name: "4.9.1"',
		'  flavor: "stable"',
		'',
	])


func _editor(editor_name: String, path: String) -> LocalEditors.Item:
	var cfg := ConfigFile.new()
	cfg.set_value(path, "name", editor_name)
	return LocalEditors.Item.new(ConfigFileSection.new(path, IConfigFileLike.of_config(cfg)))


func _check_names(entries: Array, expected: Array, what: String) -> void:
	var names := PackedStringArray()
	for entry: EditorCatalog.CatalogEntry in entries:
		names.append(entry.display_name)
	_check(
		names == PackedStringArray(expected),
		"Wrong %s entries:\n  got      %s\n  expected %s" % [what, names, expected],
	)


func _check(condition: bool, message: String) -> void:
	if condition: return
	_failures += 1
	push_error(message)


## Serves the 4.7.2 fixture for 4.7.2-stable, a Standard-only copy of it for 4.8-dev6
## and no assets for anything else. Records every requested tag.
class FixtureAssetSource extends RemoteEditorsTreeDataSourceGithub.GithubAssetSource:
	var loaded_tags: Array[String] = []

	func async_load(
		version: String, release: String
	) -> Array[RemoteEditorsTreeDataSourceGithub.GodotAsset]:
		var tag := "%s-%s" % [version, release]
		loaded_tags.append(tag)
		var result: Array[RemoteEditorsTreeDataSourceGithub.GodotAsset] = []
		if tag != "4.7.2-stable" and tag != "4.8-dev6":
			return result
		var file_src := RemoteEditorsTreeDataSourceGithub.GithubAssetSourceFileJson.new(
			RELEASE_JSON
		)
		for asset in file_src.async_load(version, release):
			if tag == "4.8-dev6" and asset.name.contains("_mono_"):
				continue
			result.append(asset)
		return result


## Serves files by release tag: [member files] maps "4.8-dev7" to the file names after
## "Godot_v4.8-dev7_". Other tags have no files. Records every requested tag.
class MapAssetSource extends RemoteEditorsTreeDataSourceGithub.GithubAssetSource:
	var files: Dictionary = {}
	var loaded_tags: Array[String] = []
	## Frames to wait before answering, like a slow network.
	var delay_frames := 0

	func _init(p_files: Dictionary) -> void:
		files = p_files

	func async_load(
		version: String, release: String
	) -> Array[RemoteEditorsTreeDataSourceGithub.GodotAsset]:
		var tag := "%s-%s" % [version, release]
		loaded_tags.append(tag)
		for _frame: int in delay_frames:
			await (Engine.get_main_loop() as SceneTree).process_frame
		var result: Array[RemoteEditorsTreeDataSourceGithub.GodotAsset] = []
		var tails: Array = files.get(tag, [])
		for tail: String in tails:
			var asset_name := "Godot_v%s_%s" % [tag, tail]
			result.append(RemoteEditorsTreeDataSourceGithub.GodotAsset.new({
				"name": asset_name,
				"browser_download_url": "https://example.com/%s/%s" % [tag, asset_name],
				"size": 1000.0,
			}))
		return result


## Returns fixed yml text and reports an optional fetch error.
class YmlSourceText extends RemoteEditorsTreeDataSourceGithub.YmlSource:
	var _text: String
	var _error: String

	func _init(text: String, error: String = "") -> void:
		_text = text
		_error = error

	func async_load(errors: Array[String] = []) -> String:
		if not _error.is_empty():
			errors.append(_error)
		return _text
