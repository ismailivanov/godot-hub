class_name AssetLibItemDetailsDialog
extends ConfirmationDialog

signal download_requested(item: AssetLib.Item, icon: Texture2D)

const _GITHUB_REPO_RE := r"^https?://github\.com/([^/]+)/([^/?#]+)"

@onready var _asset_list_item := %AssetListItem as AssetListItemView
@onready var _description_label := %DescriptionLabel as AssetLibDetailsDescriptionLabel
@onready var _preview := %Preview as TextureRect
@onready var _preview_bg := %PreviewBg as PanelContainer
@onready var _previews_container := %PreviewsContainer as HBoxContainer
@onready var _version_option := %VersionOption as OptionButton
@onready var _store_page_button := %StorePageButton as Button
@onready var _tabs := %Tabs as TabContainer
@onready var _changelog_label := %ChangelogLabel as RichTextLabel

var _item_id: String
var _asset_lib: AssetLib.I
var _images_src: RemoteImageSrc.I
var _releases_request: HTTPRequest


func init(item_id: String, asset_lib: AssetLib.I, images: RemoteImageSrc.I) -> void:
	_item_id = item_id
	_asset_lib = asset_lib
	_images_src = images


func _ready() -> void:
	_description_label.add_theme_constant_override("line_separation", roundi(5 * Config.EDSCALE))

	min_size = Vector2(1100, 600) * Config.EDSCALE

	_preview.custom_minimum_size = Vector2(640, 345) * Config.EDSCALE
	_preview_bg.custom_minimum_size = Vector2(640, 101) * Config.EDSCALE

	_tabs.set_tab_title(0, tr("Description"))
	_tabs.set_tab_title(1, tr("Changelog"))

	_store_page_button.icon = get_theme_icon("ExternalLink", "EditorIcons")

	_releases_request = HTTPRequest.new()
	add_child(_releases_request)

	_changelog_label.meta_clicked.connect(func(meta: Variant) -> void:
		OS.shell_open(str(meta))
	)

	var item := await _asset_lib.async_fetch_one(_item_id)
	if item == null:
		return
	_configure(item)


func _configure(item: AssetLib.Item) -> void:
	confirmed.connect(func() -> void:
		download_requested.emit(_item_with_selected_version(item), _asset_list_item.get_icon_texture())
	)
	_asset_list_item.init(item, _images_src)
	_description_label.configure(item)
	title = item.title

	_populate_versions(item)
	_async_fetch_github_releases(item)

	var url := item.browse_url
	_store_page_button.disabled = url.is_empty()
	if not url.is_empty():
		_store_page_button.pressed.connect(func() -> void: OS.shell_open(url))

	var first_preview_selected := false
	for preview in item.previews:
		var btn := add_preview(preview)
		if not first_preview_selected and not preview.is_video:
			first_preview_selected = true
			_handle_btn_pressed.bind(preview, btn).call_deferred()


func _populate_versions(item: AssetLib.Item) -> void:
	_version_option.clear()
	var label := item.version_string
	_version_option.add_item(label if not label.is_empty() else tr("Latest"))
	_version_option.set_item_metadata(0, null)
	for prev in item.previous_versions:
		var prev_label := prev.version_string
		if not prev.godot_version.is_empty():
			prev_label += "  (Godot " + prev.godot_version + ")"
		_version_option.add_item(prev_label)
		_version_option.set_item_metadata(_version_option.item_count - 1, prev)


func _async_fetch_github_releases(item: AssetLib.Item) -> void:
	var owner_repo := _parse_github_owner_repo(item.browse_url)
	if owner_repo.is_empty():
		_changelog_label.clear()
		_changelog_label.append_text("[i]" + tr("Changelog not available.") + "[/i]")
		return
	var url := "https://api.github.com/repos/%s/%s/releases?per_page=100" % [owner_repo[0], owner_repo[1]]
	var headers: PackedStringArray = ["Accept: application/vnd.github+json", Config.AGENT_HEADER]
	var err := _releases_request.request(url, headers)
	if err != OK:
		_changelog_label.clear()
		_changelog_label.append_text("[i]" + tr("Failed to fetch changelog.") + "[/i]")
		return
	var response: Array = await _releases_request.request_completed
	var result: int = response[0]
	var code: int = response[1]
	var body: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_changelog_label.clear()
		_changelog_label.append_text("[i]" + tr("Failed to fetch changelog.") + "[/i]")
		return
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not json is Array:
		return

	var existing_tags: Dictionary = {}
	for i in range(_version_option.item_count):
		existing_tags[_version_option.get_item_text(i).strip_edges()] = true

	for rel: Dictionary in json:
		var tag: String = rel.get("tag_name", "")
		if tag.is_empty() or existing_tags.has(tag):
			continue
		var zip_url: String = rel.get("zipball_url", "")
		if zip_url.is_empty():
			continue
		var label := tag
		if rel.get("prerelease", false):
			label += "  (pre-release)"
		_version_option.add_item(label)
		var version := AssetLib.ItemVersion.new({
			"version_string": tag,
			"download_url": zip_url,
		})
		_version_option.set_item_metadata(_version_option.item_count - 1, version)

	_render_changelog(json as Array)


