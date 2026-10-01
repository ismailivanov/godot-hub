class_name RemoteEditorsControl
extends Control
## The Install Editor modal: pick a Godot build, then download and install it.
##
## An in-app overlay (a dim layer and a centered panel) above the Installs page, not a
## window, in steps: the versions of an [EditorCatalog] in tabs; the Standard or .NET
## build for this platform, or why there is none and another build instead; then,
## optionally, export templates, which [ExportTemplatesJobs] installs once the editor
## is. [method open_manage_templates] shows the templates step alone, to add or remove
## the templates of an installed editor. Download rows go where [method init] says;
## finished downloads are extracted and installed from here.


## Emitted when installed.
signal installed(name: String, abs_path: String)
## Emitted when recommended stable download busy.
signal recommended_stable_download_busy(busy: bool)
## Emitted when the modal closes.
signal closed

## Items of the header's menu.
enum MenuItem {
	DIRECT_LINK,
	OPEN_DOWNLOADS,
	REFRESH,
}

## The page the modal shows.
enum Step {
	## The version list.
	VERSIONS,
	## The Standard or .NET build of a version.
	BUILD,
	## Export templates to install with the editor.
	TEMPLATES,
	## The export templates of an installed editor, to add or remove.
	MANAGE,
}

## What the version list area shows.
enum ListState {
	LOADING,
	LIST,
	EMPTY,
	ERROR,
}

## What the build step shows about the builds of its release.
enum VariantsState {
	LOADING,
	READY,
	## The release has no desktop editor yet, for any platform.
	NO_EDITOR_BUILDS,
	## The release has desktop editors, none for this platform.
	NOT_FOR_PLATFORM,
	ERROR,
}

## What the build step shows under a release without builds for this platform.
enum AlternativeState {
	HIDDEN,
	## Looking for another build that can be installed.
	SEARCHING,
	## An Install button for the build found.
	OFFERED,
	## The build found is installed already.
	INSTALLED,
}

## What the manage page shows instead of the templates tree, or above it.
enum ManageState {
	## The tree.
	READY,
	LOADING,
	## The editor is no official Godot release, so its templates are unknown.
	NOT_OFFICIAL,
	## Its release has no export templates archive for its build.
	NO_TEMPLATES,
	ERROR,
}

## Panel size before EDSCALE when the window has room for it.
const PANEL_MAX_SIZE := Vector2(960, 640)
## Share of the overlay the panel may take in smaller windows.
const PANEL_MAX_SHARE := Vector2(0.92, 0.88)
## Padding before EDSCALE of the build rows and their header.
const VARIANT_ROW_PADDING := Vector2(8, 6)
## Width before EDSCALE of the footer buttons.
const FOOTER_BUTTON_WIDTH := 96
## Uuid constant.
const uuid = preload("res://addons/uuid.gd")
## Read permissions of owner, group and others: shifted right by two, the execute ones.
const READ_PERMISSIONS := (
	FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_READ_OTHER
)

## Packed scene for editor download scene.
@export var _editor_download_scene: PackedScene
## Packed scene for editor install scene.
@export var _editor_install_scene: PackedScene
## Packed scene for remote editor direct link scene.
@export var _remote_editor_direct_link_scene: PackedScene
## Packed scene for one row of the version list.
@export var _catalog_row_scene: PackedScene

var _editor_downloads: DownloadRows
var _stable_download_busy := false
var _stable_download_generation := 0
var _open := false
var _step := Step.VERSIONS
## Loaded lazily on the first open, see [method use_catalog].
var _catalog: EditorCatalog
var _catalog_loaded := false
var _loading := false
var _load_generation := 0
var _list_state := ListState.LOADING
var _installed_editors: Array[LocalEditors.Item] = []
## The build shown on the build step.
var _options_entry: EditorCatalog.CatalogEntry
var _variants: Array[EditorCatalog.CatalogVariant] = []
var _variant_buttons: Array[CheckBox] = []
var _variants_generation := 0
var _variants_state := VariantsState.LOADING
var _alternative_state := AlternativeState.HIDDEN
## The build the build step offers instead of [member _options_entry].
var _alternative_entry: EditorCatalog.CatalogEntry
var _spinner_time := 0.0
## Focus behavior of the controls under the modal, restored when it closes.
var _covered_focus: Dictionary[Control, Control.FocusBehaviorRecursive] = {}
## Installs and removes export templates, see [method set_templates_jobs].
var _templates_jobs: ExportTemplatesJobs
## The installed editor whose templates the manage page shows.
var _manage_editor: ManagedEditor
## The build of [member _manage_editor] whose templates the manage page shows.
var _manage_variant: EditorCatalog.CatalogVariant
var _manage_state := ManageState.LOADING
var _manage_generation := 0

@onready var _dim: ColorRect = %Dim
@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %Title
@onready var _menu_button: MenuButton = %MenuButton
@onready var _close_button: Button = %CloseButton
@onready var _versions_page: Control = %VersionsPage
@onready var _tabs: TabBar = %Tabs
@onready var _search_edit: LineEdit = %SearchEdit
@onready var _list_panel: PanelContainer = %ListPanel
@onready var _scroll: ScrollContainer = %Scroll
@onready var _rows: VBoxContainer = %Rows
@onready var _state: Control = %State
@onready var _state_icon: TextureRect = %StateIcon
@onready var _state_label: Label = %StateLabel
@onready var _retry_button: Button = %RetryButton
@onready var _options_page: Control = %OptionsPage
@onready var _options_date: Label = %OptionsDate
@onready var _options_release_notes: LinkButton = %OptionsReleaseNotes
@onready var _variants_panel: PanelContainer = %VariantsPanel
@onready var _variants_header: PanelContainer = %VariantsHeader
@onready var _build_header: Label = %BuildHeader
@onready var _size_header: Label = %SizeHeader
@onready var _variants_box: VBoxContainer = %Variants
@onready var _variants_state_box: HBoxContainer = %VariantsState
@onready var _variants_icon: TextureRect = %VariantsIcon
@onready var _variants_status: Label = %VariantsStatus
@onready var _variants_retry_button: Button = %VariantsRetryButton
@onready var _alternative_row: MarginContainer = %AlternativeRow
@onready var _alternative_icon: TextureRect = %AlternativeIcon
@onready var _alternative_label: Label = %AlternativeLabel
@onready var _alternative_button: Button = %AlternativeButton
@onready var _templates_page: Control = %TemplatesPage
@onready var _manage_state_box: HBoxContainer = %ManageState
@onready var _manage_icon: TextureRect = %ManageIcon
@onready var _manage_status: Label = %ManageStatus
@onready var _manage_retry_button: Button = %ManageRetryButton
@onready var _templates: ExportTemplatesPicker = %ExportTemplates
@onready var _footer_separator: HSeparator = %FooterSeparator
@onready var _footer: HBoxContainer = %Footer
@onready var _footer_info: Label = %FooterInfo
@onready var _back_button: Button = %BackButton
@onready var _next_button: Button = %NextButton
@onready var _install_button: Button = %InstallButton
@onready var _apply_button: Button = %ApplyButton


