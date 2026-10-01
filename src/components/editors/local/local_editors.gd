class_name LocalEditorsControl
extends HBoxContainer
## The Installs page: the local Godot editor installations.
##
## Provides UI for import, download, scan, and editor management. Editor
## downloads started from the Install Editor modal show up at the top of the list.


## Emitted when the user requests to download a new editor.
signal editor_download_pressed
## Emitted when the user requests to download the recommended stable version.
signal recommended_stable_download_requested
## Emitted when editors are added, removed, edited or reloaded, passing whether any
## editors are installed.
signal editor_inventory_changed(has_any_installed: bool)
## Emitted when tag management is requested for an editor item.
signal manage_tags_requested(item_tags: Array, all_tags: Array, on_confirm: Callable)
## Emitted when the user asks to add or remove the export templates of [param editor].
signal export_templates_requested(editor: LocalEditors.Item)

## Items of the header's Locate menu.
enum LocateMenuItem {
	IMPORT,
	SCAN,
}

var _local_editors: LocalEditors.List
var _remove_missing_action: Action.Self
var _refresh_action: Action.Self
var _refresh_busy := false

@onready var _editors_list: EditorsVBoxList = %EditorsList
@onready var _sidebar: ActionsSidebarControl = %ActionsSidebar
@onready var _orphan_editors_explorer: OrphanEditorExplorerWindow = %OrphanEditorExplorer
@onready var _scan_dialog: ScanFileDialog = %ScanDialog
@onready var _locate_button: MenuButton = %LocateButton
@onready var _install_editor_button: Button = %InstallEditorButton
@onready var _editor_downloads: EditorDownloadsArea = %EditorDownloads


func _ready() -> void:
	(%EditorImport as EditorImportDialog).imported.connect(func(editor_name: String, editor_path: String) -> void:
		add(editor_name, editor_path)
	)

	_scan_dialog.dir_to_scan_selected.connect(func(dir_to_scan: String) -> void:
		_scan_editors(dir_to_scan)
	)

	var remove_missing_popup := RemoveMissingDialog.new(_remove_missing)
	add_child(remove_missing_popup)

	var actions := Action.List.new([
		Action.from_dict({
			"key": "import",
			"icon": Action.IconTheme.new(self, "Load", "EditorIcons"),
			"act": import,
			"label": tr("Import"),
		}),
		Action.from_dict({
			"key": "download",
			"icon": Action.IconTheme.new(self, "AssetLib", "EditorIcons"),
			"act": func() -> void: editor_download_pressed.emit(),
			"label": tr("Download"),
		}),
		Action.from_dict({
			"key": "orphan",
			"icon": Action.IconTheme.new(self, "Debug", "EditorIcons"),
			"act": func() -> void:
				_orphan_editors_explorer.before_popup()
				_orphan_editors_explorer.popup_centered_ratio(0.4)
				pass,
			"label": tr("Orphan Editors Explorer"),
			"tooltip": tr("Check if there are some leaked Godot binaries on the filesystem that can be safely removed. For advanced users.")
		}),
		Action.from_dict({
			"key": "scan",
			"icon": Action.IconTheme.new(self, "Search", "EditorIcons"),
			"act": _popup_scan_dialog,
			"label": tr("Scan"),
		}),
		Action.from_dict({
			"key": "refresh",
			"icon": Action.IconTheme.new(self, "Reload", "EditorIcons"),
			"act": _refresh,
			"label": tr("Refresh List"),
		}),
		Action.from_dict({
			"label": tr("Remove Missing"),
			"key": "remove-missing",
			"icon": Action.IconTheme.new(self, "Clear", "EditorIcons"),
			"act": func() -> void: remove_missing_popup.popup_centered()
		}),
	])

	_remove_missing_action = actions.by_key("remove-missing")
	_refresh_action = actions.by_key("refresh")

	var editor_actions := TabActions.Menu.new(
		actions.sub_list([
			"import",
			"download",
			"scan",
		]).all(),
		# Hidden from the toolbar by default: the header's Locate and Install
		# Editor buttons do the same. The menu can still show them.
		TabActions.Settings.new(Cache.section_of(self), [])
	)
	editor_actions.add_controls_to_node(%EditorsList/HBoxContainer/TabActions as Control)
	editor_actions.icon = get_theme_icon("GuiTabMenuHl", "EditorIcons")

	%EditorsList/HBoxContainer.add_child(_remove_missing_action.to_btn().make_flat(true).show_text(false))
	%EditorsList/HBoxContainer.add_child(actions.by_key("orphan").to_btn().make_flat(true).show_text(false))
	%EditorsList/HBoxContainer.add_child(_refresh_action.to_btn().make_flat(true).show_text(false))
	%EditorsList/HBoxContainer.add_child(editor_actions)

	_editors_list.install_editor_requested.connect(func() -> void: editor_download_pressed.emit())
	_editors_list.recommended_stable_download_requested.connect(
		func() -> void: recommended_stable_download_requested.emit()
	)
	(_editors_list.get_node("%SearchBox") as LineEdit).placeholder_text = tr("Filter installs")
	# While an editor downloads, the empty state has nothing to offer but waiting.
	_editor_downloads.visibility_changed.connect(func() -> void:
		_editors_list.set_empty_state_actions_visible(not _editor_downloads.visible)
	)

	_setup_header()


