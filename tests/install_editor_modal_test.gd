extends Node
## Offline tests of the Install Editor modal: opening, tabs, search, the build and
## export templates steps, builds that cannot be installed here, installs, Installed
## rows, Esc, the version list states and the theme's rounded corners.


const THEME_SOURCE := preload("res://theme/theme.gd")
const MODAL_SCENE := preload("res://src/components/editors/remote/remote_editors.tscn")
const ROW_SCENE := preload("res://src/components/editors/remote/catalog_row/catalog_row.tscn")
const DOWNLOADS_AREA_SCENE := preload(
	"res://src/components/editors/local/editor_downloads/editor_downloads.tscn"
)
const DOWNLOAD_SCENE := preload("res://src/components/asset_download/asset_download.tscn")
const VERSIONS_YML := "res://tests/assets/editor_catalog_versions.yml"
const RELEASE_JSON := "res://tests/assets/editor_catalog_release.json"
## Nothing listens there, so a started download fails without using the network.
const OFFLINE_URL := "http://127.0.0.1:9/"

var _failures := 0
var _modal: RemoteEditorsControl
var _yml_src: CountingYmlSource
var _catalog: EditorCatalog
## Asset source of [member _catalog].
var _assets: OfflineAssetSource
var _frame: Control
var _page_button: Button
var _downloads: VBoxContainer
var _download_items: Array[AssetDownload] = []
var _closed_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _setup()
	await _test_row_heights()
	await _test_lazy_load_on_open()
	_test_official_rows()
	_test_tab_switch()
	_test_search()
	_test_installed_rows()
	await _test_options_page_and_back()
	await _test_wizard_steps()
	await _test_not_for_platform()
	await _test_unavailable_variants()
	await _test_no_editor_builds()
	await _test_installed_alternative()
	await _test_live_row_update()
	await _test_failed_release_load()
	await _test_install_starts_download()
	await _test_escape()
	await _test_close_controls()
	await _test_direct_link()
	await _test_load_error_and_retry()
	await _test_slow_load()
	await _test_refresh()
	await _test_rounded_corners()
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Install editor modal tests passed.")
	get_tree().quit()


func _setup() -> void:
	var root := get_tree().root
	# Popups become embedded subwindows, which headless runs can show.
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 800)

	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.theme = THEME_SOURCE.create_custom_theme(null)
	add_child(frame)
	_frame = frame
	_downloads = VBoxContainer.new()
	frame.add_child(_downloads)
	# Stands in for the Installs page under the modal.
	_page_button = Button.new()
	_page_button.text = "Remove"
	_downloads.add_child(_page_button)

	# Added hidden like in GuiMain, above the page.
	_modal = MODAL_SCENE.instantiate() as RemoteEditorsControl
	frame.add_child(_modal)
	_modal.init(func(item: Control) -> void:
		_download_items.append(item as AssetDownload)
		_downloads.add_child(item)
	)
	_modal.closed.connect(func() -> void: _closed_count += 1)
	# No archive to read: the templates step says so instead of going online.
	_modal.set_templates_source_factory(func(_url: String, _known_size: int) -> RangeSource:
		return FileRangeSource.new(ProjectSettings.globalize_path("user://no-such-archive.tpz"))
	)
	_yml_src = CountingYmlSource.new(VERSIONS_YML)
	_assets = OfflineAssetSource.new()
	_catalog = _fixture_catalog(_yml_src, _assets)
	_modal.use_catalog(_catalog)
	await _wait_frames(2)


func _test_row_heights() -> void:
	var full := _entry("Godot 4.7.2", "18 August 2026", "https://example.com/notes")
	full.recommended = true
	var pre := _entry("Godot 4.8 dev7", "29 September 2026", "https://example.com/dev7")
	pre.channel = EditorCatalog.CHANNEL_DEV
	var bare := _entry("Godot 1.0", "", "")
	var latest := _entry("Godot 3.6.3", "22 August 2026", "https://example.com/3.6.3")
	latest.featured = "3"
	var unavailable := _entry("Godot 4.0", "1 March 2023", "https://example.com/4.0")
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 800
	_frame.add_child(list)
	var rows: Array[EditorCatalogRow] = []
	var entries: Array[EditorCatalog.CatalogEntry] = [full, pre, bare, latest, unavailable]
	for entry in entries:
		var row := ROW_SCENE.instantiate() as EditorCatalogRow
		list.add_child(row)
		row.init(entry, entry == bare)
		rows.append(row)
	rows[4].set_unavailable_reason("Godot 4.0 has no editor build for Linux arm64.")
	await _wait_frames(2)
	var unavailable_label := rows[4].get_node("%UnavailableLabel") as Label
	_check(
		unavailable_label.visible and not rows[4].get_install_button().visible,
		"A Not available label replaces the Install button",
	)
	_check(unavailable_label.text == "Not available", "Wrong Not available text")
	_check(
		unavailable_label.tooltip_text == "Godot 4.0 has no editor build for Linux arm64.",
		"The Not available label says why in its tooltip",
	)
	_check(rows[4].is_unavailable(), "Expected an unavailable row")
	_check(
		not (rows[2].get_node("%UnavailableLabel") as Control).visible,
		"Installed rows never say Not available",
	)
	_check(EditorCatalogRow.badge_text(full) == "Recommended", "Wrong recommended badge")
	_check(EditorCatalogRow.badge_text(pre) == "dev", "Wrong pre-release badge")
	_check(EditorCatalogRow.badge_text(bare).is_empty(), "Stable builds have no badge")
	_check(EditorCatalogRow.badge_text(latest) == "Latest 3.x", "Wrong older featured badge")
	_check(not (rows[2].get_node("%Badge") as Control).visible, "Expected no badge shown")
	_check(
		not (rows[2].get_node("%ReleaseNotesButton") as Control).visible,
		"Expected no release notes link without a url",
	)
	var heights := PackedFloat32Array()
	for row in rows:
		heights.append(row.size.y)
	_check(
		Array(heights).all(func(height: float) -> bool: return is_equal_approx(height, heights[0])),
		"Rows should have one height, got %s" % heights,
	)
	_check(
		is_equal_approx(rows[0].size.y, EditorCatalogRow.ROW_HEIGHT * Config.EDSCALE),
		"ROW_HEIGHT should be the row height, got %s" % rows[0].size.y,
	)
	var install_widths := {}
	for row in rows:
		if row.get_install_button().visible:
			install_widths[roundi(row.get_install_button().size.x)] = true
	_check(install_widths.size() == 1, "Install buttons should have one width")
	list.queue_free()
	await _wait_frames(1)


