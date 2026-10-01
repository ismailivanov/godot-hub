class_name EditorCatalog
extends RefCounted
## Godot editor builds offered by the Install Editor modal, split into tabs.
##
## Wraps the GitHub versions.yml and release asset sources. Pass other sources to
## [method _init] to run offline (tests, screenshots); [method default] uses GitHub.
## Builds are picked for this OS and CPU, or the platform given to [method use_platform].


## Emitted when what is known about installing [param entry] here changes, see
## [method entry_availability].
signal availability_changed(entry: CatalogEntry)

## Whether a build can be installed here, known once its release files are loaded.
enum Availability {
	## The release files are not loaded yet.
	UNKNOWN,
	## A Standard or .NET build runs here.
	AVAILABLE,
	## The release has no desktop editor for any platform yet, e.g. only Android
	## builds and export templates.
	NO_EDITOR_BUILDS,
	## The release has desktop editors, none of them for this platform.
	NOT_FOR_PLATFORM,
	## The release files could not be loaded (offline, rate limited, no such release).
	LOAD_FAILED,
}

## Newest stable patch of each major.minor.
const TAB_OFFICIAL := 0
## Builds of versions that are not stable yet.
const TAB_PRERELEASE := 1
## Every stable release.
const TAB_ARCHIVE := 2

const CHANNEL_STABLE := "stable"
const CHANNEL_DEV := "dev"
const CHANNEL_ALPHA := "alpha"
const CHANNEL_BETA := "beta"
const CHANNEL_RC := "rc"

## versions.yml release notes are paths on this site.
const RELEASE_NOTES_SITE := "https://godotengine.org"
## Official releases start at this major; older ones are in the Archive only.
const OFFICIAL_MIN_MAJOR := 3
## Release files [method async_nearest_available] loads at most per call.
const MAX_NEAREST_CHECKS := 3

var _version_src: RemoteEditorsTreeDataSourceGithub.GithubVersionSource
var _asset_src: RemoteEditorsTreeDataSourceGithub.GithubAssetSource
## All entries, newest first.
var _entries: Array[CatalogEntry] = []
## Pre-releases of versions that are stable now, which the tabs leave out: their
## editors may still be installed, see [method entry_of_hint].
var _unlisted_entries: Array[CatalogEntry] = []
## Asset lists with desktop editor builds by "version-release" tag. The GitHub API is
## rate limited.
var _assets_by_tag: Dictionary[String, Array] = {}
## Asset requests still running by tag, which later callers wait for.
var _requests_by_tag: Dictionary[String, AssetsRequest] = {}
## What is known about installing each "version-release" tag here.
var _availability_by_tag: Dictionary[String, Availability] = {}
## Bumped when cached release files and availability are dropped, so answers to
## requests made before are not cached.
var _cache_generation := 0
## Editor file endings of the platform builds are picked for, best first.
var _platform_suffixes: Array[String] = []
## The platform builds are picked for, e.g. "Linux arm64".
var _platform_label := ""


func _init(
	version_src: RemoteEditorsTreeDataSourceGithub.GithubVersionSource,
	asset_src: RemoteEditorsTreeDataSourceGithub.GithubAssetSource,
) -> void:
	_version_src = version_src
	_asset_src = asset_src
	var host := RemoteEditorsTreeDataSourceGithub.host_platform()
	use_platform(host["os"], host["arch"])


## Returns a catalog that reads versions.yml and release assets from GitHub.
static func default() -> EditorCatalog:
	var asset_src := RemoteEditorsTreeDataSourceGithub.GithubAssetSourceDefault.new()
	return EditorCatalog.new(
		RemoteEditorsTreeDataSourceGithub.GithubVersionSourceParseYml.new(
			RemoteEditorsTreeDataSourceGithub.YmlSourceGithub.new(), asset_src
		),
		asset_src,
	)


