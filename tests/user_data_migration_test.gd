extends Node


func _ready() -> void:
	var root := ProjectSettings.globalize_path(
		"user://migration-test-%s" % Time.get_ticks_msec()
	)
	var source_path := root.path_join("legacy/editors.cfg")
	var target_path := root.path_join("current/editors.cfg")
	_write_config(source_path, {
		"old-editor": {"name": "Godot 4.5", "favorite": true},
		"shared-editor": {"name": "Legacy name"},
	})
	_write_config(target_path, {
		"new-editor": {"name": "Godot 4.7"},
		"shared-editor": {"name": "Current name"},
	})

	assert(Config.merge_missing_config_entries(source_path, target_path) == OK)
	var merged := ConfigFile.new()
	assert(merged.load(target_path) == OK)
	assert(merged.get_value("old-editor", "name") == "Godot 4.5")
	assert(merged.get_value("old-editor", "favorite") == true)
	assert(merged.get_value("new-editor", "name") == "Godot 4.7")
	assert(merged.get_value("shared-editor", "name") == "Current name")
	var missing_target := root.path_join("empty-current/editors.cfg")
	assert(Config.merge_missing_config_entries(source_path, missing_target) == OK)
	assert(FileAccess.file_exists(missing_target))

	var nested_dir := root.path_join("remove/nested")
	DirAccess.make_dir_recursive_absolute(nested_dir)
	var file := FileAccess.open(nested_dir.path_join("editor.exe"), FileAccess.WRITE)
	assert(file != null)
	file.store_string("test")
	file.close()
	assert(edir.remove_recursive(root.path_join("remove")) == OK)
	assert(not DirAccess.dir_exists_absolute(root.path_join("remove")))
	assert(edir.remove_recursive(root) == OK)
	get_tree().quit()


func _write_config(path: String, sections: Dictionary) -> void:
	var config := ConfigFile.new()
	for section: String in sections:
		var values := sections[section] as Dictionary
		for key: String in values:
			config.set_value(section, key, values[key])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert(config.save(path) == OK)