func _test_lazy_load_on_open() -> void:
	_check(not _modal.visible, "The modal should start hidden")
	_check(not _modal.is_open(), "The modal should start closed")
	_check(_yml_src.load_count == 0, "The catalog should not load before the first open")

	_modal.open()
	await _wait_frames(2)
	_check(_modal.is_open() and _modal.visible, "open() should show the modal")
	_check(_yml_src.load_count == 1, "The first open should load the catalog")
	_check(_part("Dim").mouse_filter == Control.MOUSE_FILTER_STOP, "The dim layer stops clicks")
	var panel := _part("Panel") as Control
	_check(
		panel.size.is_equal_approx(RemoteEditorsControl.PANEL_MAX_SIZE * Config.EDSCALE),
		"Expected the panel at its largest size in a 1280x800 window, got %s" % panel.size,
	)
	_check(
		panel.get_global_rect().get_center().is_equal_approx(_modal.get_global_rect().get_center()),
		"Expected the panel centered",
	)
	_check(
		_modal.get_viewport().gui_get_focus_owner() == _part("SearchEdit"),
		"Opening should focus the search field",
	)

	_check(
		_page_button.get_focus_mode_with_override() == Control.FOCUS_NONE,
		"The page under the open modal must not take keyboard focus",
	)

	_modal.close()
	_page_button.grab_focus()
	_check(
		_modal.get_viewport().gui_get_focus_owner() == _page_button,
		"Closing should give the page its keyboard focus back",
	)
	_modal.open()
	await _wait_frames(1)
	_check(_yml_src.load_count == 1, "Reopening should reuse the loaded catalog")


func _test_official_rows() -> void:
	_check((_part("Title") as Label).text == "Install Godot Editor", "Wrong modal title")
	_check((_part("Tabs") as TabBar).current_tab == 0, "Expected the Official releases tab")
	_check_row_names(_catalog.entries(EditorCatalog.TAB_OFFICIAL), "official")
	var newest := _find_row("4.7.2", "stable")
	_check(newest != null, "Expected a 4.7.2 row")
	if newest != null:
		_check(_row_badge(newest) == "Recommended", "4.7.2 should be Recommended")
		_check(
			(newest.get_node("%DateLabel") as Label).text == "18 August 2026",
			"Expected the 4.7.2 release date",
		)
		_check(
			(newest.get_node("%ReleaseNotesButton") as Control).visible,
			"Expected a release notes link",
		)
		_check(newest.get_install_button().is_visible_in_tree(), "Expected an Install button")
	var old := _find_row("4.6.3", "stable")
	_check(old != null and _row_badge(old).is_empty(), "4.6.3 should have no badge")
	var latest_3 := _find_row("3.6.3", "stable")
	_check(
		latest_3 != null and _row_badge(latest_3) == "Latest 3.x",
		"3.6.3 should be the latest 3.x, not Recommended",
	)
	var heights := {}
	for row in _rows():
		heights[roundi(row.size.y)] = true
	_check(heights.size() == 1, "Expected rows of one height, got %s" % [heights.keys()])


func _test_tab_switch() -> void:
	var tabs := _part("Tabs") as TabBar
	tabs.current_tab = 1
	_check_row_names(_catalog.entries(EditorCatalog.TAB_PRERELEASE), "pre-release")
	var dev := _find_row("4.8", "dev7")
	_check(dev != null and _row_badge(dev) == "dev", "4.8 dev7 should have a dev badge")
	tabs.current_tab = 2
	_check_row_names(_catalog.entries(EditorCatalog.TAB_ARCHIVE), "archive")
	tabs.current_tab = 0
	_check_row_names(_catalog.entries(EditorCatalog.TAB_OFFICIAL), "official again")


func _test_search() -> void:
	var tabs := _part("Tabs") as TabBar
	tabs.current_tab = 2
	_search("4.6")
	_check_row_names(_catalog.entries(EditorCatalog.TAB_ARCHIVE, "4.6"), "search 4.6")
	_check(_rows().size() == 4, "Expected the four 4.6 releases, got %d" % _rows().size())

	_search("no such version")
	_check(_rows().is_empty(), "A search without matches should list nothing")
	_check((_part("State") as Control).visible, "Expected the empty state")
	_check(
		(_part("StateLabel") as Label).text.contains("no such version"),
		"The empty state should name the search",
	)
	_check(not (_part("RetryButton") as Control).visible, "The empty state has no Retry")

	_search("")
	tabs.current_tab = 0
	_check(not (_part("State") as Control).visible, "Clearing the search shows the list again")
	_check_row_names(_catalog.entries(EditorCatalog.TAB_OFFICIAL), "cleared search")


func _test_installed_rows() -> void:
	var editors: Array[LocalEditors.Item] = [
		_editor("Godot v4.7.2 stable", "/editors/stable"),
		_editor("Godot v4.5.2 stable mono", "/editors/mono"),
	]
	_modal.set_installed_editors(editors)
	for key: Array in [["4.7.2", true], ["4.5.2", true], ["4.6.3", false]]:
		var row := _find_row(key[0] as String, "stable")
		var installed: bool = key[1]
		_check(row != null, "Missing row %s" % key[0])
		if row == null:
			continue
		_check(row.is_installed() == installed, "Wrong installed state of %s" % key[0])
		_check(
			row.get_install_button().is_visible_in_tree() != installed,
			"%s should %s an Install button" % [key[0], "not have" if installed else "have"],
		)
		_check(
			(row.get_node("%InstalledBox") as Control).is_visible_in_tree() == installed,
			"%s should %s the Installed mark" % [key[0], "show" if installed else "not show"],
		)

	# The Installs page frees its items when it reloads them.
	for editor in editors:
		editor.free()
	var none: Array[LocalEditors.Item] = []
	_modal.set_installed_editors(none)
	var newest := _find_row("4.7.2", "stable")
	_check(newest != null and not newest.is_installed(), "Expected 4.7.2 installable again")