func _render_changelog(releases: Array) -> void:
	if releases.is_empty():
		_changelog_label.text = ""
		_changelog_label.append_text("[i]" + tr("No releases found.") + "[/i]")
		return

	var accent := get_theme_color("accent_color", "Editor")
	var dim := get_theme_color("font_color", "Label")
	dim.a = 0.65
	var accent_hex := accent.to_html(false)
	var dim_hex := dim.to_html(false)

	_changelog_label.clear()
	for i in range(releases.size()):
		var rel: Dictionary = releases[i]
		var tag: String = rel.get("tag_name", "")
		var name: String = rel.get("name", "")
		var published: String = rel.get("published_at", "")
		var is_pre: bool = rel.get("prerelease", false)
		var body_md: String = rel.get("body", "")

		var header := "[b][color=#%s]%s[/color][/b]" % [accent_hex, tag if not tag.is_empty() else name]
		if not name.is_empty() and name != tag:
			header += "  [color=#%s]%s[/color]" % [dim_hex, name]
		if is_pre:
			header += "  [color=#%s][pre-release][/color]" % dim_hex
		_changelog_label.append_text(header + "\n")

		if not published.is_empty():
			_changelog_label.append_text("[color=#%s]%s[/color]\n" % [dim_hex, published.substr(0, 10)])

		_changelog_label.append_text("\n")
		if body_md.strip_edges().is_empty():
			_changelog_label.append_text("[i][color=#%s]" % dim_hex + tr("No release notes.") + "[/color][/i]\n")
		else:
			_changelog_label.append_text(_md_to_bbcode(body_md) + "\n")

		if i < releases.size() - 1:
			_changelog_label.append_text("\n[color=#%s]────────────────────[/color]\n\n" % dim_hex)


func _md_to_bbcode(md: String) -> String:
	var accent := get_theme_color("accent_color", "Editor")
	var accent_hex := accent.to_html(false)
	var code_bg := get_theme_color("base_color", "Editor")
	var code_bg_hex := code_bg.to_html(false)
	var dim := get_theme_color("font_color", "Label")
	dim.a = 0.7
	var dim_hex := dim.to_html(false)

	var admonitions := {
		"NOTE": ["#3FB6FF", "ℹ Note"],
		"TIP": ["#3DD68C", "✓ Tip"],
		"IMPORTANT": ["#A371F7", "★ Important"],
		"WARNING": ["#E3B341", "⚠ Warning"],
		"CAUTION": ["#F85149", "⛔ Caution"],
	}
	var admon_re := RegEx.create_from_string(r"(?i)^\s*>?\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$")

	var lines := md.split("\n")
	var out: PackedStringArray = []
	var in_code_block := false
	for raw_line in lines:
		var line := raw_line as String
		var trimmed := line.strip_edges(false, true)

		if trimmed.begins_with("```"):
			in_code_block = not in_code_block
			if in_code_block:
				out.append("[bgcolor=#%s][code]" % code_bg_hex)
			else:
				out.append("[/code][/bgcolor]")
			continue
		if in_code_block:
			out.append(line)
			continue

		# GitHub admonitions: > [!NOTE], > [!TIP], etc.
		var am := admon_re.search(line)
		if am:
			var key := am.get_string(1).to_upper()
			var info: Array = admonitions[key]
			out.append("[b][color=#%s]%s[/color][/b]" % [info[0], info[1]])
			continue

		# Headings
		if trimmed.begins_with("### "):
			out.append("[b][color=#%s]%s[/color][/b]" % [accent_hex, _md_inline(trimmed.substr(4))])
			continue
		if trimmed.begins_with("## "):
			out.append("[font_size=18][b][color=#%s]%s[/color][/b][/font_size]" % [accent_hex, _md_inline(trimmed.substr(3))])
			continue
		if trimmed.begins_with("# "):
			out.append("[font_size=20][b][color=#%s]%s[/color][/b][/font_size]" % [accent_hex, _md_inline(trimmed.substr(2))])
			continue

		# Bullet lists
		var bullet_re := RegEx.create_from_string(r"^(\s*)[-*+]\s+(.*)$")
		var bm := bullet_re.search(line)
		if bm:
			var indent := bm.get_string(1).length()
			var content := _md_inline(bm.get_string(2))
			out.append("%s•  %s" % ["    ".repeat(indent / 2 + 1), content])
			continue

		# Numbered lists
		var num_re := RegEx.create_from_string(r"^(\s*)\d+\.\s+(.*)$")
		var nm := num_re.search(line)
		if nm:
			var indent2 := nm.get_string(1).length()
			out.append("%s%s" % ["    ".repeat(indent2 / 2 + 1), _md_inline(nm.get_string(2))])
			continue

		# Blockquote (after admonition check so admonition body isn't double-italicized)
		if trimmed.begins_with("> "):
			out.append("[color=#%s][i]%s[/i][/color]" % [dim_hex, _md_inline(trimmed.substr(2))])
			continue
		if trimmed == ">":
			out.append("")
			continue

		out.append(_md_inline(line))
	return "\n".join(out)