func _ready() -> void:
	set_process(false)
	set_process_unhandled_input(false)

	# Without the Label margin the title lines up with the tabs and the list.
	_title.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	# Icon-only buttons: name them for tooltips and screen readers.
	_close_button.tooltip_text = tr("Close")
	_close_button.accessibility_name = _close_button.tooltip_text
	_close_button.pressed.connect(close)
	_menu_button.tooltip_text = tr("More options")
	_menu_button.accessibility_name = _menu_button.tooltip_text
	var menu := _menu_button.get_popup()
	menu.add_item(tr("Direct link..."), MenuItem.DIRECT_LINK)
	menu.add_item(tr("Open downloads folder"), MenuItem.OPEN_DOWNLOADS)
	menu.add_separator()
	menu.add_item(tr("Refresh"), MenuItem.REFRESH)
	menu.id_pressed.connect(_on_menu_id_pressed)
	_dim.gui_input.connect(_on_dim_gui_input)

	_tabs.clip_tabs = false
	_tabs.add_tab(tr("Official releases"))
	_tabs.set_tab_metadata(0, EditorCatalog.TAB_OFFICIAL)
	_tabs.add_tab(tr("Pre-releases"))
	_tabs.set_tab_metadata(1, EditorCatalog.TAB_PRERELEASE)
	_tabs.add_tab(tr("Archive"))
	_tabs.set_tab_metadata(2, EditorCatalog.TAB_ARCHIVE)
	_tabs.tab_changed.connect(func(_tab: int) -> void: _render_rows())
	_search_edit.placeholder_text = tr("Search versions")
	_search_edit.custom_minimum_size.x = 220 * Config.EDSCALE
	_search_edit.text_changed.connect(func(_text: String) -> void: _render_rows())
	# Esc closes even while typing; the field would otherwise take it.
	_search_edit.gui_input.connect(func(event: InputEvent) -> void:
		if _is_cancel(event):
			_search_edit.accept_event()
			_cancel()
	)
	_state_label.custom_minimum_size.x = 360 * Config.EDSCALE
	_retry_button.text = tr("Retry")
	_retry_button.pressed.connect(_load_catalog)

	_options_release_notes.text = tr("Release notes")
	_options_release_notes.pressed.connect(func() -> void:
		OS.shell_open(_options_entry.release_notes_url)
	)
	_build_header.text = tr("Build")
	_size_header.text = tr("Download size")
	_variants_header.add_theme_stylebox_override("panel", _variant_row_padding())
	# Retry, or Check again for a release without editor builds yet: they are not
	# cached, so both load the release files again.
	_variants_retry_button.pressed.connect(func() -> void: _show_options(_options_entry))
	_alternative_button.pressed.connect(func() -> void: _show_options(_alternative_entry))
	_manage_retry_button.text = tr("Retry")
	_manage_retry_button.pressed.connect(_show_manage_page)
	_templates.selection_changed.connect(_update_footer)

	_back_button.pressed.connect(_cancel)
	_next_button.text = tr("Next")
	_next_button.pressed.connect(_show_templates_step)
	_install_button.text = tr("Install")
	_install_button.pressed.connect(_install_selected_variant)
	_apply_button.text = tr("Apply")
	_apply_button.pressed.connect(_apply_template_changes)
	for button: Button in [_back_button, _next_button, _install_button, _apply_button]:
		button.custom_minimum_size.x = FOOTER_BUTTON_WIDTH * Config.EDSCALE

	resized.connect(_update_panel_size)
	_update_theme()
	# Deferred: theme_changed comes before the cached theme items are dropped.
	theme_changed.connect(_update_theme, CONNECT_DEFERRED)
	_show_versions_page()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		sync_stable_download_buttons_if_idle()


func _process(delta: float) -> void:
	# Only runs while a spinner shows, see _update_spinner().
	_spinner_time += delta
	var frame := int(_spinner_time * 10.0) % 8 + 1
	var texture := get_theme_icon("Progress%d" % frame, "EditorIcons")
	if _list_state == ListState.LOADING:
		_state_icon.texture = texture
	if _variants_state == VariantsState.LOADING:
		_variants_icon.texture = texture
	if _alternative_state == AlternativeState.SEARCHING:
		_alternative_icon.texture = texture
	if _manage_state == ManageState.LOADING:
		_manage_icon.texture = texture


func _unhandled_input(event: InputEvent) -> void:
	if _open and _is_cancel(event):
		get_viewport().set_input_as_handled()
		_cancel()


## Sets where download rows go: [param add_download_item] takes an [AssetDownload].
func init(add_download_item: Callable) -> void:
	_editor_downloads = DownloadRows.new(add_download_item)


## Shows the modal on its versions page. The catalog loads on the first open.
func open() -> void:
	if _open:
		return
	_show_overlay()
	_show_versions_page()
	if _catalog == null:
		_set_catalog(EditorCatalog.default())
	# Releases without editor builds may have them now: their rows offer Install again.
	_catalog.forget_no_editor_builds()
	if _catalog_loaded:
		_render_rows()
	elif _loading:
		# The spinner stopped when the modal closed.
		_update_spinner()
	else:
		_load_catalog()
	_search_edit.grab_focus()
	_search_edit.edit()


## Opens the modal on the export templates of [param editor], an installed editor:
## installed ones checked, to uncheck for removal, and the others to check for
## download, like Unity's Add modules. Apply hands the changes to the
## [ExportTemplatesJobs] given to [method set_templates_jobs].
func open_manage_templates(editor: LocalEditors.Item) -> void:
	if not _open:
		_show_overlay()
	_manage_editor = ManagedEditor.new(editor)
	_show_manage_page()


## Hides the modal and emits [signal closed]. Does nothing when it is not open.
func close() -> void:
	if not _open:
		return
	_open = false
	# A variants fetch or templates search still running has nothing to show.
	_variants_generation += 1
	_manage_generation += 1
	_manage_editor = null
	_templates.clear()
	_update_spinner()
	set_process_unhandled_input(false)
	_restore_covered_focus()
	hide()
	closed.emit()


func is_open() -> bool:
	return _open


## Uses [param catalog] for the version list, e.g. one with offline sources. It
## loads now when the modal is open, else on the next open.
func use_catalog(catalog: EditorCatalog) -> void:
	_set_catalog(catalog)
	_catalog_loaded = false
	# Results of a load still running belong to the old catalog.
	_load_generation += 1
	_loading = false
	if _open:
		_show_versions_page()
		_load_catalog()


## Reads export template archives with [param factory] instead of HTTP, e.g. local
## files in tests: [code](url: String, known_size: int) -> RangeSource[/code].
func set_templates_source_factory(factory: Callable) -> void:
	_templates.set_source_factory(factory)


## Hands the export templates picked on the templates step, and the changes made on
## the manage page, to [param jobs], which shows them on the editors' rows.
func set_templates_jobs(jobs: ExportTemplatesJobs) -> void:
	if _templates_jobs != null and _templates_jobs.job_changed.is_connected(_on_job_changed):
		_templates_jobs.job_changed.disconnect(_on_job_changed)
	_templates_jobs = jobs
	if jobs != null:
		jobs.job_changed.connect(_on_job_changed)


## Sets the local editors used to mark builds as Installed.
func set_installed_editors(editors: Array[LocalEditors.Item]) -> void:
	_installed_editors.assign(editors)
	if _open and _catalog_loaded:
		_render_rows()


## Kept for callers of the old Remote page; the modal reads installs from
## [method set_installed_editors].
func set_has_installed_editors(_has_any: bool) -> void:
	pass


func force_reset_recommended_stable_state() -> void:
	_stable_download_busy = false
	recommended_stable_download_busy.emit(false)


## Re-enable recommended-stable buttons after reopening a tab/window if no download is in flight.
func sync_stable_download_buttons_if_idle() -> void:
	if _stable_download_busy:
		return
	recommended_stable_download_busy.emit(false)


func request_latest_stable_editor_download() -> void:
	if _stable_download_busy:
		return
	_set_stable_download_busy(true)
	_stable_download_generation += 1
	var generation := _stable_download_generation
	var info := await RemoteEditorsTreeDataSourceGithub.async_latest_stable_editor_download_for_this_os()
	if info.is_empty():
		_set_stable_download_busy(false)
		_show_error(tr("Could not find a stable editor download for this platform."))
		return
	# An old download card reports again when dismissed, possibly while a newer stable
	# download owns the flag; only the latest request may clear it.
	var finish_busy := func() -> void:
		if generation == _stable_download_generation:
			_set_stable_download_busy(false)
	download_zip(info["url"] as String, info["file_name"] as String, finish_busy)


