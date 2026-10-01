class_name ExportTemplatesPicker
extends VBoxContainer
## The Install Editor modal's choice of export templates: a tree like Godot's Export
## Template Manager (Desktop > Windows > Windows x86_64 > files) with tri-state checks.
##
## Shows the templates of one build: the Standard or .NET archive (.tpz). Its central
## directory (the last 64 KB, more for Godot 3 .NET archives) says which templates it
## has and their sizes; templates it lacks are disabled. Archives without Godot 4 file
## names (Godot 3 and older) offer them all as one item.
## [br][br]
## [method show_build] picks templates to install with an editor: nothing is checked
## at first, and templates of this version that are installed already show checked
## and disabled. [method show_manage] edits the installed ones, like Unity's modules:
## they show checked, and unchecking one marks it for removal.


## Emitted when the user checks or unchecks templates.
signal selection_changed

## What an item stands for.
enum ItemState {
	## Can be installed.
	AVAILABLE,
	## Installed for this version already.
	INSTALLED,
	## Not in this build's archive.
	ABSENT,
}

## What the status line says about the archive's central directory.
enum IndexState {
	NONE,
	LOADING,
	READY,
	ERROR,
}

## File of the "All export templates" item of archives without Godot 4 file names.
const ALL_FILES := "*"
## Width before EDSCALE of the size column, unless its notes need more.
const SIZE_COLUMN_WIDTH := 110
## Height before EDSCALE the tree keeps when the modal is short.
const MIN_TREE_HEIGHT := 120
const _STATE_META := &"state"

## Makes the source reading an archive: [code](url: String, known_size: int) ->
## RangeSource[/code]. HTTP when not valid.
var _source_factory := Callable()
var _entry: EditorCatalog.CatalogEntry
var _variant: EditorCatalog.CatalogVariant
## True when installed templates can be unchecked to remove them.
var _manage := false
## Version folder of the shown templates, e.g. "4.7.2.stable.mono".
var _folder := ""
## True for the Godot 4 table, false for one "All export templates" item.
var _granular := true
var _index: TemplateArchive.Index
var _index_state := IndexState.NONE
var _index_error := ""
## Central directories by archive url; GitHub release files do not change.
var _index_cache: Dictionary[String, TemplateArchive.Index] = {}
var _generation := 0
var _source: RangeSource
var _http: HTTPRequest
var _installed := PackedStringArray()
## Files the user checked, kept when the tree follows another build.
var _checked_files := PackedStringArray()
## Installed files the user unchecked, in manage mode.
var _removed_files := PackedStringArray()
## The checked files the shown tree has and can install: what Install downloads.
var _selected_files := PackedStringArray()
## The installed files the shown tree has unchecked: what Apply removes.
var _unchecked_installed := PackedStringArray()
var _spinner_time := 0.0

@onready var _hint_label: Label = %HintLabel
@onready var _tree: Tree = %Tree
@onready var _status: HBoxContainer = %Status
@onready var _status_icon: TextureRect = %StatusIcon
@onready var _status_label: Label = %StatusLabel
@onready var _retry_button: Button = %RetryButton


func _ready() -> void:
	set_process(false)
	_tree.columns = 2
	_tree.hide_root = true
	# Highlights the whole row, sizes too, like the modal's other rows. The size column
	# cannot be selected, so Space always toggles the check.
	_tree.select_mode = Tree.SELECT_ROW
	_tree.set_column_expand(1, false)
	_tree.set_column_clip_content(0, true)
	_tree.custom_minimum_size.y = MIN_TREE_HEIGHT * Config.EDSCALE
	_tree.item_edited.connect(_on_item_edited)
	_retry_button.text = tr("Retry")
	_retry_button.pressed.connect(_load_index)
	_update_theme()
	# Deferred: theme_changed comes before the cached theme items are dropped.
	theme_changed.connect(_update_theme, CONNECT_DEFERRED)
	_show_index_state(IndexState.NONE)


func _process(delta: float) -> void:
	# Only runs while the archive's directory loads.
	_spinner_time += delta
	_status_icon.texture = get_theme_icon(
		"Progress%d" % (int(_spinner_time * 10.0) % 8 + 1), "EditorIcons"
	)


## Reads archives with [param factory] instead of HTTP, e.g. local files in tests:
## [code](url: String, known_size: int) -> RangeSource[/code].
func set_source_factory(factory: Callable) -> void:
	_source_factory = factory


