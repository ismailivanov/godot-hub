extends Node


var _failures := 0


func _ready() -> void:
	_test_quote_desktop_exec()
	if OS.has_feature("linux"):
		_test_load_rewrites_unquoted_exec()
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Desktop entry tests passed.")
	get_tree().quit()


func _test_quote_desktop_exec() -> void:
	_check_equal(LocalEditors.quote_desktop_exec("/opt/godot/godot"), '"/opt/godot/godot"')
	_check_equal(
		LocalEditors.quote_desktop_exec("/home/u/Godot Hub/versions/godot"),
		'"/home/u/Godot Hub/versions/godot"',
	)
	# Expected values are the file contents: \\ stands for one backslash.
	_check_equal(LocalEditors.quote_desktop_exec("/a/100%/b"), '"/a/100%%/b"')
	_check_equal(LocalEditors.quote_desktop_exec("/a/$HOME/b"), '"/a/\\\\$HOME/b"')
	_check_equal(LocalEditors.quote_desktop_exec("/a/`b`"), '"/a/\\\\`b\\\\`"')
	_check_equal(LocalEditors.quote_desktop_exec('/a/"b"'), '"/a/\\\\"b\\\\""')
	_check_equal(LocalEditors.quote_desktop_exec("/a\\b"), '"/a\\\\\\\\b"')


func _test_load_rewrites_unquoted_exec() -> void:
	var root := ProjectSettings.globalize_path(
		"user://desktop-entry-test-%s" % Time.get_ticks_msec()
	)
	var old_path := root.path_join("Godot Hub/versions/Godot_v4.3-stable_linux.x86_64")
	var current_path := root.path_join("versions/Godot_v4.4-stable_linux.x86_64")
	var cfg_path := root.path_join("editors.cfg")
	var cfg := ConfigFile.new()
	cfg.set_value(old_path, "name", "Godot v4.3 stable")
	cfg.set_value(current_path, "name", "Godot v4.4 stable")
	DirAccess.make_dir_recursive_absolute(root)
	_check(cfg.save(cfg_path) == OK, "Could not write the test editors.cfg")
	# Desktop entries live under $HOME, so keep them inside the temp root.
	var old_home := OS.get_environment("HOME")
	OS.set_environment("HOME", root)
	# Older releases wrote the Exec path unquoted.
	var old_entry := _desktop_path(old_path)
	_write(old_entry, "[Desktop Entry]\nName=Godot v4.3 stable\nExec=%s\n" % old_path)
	var current_entry := _desktop_path(current_path)
	var current_content := "[Desktop Entry]\nName=Mine\nExec=\"%s\"\n" % current_path
	_write(current_entry, current_content)

	var editors := LocalEditors.List.new(cfg_path)
	_check(editors.load() == OK, "Could not load the test editors.cfg")
	var old_content := FileAccess.get_file_as_string(old_entry)
	_check(
		old_content.contains("\nExec=\"%s\"\n" % old_path),
		"Expected the unquoted Exec path to be rewritten, got:\n%s" % old_content,
	)
	_check_equal(FileAccess.get_file_as_string(current_entry), current_content)

	for editor: LocalEditors.Item in editors.all():
		editors.erase(editor.path)
	editors.cleanup()
	_check(not FileAccess.file_exists(old_entry), "Expected the desktop entry to be removed")
	OS.set_environment("HOME", old_home)
	_check(edir.remove_recursive(root) == OK, "Could not remove the test directory")


func _desktop_path(editor_path: String) -> String:
	return OS.get_environment("HOME").path_join(
		".local/share/applications/godots-editor-%s.desktop" % editor_path.md5_text()
	)


func _write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Could not write %s" % path)
	if file:
		file.store_string(content)
		file.close()


func _check_equal(actual: String, expected: String) -> void:
	_check(actual == expected, "Expected '%s', got '%s'" % [expected, actual])


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
