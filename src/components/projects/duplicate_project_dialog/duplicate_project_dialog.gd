class_name DuplicateProjectDialog
extends "res://src/components/projects/install_project_dialog/install_project_dialog.gd"
## Dialog for duplicating existing projects.


## Emitted when duplicated.
signal duplicated(path: String, callback: Callable)

@onready var _rename_check_box: CheckBox = %RenameCheckBox

var _cache_should_rename := Cache.smart_value(self, "rename_duple", true)
var _project: Projects.Item
var _copy_thread: Thread


func _ready() -> void:
	super._ready()
	_rename_check_box.button_pressed = _cache_should_rename.ret(false)
	get_ok_button().text = tr("Duplicate")
	dialog_hide_on_ok = false

	visibility_changed.connect(func() -> void:
		if not visible:
			_project = null
	)

	_successfully_confirmed.connect(func() -> void:
		var final_project_name := _project_name_edit.text.strip_edges()
		var project_dir := _project_path_line_edit.text.strip_edges()
		var source_project := _project

		var err := 0
		if OS.has_feature("macos") or OS.has_feature("linux"):
			err = await _execute_in_thread(
				"cp", ["-r", _project.path.get_base_dir().path_join("."), project_dir]
			)
		elif OS.has_feature("windows"):
			err = await _execute_in_thread(
				"powershell.exe", 
				[
					"-command",
					"\"Copy-Item -Path '%s' -Destination '%s' -Recurse\"" % [ 
						ProjectSettings.globalize_path(_project.path.get_base_dir().path_join("*")), 
						ProjectSettings.globalize_path(project_dir)
					]
				]
			)
		# The dialog stays usable during the copy. If it was cancelled or opened for
		# another project meanwhile, it keeps that state and the copy only gets
		# offered for import.
		var is_same_dialog := _project == source_project
		if not is_same_dialog:
			_validate()
		if err != 0:
			if is_same_dialog:
				error(tr("Error. Code: %s" % err))
			return

		var project_configs := utils.find_project_godot_files(project_dir)
		if len(project_configs) == 0:
			if is_same_dialog:
				error(tr("No project.godot found."))
			return
		
		_cache_should_rename.put(_rename_check_box.button_pressed)
		if is_same_dialog:
			hide()
		
		var project_file_path := project_configs[0]
		duplicated.emit(
			project_file_path.path,
			func(imported_project: Projects.Item, projects: Projects.List) -> void:
				if _rename_check_box.button_pressed:
					imported_project.name = final_project_name
					imported_project.emit_internals_changed()
					projects.save()
		)
	)


func _on_raise(args: Variant = null) -> void:
	_project = args as Projects.Item
	title = "Duplicate Project: %s" % _project.name


func _validate() -> void:
	# Focus changes and edits validate again, which must not allow a second copy.
	# The target is being filled on purpose, so checking it would only report
	# that it is not empty.
	if _copy_thread:
		get_ok_button().disabled = true
		return
	super._validate()


## Runs a copy command on a thread, since copying a big project takes long enough
## to freeze the UI.
func _execute_in_thread(path: String, args: PackedStringArray) -> int:
	get_ok_button().disabled = true
	_set_message(tr("Copying..."), "warning")
	_copy_thread = Thread.new()
	_copy_thread.start(func() -> int: return OS.execute(path, args))
	while _copy_thread.is_alive():
		await get_tree().process_frame
	var err: int = _copy_thread.wait_to_finish()
	_copy_thread = null
	return err