## Shows the templates of [param variant], a build of [param entry], to install with
## it. Keeps the checked templates its archive has too.
func show_build(entry: EditorCatalog.CatalogEntry, variant: EditorCatalog.CatalogVariant) -> void:
	if (
		not _manage
		and _variant != null
		and _variant.templates_url == variant.templates_url
		and _entry == entry
	):
		# Shown already, e.g. back from the build step: a job may have installed or
		# removed some of them since.
		refresh_installed()
		return
	if _manage:
		clear()
	_show(entry, variant)


## Shows the templates of [param variant], a build of [param entry], to add or remove:
## installed ones checked, the others not.
func show_manage(entry: EditorCatalog.CatalogEntry, variant: EditorCatalog.CatalogVariant) -> void:
	clear()
	_manage = true
	_show(entry, variant)


## Reads again which templates are installed, e.g. after an install or a removal
## finished. Changes the user asked for that happened already are dropped.
func refresh_installed() -> void:
	if _variant == null:
		return
	_installed = ExportTemplates.installed_files(_folder)
	for i in range(_checked_files.size() - 1, -1, -1):
		if _file_state(_checked_files[i]) == ItemState.INSTALLED:
			_checked_files.remove_at(i)
	for i in range(_removed_files.size() - 1, -1, -1):
		if _file_state(_removed_files[i]) != ItemState.INSTALLED:
			_removed_files.remove_at(i)
	_update_states()
	selection_changed.emit()


## Gives the tree the keyboard, on its first item, so arrows and Space pick templates.
func focus_tree() -> void:
	var first := _tree.get_root().get_first_child() if _tree.get_root() != null else null
	if first != null and _tree.get_selected() == null:
		_tree.set_selected(first, 0)
	_tree.grab_focus()


## Forgets the shown build and what was checked, and stops loading.
func clear() -> void:
	_stop_loading()
	_entry = null
	_variant = null
	_manage = false
	_index = null
	_checked_files.clear()
	_removed_files.clear()
	_selected_files.clear()
	_unchecked_installed.clear()
	_tree.clear()
	_update_hint()
	_show_index_state(IndexState.NONE)


func has_selection() -> bool:
	return not _selected_files.is_empty()


## True in manage mode when Apply has something to do.
func has_changes() -> bool:
	return has_selection() or not _unchecked_installed.is_empty()


## The version folder of the shown templates, e.g. "4.7.2.stable.mono", or empty.
func get_folder() -> String:
	return _folder if _variant != null else ""


## The templates to install, or null when none are checked.
func selection() -> Selection:
	if not has_selection():
		return null
	var result := Selection.new()
	result.url = _variant.templates_url
	result.archive_size = _variant.templates_size_bytes
	result.all_files = _selected_files.has(ALL_FILES)
	if not result.all_files:
		result.files = _selected_files.duplicate()
	return result


## What Apply changes in manage mode: templates to download and to remove.
func pending_changes() -> Changes:
	var result := Changes.new()
	result.all_files = _selected_files.has(ALL_FILES)
	if not result.all_files:
		result.add_files = _selected_files.duplicate()
	if _unchecked_installed.has(ALL_FILES):
		# The single item of an old archive stands for the whole folder.
		result.remove_files = _installed.duplicate()
	else:
		result.remove_files = _unchecked_installed.duplicate()
	return result


## Compressed bytes of the checked templates, or -1 while the archive's directory is
## not loaded.
func selected_size() -> int:
	if _index == null:
		return -1
	if _selected_files.has(ALL_FILES):
		return _files_size(_index.files())
	return _files_size(_selected_files)


## Bytes the templates marked for removal take on disk.
func removed_size() -> int:
	var dir := ExportTemplates.version_dir(_folder)
	var total := 0
	for file in pending_changes().remove_files:
		var opened := FileAccess.open(dir.path_join(file), FileAccess.READ)
		if opened != null:
			total += opened.get_length()
	return total


func _update_theme() -> void:
	_update_hint()
	_status_label.add_theme_color_override(
		"font_color", get_theme_color("readonly_font_color", "Editor")
	)
	_retry_button.icon = get_theme_icon("Reload", "EditorIcons")
	# The tree is a panel inside the modal: rounded like the Hub's other panels.
	_tree.remove_theme_stylebox_override("panel")
	_tree.add_theme_stylebox_override(
		"panel", ThemeCorners.rounded(_tree.get_theme_stylebox("panel"), self)
	)
	_tree.set_column_custom_minimum_width(1, _size_column_width())
	if _tree.get_root() != null:
		_update_states()
	_show_index_state(_index_state)