## Fetches the version list and replaces the entries. Fetch errors go to [param errors].
func async_load(errors: Array[String] = []) -> void:
	@warning_ignore("redundant_await")
	var versions := await _version_src.async_load(errors)
	var loaded: Array[CatalogEntry] = []
	var unlisted: Array[CatalogEntry] = []
	for version in versions:
		loaded.append_array(_entries_of(version))
		unlisted.append_array(_prereleases_of_stable(version))
	loaded.sort_custom(func(a: CatalogEntry, b: CatalogEntry) -> bool:
		return a.sort_key > b.sort_key
	)
	_entries = loaded
	_unlisted_entries = unlisted
	_mark_recommended()
	_clear_release_cache()


## Picks builds for [param os_name] and [param arch] (see
## [method RemoteEditorsTreeDataSourceGithub.platform_suffixes]) instead of this OS
## and CPU, e.g. in tests. Drops what is known about availability.
func use_platform(os_name: String, arch: String) -> void:
	_platform_suffixes = RemoteEditorsTreeDataSourceGithub.platform_suffixes(os_name, arch)
	_platform_label = RemoteEditorsTreeDataSourceGithub.platform_label(os_name, arch)
	_availability_by_tag.clear()


## The platform builds are picked for, for messages, e.g. "Linux arm64".
func platform_label() -> String:
	return _platform_label


## Returns the entries of [param tab] (a TAB_* constant), newest first. A non-blank
## [param search] keeps entries with a word of the display name starting with it,
## ignoring case: "4.3" finds Godot 4.3, not Godot 3.4.3.
func entries(tab: int, search := "") -> Array[CatalogEntry]:
	var result: Array[CatalogEntry] = []
	match tab:
		TAB_OFFICIAL:
			result = _newest_patch_per_branch()
		TAB_PRERELEASE:
			result.assign(_entries.filter(func(e: CatalogEntry) -> bool: return not e.is_stable()))
		TAB_ARCHIVE:
			result.assign(_entries.filter(func(e: CatalogEntry) -> bool: return e.is_stable()))
	var needle := search.strip_edges()
	if needle.is_empty():
		return result
	var found: Array[CatalogEntry] = []
	found.assign(result.filter(func(e: CatalogEntry) -> bool:
		return _has_word_starting_with(e.display_name, needle)
	))
	return found


## Returns the build with the version and release of [param version_hint] (see
## [VersionHint]), e.g. that of an installed editor, or null: one of the tabs, or a
## pre-release of a version that is stable now, which the tabs leave out.
func entry_of_hint(version_hint: String) -> CatalogEntry:
	for entries_list: Array[CatalogEntry] in [_entries, _unlisted_entries]:
		for entry in entries_list:
			if VersionHint.are_equal(entry.tag(), version_hint, true):
				return entry
	return null


## Returns the Standard and .NET builds of [param entry] for this platform, in that
## order, and sets its [method entry_availability]. A build without a file for this
## platform comes back with [code]available = false[/code]. A release without any files
## (a failed request, or no such release on GitHub) also adds a message to
## [param errors].
func async_variants(entry: CatalogEntry, errors: Array[String] = []) -> Array[CatalogVariant]:
	var generation := _cache_generation
	var assets := await _async_assets(entry)
	if assets.is_empty():
		errors.append("no release files for %s" % entry.tag())
	var result: Array[CatalogVariant] = []
	for mono: bool in [false, true]:
		result.append(_variant(assets, mono))
	# A refresh while loading dropped what this request knew.
	if generation == _cache_generation:
		_set_availability(entry, _availability_of(assets, result))
	return result


## What is known about installing [param entry] here: UNKNOWN until
## [method async_variants] or [method async_nearest_available] loads its release
## files. A refresh ([method async_load]) forgets it, and
## [method forget_no_editor_builds] forgets NO_EDITOR_BUILDS.
func entry_availability(entry: CatalogEntry) -> Availability:
	var tag := entry.tag()
	if _availability_by_tag.has(tag):
		return _availability_by_tag[tag]
	return Availability.UNKNOWN


## Forgets which builds have no editor downloads yet, so they are checked again when
## asked for: Godot may publish them any time. Emits [signal availability_changed]
## for each.
func forget_no_editor_builds() -> void:
	for entry in _entries:
		if entry_availability(entry) == Availability.NO_EDITOR_BUILDS:
			_availability_by_tag.erase(entry.tag())
			availability_changed.emit(entry)