func _test_options_page_and_back() -> void:
	var row := _find_row("4.7.2", "stable")
	if row == null:
		_check(false, "Missing the 4.7.2 row")
		return
	row.get_install_button().pressed.emit()
	await _wait_frames(2)
	_check((_part("OptionsPage") as Control).visible, "Install should open the build step")
	_check(not (_part("VersionsPage") as Control).visible, "The versions page should hide")
	_check((_part("Title") as Label).text == "Install Godot 4.7.2 › Build", "Wrong build title")
	_check((_part("OptionsDate") as Label).text == "18 August 2026", "Wrong options date")
	_check(not _part("MenuButton").visible, "The version list menu has no use on the build step")

	var expected := await _catalog.async_variants(row.get_entry())
	var buttons := _variant_buttons()
	_check(buttons.size() == 2, "Expected Standard and .NET, got %d" % buttons.size())
	if buttons.size() == 2 and expected.size() == 2:
		_check(buttons[0].text == "Standard" and buttons[1].text == ".NET (C#)", "Wrong labels")
		_check(not buttons[0].disabled and not buttons[1].disabled, "Both builds exist")
		_check(buttons[0].button_pressed, "Standard should be picked first")
		_check(buttons[0].button_group == buttons[1].button_group, "Expected a radio group")
		for i in 2:
			var details := _option_text(buttons[i])
			var variant := expected[i]
			_check(
				details.contains(variant.platform_label)
					and details.contains(variant.file_name)
					and details.contains(String.humanize_size(variant.size_bytes)),
				"Option %d should show platform, file and size, got: %s" % [i, details],
			)
	var next := _part("NextButton") as Button
	_check(next.visible and not next.disabled, "Next should lead to the export templates")
	_check(not _part("InstallButton").visible, "Install waits for the export templates step")
	_check((_part("BackButton") as Button).text == "Back", "Expected a Back button")
	_check(not _part("ExportTemplates").is_visible_in_tree(), "No templates on the build step")
	_check(
		_modal.get_viewport().gui_get_focus_owner() == next,
		"The loaded builds should focus Next",
	)
	_check(not (_part("VariantsStatus") as Control).visible, "No status when builds exist")
	if expected.size() == 2:
		var footer := (_part("FooterInfo") as Label).text
		_check(
			footer.contains(String.humanize_size(expected[0].size_bytes)),
			"The footer should say the Standard download size, got: %s" % footer,
		)
		await _test_row_click_selects(buttons)
		footer = (_part("FooterInfo") as Label).text
		_check(
			footer.contains(String.humanize_size(expected[1].size_bytes)),
			"The footer should follow the picked build, got: %s" % footer,
		)

	(_part("BackButton") as Button).pressed.emit()
	_check((_part("VersionsPage") as Control).visible, "Back should show the versions page")
	_check((_part("Title") as Label).text == "Install Godot Editor", "Back restores the title")
	_check(_part("MenuButton").visible, "Back shows the version list menu again")
	_check_row_names(_catalog.entries(EditorCatalog.TAB_OFFICIAL), "after Back")
	var back_row := _find_row("4.7.2", "stable")
	_check(
		back_row != null
			and _modal.get_viewport().gui_get_focus_owner() == back_row.get_install_button(),
		"Back should focus the row it came from",
	)


## Next leads to the optional export templates step; Back goes to the build step with
## the build that was picked.
func _test_wizard_steps() -> void:
	_find_row("4.7.2", "stable").get_install_button().pressed.emit()
	await _wait_frames(2)
	var buttons := _variant_buttons()
	if buttons.size() != 2:
		_check(false, "Expected two builds before Next")
		return
	buttons[1].button_pressed = true
	var variants := await _catalog.async_variants(_find_entry("4.7.2", "stable"))
	(_part("NextButton") as Button).pressed.emit()
	await _wait_frames(1)
	var title := (_part("Title") as Label).text
	_check(
		title == "Install Godot 4.7.2 › Export templates (optional)",
		"The title should name the step and say it is optional, got %s" % title,
	)
	_check(
		_part("TemplatesPage").visible and not _part("OptionsPage").visible,
		"Next should show the export templates step alone",
	)
	_check(_part("ExportTemplates").is_visible_in_tree(), "Expected the templates tree")
	var hint := (_part("ExportTemplates").get_node("%HintLabel") as Label).text
	_check(
		hint == (
			"Optional. Only needed to export projects. You can add or remove them later from "
			+ "the editor's menu."
		),
		"The step should say the templates are optional, got %s" % hint,
	)
	_check(not _part("NextButton").visible, "The templates step is the last")
	var install := _part("InstallButton") as Button
	_check(install.visible and not install.disabled, "Expected Install on the templates step")
	_check(_modal.get_viewport().gui_get_focus_owner() == install, "Install should take the focus")
	var footer := (_part("FooterInfo") as Label).text
	_check(
		variants.size() == 2 and footer.contains(String.humanize_size(variants[1].size_bytes)),
		"The footer should say the .NET download size, got %s" % footer,
	)

	(_part("BackButton") as Button).pressed.emit()
	await _wait_frames(1)
	_check(
		_part("OptionsPage").visible and not _part("TemplatesPage").visible,
		"Back should show the build step",
	)
	_check(
		(_part("Title") as Label).text == "Install Godot 4.7.2 › Build",
		"Back should name the build step",
	)
	_check(_variant_buttons() == buttons, "Back keeps the builds, without loading them again")
	_check(buttons[1].button_pressed, "Back keeps the picked build")
	_check(
		_modal.get_viewport().gui_get_focus_owner() == _part("NextButton"),
		"Back should focus Next",
	)
	(_part("BackButton") as Button).pressed.emit()
	_check(_part("VersionsPage").visible, "Back again shows the versions")


func _test_unavailable_variants() -> void:
	var tabs := _part("Tabs") as TabBar
	tabs.current_tab = 1
	var standard_only := _find_row("4.8", "dev6")
	standard_only.get_install_button().pressed.emit()
	await _wait_frames(2)
	var buttons := _variant_buttons()
	_check(buttons.size() == 2, "Expected both options for 4.8 dev6")
	if buttons.size() == 2:
		_check(not buttons[0].disabled and buttons[0].button_pressed, "Standard is available")
		_check(buttons[1].disabled and not buttons[1].button_pressed, ".NET is not available")
		_check(
			_option_text(buttons[1]).contains("Not available for Linux x86_64"),
			"Say why .NET is disabled",
		)
	# The fixture's dev6 has no export templates: no step to offer them.
	var install := _part("InstallButton") as Button
	_check(install.visible and not install.disabled, "Standard can be installed right away")
	_check(not _part("NextButton").visible, "No templates step without templates")
	_check(not _part("AlternativeRow").visible, "No other build is offered for an available one")
	(_part("BackButton") as Button).pressed.emit()
	_check(
		standard_only.get_install_button().visible,
		"A build with one of its variants keeps its Install button",
	)
	tabs.current_tab = 0