## Wide enough for sizes and for the Installed and Will be removed notes.
func _size_column_width() -> int:
	var font := _tree.get_theme_font("font")
	var font_size := _tree.get_theme_font_size("font_size")
	var widest := 0.0
	for note: String in [tr("Installed"), tr("Will be removed")]:
		var note_size := font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		widest = maxf(widest, note_size.x)
	var padding := (
		2 * _tree.get_theme_constant("h_separation")
		+ _tree.get_theme_constant("inner_item_margin_left")
		+ _tree.get_theme_constant("inner_item_margin_right")
		+ roundi(8 * Config.EDSCALE)
	)
	return maxi(roundi(SIZE_COLUMN_WIDTH * Config.EDSCALE), ceili(widest) + padding)


## Says what the tree is for: on the install step, in the normal text color, that it
## is optional; on the manage page, dimmed, how checks work there.
func _update_hint() -> void:
	if _manage:
		_hint_label.text = tr(
			"Check templates to download them, uncheck installed ones to remove them. "
			+ "Every editor of this version uses the same templates."
		)
	else:
		_hint_label.text = tr(
			"Optional. Only needed to export projects. You can add or remove them later "
			+ "from the editor's menu."
		)
	_hint_label.add_theme_color_override(
		"font_color",
		get_theme_color("readonly_font_color" if _manage else "font_color", "Editor"),
	)


func _show(entry: EditorCatalog.CatalogEntry, variant: EditorCatalog.CatalogVariant) -> void:
	_stop_loading()
	_entry = entry
	_variant = variant
	_folder = ExportTemplates.folder_name(entry.version, entry.release, variant.mono)
	_installed = ExportTemplates.installed_files(_folder)
	_index = _index_cache.get(variant.templates_url) as TemplateArchive.Index
	_update_hint()
	_update_granular()
	_rebuild()
	if _index != null:
		_show_index_state(IndexState.READY)
	else:
		_load_index()


func _make_source(url: String, known_size: int) -> RangeSource:
	if _source_factory.is_valid():
		return _source_factory.call(url, known_size) as RangeSource
	# A canceled request's node may still be finishing; each load gets its own.
	if _http != null:
		_http.queue_free()
	_http = HTTPRequest.new()
	add_child(_http)
	return HttpRangeSource.new(url, _http, known_size)


func _stop_loading() -> void:
	_generation += 1
	if _source != null:
		_source.cancel()
		_source = null
	set_process(false)


## Reads the archive's central directory from its last 64 KB, or all of it when it is
## bigger (Godot 3 .NET archives).
func _load_index() -> void:
	_stop_loading()
	var generation := _generation
	var url := _variant.templates_url
	var source := _make_source(url, _variant.templates_size_bytes)
	_source = source
	_show_index_state(IndexState.LOADING)
	var index: TemplateArchive.Index = null
	var size := await source.async_size()
	var error := size.error
	if error.is_empty():
		var tail := TemplateArchive.tail_range(size.total_size)
		var read := await source.async_read(tail[0], tail[1])
		error = read.error
		if error.is_empty():
			index = TemplateArchive.parse_index(read.bytes, size.total_size)
			var whole := TemplateArchive.directory_range(index)
			if not whole.is_empty():
				read = await source.async_read(whole[0], whole[1])
				error = read.error
				if error.is_empty():
					index = TemplateArchive.parse_index(read.bytes, size.total_size)
		if error.is_empty():
			error = index.error
	if generation != _generation:
		return
	_source = null
	if not error.is_empty():
		Output.push("Export templates archive read error: %s" % error)
		_index_error = error
		_show_index_state(IndexState.ERROR)
		return
	_index_cache[url] = index
	_index = index
	if _update_granular():
		_rebuild()
	else:
		_update_states()
	_show_index_state(IndexState.READY)
	selection_changed.emit()


## Picks the Godot 4 table or the single item for the shown build. Returns true when
## that changed.
func _update_granular() -> bool:
	var granular := VersionComparison.parts(_entry.version)[0] >= ExportTemplates.TABLE_MIN_MAJOR
	if granular and _index != null:
		granular = ExportTemplates.archive_uses_table(_index.files())
	var changed := granular != _granular
	_granular = granular
	if changed:
		_checked_files.clear()
		_removed_files.clear()
	return changed


func _show_index_state(state: IndexState) -> void:
	_index_state = state
	_status.visible = state == IndexState.LOADING or state == IndexState.ERROR
	_retry_button.visible = state == IndexState.ERROR
	if state == IndexState.LOADING and not is_processing():
		_spinner_time = 0.0
	set_process(state == IndexState.LOADING)
	match state:
		IndexState.LOADING:
			_status_icon.texture = get_theme_icon("Progress1", "EditorIcons")
			_status_label.text = tr("Reading the export templates archive...")
		IndexState.ERROR:
			_status_icon.texture = get_theme_icon("StatusWarning", "EditorIcons")
			_status_label.text = tr("Could not read the export templates archive: %s.") % (
				_index_error
			)
	_hint_label.tooltip_text = ""
	if _variant != null:
		_hint_label.tooltip_text = tr("Installed to %s") % ExportTemplates.version_dir(_folder)