## Returns a build of [param tab] with the same major version as [param entry] that
## can be installed here, or null. For a build without editors for this platform it
## looks at newer builds, closest first, as Godot only adds platforms over time; else
## (no editor builds yet) at older builds, newest first. Loads the release files of at
## most [constant MAX_NEAREST_CHECKS] builds not checked yet, and stops at a failed
## load, as the GitHub API is rate limited, or before a load once [param is_wanted]
## returns false.
func async_nearest_available(
	entry: CatalogEntry, tab: int, is_wanted := Callable()
) -> CatalogEntry:
	# Nothing is built for this platform at all.
	if _platform_suffixes.is_empty():
		return null
	var newer := entry_availability(entry) == Availability.NOT_FOR_PLATFORM
	var candidates := entries(tab)
	if newer:
		# Entries are newest first.
		candidates.reverse()
	var major := VersionComparison.parts(entry.version)[0]
	var checks := 0
	for candidate in candidates:
		var is_newer := candidate.sort_key > entry.sort_key
		if is_newer != newer or candidate.sort_key == entry.sort_key:
			continue
		if VersionComparison.parts(candidate.version)[0] != major:
			continue
		var availability := entry_availability(candidate)
		if availability == Availability.UNKNOWN or availability == Availability.LOAD_FAILED:
			if checks == MAX_NEAREST_CHECKS or (is_wanted.is_valid() and not is_wanted.call()):
				return null
			checks += 1
			await async_variants(candidate)
			availability = entry_availability(candidate)
		match availability:
			Availability.AVAILABLE:
				return candidate
			Availability.LOAD_FAILED, Availability.UNKNOWN:
				# Offline or rate limited: the next requests would fail too.
				return null
	return null


## Returns true when a local Godot editor has the version and release of [param entry].
## Standard and .NET builds count the same.
func is_installed(entry: CatalogEntry, editors: Array[LocalEditors.Item]) -> bool:
	var hint := entry.tag()
	for editor in editors:
		# Redot shares Godot's version numbers but is another engine.
		if editor.engine_brand == EditorEngineBrand.REDOT:
			continue
		if VersionHint.are_equal(hint, editor.version_hint, true):
			return true
	return false


func _entries_of(version: RemoteEditorsTreeDataSourceGithub.GithubVersion) -> Array[CatalogEntry]:
	var result: Array[CatalogEntry] = []
	var flavor := version.flavor.strip_edges()
	if flavor == CHANNEL_STABLE:
		# Release candidates of a stable version are left out.
		result.append(_entry(version, flavor, 0))
		return result
	# The flavor is the newest build, then releases as listed (newest first).
	var builds: Array[String] = [flavor]
	builds.append_array(version.releases)
	for i in builds.size():
		result.append(_entry(version, builds[i], i))
	return result


## The pre-releases of [param version] when it is stable, which [method _entries_of]
## leaves out.
func _prereleases_of_stable(
	version: RemoteEditorsTreeDataSourceGithub.GithubVersion
) -> Array[CatalogEntry]:
	var result: Array[CatalogEntry] = []
	if version.flavor.strip_edges() != CHANNEL_STABLE:
		return result
	for i in version.releases.size():
		if version.releases[i] != CHANNEL_STABLE:
			result.append(_entry(version, version.releases[i], i + 1))
	return result


func _entry(
	version: RemoteEditorsTreeDataSourceGithub.GithubVersion, release: String, order: int
) -> CatalogEntry:
	var info := version.get_release_info(release)
	var entry := CatalogEntry.new()
	entry.version = version.name
	entry.release = release
	entry.channel = _channel_of(release)
	if entry.is_stable():
		entry.display_name = "Godot %s" % version.name
	else:
		entry.display_name = "Godot %s %s" % [version.name, release]
	entry.release_date = info.release_date
	entry.release_notes_url = _absolute_url(info.release_notes)
	# Set per major on stable versions; pre-releases are never featured.
	entry.featured = info.featured.strip_edges() if entry.is_stable() else ""
	entry.sort_key = _sort_key(version.name, order)
	return entry