## Desktop builds, none for this platform: a message instead of two dead options, and
## the nearest newer build offered instead, as Godot only adds platforms over time.
func _test_not_for_platform() -> void:
	var tabs := _part("Tabs") as TabBar
	tabs.current_tab = 1
	# Slow requests, so the search for another build can be seen.
	_assets.delay_frames = 3
	var dev4_loads := _assets.loaded_tags.count("4.8-dev4")
	var dev6_loads := _assets.loaded_tags.count("4.8-dev6")
	_find_row("4.8", "dev5").get_install_button().pressed.emit()
	await _wait_until(func() -> bool: return _part("AlternativeRow").visible)
	_check(_variant_buttons().is_empty(), "No dead options without builds for this platform")
	_check(not _part("VariantsPanel").visible, "No build table without builds")
	_check((_part("NextButton") as Button).disabled, "Nothing to install for 4.8 dev5")
	_check(not _part("InstallButton").visible, "No Install button for 4.8 dev5")
	var status := _part("VariantsStatus") as Label
	_check(
		status.visible and status.text == "Godot 4.8 dev5 has no editor build for Linux x86_64.",
		"Expected the not-for-platform message, got %s" % status.text,
	)
	_check(
		(_part("VariantsIcon") as TextureRect).texture
			== _modal.get_theme_icon("StatusWarning", "EditorIcons"),
		"Expected the warning icon",
	)
	_check(not _part("VariantsRetryButton").visible, "Retry cannot help a missing platform")
	_check((_part("FooterInfo") as Label).text.is_empty(), "Nothing to download, no footer")
	# Looking for another build: a spinner while the newer dev6's files load.
	_check(
		_part("AlternativeIcon").visible and _part("AlternativeLabel").visible,
		"Expected the search spinner",
	)
	_check(
		(_part("AlternativeLabel") as Label).text == "Looking for another build...",
		"Expected the search label, got %s" % (_part("AlternativeLabel") as Label).text,
	)
	_check(not _part("AlternativeButton").visible, "No button while searching")
	_check(_modal.is_processing(), "The search spinner should turn")
	await _wait_until(func() -> bool: return _part("AlternativeButton").visible)
	_check(
		_assets.loaded_tags.count("4.8-dev6") == dev6_loads + 1,
		"Expected one request for the newer dev6",
	)
	_check(
		_assets.loaded_tags.count("4.8-dev4") == dev4_loads,
		"Older builds lack the platform too: not checked",
	)
	_check(
		(_part("AlternativeButton") as Button).text == "Install Godot 4.8 dev6 instead",
		"Expected dev6 offered, got %s" % (_part("AlternativeButton") as Button).text,
	)
	_check(not _part("AlternativeIcon").visible, "No spinner next to the button")
	_check(not _modal.is_processing(), "No spinner after the search")
	_assets.delay_frames = 0

	(_part("BackButton") as Button).pressed.emit()
	var row := _find_row("4.8", "dev5")
	_check(row != null and row.is_unavailable(), "The dev5 row should say Not available")
	if row != null:
		_check(not row.get_install_button().visible, "Not available rows have no Install")
		_check(
			(row.get_node("%UnavailableLabel") as Control).tooltip_text == status.text,
			"The row's tooltip should give the reason",
		)
	_check(
		_modal.get_viewport().gui_get_focus_owner() == _part("SearchEdit"),
		"Back from a build without Install focuses the search field",
	)
	# Rows made again keep what is known.
	tabs.current_tab = 0
	tabs.current_tab = 1
	_check(_find_row("4.8", "dev5").is_unavailable(), "Re-rendered rows keep Not available")
	tabs.current_tab = 0


## No desktop editor for any platform yet, like 4.8 dev7 when it came out: offer the
## nearest older build instead, and check again on request or on the next open.
func _test_no_editor_builds() -> void:
	var tabs := _part("Tabs") as TabBar
	tabs.current_tab = 1
	var dev6_loads := _assets.loaded_tags.count("4.8-dev6")
	_find_row("4.8", "dev7").get_install_button().pressed.emit()
	await _wait_until(func() -> bool: return _part("AlternativeButton").visible)
	_check(_variant_buttons().is_empty(), "No dead options without editor builds")
	_check(not _part("VariantsPanel").visible, "No build table without editor builds")
	_check((_part("NextButton") as Button).disabled, "Nothing to install for 4.8 dev7")
	var status := (_part("VariantsStatus") as Label).text
	_check(
		status == (
			"Godot 4.8 dev7 has no editor downloads yet, for any platform. Check again later."
		),
		"Expected the no-editor-builds message, got %s" % status,
	)
	var check_again := _part("VariantsRetryButton") as Button
	_check(
		check_again.visible and check_again.text == "Check again",
		"Expected Check again: Godot may publish the editors any time",
	)
	var alternative := _part("AlternativeButton") as Button
	_check(
		alternative.text == "Install Godot 4.8 dev6 instead",
		"Expected dev6 offered instead, got %s" % alternative.text,
	)
	_check(
		_assets.loaded_tags.count("4.8-dev6") == dev6_loads,
		"dev6 was checked before: no new request",
	)
	_check(not _part("AlternativeIcon").visible, "No spinner next to the button")
	_check(
		_modal.get_viewport().gui_get_focus_owner() == alternative,
		"The offered build takes the focus from Back",
	)

	# Files without editor builds are not cached: Check again asks GitHub again.
	var dev7_loads := _assets.loaded_tags.count("4.8-dev7")
	check_again.pressed.emit()
	await _wait_until(func() -> bool: return _part("AlternativeButton").visible)
	_check(
		_assets.loaded_tags.count("4.8-dev7") == dev7_loads + 1,
		"Check again should load dev7's files again",
	)
	_check(
		(_part("Title") as Label).text == "Install Godot 4.8 dev7 › Build",
		"Check again stays on dev7's page",
	)
	_check(check_again.visible, "Still nothing: Check again stays")

	alternative.pressed.emit()
	await _wait_frames(2)
	_check(
		(_part("Title") as Label).text == "Install Godot 4.8 dev6 › Build",
		"Expected dev6's build step",
	)
	_check(_variant_buttons().size() == 2, "Expected dev6's builds")
	_check(not (_part("InstallButton") as Button).disabled, "dev6 can be installed")
	_check(not _part("AlternativeRow").visible, "dev6's page offers nothing else")
	_check(not (_part("VariantsStatus") as Control).visible, "No message on dev6's page")

	(_part("BackButton") as Button).pressed.emit()
	var dev7 := _find_row("4.8", "dev7")
	_check(dev7 != null and dev7.is_unavailable(), "The dev7 row should say Not available")
	if dev7 != null:
		# Not "Not available": the build exists, Godot just has not uploaded its editors.
		_check(
			(dev7.get_node("%UnavailableLabel") as Label).text == "Not published yet",
			"The dev7 row should say its downloads are not published yet",
		)
		_check(
			(dev7.get_node("%UnavailableLabel") as Control).tooltip_text == status,
			"The dev7 row's tooltip should give the reason",
		)
	var dev6 := _find_row("4.8", "dev6")
	_check(
		dev6 != null
			and _modal.get_viewport().gui_get_focus_owner() == dev6.get_install_button(),
		"Back from dev6's page focuses the dev6 row",
	)

	# By the next open Godot may have published them: dev7 offers Install again.
	_modal.close()
	_modal.open()
	await _wait_frames(1)
	dev7 = _find_row("4.8", "dev7")
	_check(
		dev7 != null and dev7.get_install_button().visible and not dev7.is_unavailable(),
		"Reopening should forget that dev7 had no editor builds",
	)
	_check(
		_assets.loaded_tags.count("4.8-dev7") == dev7_loads + 1,
		"Forgetting sends no request; Install does",
	)
	_check(
		not _find_row("4.8", "dev5").get_install_button().visible,
		"A build without this platform's editor stays Not available",
	)
	tabs.current_tab = 0