func request_editor_download(
	version_hint: String,
	require_mono := false,
	on_installed: Callable = Callable(),
) -> void:
	var info := await RemoteEditorsTreeDataSourceGithub.async_editor_download_for_this_os(
		version_hint, require_mono
	)
	if info.is_empty():
		_show_error(tr(
			"Could not find Godot %s for this platform. Choose another version in Install Editor."
		) % version_hint)
		return
	download_zip(
		info["url"] as String,
		info["file_name"] as String,
		Callable(),
		on_installed,
	)


func _show_error(message: String) -> void:
	var accept_dialog := AcceptDialog.new()
	accept_dialog.visibility_changed.connect(func() -> void:
		if not accept_dialog.visible:
			accept_dialog.queue_free()
	)
	accept_dialog.dialog_text = message
	add_child(accept_dialog)
	accept_dialog.popup_centered()


func _set_stable_download_busy(busy: bool) -> void:
	if _stable_download_busy == busy:
		return
	_stable_download_busy = busy
	recommended_stable_download_busy.emit(busy)


func _update_theme() -> void:
	# The editor's dialog surface, which the list stands out on (popups are darker
	# than the dim layer), floating like a popup, with room for a page of content.
	var panel_style := get_theme_stylebox("panel", "AcceptDialog").duplicate() as StyleBox
	var panel_flat := panel_style as StyleBoxFlat
	var popup_flat := get_theme_stylebox("panel", "PopupPanel") as StyleBoxFlat
	if panel_flat != null:
		if popup_flat != null:
			panel_flat.shadow_color = popup_flat.shadow_color
			panel_flat.shadow_size = popup_flat.shadow_size
		# The theme squares dialogs, which are OS windows in Godot; this panel is drawn
		# in the Hub's window, rounded like its buttons and panels. The shadow follows.
		ThemeCorners.apply(panel_flat, ThemeCorners.radius(self))
	panel_style.content_margin_left = 12 * Config.EDSCALE
	panel_style.content_margin_right = 12 * Config.EDSCALE
	panel_style.content_margin_top = 8 * Config.EDSCALE
	panel_style.content_margin_bottom = 12 * Config.EDSCALE
	_panel.add_theme_stylebox_override("panel", panel_style)

	var list_style := ThemeCorners.rounded(
		get_theme_stylebox("search_panel", "ProjectManager"), self
	)
	_variants_panel.add_theme_stylebox_override("panel", list_style)
	_update_tabs_style(list_style)

	_menu_button.icon = get_theme_icon("GuiTabMenuHl", "EditorIcons")
	_close_button.icon = get_theme_icon("Close", "EditorIcons")
	_set_menu_icon(MenuItem.DIRECT_LINK, "AssetLib")
	_set_menu_icon(MenuItem.OPEN_DOWNLOADS, "Load")
	_set_menu_icon(MenuItem.REFRESH, "Reload")
	_search_edit.right_icon = get_theme_icon("Search", "EditorIcons")
	_retry_button.icon = get_theme_icon("Reload", "EditorIcons")
	_variants_retry_button.icon = get_theme_icon("Reload", "EditorIcons")
	_manage_retry_button.icon = get_theme_icon("Reload", "EditorIcons")
	# Lines up the build offered with the message text, after its icon.
	_alternative_row.add_theme_constant_override(
		"margin_left",
		get_theme_icon("StatusWarning", "EditorIcons").get_width()
			+ _variants_state_box.get_theme_constant("separation")
	)

	var dimmed := get_theme_color("readonly_font_color", "Editor")
	for label: Label in [
		_state_label, _options_date, _variants_status, _build_header, _size_header, _footer_info,
		_alternative_label, _manage_status,
	]:
		label.add_theme_color_override("font_color", dimmed)
	var link_color := get_theme_color("accent_color", "Editor")
	for state_name: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		_options_release_notes.add_theme_color_override(state_name, link_color)
	match _step:
		Step.BUILD:
			_show_variants_state(_variants_state)
			_show_alternative(_alternative_state)
		Step.MANAGE:
			_show_manage_state(_manage_state)
	_update_footer()


## Draws the tabs attached to the list below them, like a TabContainer: the selected
## tab takes the list's color and the others only show their text.
func _update_tabs_style(list_style: StyleBox) -> void:
	var list_flat := list_style as StyleBoxFlat
	var selected := get_theme_stylebox("tab_selected", "TabBar").duplicate() as StyleBox
	var selected_flat := selected as StyleBoxFlat
	if selected_flat != null and list_flat != null:
		selected_flat.bg_color = list_flat.bg_color
	_tabs.add_theme_stylebox_override("tab_selected", selected)
	var unselected := get_theme_stylebox("tab_unselected", "TabBar").duplicate() as StyleBox
	var unselected_flat := unselected as StyleBoxFlat
	if unselected_flat != null:
		unselected_flat.draw_center = false
	_tabs.add_theme_stylebox_override("tab_unselected", unselected)

	var attached := list_style.duplicate() as StyleBox
	var attached_flat := attached as StyleBoxFlat
	if attached_flat != null:
		# The first tab meets the list at this corner.
		if is_layout_rtl():
			attached_flat.corner_radius_top_right = 0
		else:
			attached_flat.corner_radius_top_left = 0
	_list_panel.add_theme_stylebox_override("panel", attached)


func _set_menu_icon(id: MenuItem, icon_name: String) -> void:
	var menu := _menu_button.get_popup()
	menu.set_item_icon(menu.get_item_index(id), get_theme_icon(icon_name, "EditorIcons"))


func _update_panel_size() -> void:
	var max_size := PANEL_MAX_SIZE * Config.EDSCALE
	_panel.custom_minimum_size = Vector2(
		minf(max_size.x, size.x * PANEL_MAX_SHARE.x),
		minf(max_size.y, size.y * PANEL_MAX_SHARE.y),
	)


## Shows the dim layer and the panel, taking the keyboard from the page under them.
func _show_overlay() -> void:
	_open = true
	show()
	set_process_unhandled_input(true)
	_block_covered_focus()
	_update_panel_size()


## Keeps Tab and arrow keys from moving focus to the page under the dim layer,
## where Enter would press buttons nobody can see.
func _block_covered_focus() -> void:
	for sibling in get_parent().get_children():
		var control := sibling as Control
		if control == null or control == self:
			continue
		_covered_focus[control] = control.focus_behavior_recursive
		control.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED


func _restore_covered_focus() -> void:
	for control in _covered_focus:
		if is_instance_valid(control):
			control.focus_behavior_recursive = _covered_focus[control]
	_covered_focus.clear()