## Only the newest featured major is Recommended, like Unity's one recommended
## version. Older featured majors (the newest 3.x) keep their featured value.
func _mark_recommended() -> void:
	var newest_major := -1
	for entry in _entries:
		if not entry.featured.is_empty():
			newest_major = maxi(newest_major, entry.featured.to_int())
	for entry in _entries:
		entry.recommended = (
			not entry.featured.is_empty() and entry.featured.to_int() == newest_major
		)


func _newest_patch_per_branch() -> Array[CatalogEntry]:
	var result: Array[CatalogEntry] = []
	var seen_branches: Array[String] = []
	# Entries are newest first, so the first stable one of a branch is its newest patch.
	for entry in _entries:
		if not entry.is_stable():
			continue
		var parts := VersionComparison.parts(entry.version)
		if parts[0] < OFFICIAL_MIN_MAJOR:
			continue
		var branch := "%d.%d" % [parts[0], parts[1] if parts.size() > 1 else 0]
		if branch in seen_branches:
			continue
		seen_branches.append(branch)
		result.append(entry)
	return result


func _async_assets(entry: CatalogEntry) -> Array[RemoteEditorsTreeDataSourceGithub.GodotAsset]:
	var tag := entry.tag()
	var result: Array[RemoteEditorsTreeDataSourceGithub.GodotAsset] = []
	if _assets_by_tag.has(tag):
		result.assign(_assets_by_tag[tag])
		return result
	# One request for callers asking at the same time, e.g. two searches.
	if _requests_by_tag.has(tag):
		var running := _requests_by_tag[tag]
		await running.finished
		result.assign(running.assets)
		return result
	var request := AssetsRequest.new()
	_requests_by_tag[tag] = request
	var generation := _cache_generation
	@warning_ignore("redundant_await")
	result = await _asset_src.async_load(entry.version, entry.release)
	_requests_by_tag.erase(tag)
	# Empty may mean a network error, and editors of a release without any may be
	# published any time: fetch those again next time.
	if _has_editor_builds(result) and generation == _cache_generation:
		_assets_by_tag[tag] = result
	request.assets = result
	request.finished.emit()
	return result


func _clear_release_cache() -> void:
	_cache_generation += 1
	_assets_by_tag.clear()
	_availability_by_tag.clear()


func _set_availability(entry: CatalogEntry, availability: Availability) -> void:
	if entry_availability(entry) == availability:
		return
	_availability_by_tag[entry.tag()] = availability
	availability_changed.emit(entry)


func _availability_of(
	assets: Array[RemoteEditorsTreeDataSourceGithub.GodotAsset],
	variants: Array[CatalogVariant],
) -> Availability:
	if assets.is_empty():
		return Availability.LOAD_FAILED
	for variant in variants:
		if variant.available:
			return Availability.AVAILABLE
	if _has_editor_builds(assets):
		return Availability.NOT_FOR_PLATFORM
	return Availability.NO_EDITOR_BUILDS


func _variant(
	assets: Array[RemoteEditorsTreeDataSourceGithub.GodotAsset], mono: bool
) -> CatalogVariant:
	var variant := CatalogVariant.new()
	variant.mono = mono
	# Export templates are for every platform: an editor built elsewhere (or from
	# source) can still manage them.
	var templates := _templates_asset(assets, mono)
	if templates != null:
		variant.templates_url = templates.browser_download_url
		variant.templates_size_bytes = templates.size
	var asset := RemoteEditorsTreeDataSourceGithub.pick_platform_asset(
		assets, _platform_suffixes, mono
	)
	if asset == null:
		# Still name the platform, so the UI can say what is missing.
		variant.platform_label = _platform_label
		return variant
	# The build may be for another platform this one runs, e.g. x64 on Windows on ARM.
	variant.platform_label = RemoteEditorsTreeDataSourceGithub.platform_label_for_asset(
		asset.name
	)
	variant.available = true
	variant.url = asset.browser_download_url
	variant.file_name = asset.file_name
	variant.size_bytes = asset.size
	return variant