## Wires the Installs title, the Locate menu and the Install Editor button.
func _setup_header() -> void:
	var title := %Title as Label
	title.text = tr("Installs")
	# Without the Label margin the title lines up with the list below it.
	title.add_theme_stylebox_override("normal", StyleBoxEmpty.new())

	_install_editor_button.text = tr("Install Editor")
	_install_editor_button.tooltip_text = tr("Download and install a Godot editor.")
	_install_editor_button.pressed.connect(func() -> void: editor_download_pressed.emit())

	_locate_button.text = tr("Locate")
	_locate_button.tooltip_text = tr("Add editors that are already on this computer.")
	# Drawn like the Install Editor button, not as a flat editor menu, in both themes:
	# see _update_header_theme().
	_locate_button.flat = false
	var locate_menu := _locate_button.get_popup()
	locate_menu.add_item(tr("Import..."), LocateMenuItem.IMPORT)
	locate_menu.add_item(tr("Scan..."), LocateMenuItem.SCAN)
	locate_menu.id_pressed.connect(_on_locate_menu_id_pressed)

	_update_header_theme()
	# Deferred: theme_changed comes before the cached theme items are dropped.
	theme_changed.connect(_update_header_theme, CONNECT_DEFERRED)


## Applies the header's editor icons and the Locate menu's button look, again when the
## theme changes.
func _update_header_theme() -> void:
	# Not a "Button" type variation: the Classic style's own (flat) MenuButton styles
	# would still come first.
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		_locate_button.add_theme_stylebox_override(state, get_theme_stylebox(state, "Button"))
	_install_editor_button.icon = get_theme_icon("AssetLib", "EditorIcons")
	_locate_button.icon = get_theme_icon("arrow", "OptionButton")
	var locate_menu := _locate_button.get_popup()
	locate_menu.set_item_icon(
		locate_menu.get_item_index(LocateMenuItem.IMPORT), get_theme_icon("Load", "EditorIcons")
	)
	locate_menu.set_item_icon(
		locate_menu.get_item_index(LocateMenuItem.SCAN), get_theme_icon("Search", "EditorIcons")
	)


## Sets busy state on the recommended stable download button.
func set_recommended_stable_download_busy(busy: bool) -> void:
	_editors_list.set_recommended_stable_button_disabled(busy)


## Shows an editor download (an AssetDownload card) at the top of the list.
func add_download_item(item: Control) -> void:
	_editor_downloads.add_download_item(item)


## Binds the editor list service and refreshes the UI.
func init(editors: LocalEditors.List) -> void:
	_local_editors = editors
	_editors_list.refresh(_local_editors.all())
	_editors_list.sort_items()

	_orphan_editors_explorer.init(editors, Config.versions_path.ret() as String)
	_update_remove_missing_disabled()
	_notify_editor_inventory_changed()


## Emits inventory changed and updates the install prompt.
func _notify_editor_inventory_changed() -> void:
	if not _local_editors:
		return

	var has_any := not _local_editors.all().is_empty()
	editor_inventory_changed.emit(has_any)
	_editors_list.apply_install_prompt_for_inventory_empty(not has_any)