func _md_inline(s: String) -> String:
	# Escape BBCode brackets first to prevent injection.
	s = s.replace("[", "[lb]")
	# Inline code: `...` -> [code]...[/code]
	var code_re := RegEx.create_from_string(r"`([^`]+)`")
	s = code_re.sub(s, "[code]$1[/code]", true)
	# Bold: **...** -> [b]...[/b]
	var bold_re := RegEx.create_from_string(r"\*\*([^*]+)\*\*")
	s = bold_re.sub(s, "[b]$1[/b]", true)
	# Italic: *...* -> [i]...[/i]
	var ital_re := RegEx.create_from_string(r"(?<!\*)\*([^*\n]+)\*(?!\*)")
	s = ital_re.sub(s, "[i]$1[/i]", true)
	# Links: [text](url) -> [url=url]text[/url] (after [ escape, source is "[lb]text](url)")
	var link_re := RegEx.create_from_string(r"\[lb\]([^\]]+)\]\(([^)]+)\)")
	s = link_re.sub(s, "[url=$2]$1[/url]", true)
	return s


func _parse_github_owner_repo(url: String) -> Array:
	var re := RegEx.create_from_string(_GITHUB_REPO_RE)
	var m := re.search(url)
	if m == null:
		return []
	var repo := m.get_string(2)
	if repo.ends_with(".git"):
		repo = repo.substr(0, repo.length() - 4)
	return [m.get_string(1), repo]


func _item_with_selected_version(item: AssetLib.Item) -> AssetLib.Item:
	var meta: Variant = _version_option.get_selected_metadata()
	if meta == null:
		return item
	var prev := meta as AssetLib.ItemVersion
	var data := {
		"asset_id": item.id,
		"author": item.author,
		"cost": item.cost,
		"title": item.title,
		"category": item.category,
		"description": item.description,
		"version_string": prev.version_string,
		"browse_url": item.browse_url,
		"download_url": prev.download_url,
		"download_hash": prev.download_hash,
		"icon_url": item.icon_url,
	}
	return AssetLib.Item.new(data)


func add_preview(item: AssetLib.ItemPreview) -> Button:
	var btn := Button.new()
	btn.icon = get_theme_icon("ThumbnailWait", "EditorIcons")
	btn.toggle_mode = true
	btn.pressed.connect(_handle_btn_pressed.bind(item, btn))
	_previews_container.add_child(btn)
	_images_src.async_load_img(item.thumbnail, func(tex: Texture2D) -> void:
		if not item.is_video:
			if tex is ImageTexture:
				utils.fit_height(85 * Config.EDSCALE, tex.get_size(), func(new_size: Vector2i) -> void:
					(tex as ImageTexture).set_size_override(new_size)
				)
			btn.icon = tex
		else:
			var overlay := get_theme_icon("PlayOverlay", "EditorIcons").get_image()
			var tex_image: Image = tex.get_image()
			if tex_image == null:
				tex_image = get_theme_icon("FileBrokenBigThumb", "EditorIcons").get_image()
			utils.fit_height(85 * Config.EDSCALE, tex_image.get_size(), func(new_size: Vector2i) -> void:
				tex_image.resize(new_size.x, new_size.y, Image.INTERPOLATE_LANCZOS)
			)
			var thumbnail := tex_image.duplicate() as Image
			var overlay_pos := Vector2i(
				(thumbnail.get_width() - overlay.get_width()) / 2,
				(thumbnail.get_height() - overlay.get_height()) / 2
			)
			thumbnail.convert(Image.FORMAT_RGBA8)
			thumbnail.blend_rect(overlay, overlay.get_used_rect(), overlay_pos)
			btn.icon = ImageTexture.create_from_image(thumbnail)
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	)
	return btn


func _handle_btn_pressed(item: AssetLib.ItemPreview, btn: Button) -> void:
	for child in _previews_container.get_children():
		child.set("button_pressed", false)
	btn.button_pressed = true
	if item.is_video:
		OS.shell_open(item.link)
	else:
		_images_src.async_load_img(item.link, func(tex: Texture2D) -> void:
			if tex is ImageTexture:
				utils.fit_height(397 * Config.EDSCALE, tex.get_size(), func(new_size: Vector2i) -> void:
					(tex as ImageTexture).set_size_override(new_size)
				)
			_preview.texture = tex
		)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		if is_node_ready():
			_preview_bg.add_theme_stylebox_override("panel", get_theme_stylebox("normal", "TextEdit"))