## The export templates archive (.tpz) of the Standard or .NET build, or null.
static func _templates_asset(
	assets: Array[RemoteEditorsTreeDataSourceGithub.GodotAsset], mono: bool
) -> RemoteEditorsTreeDataSourceGithub.GodotAsset:
	for asset in assets:
		var low := asset.name.to_lower()
		if low.ends_with("_export_templates.tpz") and low.contains("_mono_") == mono:
			return asset
	return null


static func _has_editor_builds(
	assets: Array[RemoteEditorsTreeDataSourceGithub.GodotAsset]
) -> bool:
	for asset in assets:
		if RemoteEditorsTreeDataSourceGithub.is_desktop_editor_asset(asset.name):
			return true
	return false


static func _channel_of(release: String) -> String:
	var low := release.to_lower()
	if low == CHANNEL_STABLE:
		return CHANNEL_STABLE
	# "alpha" first: "pre-alpha" must not read as rc or dev.
	for channel: String in [CHANNEL_ALPHA, CHANNEL_BETA, CHANNEL_RC]:
		if low.contains(channel):
			return channel
	return CHANNEL_DEV


static func _has_word_starting_with(text: String, needle: String) -> bool:
	var at := text.findn(needle)
	while at != -1:
		if at == 0 or text[at - 1] == " ":
			return true
		at = text.findn(needle, at + 1)
	return false


static func _absolute_url(path: String) -> String:
	var trimmed := path.strip_edges()
	if trimmed.is_empty() or trimmed.contains("://"):
		return trimmed
	return RELEASE_NOTES_SITE + trimmed


## Sorts by version (up to four parts), then by the build's place in versions.yml.
static func _sort_key(version_name: String, order: int) -> int:
	var parts := VersionComparison.parts(version_name)
	var key := 0
	for i in 4:
		key = key * 1000 + clampi(parts[i] if i < parts.size() else 0, 0, 999)
	# Earlier in versions.yml is newer.
	return key * 1000 + 999 - clampi(order, 0, 999)


## One installable build, e.g. Godot 4.7.2 or Godot 4.8 dev7.
class CatalogEntry:
	var version: String
	## "stable", "dev7", "rc1", ...
	var release: String
	## "Godot 4.7.2" or "Godot 4.8 dev7".
	var display_name: String
	## One of the CHANNEL_* constants.
	var channel: String
	## As written in versions.yml, e.g. "18 August 2026". May be empty.
	var release_date: String
	## Absolute url, or empty when there are no notes.
	var release_notes_url: String
	## The major this stable build is featured for on godotengine.org ("4", "3"), or
	## empty.
	var featured: String
	## Featured for the newest featured major: the one recommended build.
	var recommended: bool
	## Bigger is newer.
	var sort_key: int

	func is_stable() -> bool:
		return channel == EditorCatalog.CHANNEL_STABLE

	## The godot-builds release tag, e.g. "4.8-dev7".
	func tag() -> String:
		return "%s-%s" % [version, release]


## Standard or .NET build of a [EditorCatalog.CatalogEntry] for this platform.
class CatalogVariant:
	## True for the .NET (C#) build.
	var mono: bool
	## False when the release has no file for this platform.
	var available: bool
	var url: String
	var file_name: String
	var size_bytes: int
	## Platform of the picked file, e.g. "Linux x86_64", or "Windows x86_64" for the
	## x64 build picked on Windows on ARM. This platform when not available.
	var platform_label: String
	## The release's export templates archive (.tpz) for this build, or empty. Set
	## when the build is not [member available] too.
	var templates_url: String
	## Download size of the whole templates archive, or 0 when unknown.
	var templates_size_bytes: int


## A release files request that callers asking for the same files wait for.
class AssetsRequest:
	## Emitted when [member assets] is set.
	signal finished

	## The files loaded, empty when the request failed.
	var assets: Array[RemoteEditorsTreeDataSourceGithub.GodotAsset] = []