## Adds an editor if not already present.
func add(editor_name: String, exec_path: String) -> void:
	if not _local_editors.has(exec_path):
		var editor := _local_editors.add(editor_name, exec_path)
		_local_editors.save()
		_editors_list.add_in_view(editor)
		_notify_editor_inventory_changed()


## Opens the editor import dialog.
func import(editor_name: String = "", editor_path: String = "") -> void:
	var editor_import := %EditorImport as EditorImportDialog
	if editor_import.visible: return

	editor_import.init(editor_name, editor_path)
	editor_import.popup_centered()


## Opens the folder picker for scanning editors.
func _popup_scan_dialog() -> void:
	_scan_dialog.current_dir = ProjectSettings.globalize_path(Config.versions_path.ret() as String)
	_scan_dialog.popup_centered_ratio(0.5)


## Runs the picked Locate menu item.
func _on_locate_menu_id_pressed(id: int) -> void:
	match id:
		LocateMenuItem.IMPORT:
			import()
		LocateMenuItem.SCAN:
			_popup_scan_dialog()


## Reloads editors and detects engine brands on a worker thread.
func _refresh() -> void:
	if _refresh_busy:
		return

	_refresh_busy = true
	_refresh_action.disable(true)

	_local_editors.load()
	# load() frees the old items, so rebuild the rows and let listeners (the
	# Install Editor modal) drop them before awaiting.
	_editors_list.refresh(_local_editors.all())
	_editors_list.sort_items()
	_notify_editor_inventory_changed()
	var snapshots := _local_editors.engine_brand_snapshots()
	var brands := await _detect_engine_brands_threaded(snapshots)
	if not is_instance_valid(self):
		return

	_local_editors.apply_engine_brands(brands)
	_local_editors.save()
	_editors_list.refresh(_local_editors.all())
	_editors_list.sort_items()
	_update_remove_missing_disabled()
	_notify_editor_inventory_changed()

	_refresh_busy = false
	if _refresh_action:
		_refresh_action.disable(false)


## Detects engine brands for snapshot entries using WorkerThreadPool.
func _detect_engine_brands_threaded(snapshots: Array[Dictionary]) -> Dictionary:
	var brands := {}
	if snapshots.is_empty():
		return brands

	var mutex := Mutex.new()
	var detect_one := func(index: int) -> void:
		var snap: Dictionary = snapshots[index]
		if snap.get("skip", false):
			return

		var brand := EditorEngineBrand.detect_from_fields(
			str(snap.get("name", "")),
			str(snap.get("path", "")),
			str(snap.get("version_hint", "")),
			str(snap.get("bin_path", "")),
			true
		)
		mutex.lock()
		brands[str(snap.get("path", ""))] = brand
		mutex.unlock()

	var group_id := WorkerThreadPool.add_group_task(detect_one, snapshots.size())
	while not WorkerThreadPool.is_group_task_completed(group_id):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_group_task_completion(group_id)
	return brands


## Removes all invalid editor entries.
func _remove_missing() -> void:
	for e: LocalEditors.Item in _local_editors.all().filter(func(x: LocalEditors.Item) -> bool: return not x.is_valid):
		_local_editors.erase(e.path)

	_sidebar.refresh_actions([])
	_local_editors.save()
	_editors_list.refresh(_local_editors.all())
	_editors_list.sort_items()
	_update_remove_missing_disabled()
	_notify_editor_inventory_changed()


