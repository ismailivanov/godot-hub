class_name RemoteEditorsTreeDataSourceGithub

const CHANNEL_TAB_ALL := 0
const CHANNEL_TAB_OFFICIAL := 1
const CHANNEL_TAB_PRERELEASE := 2


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


static func platform_suffixes_current_os() -> Array[String]:
	var out: Array[String] = []
	if OS.has_feature("windows"):
		out.assign(["_win64.exe.zip", "_win64.zip", "_win32.exe.zip", "_win32.zip"])
	elif OS.has_feature("macos"):
		out.assign(["_osx.universal.zip", "_macos.universal.zip", "_osx.fat.zip", "_osx64.zip", "_osx32.zip"])
	elif OS.has_feature("linux"):
		out.assign([
			"_linux.x86_64.zip",
			"_linux_x86_64.zip",
			"_linux.64.zip",
			"_x11.64.zip",
			"_linux.x86_32.zip",
			"_linux_x86_32.zip",
		])
	return out


static func _stable_editor_asset_name_ok(asset_name: String) -> bool:
	var low := asset_name.to_lower()
	if ".mono." in low or "_mono." in low:
		return false
	if low.ends_with(".mono.zip"):
		return false
	if low.contains("console"):
		return false
	return true


static func pick_platform_stable_asset(assets: Array[GodotAsset], suffixes: Array[String]) -> GodotAsset:
	for suffix in suffixes:
		for asset in assets:
			if not _stable_editor_asset_name_ok(asset.name):
				continue
			if asset.name.ends_with(suffix):
				return asset
	return null


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


class Self extends RemoteEditorsTreeDataSource.I:
	var _assets: RemoteEditorsTreeDataSource.RemoteAssets
	const platforms = {
		"X11": {
			"suffixes": ["_x11.64.zip", "_linux.64.zip", "_linux.x86_64.zip", "_linux.x86_32.zip", "_linux_x86_64.zip", "_linux_x86_32.zip"],
		},
		"OSX": {
			"suffixes": ["_osx.universal.zip", "_macos.universal.zip", "_osx.fat.zip", "_osx32.zip", "_osx64.zip"],
		},
		"Windows": {
			"suffixes": ["_win64.exe.zip", "_win32.exe.zip", "_win64.zip", "_win32.zip"],
		}
	}
	
	func _init(assets: RemoteEditorsTreeDataSource.RemoteAssets) -> void:
		_assets = assets
	
	func setup(tree: Tree) -> void:
		var root := tree.create_item()
		root.set_meta(
			"delegate", 
			GithubRootItem.new(
				root, 
				_assets,
				GithubVersionSourceParseYml.new(
					YmlSourceGithub.new(),
					GithubAssetSourceDefault.new()
				),
			)
		)
	
	func cleanup(tree: Tree) -> void:
		tree.clear()
	
	func get_platform_suffixes() -> Array:
		var current_platform: Dictionary
		if OS.has_feature("windows"):
			current_platform = platforms["Windows"]
		elif OS.has_feature("macos"):
			current_platform = platforms["OSX"]
		elif OS.has_feature("linux"):
			current_platform = platforms["X11"]
		return current_platform["suffixes"]
	
	func to_remote_item(item: TreeItem) -> RemoteEditorsTreeDataSource.Item:
		return item.get_meta("delegate")


class GithubVersion:
	var name: String
	var flavor: String
	var releases: Array[String] = []
	var _assets_src: GithubAssetSource
	
	func get_flavor_release() -> GodotRelease:
		return GodotRelease.new(name, flavor, _assets_src)
	
	func get_recent_releases() -> Array[GodotRelease]:
		var result: Array[GodotRelease] = []
		for r in releases:
			result.append(GodotRelease.new(name, r, _assets_src))
		return result


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
	
	func _init(json: Dictionary) -> void:
		_json = json


