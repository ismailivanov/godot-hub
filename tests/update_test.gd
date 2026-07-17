extends SceneTree

const VersionComparison = preload("res://src/services/version_comparison.gd")
const UpdatePlatform = preload("res://src/services/update_platform.gd")


func _init() -> void:
	assert(VersionComparison.is_newer("v1.2", "v1.1"))
	assert(VersionComparison.is_newer("v1.2.1", "v1.2"))
	assert(not VersionComparison.is_newer("v1.2", "v1.2.0"))
	assert(not VersionComparison.is_newer("v1.1", "v1.2"))
	_test_update_asset_selection()
	_test_appimage_detection()
	if OS.has_feature("linux"):
		_test_linux_file_replacement()
	quit()


func _test_update_asset_selection() -> void:
	assert(UpdatePlatform.asset_candidates("Linux", true) == ["GodotHub-x86_64.AppImage"])
	assert("GodotHub-Linux.zip" in UpdatePlatform.asset_candidates("Linux"))
	assert("GodotHub-Windows.zip" in UpdatePlatform.asset_candidates("Windows"))
	assert("GodotHub-macOS.zip" in UpdatePlatform.asset_candidates("macOS"))


func _test_appimage_detection() -> void:
	var fake_appimage := ProjectSettings.globalize_path(
		"user://GodotHub-test-%s.AppImage" % Time.get_ticks_msec()
	)
	_write_file(fake_appimage, "test")
	assert(UpdatePlatform.appimage_path(fake_appimage) == fake_appimage.simplify_path())
	assert(UpdatePlatform.appimage_path(fake_appimage + ".missing").is_empty())
	DirAccess.remove_absolute(fake_appimage)


func _test_linux_file_replacement() -> void:
	var test_root := ProjectSettings.globalize_path(
		"user://linux-update-test-%s" % Time.get_ticks_msec()
	)
	var update_dir := test_root.path_join("update")
	DirAccess.make_dir_recursive_absolute(update_dir)
	var current_exe := test_root.path_join("GodotHub.AppImage")
	var new_exe := update_dir.path_join("GodotHub-new.AppImage")
	var script_path := update_dir.path_join("apply-update.sh")
	var new_content := "#!/bin/sh\nexit 0\n# updated\n"
	_write_file(current_exe, "#!/bin/sh\nexit 0\n# old\n")
	_write_file(new_exe, new_content)
	_write_file(script_path, UpdatePlatform.LINUX_UPDATE_SCRIPT)
	OS.execute("chmod", ["+x", current_exe, new_exe, script_path])
	var output: Array = []
	var exit_code := OS.execute("sh", [
		script_path, "99999999", current_exe, new_exe, update_dir,
	], output, true)
	assert(exit_code == 0, "Linux update script failed: %s" % "\n".join(output))
	assert(FileAccess.get_file_as_string(current_exe) == new_content)
	assert(not FileAccess.file_exists(current_exe + ".old"))
	assert(not DirAccess.dir_exists_absolute(update_dir))
	DirAccess.remove_absolute(current_exe)
	DirAccess.remove_absolute(test_root)


func _write_file(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(content)
	file.close()