func _is_cancel(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_cancel", false, true)


## Esc and Back: one step back, or close from the version list and the manage page.
func _cancel() -> void:
	match _step:
		Step.TEMPLATES:
			_show_build_step()
		Step.BUILD:
			_show_versions_page()
		_:
			close()


func _on_dim_gui_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	# On release, so the click does not go on to the page under the modal.
	if mouse_button and mouse_button.button_index == MOUSE_BUTTON_LEFT and not mouse_button.pressed:
		close()


func _on_menu_id_pressed(id: int) -> void:
	match id:
		MenuItem.DIRECT_LINK:
			_popup_direct_link()
		MenuItem.OPEN_DOWNLOADS:
			OS.shell_show_in_file_manager(
				ProjectSettings.globalize_path(Config.DOWNLOADS_PATH.ret() as String)
			)
		MenuItem.REFRESH:
			_show_versions_page()
			_load_catalog()


func _popup_direct_link() -> void:
	var link_dialog: RemoteEditorDirectLinkControl = _remote_editor_direct_link_scene.instantiate()
	add_child(link_dialog)
	link_dialog.popup_centered()
	link_dialog.link_confirmed.connect(func(link: String) -> void:
		# The download row shows on the Installs page under the modal.
		close()
		download_zip(link, _direct_link_file_name(link))
	)


## The name of the archive [param link] downloads, which tells the editor's version, or
## a placeholder when the link does not end with one.
static func _direct_link_file_name(link: String) -> String:
	var file_name := link.strip_edges().get_slice("?", 0).get_slice("#", 0).get_file()
	file_name = file_name.uri_decode()
	if (
		file_name.ends_with(".zip")
		and file_name.is_valid_filename()
		and not file_name.get_basename().is_empty()
	):
		return file_name
	return "custom_editor.zip"


## Uses [param catalog], following what it learns about builds for the rows.
func _set_catalog(catalog: EditorCatalog) -> void:
	if _catalog != null and _catalog.availability_changed.is_connected(_on_availability_changed):
		_catalog.availability_changed.disconnect(_on_availability_changed)
	_catalog = catalog
	_catalog.availability_changed.connect(_on_availability_changed)


## A build checked on the build step, or while looking for one to offer, may turn out
## to have nothing for this platform: its row says so right away, and passes the focus
## on when it loses a focused Install button.
func _on_availability_changed(entry: EditorCatalog.CatalogEntry) -> void:
	var rows := _rows.get_children()
	for i in rows.size():
		var row := rows[i] as EditorCatalogRow
		if row.get_entry().tag() != entry.tag():
			continue
		var had_focus := row.get_install_button().has_focus()
		row.set_unavailable_reason(_unavailable_text(entry), _unavailable_label(entry))
		if had_focus and not row.get_install_button().visible:
			_focus_install_after(i)


## Focuses the first Install button in the rows after index [param index], or the
## search field when there is none, so the keyboard stays in the list.
func _focus_install_after(index: int) -> void:
	var rows := _rows.get_children()
	for i in range(index + 1, rows.size()):
		var install := (rows[i] as EditorCatalogRow).get_install_button()
		if install.visible:
			install.grab_focus()
			return
	_search_edit.grab_focus()


## Why [param entry] cannot be installed here, or empty when it can or is not checked
## yet. A failed check is not a reason: it may work next time.
func _unavailable_text(entry: EditorCatalog.CatalogEntry) -> String:
	match _catalog.entry_availability(entry):
		EditorCatalog.Availability.NO_EDITOR_BUILDS:
			return tr(
				"%s has no editor downloads yet, for any platform. Check again later."
			) % entry.display_name
		EditorCatalog.Availability.NOT_FOR_PLATFORM:
			return tr("%s has no editor build for %s.") % [
				entry.display_name, _catalog.platform_label(),
			]
	return ""


## The row's short form of [method _unavailable_text]. A build announced before its
## editors were uploaded is not "not available", only not published yet.
func _unavailable_label(entry: EditorCatalog.CatalogEntry) -> String:
	if _catalog.entry_availability(entry) == EditorCatalog.Availability.NO_EDITOR_BUILDS:
		return tr("Not published yet")
	return ""


func _load_catalog() -> void:
	_load_generation += 1
	var generation := _load_generation
	var catalog := _catalog
	_catalog_loaded = false
	_loading = true
	_clear_rows()
	_show_list_state(ListState.LOADING)
	var errors: Array[String] = []
	await catalog.async_load(errors)
	if generation != _load_generation:
		return
	_loading = false
	for error in errors:
		Output.push("Godot versions fetch error: %s" % error)
	# A failed load is tried again on the next open.
	_catalog_loaded = not _catalog_is_empty()
	_render_rows()


func _catalog_is_empty() -> bool:
	return (
		_catalog.entries(EditorCatalog.TAB_ARCHIVE).is_empty()
		and _catalog.entries(EditorCatalog.TAB_PRERELEASE).is_empty()
	)


func _render_rows() -> void:
	# The loading state stays until the load finishes.
	if _catalog == null or _loading:
		return
	_clear_rows()
	if _catalog_is_empty():
		_show_list_state(ListState.ERROR)
		return
	var tab := _tabs.get_tab_metadata(_tabs.current_tab) as int
	var entries := _catalog.entries(tab, _search_edit.text)
	if entries.is_empty():
		_show_list_state(ListState.EMPTY)
		return
	var editors := _live_installed_editors()
	for entry in entries:
		var row := _catalog_row_scene.instantiate() as EditorCatalogRow
		_rows.add_child(row)
		row.init(entry, _catalog.is_installed(entry, editors))
		row.set_unavailable_reason(_unavailable_text(entry), _unavailable_label(entry))
		row.install_requested.connect(_show_options)
	_show_list_state(ListState.LIST)


func _clear_rows() -> void:
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()


## The Installs page frees its editor items when it reloads them.
func _live_installed_editors() -> Array[LocalEditors.Item]:
	var result: Array[LocalEditors.Item] = []
	for editor in _installed_editors:
		if is_instance_valid(editor):
			result.append(editor)
	return result


func _show_list_state(state: ListState) -> void:
	_list_state = state
	_scroll.visible = state == ListState.LIST
	_state.visible = state != ListState.LIST
	_retry_button.visible = state == ListState.ERROR
	_update_spinner()
	var menu := _menu_button.get_popup()
	menu.set_item_disabled(menu.get_item_index(MenuItem.REFRESH), state == ListState.LOADING)
	match state:
		ListState.LOADING:
			_spinner_time = 0.0
			_state_icon.texture = get_theme_icon("Progress1", "EditorIcons")
			_state_label.text = tr("Loading versions...")
		ListState.EMPTY:
			_state_icon.texture = get_theme_icon("Search", "EditorIcons")
			var search := _search_edit.text.strip_edges()
			if search.is_empty():
				_state_label.text = tr("No versions in this tab.")
			else:
				_state_label.text = tr("No versions match \"%s\".") % search
		ListState.ERROR:
			_state_icon.texture = get_theme_icon("StatusError", "EditorIcons")
			_state_label.text = tr(
				"Could not load the list of Godot versions. Check your connection and try again."
			)


## Runs [method _process] only while the modal shows a loading spinner.
func _update_spinner() -> void:
	var list_loading := _step == Step.VERSIONS and _list_state == ListState.LOADING
	var variants_loading := _step == Step.BUILD and (
		_variants_state == VariantsState.LOADING
		or _alternative_state == AlternativeState.SEARCHING
	)
	var manage_loading := _step == Step.MANAGE and _manage_state == ManageState.LOADING
	var spinning := _open and (list_loading or variants_loading or manage_loading)
	if spinning and not is_processing():
		_spinner_time = 0.0
	set_process(spinning)


## Shows the page of [param step] with its footer buttons.
func _set_step(step: Step) -> void:
	_step = step
	_versions_page.visible = step == Step.VERSIONS
	_options_page.visible = step == Step.BUILD
	_templates_page.visible = step == Step.TEMPLATES or step == Step.MANAGE
	if step != Step.MANAGE:
		# The manage page's message, and the tree it hides for it, are that page's
		# alone: the templates step shows the tree.
		_manage_state_box.hide()
		_templates.show()
	# Direct link and Refresh are about the version list.
	_menu_button.visible = step == Step.VERSIONS
	_footer_separator.visible = step != Step.VERSIONS
	_footer.visible = step != Step.VERSIONS
	_update_footer()


func _show_versions_page() -> void:
	var from_build := _step == Step.BUILD
	_variants_generation += 1
	_manage_generation += 1
	_alternative_state = AlternativeState.HIDDEN
	_set_step(Step.VERSIONS)
	_templates.clear()
	_title.text = tr("Install Godot Editor")
	_update_spinner()
	if from_build and _options_entry != null:
		_focus_row_of(_options_entry)


func _focus_row_of(entry: EditorCatalog.CatalogEntry) -> void:
	for row: EditorCatalogRow in _rows.get_children():
		if row.get_entry() == entry and row.get_install_button().visible:
			row.get_install_button().grab_focus()
			return
	# The row has no Install button now, e.g. Not available: keep the keyboard usable.
	_search_edit.grab_focus()


## The title of the install steps: the build and, as a breadcrumb, [param step_name].
func _install_title(step_name: String) -> String:
	return "%s › %s" % [tr("Install %s") % _options_entry.display_name, step_name]


## The build step of [param entry]: loads its builds for this platform.
func _show_options(entry: EditorCatalog.CatalogEntry) -> void:
	_options_entry = entry
	_variants_generation += 1
	var generation := _variants_generation
	# Templates checked for another version do not carry over.
	_templates.clear()
	_set_variants([])
	_set_step(Step.BUILD)
	_title.text = _install_title(tr("Build"))
	_options_date.text = entry.release_date
	_options_date.visible = not entry.release_date.is_empty()
	_options_release_notes.visible = not entry.release_notes_url.is_empty()
	_options_release_notes.tooltip_text = entry.release_notes_url
	_show_variants_state(VariantsState.LOADING)
	_show_alternative(AlternativeState.HIDDEN)
	_back_button.grab_focus()

	var errors: Array[String] = []
	var variants := await _catalog.async_variants(entry, errors)
	if generation != _variants_generation:
		return
	for error in errors:
		Output.push("Godot release files fetch error: %s" % error)
	match _catalog.entry_availability(entry):
		EditorCatalog.Availability.AVAILABLE:
			_set_variants(variants)
			_show_variants_state(VariantsState.READY)
			_primary_button().grab_focus()
		EditorCatalog.Availability.NO_EDITOR_BUILDS:
			# A message, not two options that cannot be picked.
			_show_variants_state(VariantsState.NO_EDITOR_BUILDS)
			_offer_alternative(entry, generation)
		EditorCatalog.Availability.NOT_FOR_PLATFORM:
			_show_variants_state(VariantsState.NOT_FOR_PLATFORM)
			_offer_alternative(entry, generation)
		_:
			_show_variants_state(VariantsState.ERROR)
			_variants_retry_button.grab_focus()


## Back on the build step from the templates step, with the build and the templates
## as they were picked.
func _show_build_step() -> void:
	_set_step(Step.BUILD)
	_title.text = _install_title(tr("Build"))
	_update_spinner()
	_primary_button().grab_focus()


## The templates step: export templates of the picked build to install with it.
func _show_templates_step() -> void:
	var variant := _selected_variant()
	if variant == null or variant.templates_url.is_empty():
		return
	_set_step(Step.TEMPLATES)
	_title.text = _install_title(tr("Export templates (optional)"))
	_templates.show_build(_options_entry, variant)
	_update_footer()
	_install_button.grab_focus()


## Next on the build step, or Install when the picked build has no export templates
## to offer: the step that would show them is left out.
func _primary_button() -> Button:
	return _install_button if _install_button.visible else _next_button


## Looks for another build of [param entry]'s tab to install instead, with a spinner
## under the message while the catalog checks a few, and offers what it finds.
func _offer_alternative(entry: EditorCatalog.CatalogEntry, generation: int) -> void:
	_show_alternative(AlternativeState.SEARCHING)
	var tab := _tabs.get_tab_metadata(_tabs.current_tab) as int
	# Stops loading release files once the build step shows something else or the
	# modal closes.
	var is_wanted := func() -> bool: return generation == _variants_generation
	var found := await _catalog.async_nearest_available(entry, tab, is_wanted)
	if generation != _variants_generation:
		return
	_alternative_entry = found
	if found == null:
		_show_alternative(AlternativeState.HIDDEN)
	elif _catalog.is_installed(found, _live_installed_editors()):
		_show_alternative(AlternativeState.INSTALLED)
	else:
		_show_alternative(AlternativeState.OFFERED)
		# Unless the keyboard moved on while the search ran.
		if get_viewport().gui_get_focus_owner() == _back_button:
			_alternative_button.grab_focus()


## Shows [param state] under the build step's message: a spinner while searching, then
## the build to install instead, or that it is installed.
func _show_alternative(state: AlternativeState) -> void:
	_alternative_state = state
	_alternative_row.visible = state != AlternativeState.HIDDEN
	_alternative_icon.visible = state != AlternativeState.OFFERED
	_alternative_label.visible = state != AlternativeState.OFFERED
	_alternative_button.visible = state == AlternativeState.OFFERED
	match state:
		AlternativeState.SEARCHING:
			_alternative_icon.texture = get_theme_icon("Progress1", "EditorIcons")
			_alternative_label.text = tr("Looking for another build...")
		AlternativeState.OFFERED:
			_alternative_button.text = tr("Install %s instead") % _alternative_entry.display_name
		AlternativeState.INSTALLED:
			_alternative_icon.texture = get_theme_icon("StatusSuccess", "EditorIcons")
			_alternative_label.text = tr("%s is installed.") % _alternative_entry.display_name
	_update_spinner()


## Shows [param state] on the build step: a spinner, the builds, or why there is
## nothing to install, with a Retry when the release files could not be loaded and a
## Check again when the release has no editor builds yet.
func _show_variants_state(state: VariantsState) -> void:
	_variants_state = state
	# An empty panel would still draw as a strip.
	_variants_panel.visible = not _variants.is_empty()
	var has_status := state != VariantsState.READY
	_variants_state_box.visible = has_status
	_variants_status.visible = has_status
	_variants_retry_button.visible = (
		state == VariantsState.ERROR or state == VariantsState.NO_EDITOR_BUILDS
	)
	_variants_retry_button.text = (
		tr("Check again") if state == VariantsState.NO_EDITOR_BUILDS else tr("Retry")
	)
	match state:
		VariantsState.LOADING:
			_variants_icon.texture = get_theme_icon("Progress1", "EditorIcons")
			_variants_status.text = tr("Looking for downloads...")
		VariantsState.NO_EDITOR_BUILDS, VariantsState.NOT_FOR_PLATFORM:
			_variants_icon.texture = get_theme_icon("StatusWarning", "EditorIcons")
			_variants_status.text = _unavailable_text(_options_entry)
		VariantsState.ERROR:
			_variants_icon.texture = get_theme_icon("StatusError", "EditorIcons")
			_variants_status.text = tr(
				"Could not load the downloads of this release. Check your connection and try again."
			)
	_update_footer()
	_update_spinner()


## Builds the radio group of [param variants], selecting the first available one.
func _set_variants(variants: Array[EditorCatalog.CatalogVariant]) -> void:
	for child in _variants_box.get_children():
		_variants_box.remove_child(child)
		child.queue_free()
	_variants = variants
	_variant_buttons.clear()
	var group := ButtonGroup.new()
	group.pressed.connect(func(_button: BaseButton) -> void: _update_footer())
	var selected := false
	for variant in variants:
		var row := _variant_row(variant, group)
		_variants_box.add_child(row)
		_variant_buttons.append(row.button)
		if variant.available and not selected:
			row.button.button_pressed = true
			selected = true


## A full-width row of the build table: the radio button with the build's name, its
## download size in the right column, and what it is for and its file under the name.
func _variant_row(variant: EditorCatalog.CatalogVariant, group: ButtonGroup) -> VariantRow:
	var row := VariantRow.new()
	row.add_theme_stylebox_override("panel", _variant_row_padding())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("v_separation", 0)
	row.add_child(grid)

	row.button = CheckBox.new()
	row.button.button_group = group
	row.button.text = tr(".NET (C#)") if variant.mono else tr("Standard")
	row.button.disabled = not variant.available
	row.button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.button.add_theme_font_override("font", get_theme_font("bold", "EditorFonts"))
	row.button.toggled.connect(func(_pressed: bool) -> void: row.queue_redraw())
	grid.add_child(row.button)

	var size_label := Label.new()
	size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	size_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if variant.available and variant.size_bytes > 0:
		size_label.text = String.humanize_size(variant.size_bytes)
	grid.add_child(size_label)

	# Lines up the details with the option text, after the radio icon.
	var details := MarginContainer.new()
	details.add_theme_constant_override(
		"margin_left",
		get_theme_icon("radio_unchecked", "CheckBox").get_width()
			+ get_theme_constant("h_separation", "CheckBox")
	)
	if not variant.available:
		details.modulate.a = 0.6
	var details_box := VBoxContainer.new()
	details_box.add_theme_constant_override("separation", 0)
	details.add_child(details_box)
	grid.add_child(details)
	# Keeps the size column empty next to the details; clicks go on to the row.
	var empty_cell := Control.new()
	empty_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(empty_cell)

	var description := tr("Adds C# support. Needs the .NET SDK.") if variant.mono else tr(
		"For GDScript and GDExtension projects."
	)
	details_box.add_child(_dimmed_label(description))
	var file_label := _dimmed_label(_variant_file_text(variant))
	file_label.add_theme_font_size_override(
		"font_size",
		get_theme_font_size("main_size", "EditorFonts") - roundi(2 * Config.EDSCALE)
	)
	details_box.add_child(file_label)
	row.tooltip_text = variant.file_name
	return row


func _variant_file_text(variant: EditorCatalog.CatalogVariant) -> String:
	if not variant.available:
		return tr("Not available for %s") % variant.platform_label
	return "%s · %s" % [variant.platform_label, variant.file_name]


## Padding of the build rows and their header, so the columns line up.
func _variant_row_padding() -> StyleBoxEmpty:
	var padding := StyleBoxEmpty.new()
	padding.content_margin_left = VARIANT_ROW_PADDING.x * Config.EDSCALE
	padding.content_margin_right = VARIANT_ROW_PADDING.x * Config.EDSCALE
	padding.content_margin_top = VARIANT_ROW_PADDING.y * Config.EDSCALE
	padding.content_margin_bottom = VARIANT_ROW_PADDING.y * Config.EDSCALE
	return padding


## Shows the footer buttons of the current step: Back and Next (or Install when the
## build has no templates to offer) on the build step, Back and Install on the
## templates step, Cancel and Apply on the manage page.
func _update_footer() -> void:
	var variant := _selected_variant()
	var build_ready := _variants_state == VariantsState.READY and variant != null
	var has_templates := build_ready and not variant.templates_url.is_empty()
	var manage := _step == Step.MANAGE
	_back_button.text = tr("Cancel") if manage else tr("Back")
	_back_button.icon = null if manage else get_theme_icon("Back", "EditorIcons")
	_next_button.visible = _step == Step.BUILD and (has_templates or not build_ready)
	_next_button.disabled = not build_ready
	_install_button.visible = (
		_step == Step.TEMPLATES or (_step == Step.BUILD and build_ready and not has_templates)
	)
	_install_button.disabled = not build_ready
	_apply_button.visible = manage
	_apply_button.disabled = not _can_apply()
	_update_footer_info()


## Says what the footer's button will do: what Install downloads and where it goes,
## like Unity's required space, or what Apply adds and removes.
func _update_footer_info() -> void:
	var text := ""
	match _step:
		Step.BUILD, Step.TEMPLATES:
			text = _install_summary()
		Step.MANAGE:
			text = _manage_summary()
	_footer_info.text = text
	_footer_info.tooltip_text = text


func _install_summary() -> String:
	var variant := _selected_variant()
	if variant == null or _variants_state != VariantsState.READY:
		return ""
	var install_dir := ProjectSettings.globalize_path(Config.VERSIONS_PATH.ret() as String)
	var templates := ""
	if _step == Step.TEMPLATES and _templates.has_selection():
		# The size is known once the archive's directory is read.
		var templates_size := _templates.selected_size()
		if templates_size >= 0:
			templates = tr("%s templates") % String.humanize_size(templates_size)
		else:
			templates = tr("templates")
	if variant.size_bytes > 0 and not templates.is_empty():
		# Templates go to Godot's own folder, not the editors'.
		return tr("Download %s + %s · editor installs to %s") % [
			String.humanize_size(variant.size_bytes), templates, install_dir,
		]
	if variant.size_bytes > 0:
		return tr("Download %s · installs to %s") % [
			String.humanize_size(variant.size_bytes), install_dir,
		]
	return tr("Installs to %s") % install_dir


func _manage_summary() -> String:
	if _manage_state != ManageState.READY:
		return ""
	var parts := PackedStringArray()
	if _templates.has_selection():
		var download_size := _templates.selected_size()
		if download_size >= 0:
			parts.append(tr("+%s to download") % String.humanize_size(download_size))
		else:
			parts.append(tr("Templates to download"))
	if not _templates.pending_changes().remove_files.is_empty():
		parts.append(tr("%s to remove") % String.humanize_size(_templates.removed_size()))
	if parts.is_empty():
		return tr("No changes")
	return ", ".join(parts)


func _dimmed_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", get_theme_color("readonly_font_color", "Editor"))
	return label


func _selected_variant() -> EditorCatalog.CatalogVariant:
	for i in _variant_buttons.size():
		if _variant_buttons[i].button_pressed:
			return _variants[i]
	return null


func _install_selected_variant() -> void:
	var variant := _selected_variant()
	if variant == null:
		return
	# Read before close(), which clears the templates tree.
	var templates: ExportTemplatesPicker.Selection = null
	if _step == Step.TEMPLATES:
		templates = _templates.selection()
	var folder := _templates.get_folder()
	close()
	# The Installs page hands over its downloads area when it initializes.
	while _editor_downloads == null:
		await get_tree().process_frame
	var on_installed := Callable()
	if templates != null:
		# Once the editor is installed, its row in the Installs list shows the templates
		# being installed: there is no separate download row for them.
		on_installed = func(editor_name: String, abs_exec_path: String) -> void:
			_start_templates_job(abs_exec_path, _install_request(editor_name, templates, folder))
	download_zip(variant.url, variant.file_name, Callable(), on_installed)


## The job installing the export templates of [param selection] into the version
## folder [param folder] for the editor [param editor_name].
static func _install_request(
	editor_name: String, selection: ExportTemplatesPicker.Selection, folder: String
) -> ExportTemplatesJobs.Request:
	var request := ExportTemplatesJobs.Request.new()
	request.editor_name = editor_name
	request.archive_url = selection.url
	request.archive_size = selection.archive_size
	request.add_files = selection.files
	request.all_files = selection.all_files
	request.folder = folder
	return request


func _start_templates_job(editor_path: String, request: ExportTemplatesJobs.Request) -> void:
	if _templates_jobs == null:
		Output.push("Export templates of %s not installed: no jobs" % request.editor_name)
		return
	_templates_jobs.start(editor_path, request)


## The manage page of [member _manage_editor]: finds its release and build in the
## catalog (loading it when needed), then shows their templates, or why it cannot.
func _show_manage_page() -> void:
	_variants_generation += 1
	_manage_generation += 1
	var generation := _manage_generation
	var editor := _manage_editor
	if editor == null:
		return
	_manage_variant = null
	_alternative_state = AlternativeState.HIDDEN
	_templates.clear()
	_manage_state = ManageState.LOADING
	_set_step(Step.MANAGE)
	_title.text = tr("Export templates · %s") % editor.name
	_show_manage_state(ManageState.LOADING)
	_back_button.grab_focus()

	var hint := VersionHint.parse(editor.version_hint)
	# Redot shares Godot's version numbers, not its templates.
	if not hint.is_valid or editor.engine_brand == EditorEngineBrand.REDOT:
		_show_manage_state(ManageState.NOT_OFFICIAL)
		return
	if _catalog == null:
		_set_catalog(EditorCatalog.default())
	if not _catalog_loaded and not _loading:
		_load_catalog()
	while _loading:
		await get_tree().process_frame
		if generation != _manage_generation:
			return
	if not _catalog_loaded:
		_show_manage_state(ManageState.ERROR)
		_manage_retry_button.grab_focus()
		return
	# Pre-releases of versions that went stable since are found too, though the tabs
	# leave them out.
	var entry := _catalog.entry_of_hint(editor.version_hint)
	if entry == null:
		_show_manage_state(ManageState.NOT_OFFICIAL)
		return
	var errors: Array[String] = []
	var variants := await _catalog.async_variants(entry, errors)
	if generation != _manage_generation:
		return
	for error in errors:
		Output.push("Godot release files fetch error: %s" % error)
	if _catalog.entry_availability(entry) == EditorCatalog.Availability.LOAD_FAILED:
		_show_manage_state(ManageState.ERROR)
		_manage_retry_button.grab_focus()
		return
	for variant in variants:
		if variant.mono == hint.is_mono and not variant.templates_url.is_empty():
			_manage_variant = variant
	if _manage_variant == null:
		_show_manage_state(ManageState.NO_TEMPLATES)
		return
	_templates.show_manage(entry, _manage_variant)
	_show_manage_state(ManageState.READY)
	_templates.focus_tree()


## Shows [param state] on the manage page: the templates tree, or a spinner or a
## message instead. Over the tree, says when a job changes these templates already.
func _show_manage_state(state: ManageState) -> void:
	_manage_state = state
	var busy := state == ManageState.READY and _manage_busy()
	_templates.visible = state == ManageState.READY
	_manage_state_box.visible = state != ManageState.READY or busy
	_manage_retry_button.visible = state == ManageState.ERROR
	var editor_name := _manage_editor.name if _manage_editor != null else ""
	match state:
		ManageState.LOADING:
			_manage_icon.texture = get_theme_icon("Progress1", "EditorIcons")
			_manage_status.text = tr("Looking for the export templates of %s...") % editor_name
		ManageState.NOT_OFFICIAL:
			_manage_icon.texture = get_theme_icon("StatusWarning", "EditorIcons")
			_manage_status.text = tr(
				"%s is not an official Godot release, so the Hub cannot tell which export "
				+ "templates it needs. Install them from the editor's Export Template Manager."
			) % editor_name
		ManageState.NO_TEMPLATES:
			_manage_icon.texture = get_theme_icon("StatusWarning", "EditorIcons")
			_manage_status.text = tr(
				"The release of %s has no export templates to download for this build."
			) % editor_name
		ManageState.ERROR:
			_manage_icon.texture = get_theme_icon("StatusError", "EditorIcons")
			_manage_status.text = tr(
				"Could not load the downloads of this release. Check your connection and try again."
			)
		ManageState.READY:
			_manage_icon.texture = get_theme_icon("StatusWarning", "EditorIcons")
			_manage_status.text = tr(
				"These export templates are being changed. Apply more changes once that is done."
			)
	_update_footer()
	_update_spinner()


## True while a job adds or removes the templates the manage page shows.
func _manage_busy() -> bool:
	if _templates_jobs == null or _manage_editor == null:
		return false
	var job := _templates_jobs.get_job(_manage_editor.path)
	if job != null and job.state == ExportTemplatesJobs.Job.State.RUNNING:
		return true
	return _templates_jobs.is_folder_busy(_templates.get_folder())


func _can_apply() -> bool:
	return (
		_step == Step.MANAGE
		and _manage_state == ManageState.READY
		and _templates_jobs != null
		and not _manage_busy()
		and _templates.has_changes()
	)


## Hands the changes of the manage page to the jobs, whose progress shows on the
## editor's row in the Installs list.
func _apply_template_changes() -> void:
	if not _can_apply():
		return
	var changes := _templates.pending_changes()
	var request := ExportTemplatesJobs.Request.new()
	request.editor_name = _manage_editor.name
	request.archive_url = _manage_variant.templates_url
	request.archive_size = _manage_variant.templates_size_bytes
	request.add_files = changes.add_files
	request.all_files = changes.all_files
	request.remove_files = changes.remove_files
	request.folder = _templates.get_folder()
	var editor_path := _manage_editor.path
	close()
	_templates_jobs.start(editor_path, request)


## A job started, progressed or ended: the templates shown may be installed or gone
## now, and the manage page may apply again.
func _on_job_changed(editor_path: String) -> void:
	if not _open:
		return
	var job := _templates_jobs.get_job(editor_path)
	var running := job != null and job.state == ExportTemplatesJobs.Job.State.RUNNING
	var tree_shown := _step == Step.TEMPLATES or (
		_step == Step.MANAGE and _manage_state == ManageState.READY
	)
	if tree_shown and not running:
		_templates.refresh_installed()
	if _step == Step.MANAGE:
		_show_manage_state(_manage_state)


func download_zip(
	url: String,
	file_name: String,
	on_http_terminal: Callable = Callable(),
	on_installed: Callable = Callable(),
) -> void:
	var editor_download: AssetDownload = _editor_download_scene.instantiate()
	_editor_downloads.add_download_item(editor_download)
	var http_terminal := func() -> void:
		if on_http_terminal.is_valid():
			on_http_terminal.call()
	# These signals carry one argument; a 0-arg callable would never be called.
	editor_download.download_failed.connect(http_terminal.unbind(1), CONNECT_ONE_SHOT)
	editor_download.downloaded.connect(http_terminal.unbind(1), CONNECT_ONE_SHOT)
	editor_download.request_failed.connect(http_terminal.unbind(1), CONNECT_ONE_SHOT)
	# Dismissing the download emits none of the above.
	editor_download.tree_exiting.connect(http_terminal, CONNECT_ONE_SHOT)
	editor_download.start(
		url, (Config.DOWNLOADS_PATH.ret() as String) + "/", file_name
	)
	editor_download.download_failed.connect(func(response_code: int) -> void:
		Output.push(
			"Failed to download editor: %s" % response_code
		)
	)
	editor_download.downloaded.connect(func(abs_path: String) -> void:
		install_zip(
			abs_path, 
			file_name.replace(".zip", "").replace(".", "_"), 
			utils.guess_editor_name(file_name.replace(".zip", "")),
			func() -> void: editor_download.queue_free(),
			on_installed,
		)
	)


## Extracts the editor archive [param zip_abs_path] to the folder
## [param root_unzip_folder_name] of the versions folder and installs its editor right
## away: the one [method RemoteEditorInstallControl.find_editor_executable] finds, named
## [param possible_editor_name], or after the version in its own name when that one has
## none. A dialog asks for the file and the name instead when the archive has no single
## Godot or Redot editor for this platform, when no name tells its version, or when an
## editor of that version and build is installed already.
## [param on_install] (an optional Callable), then [param on_installed], are called once
## the editor is installed.
func install_zip(
	zip_abs_path: String,
	root_unzip_folder_name: String,
	possible_editor_name: String,
	on_install: Variant = null,
	on_installed: Callable = Callable(),
) -> void:
	var zip_content_dir := _unzip_downloaded(zip_abs_path, root_unzip_folder_name)
	if zip_content_dir.is_empty():
		var accept_dialog := AcceptDialog.new()
		accept_dialog.visibility_changed.connect(func() -> void:
			if not accept_dialog.visible:
				accept_dialog.queue_free()
		)
		accept_dialog.dialog_text = tr("Error extracting archive.")
		add_child(accept_dialog)
		accept_dialog.popup_centered()
		return
	var exec_path := RemoteEditorInstallControl.find_editor_executable(
		edir.list_recursive(zip_content_dir), OS.get_name()
	)
	var editor_name := _versioned_editor_name(possible_editor_name, exec_path, zip_content_dir)
	if editor_name.is_empty() or _is_installed_build(editor_name, exec_path):
		_ask_editor_executable(
			zip_content_dir,
			possible_editor_name if editor_name.is_empty() else editor_name,
			on_install,
			on_installed,
		)
		return
	Output.push("Installing editor: %s" % exec_path)
	_install_extracted_editor(editor_name, exec_path, on_install, on_installed)


## Returns the name to install the editor [param exec_path], extracted to
## [param zip_content_dir], under without asking: [param possible_editor_name], or the
## name guessed from the editor's path in the archive when only that one has a version.
## Returns an empty string when neither has a version, so the Installs list could not
## tell it, or when the file is not named like an editor, e.g. an exported game.
static func _versioned_editor_name(
	possible_editor_name: String, exec_path: String, zip_content_dir: String
) -> String:
	if exec_path.is_empty() or not RemoteEditorInstallControl.is_named_like_editor(exec_path):
		return ""
	if utils.names_version(possible_editor_name):
		return possible_editor_name
	var in_archive := exec_path.trim_prefix(zip_content_dir.simplify_path()).trim_prefix("/")
	var guessed := utils.guess_editor_name(in_archive)
	return guessed if utils.names_version(guessed) else ""


## Whether an editor of the version and build (Standard or .NET, Godot or Redot) of
## [param editor_name] at [param exec_path] is installed already: a second one installs
## only if the user wants it, e.g. after starting the same download twice.
func _is_installed_build(editor_name: String, exec_path: String) -> bool:
	var hint := LocalEditors.Item.version_hint_from_name(editor_name)
	var brand := EditorEngineBrand.detect_from_metadata(editor_name, exec_path, hint)
	for editor in _live_installed_editors():
		if editor.engine_brand == brand and VersionHint.are_equal(hint, editor.version_hint):
			return true
	return false


## Asks which file of [param zip_content_dir] is the editor, see [method install_zip].
func _ask_editor_executable(
	zip_content_dir: String,
	possible_editor_name: String,
	on_install: Variant,
	on_installed: Callable,
) -> void:
	var editor_install: RemoteEditorInstallControl = _editor_install_scene.instantiate()
	add_child(editor_install)
	editor_install.init(possible_editor_name, zip_content_dir)
	# Cancel, Esc and closing the dialog all mean the extracted editor is not wanted.
	editor_install.canceled.connect(func() -> void:
		edir.remove_recursive(ProjectSettings.globalize_path(zip_content_dir))
	)
	editor_install.installed.connect(func(p_name: String, exec_path: String) -> void:
		_install_extracted_editor(p_name, exec_path, on_install, on_installed)
	)
	editor_install.popup_centered()


## Reports the extracted editor [param exec_path] as installed under
## [param editor_name], made runnable, see [method install_zip].
func _install_extracted_editor(
	editor_name: String,
	exec_path: String,
	on_install: Variant,
	on_installed: Callable,
) -> void:
	var abs_exec_path := ProjectSettings.globalize_path(exec_path)
	_make_runnable(abs_exec_path)
	installed.emit(editor_name, abs_exec_path)
	if on_install:
		(on_install as Callable).call()
	if on_installed.is_valid():
		on_installed.call(editor_name, abs_exec_path)


## Lets whoever may read the editor [param abs_exec_path] run it: archives made on
## Windows, or by tools such as ZIPPacker, extract without the execute permission. For
## an app bundle, those are the binaries in its Contents/MacOS folder.
static func _make_runnable(abs_exec_path: String) -> void:
	if OS.get_name() == "Windows":
		return
	var binaries: Array[String] = []
	if DirAccess.dir_exists_absolute(abs_exec_path):
		var macos_dir := abs_exec_path.path_join("Contents/MacOS")
		if DirAccess.dir_exists_absolute(macos_dir):
			for file_name in DirAccess.get_files_at(macos_dir):
				binaries.append(macos_dir.path_join(file_name))
	elif FileAccess.file_exists(abs_exec_path):
		binaries.append(abs_exec_path)
	for binary in binaries:
		var permissions := FileAccess.get_unix_permissions(binary)
		var runnable := permissions | ((permissions & READ_PERMISSIONS) >> 2)
		if runnable != permissions:
			FileAccess.set_unix_permissions(binary, runnable)


func _unzip_downloaded(downloaded_abs_path: String, root_unzip_folder_name: String) -> String:
	var zip_content_dir := "%s/%s" % [Config.VERSIONS_PATH.ret(), root_unzip_folder_name]
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(zip_content_dir)):
		zip_content_dir += "-%s" % uuid.v4().substr(0, 8)
	zip_content_dir += "/"
	if zip.unzip(downloaded_abs_path, zip_content_dir) != OK:
		# zip.unzip creates the folder first; drop the empty or partial extraction.
		edir.remove_recursive(ProjectSettings.globalize_path(zip_content_dir))
		return ""
	return zip_content_dir