class GithubItemBase extends RemoteEditorsTreeDataSource.Item:
	var _item: TreeItem
	var _assets: RemoteEditorsTreeDataSource.RemoteAssets
	
	func _init(item: TreeItem, assets: RemoteEditorsTreeDataSource.RemoteAssets) -> void:
		_item = item
		_assets = assets
	
	func is_loaded() -> bool:
		return _item.has_meta("loaded")
	
	func async_expand(tree: RemoteTree) -> void:
		return
	
	func handle_item_activated() -> void:
		pass
	
	func handle_button_clicked(col: int, id: int, mouse: int) -> void:
		pass
	
	func update_visibility(filters: Array) -> void:
		var filter_target := _to_filter_target() 
		if filter_target == null:
			return
		_item.visible = _should_be_visible(filter_target, filters)
	
	func _should_be_visible(target: GithubFilterTarget, filters: Array) -> bool:
		if target.is_file() and not target.is_zip():
			return false

		for filter: RemoteEditorsTreeControl.RowFilter in filters:
			if filter.test(target):
				return false
		
		return true
	
	func _to_filter_target() -> GithubFilterTarget:
		return null
	
	func _asset_to_item(asset: GodotAsset, tree: RemoteEditorsTreeDataSource.RemoteTree, channel_major: int, channel_prerelease: bool) -> void:
		var tree_item := tree.create_item(_item)
		tree_item.set_meta("delegate", GithubAssetItem.new(tree_item, _assets, asset, channel_major, channel_prerelease))
		tree_item.set_text(0, asset.name)
		tree_item.set_icon(0, tree.theme_source.get_theme_icon("Godot", "EditorIcons"))
		var btn_texture: Texture2D = tree.theme_source.get_theme_icon("AssetLib", "EditorIcons")
		tree_item.add_button(0, btn_texture)
		tree_item.collapsed = true
	
	func get_children() -> Array[RemoteEditorsTreeDataSource.Item]:
		var result: Array[RemoteEditorsTreeDataSource.Item] = []
		for child in _item.get_children():
			if child.has_meta("delegate"):
				result.append(child.get_meta("delegate"))
		return result


class GithubAssetItem extends GithubItemBase:
	var _asset: GodotAsset
	var _channel_major: int
	var _channel_prerelease: bool
	
	func _init(item: TreeItem, assets: RemoteEditorsTreeDataSource.RemoteAssets, asset: GodotAsset, channel_major: int, channel_prerelease: bool) -> void:
		super._init(item, assets)
		_asset = asset
		_channel_major = channel_major
		_channel_prerelease = channel_prerelease
	
	func _to_filter_target() -> GithubFilterTarget:
		return GithubFilterTarget.new(_asset.name, false, true, _asset.is_zip, _channel_major, _channel_prerelease)

	func handle_item_activated() -> void:
		_assets.download(_asset.browser_download_url, _asset.file_name)

	func handle_button_clicked(col: int, id: int, mouse: int) -> void:
		_assets.download(_asset.browser_download_url, _asset.file_name)


class GithubReleaseItem extends GithubItemBase:
	var _release: GodotRelease
	
	func _init(item: TreeItem, assets: RemoteEditorsTreeDataSource.RemoteAssets, release: GodotRelease) -> void:
		super._init(item, assets)
		_release = release
	
	func async_expand(tree: RemoteEditorsTreeDataSource.RemoteTree) -> void:
		_item.set_meta("loaded", true)
		var assets := await _release.async_load_assets()
		for asset in assets:
			var maj_r: int = RemoteEditorsTreeDataSourceGithub.channel_major_from_version_name(_release._version)
			var rel_pre: bool = _release.name != "stable" or RemoteEditorsTreeDataSourceGithub.channel_name_looks_prerelease(_release.name)
			var file_pre: bool = RemoteEditorsTreeDataSourceGithub.channel_name_looks_prerelease(asset.name)
			_asset_to_item(asset, tree, maj_r, rel_pre or file_pre)
		tree.free_loading_placeholder(_item)

	func _to_filter_target() -> GithubFilterTarget:
		var maj: int = RemoteEditorsTreeDataSourceGithub.channel_major_from_version_name(_release._version)
		var pre: bool = _release.name != "stable" or RemoteEditorsTreeDataSourceGithub.channel_name_looks_prerelease(_release.name)
		return GithubFilterTarget.new(_release.name, false, false, false, maj, pre)


class GithubVersionItem extends GithubItemBase:
	var _version: GithubVersion
	
	func _init(item: TreeItem, assets: RemoteEditorsTreeDataSource.RemoteAssets, version: GithubVersion) -> void:
		super._init(item, assets)
		_version = version
	
	func async_expand(tree: RemoteEditorsTreeDataSource.RemoteTree) -> void:
		_item.set_meta("loaded", true)
		
		var releases: Array[GodotRelease] = []
		var flavor := _version.get_flavor_release()
		if not flavor.is_stable():
			releases.append(flavor)
		releases.append_array(_version.get_recent_releases())
		
		for release in releases:
			var tree_item := tree.create_item(_item)
			tree_item.visible = false
			tree_item.set_text(0, release.name)
			tree.set_as_folder(tree_item)
			tree_item.set_meta(
				"delegate", 
				GithubReleaseItem.new(tree_item, _assets, release)
			)
			tree_item.collapsed = true
		
		if flavor.is_stable():
			var assets := await flavor.async_load_assets()
			var maj_v: int = RemoteEditorsTreeDataSourceGithub.channel_major_from_version_name(_version.name)
			for asset in assets:
				var file_pre: bool = RemoteEditorsTreeDataSourceGithub.channel_name_looks_prerelease(asset.name)
				_asset_to_item(asset, tree, maj_v, file_pre)

		tree.free_loading_placeholder(_item)

	func _to_filter_target() -> GithubFilterTarget:
		var maj: int = RemoteEditorsTreeDataSourceGithub.channel_major_from_version_name(_version.name)
		var flav := _version.flavor.strip_edges()
		var folder_hide_official: bool = flav != "stable" or RemoteEditorsTreeDataSourceGithub.channel_name_looks_prerelease(_version.flavor)
		return GithubFilterTarget.new(_version.name, true, false, false, maj, folder_hide_official)


