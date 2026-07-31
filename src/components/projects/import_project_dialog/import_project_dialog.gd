class_name ImportProjectDialog
extends ConfirmationDialog
## Dialog for importing existing Godot projects.


## Emitted when a project is imported.
signal imported(project_path: String, editor_path: String, and_edit: bool, callback: Variant)

var _editor_options: Array[Dictionary] = []
var _callback: Variant
var _browse_last_dir: String = ""

@onready var _browse_project_path_button: Button = %BrowseProjectPathButton
@onready var _browse_project_path_dialog: FileDialog = $BrowseProjectPathDialog
@onready var _project_path_edit: LineEdit = %ProjectPathEdit
@onready var _editors_option_button: OptionButton = $VBoxContainer/HBoxContainer2/EditorsOptionButton
@onready var _version_hint_value: Label = %VersionHintValue
@onready var _version_hint_container: HBoxContainer = %VersionHintContainer


func _ready() -> void:
	min_size = Vector2i(300, 0) * Config.EDSCALE
	set_process(false)
	_update_ok_button_available()
	_browse_project_path_button.pressed.connect(func() -> void:
		if _project_path_edit.text.is_empty():
			_browse_project_path_dialog.current_dir = ProjectSettings.globalize_path(
				Config.DEFAULT_PROJECTS_PATH.ret() as String
			)
		else:
			_browse_project_path_dialog.current_path = _project_path_edit.text
		_browse_project_path_dialog.popup_centered_ratio(0.5)
	)
	_browse_project_path_button.icon = get_theme_icon("Load", "EditorIcons")
	_browse_project_path_dialog.file_selected.connect(func(path: String) -> void:
		_project_path_edit.text = path
		_update_ok_button_available()
		_sort_options()
	)
	_browse_project_path_dialog.visibility_changed.connect(func() -> void:
		var open: bool = _browse_project_path_dialog.visible
		set_process(open)
		if open:
			_browse_last_dir = _browse_project_path_dialog.current_dir
			_fix_file_dialog_list_selection.call_deferred()
	)
	_editors_option_button.item_selected.connect(func(_arg: int) -> void:
		_update_ok_button_available()
	)
	_project_path_edit.text_changed.connect(func(_arg: String) -> void:
		_update_ok_button_available()
		_sort_options()
	)

	visibility_changed.connect(func() -> void:
		if not visible:
			_callback = null
	)

	custom_action.connect(func(action: String) -> void:
		if action == "just_import":
			var editor_path: String
			if _editors_option_button.selected != -1:
				editor_path = _editors_option_button.get_item_metadata(_editors_option_button.selected)
			imported.emit(
				_project_path_edit.text,
				editor_path,
				false,
				_callback
			)
			hide()
	)

	add_button(tr("Import"), false, "just_import")


func _process(_delta: float) -> void:
	if not _browse_project_path_dialog.visible:
		set_process(false)
		return
	var dir := _browse_project_path_dialog.current_dir
	if dir == _browse_last_dir:
		return
	_browse_last_dir = dir
	# FileDialog keeps a stale selection after folder entry. First file click is ignored.
	_fix_file_dialog_list_selection.call_deferred()


func _fix_file_dialog_list_selection() -> void:
	if not is_instance_valid(_browse_project_path_dialog):
		return
	for node: Node in _browse_project_path_dialog.find_children("*", "ItemList", true, false):
		var list := node as ItemList
		if not list:
			continue
		list.deselect_all()
		if list.item_count > 0:
			list.ensure_current_is_visible()


func init(project_path: String, editor_options: Array[Dictionary], callback: Variant = null) -> void:
	_callback = callback
	_editor_options = editor_options
	_set_editor_options(editor_options)
	_project_path_edit.clear()
	_project_path_edit.text = project_path
	_update_ok_button_available()
	_sort_options()


func _set_editor_options(options: Array[Dictionary]) -> void:
	_editors_option_button.clear()
	var sorted_options := options.duplicate()
	sorted_options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _editor_option_sort_before(a, b)
	)
	for idx: int in range(len(sorted_options)):
		var opt: Dictionary = sorted_options[idx]
		_editors_option_button.add_item(opt.label as String)
		_editors_option_button.set_item_metadata(idx, opt.path)
	_editor_options = sorted_options


static func _editor_option_sort_before(a: Dictionary, b: Dictionary) -> bool:
	var va := VersionHint.version_or_nothing(str(a.get("version_hint", a.get("label", ""))))
	var vb := VersionHint.version_or_nothing(str(b.get("version_hint", b.get("label", ""))))
	var cmp := VersionComparison.compare(va, vb)
	if cmp != 0:
		return cmp > 0
	return (a.label as String).naturalcasecmp_to(b.label as String) < 0


func _on_confirmed() -> void:
	imported.emit(
		_project_path_edit.text,
		_editors_option_button.get_item_metadata(_editors_option_button.selected),
		true,
		_callback
	)


func _update_ok_button_available() -> void:
	get_ok_button().disabled = (
		_editors_option_button.selected == -1
		or _project_path_edit.text.get_extension() != "godot"
	)


func _sort_options() -> void:
	if _project_path_edit.text.get_extension() == "godot":
		var cfg := Projects.ExternalProjectInfo.new(_project_path_edit.text)
		cfg.load(false)
		if cfg.has_version_hint:
			_version_hint_value.text = cfg.version_hint
			_version_hint_container.show()
		else:
			_version_hint_container.hide()
		_set_editor_options(_editor_options)
	else:
		_version_hint_container.hide()