## Hands download rows to the callable given to [method RemoteEditorsControl.init].
class DownloadRows:
	var _add_item: Callable

	func _init(add_item: Callable) -> void:
		_add_item = add_item

	func add_download_item(item: Control) -> void:
		_add_item.call(item)


## One build in the build step's radio group: a full-width row that picks its radio
## button when clicked anywhere, drawn like a Tree row when hovered or picked, with the
## Hub's rounded corners.
class VariantRow extends PanelContainer:
	var button: CheckBox
	var _hovered := false
	## Made from the theme when first drawn.
	var _hover_style: StyleBox
	var _selected_style: StyleBox

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(_set_hovered.bind(true))
		mouse_exited.connect(_set_hovered.bind(false))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			_hover_style = null
			_selected_style = null
			queue_redraw()

	func _draw() -> void:
		if _hover_style == null:
			_hover_style = ThemeCorners.rounded(get_theme_stylebox("hover", "Tree"), self)
			_selected_style = ThemeCorners.rounded(get_theme_stylebox("selected", "Tree"), self)
		var rect := Rect2(Vector2.ZERO, size)
		if button.button_pressed:
			draw_style_box(_selected_style, rect)
		elif _hovered and not button.disabled:
			draw_style_box(_hover_style, rect)

	func _gui_input(event: InputEvent) -> void:
		var mouse_button := event as InputEventMouseButton
		if (
			mouse_button != null
			and mouse_button.button_index == MOUSE_BUTTON_LEFT
			and mouse_button.pressed
			and not button.disabled
		):
			button.button_pressed = true
			accept_event()

	func _set_hovered(hovered: bool) -> void:
		_hovered = hovered
		queue_redraw()


## What the manage page keeps of an installed editor: the Installs page frees its
## items when it reloads them.
class ManagedEditor:
	var path: String
	var name: String
	var version_hint: String
	var engine_brand: String

	func _init(editor: LocalEditors.Item) -> void:
		path = editor.path
		name = editor.name
		version_hint = editor.version_hint
		engine_brand = editor.engine_brand