class GithubRootItem extends GithubItemBase:
	var _versions_source: GithubVersionSource
	
	func _init(item: TreeItem, assets: RemoteEditorsTreeDataSource.RemoteAssets, versions_source: GithubVersionSource) -> void:
		super._init(item, assets)
		_versions_source = versions_source
	
	func async_expand(tree: RemoteEditorsTreeDataSource.RemoteTree) -> void:
		_item.set_meta("loaded", true)
		var versions := await _versions_source.async_load()
		for version in versions:
			var tree_item := tree.create_item(_item)
			tree.set_as_folder(tree_item)
			tree_item.set_text(0, version.name)
			tree_item.set_meta("delegate", GithubVersionItem.new(tree_item, _assets, version))
			tree_item.collapsed = true
		tree.free_loading_placeholder(_item)


class GithubFilterTarget extends RemoteEditorsTreeDataSource.FilterTarget:
	var _name: String
	var _is_possible_version_folder: bool
	var _is_file: bool
	var _is_zip: bool
	var channel_major: int = 0
	var channel_prerelease: bool = false

	func _init(name: String, is_possible_version_folder: bool, is_file: bool, is_zip: bool, p_channel_major: int = 0, p_channel_prerelease: bool = false) -> void:
		_name = name
		_is_possible_version_folder = is_possible_version_folder
		_is_file = is_file
		_is_zip = is_zip
		channel_major = p_channel_major
		channel_prerelease = p_channel_prerelease

	func is_possible_version_folder() -> bool:
		return _is_possible_version_folder

	func is_file() -> bool:
		return _is_file

	func is_zip() -> bool:
		return _is_zip

	func is_for_different_platform(platform_suffixes: Array) -> bool:
		var cached_name := get_name()
		return not platform_suffixes.any(func(suffix: String) -> bool: return cached_name.ends_with(suffix))

	func get_name() -> String:
		return _name
	
	func channel_tab_should_hide(tab: int) -> bool:
		if tab == RemoteEditorsTreeDataSourceGithub.CHANNEL_TAB_ALL:
			return false
		if is_possible_version_folder():
			match tab:
				RemoteEditorsTreeDataSourceGithub.CHANNEL_TAB_OFFICIAL:
					return channel_major < 3 or channel_prerelease
				RemoteEditorsTreeDataSourceGithub.CHANNEL_TAB_PRERELEASE:
					return channel_major < 3
				_:
					return false
		match tab:
			RemoteEditorsTreeDataSourceGithub.CHANNEL_TAB_OFFICIAL:
				return channel_major < 3 or channel_prerelease
			RemoteEditorsTreeDataSourceGithub.CHANNEL_TAB_PRERELEASE:
				return channel_major < 3 or not channel_prerelease
			_:
				return false


class GithubVersionSource:
	func async_load() -> Array[GithubVersion]:
		return []


class GithubAssetSource:
	func async_load(version: String, release: String) -> Array[GodotAsset]:
		return []


class GithubAssetSourceDefault extends GithubAssetSource:
	const url = "https://api.github.com/repos/godotengine/godot-builds/releases/tags/%s"
	
	func async_load(version: String, release: String) -> Array[GodotAsset]:
		var tag := "%s-%s" % [version, release]
		var response := await HttpClient.async_http_get(
			url % tag,
			["Accept: application/vnd.github.v3+json"]
		)
		var json: Dictionary = JSON.parse_string(
			(response[3] as PackedByteArray).get_string_from_utf8()
		)
		var result: Array[GodotAsset] = []
		for asset_json: Dictionary in json.get('assets', []):
			result.append(GodotAsset.new(asset_json))
		return result


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
	
	func async_load() -> Array[GithubVersion]:
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
	
	func _init(src: YmlSource, assets_src: GithubAssetSource) -> void:
		_src = src
		_assets_src = assets_src
	
	func async_load() -> Array[GithubVersion]:
		var yml := await _src.async_load()
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
			for release_name: RegExMatch in name_results.slice(1):
				version.releases.append(release_name.get_string("name"))
			result.append(version)
		return result
