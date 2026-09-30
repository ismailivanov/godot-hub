extends Node


var _failures := 0
var _root := ""
var _default_icon: Texture2D


func _ready() -> void:
	_root = ProjectSettings.globalize_path("user://project-icon-test-%s" % Time.get_ticks_msec())
	DirAccess.make_dir_recursive_absolute(_root)
	_default_icon = ImageTexture.create_from_image(
		Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	)
	_test_res_icon_loads_from_project_folder()
	_test_res_icon_never_loads_hub_files()
	_test_uid_icon()
	_check(edir.remove_recursive(_root) == OK, "Could not remove the test directory")
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Project icon tests passed.")
	get_tree().quit()


func _test_res_icon_loads_from_project_folder() -> void:
	var project_dir := _make_project("res_icon", "res://art/project_icon.png")
	_write_png(project_dir.path_join("art/project_icon.png"))
	var icon := _load_icon(project_dir)
	_check(icon != _default_icon, "Expected the project's res:// icon to be loaded")
	_check(icon.get_size() == _default_icon.get_size(), "Expected the icon resized to default")


func _test_res_icon_never_loads_hub_files() -> void:
	# The Hub has this file in its own res://, the project does not.
	var project_dir := _make_project("hub_path", "res://assets/logo/logo.svg")
	_check(_load_icon(project_dir) == _default_icon, "Expected the default icon, not the Hub's")


func _test_uid_icon() -> void:
	var uid := ResourceUID.create_id()
	var resolved_dir := _make_project("uid_icon", ResourceUID.id_to_text(uid))
	_write_png(resolved_dir.path_join("uid_icon.png"))
	_write_uid_cache(resolved_dir, uid, "res://uid_icon.png")
	_check(_load_icon(resolved_dir) != _default_icon, "Expected the uid:// icon to be loaded")

	# No uid_cache.bin: this crashed release builds before f6e2825.
	var unresolved_dir := _make_project("uid_missing", ResourceUID.id_to_text(uid))
	_check(
		_load_icon(unresolved_dir) == _default_icon,
		"Expected the default icon for an unresolved uid://",
	)


func _make_project(dir_name: String, icon_path: String) -> String:
	var project_dir := _root.path_join(dir_name)
	DirAccess.make_dir_recursive_absolute(project_dir)
	var cfg := ConfigFile.new()
	cfg.set_value("application", "config/name", dir_name)
	cfg.set_value("application", "config/icon", icon_path)
	_check(cfg.save(project_dir.path_join("project.godot")) == OK, "Could not write project.godot")
	return project_dir


func _load_icon(project_dir: String) -> Texture2D:
	var info := Projects.ExternalProjectInfo.new(
		project_dir.path_join("project.godot"), _default_icon
	)
	info.load()
	return info.icon


func _write_png(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	_check(image.save_png(path) == OK, "Could not write %s" % path)


## Writes .godot/uid_cache.bin in the format ExternalProjectInfo reads.
func _write_uid_cache(project_dir: String, uid: int, res_path: String) -> void:
	var cache_path := project_dir.path_join(".godot/uid_cache.bin")
	DirAccess.make_dir_recursive_absolute(cache_path.get_base_dir())
	var file := FileAccess.open(cache_path, FileAccess.WRITE)
	_check(file != null, "Could not write %s" % cache_path)
	if file == null:
		return
	var path_bytes := res_path.to_utf8_buffer()
	file.store_32(1)
	file.store_64(uid)
	file.store_32(path_bytes.size())
	file.store_buffer(path_bytes)
	file.close()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
