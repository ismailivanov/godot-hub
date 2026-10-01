extends Node


const THEME_SOURCE := preload("res://theme/theme.gd")
const LOCAL_EDITORS_SCENE := preload(
	"res://src/components/editors/local/local_editors.tscn"
)
const ASSET_DOWNLOAD_SCENE := preload(
	"res://src/components/asset_download/asset_download.tscn"
)
const EDITORS_CONFIG_PATH := "user://installs_page_test_editors.cfg"

var _failures := 0
var _frame: MarginContainer
var _local: LocalEditorsControl
var _modal: StubInstallEditorModal
var _tabs: TabContainer
var _ctx: LocalRemoteEditorsSwitchContext
var _changed_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _setup()
	_test_header()
	_test_install_editor_entry_points()
	_test_locate_menu()
	await _test_locate_looks_like_a_button()
	await _test_downloads_area()
	await _test_row_hover_under_overlay()
	_test_context_navigation()
	_test_context_editor_download_request()
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Installs page tests passed.")
	get_tree().quit()


func _setup() -> void:
	var root := get_tree().root
	# Popups become embedded subwindows, which headless runs can show.
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 800)

	_frame = MarginContainer.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.theme = THEME_SOURCE.create_custom_theme(null)
	add_child(_frame)

	var stack := MarginContainer.new()
	_frame.add_child(stack)
	_tabs = TabContainer.new()
	_tabs.tabs_visible = false
	stack.add_child(_tabs)
	var projects_page := Control.new()
	projects_page.name = "Local Projects"
	_tabs.add_child(projects_page)
	_local = LOCAL_EDITORS_SCENE.instantiate() as LocalEditorsControl
	_tabs.add_child(_local)
	_modal = StubInstallEditorModal.new()
	stack.add_child(_modal)

	# The same wiring as GuiMain.
	_ctx = LocalRemoteEditorsSwitchContext.new(_local, _modal, _tabs)
	_ctx.changed.connect(func() -> void: _changed_count += 1)
	_local.editor_download_pressed.connect(_ctx.go_to_remote)
	_local.init(LocalEditors.List.new(EDITORS_CONFIG_PATH))
	await _wait_frames(2)


func _test_header() -> void:
	var title := _local.get_node("%Title") as Label
	_check(title.text == tr("Installs"), "Expected the Installs title")
	_check(
		title.theme_type_variation == &"HeaderMedium",
		"Expected the title to use HeaderMedium",
	)
	_check(
		title.get_theme_stylebox("normal") is StyleBoxEmpty,
		"The title should line up with the list, without the Label margin",
	)
	var search := _local.get_node("%EditorsList").get_node("%SearchBox") as LineEdit
	_check(search.placeholder_text == tr("Filter installs"), "Wrong Installs search placeholder")
	_check(
		_local.find_child("LocalRemoteProjectsSwitch", true, false) == null,
		"Expected the Local/Remote switch to be gone from the Installs page",
	)
	var install_button := _local.get_node("%InstallEditorButton") as Button
	_check(install_button.icon != null, "Expected an icon on Install Editor")
	var locate_menu := (_local.get_node("%LocateButton") as MenuButton).get_popup()
	_check(locate_menu.item_count == 2, "Expected Import and Scan in the Locate menu")


func _test_install_editor_entry_points() -> void:
	var install_button := _local.get_node("%InstallEditorButton") as Button
	_tabs.current_tab = 0
	install_button.pressed.emit()
	_check(_modal.is_open(), "Install Editor should open the modal")
	_check(
		_tabs.get_current_tab_control() == _local,
		"Opening the modal should show the Installs page under it",
	)
	_modal.close()

	var editors_list := _local.get_node("%EditorsList") as EditorsVBoxList
	editors_list.install_editor_requested.emit()
	_check(_modal.is_open(), "The empty state Install Editor should open the modal")
	_modal.close()


func _test_locate_menu() -> void:
	var locate_menu := (_local.get_node("%LocateButton") as MenuButton).get_popup()
	var import_dialog := _local.get_node("%EditorImport") as Window
	var scan_dialog := _local.get_node("%ScanDialog") as Window

	locate_menu.id_pressed.emit(LocalEditorsControl.LocateMenuItem.IMPORT)
	_check(import_dialog.visible, "Locate > Import should open the import dialog")
	import_dialog.hide()

	locate_menu.id_pressed.emit(LocalEditorsControl.LocateMenuItem.SCAN)
	_check(scan_dialog.visible, "Locate > Scan should open the scan dialog")
	scan_dialog.hide()


## Locate is drawn like the Install Editor button next to it in both styles, though the
## Classic style draws menu buttons flat.
func _test_locate_looks_like_a_button() -> void:
	var locate := _local.get_node("%LocateButton") as MenuButton
	var style_key := "interface/theme/style"
	var previous_style := Config.editor_settings_proxy_get(style_key, "Modern") as String
	var previous_theme := _frame.theme
	for style: String in ["Classic", "Modern"]:
		Config.editor_settings_proxy_set(style_key, style)
		_frame.theme = THEME_SOURCE.create_custom_theme(null)
		await _wait_frames(1)
		for state: String in ["normal", "hover", "pressed"]:
			_check(
				locate.get_theme_stylebox(state) == _local.get_theme_stylebox(state, "Button"),
				"%s: Locate should take the button's %s style" % [style, state],
			)
	Config.editor_settings_proxy_set(style_key, previous_style)
	# Settings saved meanwhile (any setting saves them all) would keep the test's style
	# for the next tests run in the same user folder.
	Config.save()
	_frame.theme = previous_theme
	await _wait_frames(1)


