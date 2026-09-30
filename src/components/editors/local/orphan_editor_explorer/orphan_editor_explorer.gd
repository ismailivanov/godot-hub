class_name OrphanEditorExplorerWindow
extends ConfirmationDialog
## Window for exploring and managing orphan editor installations.


@onready var _tree: Tree = $VBoxContainer/Tree

var _local_editors: LocalEditors.List
var _versions_abs_path: String


func _ready() -> void:
	confirmed.connect(func() -> void:
		var selected_dirs: Array[String]
		for child in _tree.get_root().get_children():
			if child.get_cell_mode(0) == TreeItem.CELL_MODE_CHECK and child.is_checked(0):
				if child.has_meta("abs_path"):
					selected_dirs.append(child.get_meta("abs_path"))
		
		var delete_confirm := ConfirmationDialogAutoFree.new()
		delete_confirm.dialog_text = tr("Permanently delete %d item(s)? (No undo!)") % len(selected_dirs)
		delete_confirm.confirmed.connect(func() -> void:
			var failed_dirs := PackedStringArray()
			for dir in selected_dirs:
				if edir.remove_recursive(dir) != OK:
					failed_dirs.append(dir)
			if failed_dirs.is_empty():
				hide()
				return
			# Stay open on what is left and say what could not be deleted.
			before_popup()
			_show_error(tr("Could not delete:") + "\n" + "\n".join(failed_dirs))
		)
		add_child(delete_confirm)
		delete_confirm.popup_centered()
	)


func init(local_editors: LocalEditors.List, versions_abs_path: String) -> void:
	_local_editors = local_editors
	_versions_abs_path = versions_abs_path


func before_popup() -> void:
	_tree.clear()
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_MULTI
	
	var root := _tree.create_item()
	for orphan_dir in self._get_orphan_dirs():
		var item := _tree.create_item(root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_text(0, orphan_dir.replace(ProjectSettings.globalize_path(_versions_abs_path), " "))
		item.set_editable(0, true)
		item.set_meta("abs_path", orphan_dir)


func _get_orphan_dirs() -> Array[String]:
	var all_dirs := DirAccess.get_directories_at(_versions_abs_path)
	var editor_dirs := _local_editors.all().map(func(x: LocalEditors.Item) -> String: return _map_path(x.path))
	var orphan_dirs: Array[String]
	var is_orphan := func(dir: String) -> bool:
		return len(editor_dirs.filter(func(x: String) -> bool: return x.begins_with(dir))) == 0
	for dir in all_dirs:
		if (dir.ends_with(".app") or dir.ends_with(".app/")) and OS.has_feature("macos"):
			continue
		var abs_dir_path := ProjectSettings.globalize_path(_versions_abs_path.path_join(dir))
		if is_orphan.call(_map_path(abs_dir_path) + "/"):
			orphan_dirs.append(abs_dir_path)
	return orphan_dirs


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


func _map_path(path: String) -> String:
	if OS.has_feature("linux"):
		return path
	else:
		return path.to_lower()