## An offered build that is installed already is named, not offered.
func _test_installed_alternative() -> void:
	# Refresh forgets what is known, so dev7 has an Install button again.
	var menu := (_part("MenuButton") as MenuButton).get_popup()
	menu.id_pressed.emit(RemoteEditorsControl.MenuItem.REFRESH)
	await _wait_frames(1)
	var tabs := _part("Tabs") as TabBar
	tabs.current_tab = 1
	var dev7 := _find_row("4.8", "dev7")
	_check(dev7 != null and not dev7.is_unavailable(), "Refresh forgets Not available")
	var editors: Array[LocalEditors.Item] = [_editor("Godot v4.8 dev6 mono", "/editors/dev6")]
	_modal.set_installed_editors(editors)
	_find_row("4.8", "dev7").get_install_button().pressed.emit()
	await _wait_until(func() -> bool: return _part("AlternativeLabel").visible)
	await _wait_until(func() -> bool: return not _modal.is_processing())
	_check(not _part("AlternativeButton").visible, "No Install button for an installed build")
	_check(
		(_part("AlternativeLabel") as Label).text == "Godot 4.8 dev6 is installed.",
		"Expected the installed note, got %s" % (_part("AlternativeLabel") as Label).text,
	)
	_check(
		(_part("AlternativeIcon") as TextureRect).texture
			== _modal.get_theme_icon("StatusSuccess", "EditorIcons"),
		"Expected the installed icon",
	)
	(_part("BackButton") as Button).pressed.emit()
	for editor in editors:
		editor.free()
	var none: Array[LocalEditors.Item] = []
	_modal.set_installed_editors(none)
	tabs.current_tab = 0


## A check finishing while the list shows updates its row in place.
func _test_live_row_update() -> void:
	var tabs := _part("Tabs") as TabBar
	tabs.current_tab = 1
	var row := _find_row("4.8", "dev3")
	_check(row != null and row.get_install_button().visible, "dev3 is not checked yet")
	if row == null:
		return
	# The keyboard is on the row, like after going Back while a search runs.
	row.get_install_button().grab_focus()
	await _catalog.async_variants(row.get_entry())
	_check(_find_row("4.8", "dev3") == row, "The row should stay, not be made again")
	_check(row.is_unavailable(), "The row should switch to Not available")
	_check(not row.get_install_button().visible, "The row should lose its Install button")
	var dev2 := _find_row("4.8", "dev2")
	_check(
		dev2 != null
			and _modal.get_viewport().gui_get_focus_owner() == dev2.get_install_button(),
		"The focus should move on to the next Install button, dev2's",
	)
	tabs.current_tab = 0


## No files at all: the request failed (or GitHub has no such release).
func _test_failed_release_load() -> void:
	var tabs := _part("Tabs") as TabBar
	tabs.current_tab = 1
	var loads_before := _assets.loaded_tags.count("4.8-dev2")
	_find_row("4.8", "dev2").get_install_button().pressed.emit()
	await _wait_frames(2)
	_check(_variant_buttons().is_empty(), "A failed request lists no builds")
	_check(not _part("VariantsPanel").visible, "No empty build panel after a failed request")
	_check((_part("NextButton") as Button).disabled, "Nothing to install for 4.8 dev2")
	_check(
		(_part("VariantsStatus") as Label).text.begins_with("Could not load"),
		"Expected the load error, got %s" % (_part("VariantsStatus") as Label).text,
	)
	_check(not _part("AlternativeRow").visible, "No other build is offered after an error")
	_check(_part("VariantsRetryButton").is_visible_in_tree(), "Expected Retry after a failure")
	(_part("VariantsRetryButton") as Button).pressed.emit()
	await _wait_frames(2)
	_check(
		_assets.loaded_tags.count("4.8-dev2") == loads_before + 2,
		"Retry should ask for the release files again",
	)
	_check((_part("OptionsPage") as Control).visible, "Retry stays on the build step")
	(_part("BackButton") as Button).pressed.emit()
	var row := _find_row("4.8", "dev2")
	_check(
		row != null and row.get_install_button().visible,
		"A failed load keeps the Install button",
	)
	tabs.current_tab = 0