## Scans a directory for Godot editor binaries.
func _scan_editors(dir_to_scan: String) -> void:
	var filter: Callable
	if OS.has_feature("windows"):
		filter = func(x: edir.DirListResult) -> bool:
			var evidences := [
				x.is_file and x.extension == "exe",
				x.file.to_lower().contains("godot_v"),
				not x.file.to_lower().contains("console"),
			]
			return evidences.all(func(is_true: bool) -> bool: return is_true)
	elif OS.has_feature("macos"):
		filter = func(x: edir.DirListResult) -> bool:
			var evidences := [
				x.is_dir and x.extension == "app",
				x.file.to_lower().contains("godot")
			]
			return evidences.all(func(is_true: bool) -> bool: return is_true)
	elif OS.has_feature("linux"):
		filter = func(x: edir.DirListResult) -> bool:
			var evidences := [
				x.is_file and (x.extension.contains("32") or x.extension.contains("64")),
				x.file.to_lower().contains("godot_v")
			]
			return evidences.all(func(is_true: bool) -> bool: return is_true)

	var editors_exec := edir.list_recursive(
		ProjectSettings.globalize_path(dir_to_scan),
		false,
		filter,
		(func(x: String) -> bool: return not x.get_file().begins_with("."))
	)
	for editor_exec: edir.DirListResult in editors_exec:
		var editor_exec_path := editor_exec.path
		if _local_editors.has(editor_exec_path): continue

		var editor := _local_editors.add(utils.guess_editor_name(editor_exec.file), editor_exec_path)
		_editors_list.add(editor)

	_local_editors.save()
	_notify_editor_inventory_changed()


## Enables or disables the remove missing action.
func _update_remove_missing_disabled() -> void:
	var invalid_count := len(_local_editors.all().filter(func(x: LocalEditors.Item) -> bool: return not x.is_valid))
	_remove_missing_action.disable(invalid_count == 0)


## Refreshes sidebar actions for the selected editor.
func _on_editors_list_item_selected(item: EditorListItemControl) -> void:
	_sidebar.refresh_actions(item.get_actions())


## Removes an editor and optionally deletes its directory.
func _on_editors_list_item_removed(item_data: LocalEditors.Item, remove_dir: bool) -> void:
	var removed_editors: Array[LocalEditors.Item] = [item_data]
	var remove_error := OK
	var install_dir := LocalEditors.managed_install_dir(item_data.path)
	if remove_dir and install_dir.is_empty():
		Output.push("skipping removing path {%s}" % item_data.path.get_base_dir())
	elif remove_dir and DirAccess.dir_exists_absolute(install_dir):
		# Editors registered inside the deleted folder go with it.
		for editor: LocalEditors.Item in _local_editors.all():
			var editor_path := ProjectSettings.globalize_path(editor.path)
			if editor != item_data and LocalEditors.is_path_inside(editor_path, install_dir):
				removed_editors.append(editor)
		remove_error = edir.remove_recursive(install_dir)
		if remove_error == OK:
			LocalEditors.remove_empty_parents(install_dir, Config.versions_path.ret() as String)
		else:
			Output.push("failed removing path {%s}: error %s" % [install_dir, remove_error])
			_show_error(
				tr("Could not delete %s: %s") % [install_dir, error_string(remove_error)]
			)

	# After a failed delete the editors stay registered and the rows are rebuilt.
	if remove_error == OK:
		for editor: LocalEditors.Item in removed_editors:
			if _local_editors.has(editor.path):
				_local_editors.erase(editor.path)
		_local_editors.save()

	_sidebar.refresh_actions([])
	_update_remove_missing_disabled()
	_editors_list.refresh(_local_editors.all())
	_editors_list.sort_items()
	_notify_editor_inventory_changed()


## Shows an error in a dialog that frees itself when closed.
func _show_error(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()


## Persists changes after an editor item edit.
func _on_editors_list_item_edited(item_data: Variant) -> void:
	_local_editors.save()
	_editors_list.sort_items()
	_editors_list.update_filters()
	# A rename can change which versions count as installed.
	_notify_editor_inventory_changed()


## Asks for the export templates manager of an editor item.
func _on_editors_list_item_export_templates_requested(item_data: LocalEditors.Item) -> void:
	export_templates_requested.emit(item_data)


## Opens tag management for an editor item.
func _on_editors_list_item_manage_tags_requested(item_data: LocalEditors.Item) -> void:
	var all_tags := Set.new()
	all_tags.append_array(_local_editors.get_all_tags())
	all_tags.append_array(Config.default_editor_tags.ret() as Array)
	manage_tags_requested.emit(
		item_data.tags,
		all_tags.values(),
		func(new_tags: Array) -> void:
			item_data.tags = new_tags
			item_data.emit_tags_edited()
			_on_editors_list_item_edited(item_data)
	)