func _test_downloads_area() -> void:
	var downloads := _local.get_node("%EditorDownloads") as EditorDownloadsArea
	var editors_list := _local.get_node("%EditorsList") as Control
	_check(
		downloads.get_parent() == editors_list and downloads.get_index() == 1,
		"Expected the downloads area between the list toolbar and the rows",
	)
	_check(not downloads.visible, "The downloads area should start hidden")

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 40)
	_local.add_download_item(row)
	await _wait_frames(2)
	_check(row.get_parent() == downloads, "Download rows should go to the downloads area")
	_check(downloads.visible, "The downloads area should show while it has rows")
	_check(
		is_equal_approx(row.size.x, downloads.size.x),
		"Download rows should take the full width",
	)

	var actions := editors_list.get("_empty_state_actions") as Control
	_check(not actions.visible, "The empty state hides its buttons while an editor downloads")

	row.queue_free()
	await _wait_frames(2)
	_check(not downloads.visible, "The downloads area should hide when emptied")
	_check(actions.visible, "The empty state buttons come back after the download")

	# Download cards become list rows: framed like the list, bold title, thin bar.
	var card := ASSET_DOWNLOAD_SCENE.instantiate() as AssetDownload
	_local.add_download_item(card)
	await _wait_frames(2)
	_check(card.custom_minimum_size == Vector2.ZERO, "A download row is as tall as its content")
	var frame := card.get_theme_stylebox("panel") as StyleBoxFlat
	var list := card.get_theme_stylebox("search_panel", "ProjectManager") as StyleBoxFlat
	_check(
		frame != null
			and list != null
			and frame.bg_color == list.bg_color
			and frame.corner_radius_bottom_right == ThemeCorners.radius(card),
		"A download row should be framed like the list, with the Hub's rounded corners",
	)
	_check(
		(card.get_node("%TitleLabel") as Label).theme_type_variation == &"HeaderSmall",
		"A download row title should be bold like editor names",
	)
	var bar := card.get_node("%ProgressBar") as ProgressBar
	_check(not bar.show_percentage, "The thin progress bar leaves the percentage to the status")
	_check(
		is_equal_approx(bar.size.y, ThemeCorners.THIN_PROGRESS_HEIGHT * Config.EDSCALE),
		"Expected a thin progress bar, got %s" % bar.size.y,
	)
	card.queue_free()
	await _wait_frames(2)


func _test_context_navigation() -> void:
	_tabs.current_tab = 0
	_changed_count = 0
	_ctx.go_to_remote()
	_check(_modal.is_open(), "go_to_remote should open the modal")
	_check(
		_tabs.get_current_tab_control() == _local,
		"go_to_remote should select the Installs page",
	)
	_check(_ctx.remote_is_selected(), "remote_is_selected should follow the modal")
	_check(not _ctx.local_is_selected(), "The Installs page is covered by the modal")
	_check(_changed_count >= 2, "Expected changed for the page switch and the modal opening")

	_changed_count = 0
	_ctx.go_to_local()
	_check(not _modal.is_open(), "go_to_local should close the modal")
	_check(_ctx.local_is_selected(), "go_to_local should leave the Installs page shown")
	_check(_changed_count >= 1, "Expected changed when the modal closes")

	_tabs.current_tab = 0
	_ctx.go_to_local()
	_check(
		_tabs.get_current_tab_control() == _local,
		"go_to_local should select the Installs page",
	)


func _test_context_editor_download_request() -> void:
	var requests: Array[Array] = []
	_ctx.editor_download_requested.connect(
		func(version_hint: String, require_mono: bool, _on_installed: Callable) -> void:
			requests.append([version_hint, require_mono])
	)
	_tabs.current_tab = 0
	_modal.open()
	_ctx.request_editor_download("4.7-stable", true, Callable())
	_check(not _modal.is_open(), "A project download should not leave the modal open")
	_check(
		_tabs.get_current_tab_control() == _local,
		"A project download should show the Installs page",
	)
	_check(
		requests.size() == 1 and requests[0] == ["4.7-stable", true],
		"Expected the download request to be forwarded once",
	)


## List rows look hovered only with the pointer on them, not on the Install Editor
## modal over them.
func _test_row_hover_under_overlay() -> void:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(layer)
	var row := HBoxListItem.new()
	row.position = Vector2(20, 20)
	row.size = Vector2(400, 60)
	layer.add_child(row)
	var cover := ColorRect.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.color = Color(0, 0, 0, 0.5)
	await _wait_frames(1)

	await _move_mouse(Vector2(100, 40))
	_check(row.get("_is_hovering") as bool, "A row under the pointer looks hovered")
	layer.add_child(cover)
	await _move_mouse(Vector2(110, 40))
	_check(not (row.get("_is_hovering") as bool), "A row under a modal does not look hovered")
	layer.remove_child(cover)
	await _move_mouse(Vector2(120, 40))
	_check(row.get("_is_hovering") as bool, "The row looks hovered again once uncovered")
	await _move_mouse(Vector2(600, 400))
	_check(not (row.get("_is_hovering") as bool), "A row the pointer left does not look hovered")
	cover.free()
	layer.queue_free()
	await _wait_frames(1)


func _move_mouse(to: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	get_viewport().push_input(motion)
	await _wait_frames(2)


func _wait_frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if condition: return
	_failures += 1
	push_error(message)


## Stands in for RemoteEditorsControl's modal API.
class StubInstallEditorModal extends Control:
	signal closed

	var _open := false

	func _init() -> void:
		visible = false

	func open() -> void:
		_open = true
		show()

	func close() -> void:
		if not _open:
			return
		_open = false
		hide()
		closed.emit()

	func is_open() -> bool:
		return _open