func _test_install_starts_download() -> void:
	var row := _find_row("4.7.2", "stable")
	row.get_install_button().pressed.emit()
	await _wait_frames(2)
	var variants := await _catalog.async_variants(row.get_entry())
	var buttons := _variant_buttons()
	if buttons.size() != 2:
		_check(false, "Expected two options before installing")
		return
	buttons[1].button_pressed = true
	(_part("NextButton") as Button).pressed.emit()
	await _wait_frames(1)
	var closed_before := _closed_count
	var items_before := _download_items.size()
	(_part("InstallButton") as Button).pressed.emit()
	await _wait_frames(1)
	_check(not _modal.is_open() and not _modal.visible, "Install should close the modal")
	_check(_closed_count == closed_before + 1, "Install should emit closed once")
	_check(_download_items.size() == items_before + 1, "Install should add one download row")
	if _download_items.size() == items_before + 1:
		var item := _download_items[-1]
		var url := str(item.get("_host"))
		_check(url == variants[1].url, "Expected the .NET build's url, got %s" % url)
		var target := (item.get_node("HTTPRequest") as HTTPRequest).download_file
		_check(target.ends_with(variants[1].file_name), "Expected the .NET file, got %s" % target)
		var title := (item.get_node("%TitleLabel") as Label).text
		_check(title == variants[1].file_name, "The download row should name its file, got %s" % title)
		_check(
			not (item.get_node("%InstallButton") as Control).visible,
			"The row's Install button waits for a finished download",
		)
	await _dismiss_downloads()


func _test_escape() -> void:
	_modal.open()
	await _wait_frames(1)
	_check(
		(_part("VersionsPage") as Control).visible,
		"Reopening should start on the versions page",
	)
	_find_row("4.7.2", "stable").get_install_button().pressed.emit()
	await _wait_frames(2)
	(_part("NextButton") as Button).pressed.emit()
	await _wait_frames(1)
	# On the templates tree, which must not keep Esc for itself.
	(_part("ExportTemplates").get_node("%Tree") as Control).grab_focus()
	_press_escape()
	_check(_modal.is_open(), "Esc on the templates step should not close the modal")
	_check((_part("OptionsPage") as Control).visible, "Esc on the templates step goes back")
	_press_escape()
	_check(_modal.is_open(), "Esc on the build step should not close the modal")
	_check((_part("VersionsPage") as Control).visible, "Esc on the build step goes back")

	var closed_before := _closed_count
	_press_escape()
	_check(not _modal.is_open(), "Esc on the versions page should close the modal")
	_check(_closed_count == closed_before + 1, "Esc should emit closed once")
	_press_escape()
	_check(_closed_count == closed_before + 1, "Esc on a closed modal does nothing")

	# Typing in the search field must not keep Esc from closing.
	_modal.open()
	await _wait_frames(1)
	var search := _part("SearchEdit") as LineEdit
	search.grab_focus()
	search.edit()
	_press_escape()
	_check(not _modal.is_open(), "Esc in the search field should close the modal")