func _rebuild() -> void:
	_tree.clear()
	var root := _tree.create_item()
	if not _granular:
		var all_item := _add_item(root, tr("All export templates"), ALL_FILES)
		all_item.set_tooltip_text(0, tr(
			"Every template of this release. Its archive does not name them like Godot 4."
		))
	else:
		var parent := root
		# Not a group name, so the first platform starts its group.
		var group := "\n"
		for platform in ExportTemplates.platforms():
			if platform.standard_only and _variant.mono:
				continue
			if platform.group != group:
				group = platform.group
				parent = root if group.is_empty() else _add_item(root, tr(group))
			var platform_item := _add_item(parent, tr(platform.name))
			for template in platform.templates:
				# A platform with one template of its name is that template, as in Godot.
				var template_item := platform_item
				if platform.templates.size() > 1 or template.name != platform.name:
					template_item = _add_item(platform_item, tr(template.name))
				template_item.set_tooltip_text(0, tr(template.description))
				for file in template.files:
					_add_item(template_item, file, file)
				template_item.collapsed = true
	_update_states()
	# A fresh list starts at the top, like Godot's Template Manager.
	if root.get_first_child() != null:
		_tree.scroll_to_item(root.get_first_child())


## Adds a check item; [param file] marks a file (leaf) item.
func _add_item(parent: TreeItem, text: String, file := "") -> TreeItem:
	var item := parent.create_child()
	item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	item.set_text(0, text)
	item.set_metadata(0, file)
	item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
	item.set_selectable(1, false)
	return item


## Sets every item's check, look and size from what is installed and in the archive.
func _update_states() -> void:
	for item in _tree.get_root().get_children():
		_update_state(item)
	_update_selection()


func _update_state(item: TreeItem) -> ItemState:
	var state := ItemState.ABSENT
	var file := item.get_metadata(0) as String
	if not file.is_empty():
		state = _file_state(file)
		if state == ItemState.AVAILABLE:
			item.set_checked(0, file in _checked_files)
		elif state == ItemState.INSTALLED and _manage:
			item.set_checked(0, file not in _removed_files)
	else:
		var installed := false
		for child in item.get_children():
			var child_state := _update_state(child)
			if child_state == ItemState.AVAILABLE:
				state = ItemState.AVAILABLE
			elif child_state == ItemState.INSTALLED:
				installed = true
		if state == ItemState.ABSENT and installed:
			state = ItemState.INSTALLED
	item.set_meta(_STATE_META, state)
	item.set_editable(0, _is_editable(state))
	item.set_custom_color(1, get_theme_color("readonly_font_color", "Editor"))
	match state:
		ItemState.AVAILABLE:
			item.clear_custom_color(0)
			var size := _available_size(item)
			item.set_text(1, String.humanize_size(size) if size > 0 else "")
			if not file.is_empty():
				item.set_tooltip_text(1, "")
			else:
				_update_check_from_children(item)
		ItemState.INSTALLED:
			item.clear_custom_color(0)
			if not _manage:
				_set_checked(item, true)
			elif file.is_empty():
				_update_check_from_children(item)
			# Unchecked and not partly checked: everything installed under it goes.
			if _manage and not item.is_checked(0) and not item.is_indeterminate(0):
				item.set_text(1, tr("Will be removed"))
				item.set_custom_color(1, get_theme_color("warning_color", "Editor"))
			else:
				item.set_text(1, tr("Installed"))
			item.set_tooltip_text(1, ExportTemplates.version_dir(_folder))
		ItemState.ABSENT:
			_set_checked(item, false)
			item.set_custom_color(0, get_theme_color("disabled_font_color", "Editor"))
			item.set_text(1, "")
			item.set_tooltip_text(0, tr("Not in the export templates of this build."))
	return state


func _file_state(file: String) -> ItemState:
	if file == ALL_FILES:
		var all_installed := "version.txt" in _installed
		if all_installed and _index != null:
			for path in _index.files():
				all_installed = all_installed and path in _installed
		return ItemState.INSTALLED if all_installed else ItemState.AVAILABLE
	if file in _installed:
		return ItemState.INSTALLED
	if _index != null and _index.entry_of(file) == null:
		return ItemState.ABSENT
	return ItemState.AVAILABLE