func _test_close_controls() -> void:
	_modal.open()
	await _wait_frames(1)
	(_part("CloseButton") as Button).pressed.emit()
	_check(not _modal.is_open(), "The close button should close the modal")

	_modal.open()
	await _wait_frames(1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_part("Dim").gui_input.emit(click)
	_check(_modal.is_open(), "The modal closes when the click ends, not when it starts")
	click = click.duplicate() as InputEventMouseButton
	click.pressed = false
	_part("Dim").gui_input.emit(click)
	_check(not _modal.is_open(), "Clicking the dim layer should close the modal")
	var closed_before := _closed_count
	_modal.close()
	_check(_closed_count == closed_before, "close() on a closed modal emits nothing")


func _test_direct_link() -> void:
	_modal.open()
	await _wait_frames(1)
	var menu := (_part("MenuButton") as MenuButton).get_popup()
	_check(menu.item_count == 4, "Expected Direct link, Open downloads, a separator, Refresh")
	menu.id_pressed.emit(RemoteEditorsControl.MenuItem.DIRECT_LINK)
	await _wait_frames(1)
	var dialogs := _modal.find_children("*", "RemoteEditorDirectLinkControl", false, false)
	_check(dialogs.size() == 1, "Direct link should open the link dialog")
	if dialogs.size() != 1:
		return
	var dialog := dialogs[0] as RemoteEditorDirectLinkControl
	_check(dialog.visible, "The link dialog should show")
	var items_before := _download_items.size()
	dialog.link_confirmed.emit(OFFLINE_URL + "custom.zip")
	_check(not _modal.is_open(), "A direct link download should close the modal")
	_check(_download_items.size() == items_before + 1, "Expected a direct link download row")
	dialog.hide()
	await _dismiss_downloads()


func _test_load_error_and_retry() -> void:
	var flaky := CountingYmlSource.new(VERSIONS_YML)
	flaky.error = "offline"
	var catalog := _fixture_catalog(flaky)
	_modal.use_catalog(catalog)
	_check(flaky.load_count == 0, "use_catalog on a closed modal should wait for open")
	_modal.open()
	await _wait_frames(1)
	_check(flaky.load_count == 1, "Opening should load the new catalog")
	_check(_rows().is_empty(), "A failed load lists nothing")
	_check((_part("RetryButton") as Control).is_visible_in_tree(), "Expected Retry on error")

	flaky.error = ""
	(_part("RetryButton") as Button).pressed.emit()
	await _wait_frames(1)
	_check(flaky.load_count == 2, "Retry should load again")
	_check(not (_part("State") as Control).visible, "Expected the list after a good retry")
	_check_row_names(catalog.entries(EditorCatalog.TAB_OFFICIAL), "after retry")
	_modal.close()

	# A failed load is tried again on the next open.
	flaky.error = "offline"
	_modal.use_catalog(catalog)
	_modal.open()
	await _wait_frames(1)
	_modal.close()
	flaky.error = ""
	_modal.open()
	await _wait_frames(1)
	_check(flaky.load_count == 4, "Reopening after an error should load again")
	_check(not _rows().is_empty(), "Expected rows after reopening")
	_modal.close()
	_modal.use_catalog(_catalog)


func _test_slow_load() -> void:
	var slow := CountingYmlSource.new(VERSIONS_YML)
	slow.delay_frames = 5
	_modal.use_catalog(_fixture_catalog(slow))
	_modal.open()
	await _wait_frames(1)
	_check((_part("State") as Control).visible, "Expected the loading state")
	var state_text := (_part("StateLabel") as Label).text
	_check(state_text == "Loading versions...", "Expected a loading label, got %s" % state_text)
	_check(not (_part("RetryButton") as Control).visible, "No Retry while loading")
	var menu := (_part("MenuButton") as MenuButton).get_popup()
	var refresh_index := menu.get_item_index(RemoteEditorsControl.MenuItem.REFRESH)
	_check(menu.is_item_disabled(refresh_index), "Refresh waits for the running load")
	_modal.close()
	_modal.open()
	await _wait_frames(1)
	_check(slow.load_count == 1, "Reopening during a load should not start another")
	_check(_modal.is_processing(), "The loading spinner should run again after reopening")
	await _wait_frames(6)
	_check(not menu.is_item_disabled(refresh_index), "Refresh is back after the load")
	_check_row_names(_catalog.entries(EditorCatalog.TAB_OFFICIAL), "after a slow load")

	# Swapping the catalog while a load runs drops the old load.
	slow.load_count = 0
	_modal.use_catalog(_fixture_catalog(slow))
	_modal.close()
	var fast := CountingYmlSource.new(VERSIONS_YML)
	_modal.use_catalog(_fixture_catalog(fast))
	_modal.open()
	await _wait_frames(8)
	_check(fast.load_count == 1, "Opening should load the newest catalog")
	_check(not _rows().is_empty(), "Expected the newest catalog's rows")
	_modal.close()
	_modal.use_catalog(_catalog)


func _test_refresh() -> void:
	_modal.open()
	await _wait_frames(1)
	var loads := _yml_src.load_count
	var menu := (_part("MenuButton") as MenuButton).get_popup()
	menu.id_pressed.emit(RemoteEditorsControl.MenuItem.REFRESH)
	await _wait_frames(1)
	_check(_yml_src.load_count == loads + 1, "Refresh should load the catalog again")
	_check_row_names(_catalog.entries(EditorCatalog.TAB_OFFICIAL), "after refresh")
	_modal.close()


## Panels, rows and badges made by the modal and the downloads area round their corners
## like the Hub's buttons, in the Modern and the Classic style.
func _test_rounded_corners() -> void:
	var previous_theme := _frame.theme
	var style_key := "interface/theme/style"
	# Modern is the default.
	var previous_style := Config.editor_settings_proxy_get(style_key, "Modern") as String
	for style: String in ["Modern", "Classic"]:
		Config.editor_settings_proxy_set(style_key, style)
		_frame.theme = THEME_SOURCE.create_custom_theme(null)
		await _wait_frames(1)
		await _check_corners(style)
	Config.editor_settings_proxy_set(style_key, previous_style)
	# Settings saved meanwhile (any setting saves them all) would keep the test's style
	# for the next tests run in the same user folder.
	Config.save()
	_frame.theme = previous_theme
	await _wait_frames(1)


func _check_corners(what: String) -> void:
	var radius := ThemeCorners.radius(_modal)
	var button := _modal.get_theme_stylebox("normal", "Button") as StyleBoxFlat
	_check(
		radius > 0 and radius == button.corner_radius_top_left,
		"%s: the radius should be the buttons', got %d" % [what, radius],
	)
	_modal.open()
	await _wait_frames(1)
	var panel := _part("Panel").get_theme_stylebox("panel") as StyleBoxFlat
	_check(_is_rounded(panel, radius), "%s: the modal's panel should be rounded" % what)
	_check(panel.shadow_size > 0, "%s: the modal's panel should keep its shadow" % what)
	var list := _part("ListPanel").get_theme_stylebox("panel") as StyleBoxFlat
	_check(
		list.corner_radius_top_left == 0
			and list.corner_radius_top_right == radius
			and list.corner_radius_bottom_right == radius
			and list.corner_radius_bottom_left == radius,
		"%s: the list should be rounded but where the first tab meets it" % what,
	)
	var row := _find_row("4.7.2", "stable")
	var badge := (row.get_node("%Badge") as Control).get_theme_stylebox("panel") as StyleBoxFlat
	_check(_is_rounded(badge, radius), "%s: the badge should be rounded" % what)
	_check(
		_is_rounded(row.get("_hover_style") as StyleBoxFlat, radius),
		"%s: the row's hover should be rounded" % what,
	)
	row.get_install_button().pressed.emit()
	await _wait_frames(2)
	_check(
		_is_rounded(_part("VariantsPanel").get_theme_stylebox("panel") as StyleBoxFlat, radius),
		"%s: the build table should be rounded" % what,
	)
	(_part("NextButton") as Button).pressed.emit()
	await _wait_frames(1)
	var tree := _part("ExportTemplates").get_node("%Tree") as Tree
	_check(
		_is_rounded(tree.get_theme_stylebox("panel") as StyleBoxFlat, radius),
		"%s: the templates tree should be rounded" % what,
	)
	_modal.close()

	var area := DOWNLOADS_AREA_SCENE.instantiate() as EditorDownloadsArea
	_frame.add_child(area)
	var download := DOWNLOAD_SCENE.instantiate() as AssetDownload
	area.add_download_item(download)
	await _wait_frames(1)
	_check(
		_is_rounded(download.get_theme_stylebox("panel") as StyleBoxFlat, radius),
		"%s: download rows should be rounded" % what,
	)
	var progress := download.get_node("%ProgressBar") as ProgressBar
	for style_name: String in ["background", "fill"]:
		# The Classic style draws progress bars with textures: they keep their look.
		var flat := progress.get_theme_stylebox(style_name) as StyleBoxFlat
		_check(
			_is_rounded(flat, radius) if flat != null else what == "Classic",
			"%s: the download progress %s should be rounded" % [what, style_name],
		)
	area.queue_free()
	await _wait_frames(1)


func _is_rounded(style: StyleBoxFlat, radius: int) -> bool:
	return (
		style != null
		and style.corner_radius_top_left == radius
		and style.corner_radius_top_right == radius
		and style.corner_radius_bottom_right == radius
		and style.corner_radius_bottom_left == radius
	)


## Clicks the .NET row away from its radio button, like a user picking the row.
func _test_row_click_selects(buttons: Array[CheckBox]) -> void:
	# On the file line: labels and containers pass the click on to the row.
	var labels := buttons[1].get_parent().find_children("*", "Label", true, false)
	var point := (labels[-1] as Control).get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = point
		click.global_position = point
		_modal.get_viewport().push_input(click)
	await _wait_frames(1)
	_check(buttons[1].button_pressed, "Clicking a build row should pick it")
	_check(not buttons[0].button_pressed, "Picking a row should drop the other build")


func _fixture_catalog(
	yml_src: RemoteEditorsTreeDataSourceGithub.YmlSource,
	assets := OfflineAssetSource.new(),
) -> EditorCatalog:
	var catalog := EditorCatalog.new(
		RemoteEditorsTreeDataSourceGithub.GithubVersionSourceParseYml.new(yml_src, assets),
		assets,
	)
	# The same builds and messages on every OS the tests run on.
	catalog.use_platform("linux", "x86_64")
	return catalog


## A unique-named node of the modal scene.
func _part(unique_name: String) -> Control:
	return _modal.get_node("%" + unique_name) as Control


func _search(text: String) -> void:
	var search := _part("SearchEdit") as LineEdit
	search.text = text
	search.text_changed.emit(text)


## Frees the started downloads before their failure dialogs take the keyboard.
func _dismiss_downloads() -> void:
	for item in _download_items:
		if is_instance_valid(item):
			item.queue_free()
	await _wait_frames(1)


func _press_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	_modal.get_viewport().push_input(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	_modal.get_viewport().push_input(release)


func _rows() -> Array[EditorCatalogRow]:
	var result: Array[EditorCatalogRow] = []
	for child in _part("Rows").get_children():
		result.append(child as EditorCatalogRow)
	return result


func _find_entry(version: String, release: String) -> EditorCatalog.CatalogEntry:
	for entry in _catalog.entries(EditorCatalog.TAB_ARCHIVE):
		if entry.version == version and entry.release == release:
			return entry
	return null


func _find_row(version: String, release: String) -> EditorCatalogRow:
	for row in _rows():
		if row.get_entry().version == version and row.get_entry().release == release:
			return row
	return null


func _row_badge(row: EditorCatalogRow) -> String:
	if not (row.get_node("%Badge") as Control).visible:
		return ""
	return (row.get_node("%BadgeLabel") as Label).text


func _variant_buttons() -> Array[CheckBox]:
	var result: Array[CheckBox] = []
	for node in _part("Variants").find_children("*", "CheckBox", true, false):
		result.append(node as CheckBox)
	return result


## Text of the labels that belong to an option's radio button.
func _option_text(button: CheckBox) -> String:
	var texts := PackedStringArray()
	for node in button.get_parent().find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	return "\n".join(texts)


func _entry(display_name: String, date: String, notes_url: String) -> EditorCatalog.CatalogEntry:
	var entry := EditorCatalog.CatalogEntry.new()
	entry.display_name = display_name
	entry.channel = EditorCatalog.CHANNEL_STABLE
	entry.release_date = date
	entry.release_notes_url = notes_url
	return entry


func _editor(editor_name: String, path: String) -> LocalEditors.Item:
	var cfg := ConfigFile.new()
	cfg.set_value(path, "name", editor_name)
	return LocalEditors.Item.new(ConfigFileSection.new(path, IConfigFileLike.of_config(cfg)))


func _check_row_names(entries: Array[EditorCatalog.CatalogEntry], what: String) -> void:
	var expected := PackedStringArray()
	for entry in entries:
		expected.append(entry.display_name)
	var got := PackedStringArray()
	for row in _rows():
		got.append((row.get_node("%NameLabel") as Label).text)
	_check(
		not expected.is_empty() and got == expected,
		"Wrong %s rows:\n  got      %s\n  expected %s" % [what, got, expected],
	)


func _wait_frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().process_frame


## Waits until [param condition] returns true, for at most [param max_frames].
func _wait_until(condition: Callable, max_frames := 30) -> void:
	for _frame: int in max_frames:
		if condition.call():
			return
		await get_tree().process_frame
	_check(false, "Timed out waiting for a condition")


func _check(condition: bool, message: String) -> void:
	if condition: return
	_failures += 1
	push_error(message)


## Reads a versions.yml fixture, counting loads and reporting an optional error.
class CountingYmlSource extends RemoteEditorsTreeDataSourceGithub.YmlSource:
	var load_count := 0
	## When set, the load fails with this error and no text.
	var error := ""
	## Frames to wait before answering, like a slow network.
	var delay_frames := 0
	var _path: String

	func _init(path: String) -> void:
		_path = path

	func async_load(errors: Array[String] = []) -> String:
		load_count += 1
		for _frame: int in delay_frames:
			await (Engine.get_main_loop() as SceneTree).process_frame
		if not error.is_empty():
			errors.append(error)
			return ""
		return FileAccess.get_file_as_string(_path)


## Serves the 4.7.2 release fixture for 4.7.2-stable, its Standard builds without
## export templates for 4.8-dev6, its files for other platforms than Linux x86_64 for
## 4.8-dev5 and dev3, its files that are no desktop editor for 4.8-dev7 and nothing
## else, with download urls that stay offline. Records every requested tag.
class OfflineAssetSource extends RemoteEditorsTreeDataSourceGithub.GithubAssetSource:
	var loaded_tags: Array[String] = []
	## Frames to wait before answering, like a slow network.
	var delay_frames := 0

	func async_load(
		version: String, release: String
	) -> Array[RemoteEditorsTreeDataSourceGithub.GodotAsset]:
		var tag := "%s-%s" % [version, release]
		loaded_tags.append(tag)
		for _frame: int in delay_frames:
			await (Engine.get_main_loop() as SceneTree).process_frame
		var result: Array[RemoteEditorsTreeDataSourceGithub.GodotAsset] = []
		if tag not in ["4.7.2-stable", "4.8-dev7", "4.8-dev6", "4.8-dev5", "4.8-dev3"]:
			return result
		var suffixes := RemoteEditorsTreeDataSourceGithub.platform_suffixes("linux", "x86_64")
		var json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RELEASE_JSON))
		for asset: Dictionary in json.get("assets", []):
			var asset_name := str(asset.get("name", ""))
			if tag == "4.8-dev6" and (
				asset_name.contains("_mono_") or asset_name.ends_with(".tpz")
			):
				continue
			if tag in ["4.8-dev5", "4.8-dev3"] and suffixes.any(
				func(suffix: String) -> bool: return asset_name.ends_with(suffix)
			):
				continue
			if (
				tag == "4.8-dev7"
				and RemoteEditorsTreeDataSourceGithub.is_desktop_editor_asset(asset_name)
			):
				continue
			var offline := asset.duplicate()
			offline["browser_download_url"] = OFFLINE_URL + asset_name
			result.append(RemoteEditorsTreeDataSourceGithub.GodotAsset.new(offline))
		return result