## Whether the user may check or uncheck an item of [param state]: templates to
## install, and in manage mode the installed ones too.
func _is_editable(state: ItemState) -> bool:
	return state == ItemState.AVAILABLE or (_manage and state == ItemState.INSTALLED)


## Compressed bytes of the files under [param item] that can be installed.
func _available_size(item: TreeItem) -> int:
	if _index == null:
		return 0
	var file := item.get_metadata(0) as String
	if file == ALL_FILES:
		return _files_size(_index.files())
	if not file.is_empty():
		return _index.compressed_size_of(file) if _state_of(item) == ItemState.AVAILABLE else 0
	var total := 0
	for child in item.get_children():
		total += _available_size(child)
	return total


func _files_size(files: PackedStringArray) -> int:
	var total := 0
	for file in files:
		total += _index.compressed_size_of(file)
	return total


func _state_of(item: TreeItem) -> ItemState:
	var state: ItemState = item.get_meta(_STATE_META, ItemState.AVAILABLE)
	return state


## Checks [param item] when all its children that can be changed are checked, unchecks
## it when none is, else shows it indeterminate. Templates the archive lacks, and
## installed ones outside manage mode, keep their own look and do not count.
func _update_check_from_children(item: TreeItem) -> void:
	var any_checked := false
	var any_unchecked := false
	for child in item.get_children():
		if not _is_editable(_state_of(child)):
			continue
		if child.is_indeterminate(0):
			any_checked = true
			any_unchecked = true
		elif child.is_checked(0):
			any_checked = true
		else:
			any_unchecked = true
	if any_checked and any_unchecked:
		item.set_indeterminate(0, true)
	else:
		_set_checked(item, any_checked)


## Checks or unchecks [param item], which may be indeterminate:
## [method TreeItem.set_checked] keeps that look when the check does not change.
func _set_checked(item: TreeItem, checked: bool) -> void:
	item.set_indeterminate(0, false)
	item.set_checked(0, checked)


## Like [method TreeItem.propagate_check], leaving templates that cannot change as
## they are.
func _on_item_edited() -> void:
	var edited := _tree.get_edited()
	_check_subtree(edited, edited.is_checked(0))
	_remember_checks(_tree.get_root())
	# Brings back the Installed and Will be removed notes of the items above.
	_update_states()
	selection_changed.emit()


func _check_subtree(item: TreeItem, checked: bool) -> void:
	if not _is_editable(_state_of(item)):
		return
	_set_checked(item, checked)
	for child in item.get_children():
		_check_subtree(child, checked)


## Updates the remembered checks from the file items under [param item] that can be
## changed. Files the tree does not show stay remembered.
func _remember_checks(item: TreeItem) -> void:
	var file := item.get_metadata(0) as String if item != _tree.get_root() else ""
	if file.is_empty():
		for child in item.get_children():
			_remember_checks(child)
		return
	match _state_of(item):
		ItemState.AVAILABLE:
			_checked_files = _listed(_checked_files, file, item.is_checked(0))
		ItemState.INSTALLED:
			if _manage:
				_removed_files = _listed(_removed_files, file, not item.is_checked(0))


## [param files] with [param file] added when [param listed], else without it.
static func _listed(files: PackedStringArray, file: String, listed: bool) -> PackedStringArray:
	var at := files.find(file)
	if listed and at == -1:
		files.append(file)
	elif not listed and at != -1:
		files.remove_at(at)
	return files


func _update_selection() -> void:
	_selected_files.clear()
	_unchecked_installed.clear()
	_collect_checks(_tree.get_root())


func _collect_checks(item: TreeItem) -> void:
	var file := item.get_metadata(0) as String if item != _tree.get_root() else ""
	if file.is_empty():
		for child in item.get_children():
			_collect_checks(child)
		return
	match _state_of(item):
		ItemState.AVAILABLE:
			if item.is_checked(0):
				_selected_files.append(file)
		ItemState.INSTALLED:
			if _manage and not item.is_checked(0):
				_unchecked_installed.append(file)


## Export templates to install, see [method ExportTemplatesPicker.selection].
class Selection:
	## The .tpz archive.
	var url: String
	## Its size from the release, or 0.
	var archive_size: int
	## Paths in the archive's templates folder.
	var files := PackedStringArray()
	## True to install every file of the archive.
	var all_files: bool


## What Apply changes in manage mode, see [method ExportTemplatesPicker.pending_changes].
class Changes:
	## Paths in the archive's templates folder to download.
	var add_files := PackedStringArray()
	## True to download every file of the archive (old archives).
	var all_files: bool
	## File names in the version folder to delete.
	var remove_files := PackedStringArray()
