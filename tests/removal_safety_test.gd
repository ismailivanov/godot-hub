extends Node


const VERSIONS := "/home/user/.local/share/godot/app_userdata/GodotHub/versions"

var _failures := 0
var _root := ""


func _ready() -> void:
	_root = ProjectSettings.globalize_path(
		"user://removal-safety-test-%s" % Time.get_ticks_msec()
	)
	DirAccess.make_dir_recursive_absolute(_root)
	_test_remove_recursive_deletes_tree()
	_test_remove_recursive_reports_missing_path()
	_test_remove_recursive_keeps_nested_link_target()
	_test_remove_recursive_keeps_top_level_link_target()
	_test_list_recursive_skips_link_cycle()
	_test_managed_install_dir()
	_test_remove_empty_parents()
	_check(edir.remove_recursive(_root) == OK, "Could not remove the test directory")
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Removal safety tests passed.")
	get_tree().quit()


func _test_remove_recursive_deletes_tree() -> void:
	var tree := _root.path_join("tree")
	_write(tree.path_join("editor.x86_64"))
	_write(tree.path_join("._sc_"))
	_write(tree.path_join(".hidden/settings.tres"))
	_write(tree.path_join("sub/deeper/file.txt"))
	_check(edir.remove_recursive(tree) == OK, "Expected a normal tree to be removed")
	_check(not DirAccess.dir_exists_absolute(tree), "Expected the tree to be gone")

	# Callers also pass folders with a trailing slash.
	var slashed := _root.path_join("slashed")
	_write(slashed.path_join("file.txt"))
	_check(edir.remove_recursive(slashed + "/") == OK, "Expected a slashed path to be removed")
	_check(not DirAccess.dir_exists_absolute(slashed), "Expected the slashed tree to be gone")


func _test_remove_recursive_reports_missing_path() -> void:
	_check(
		edir.remove_recursive(_root.path_join("missing")) != OK,
		"Expected an error for a missing folder",
	)


func _test_remove_recursive_keeps_nested_link_target() -> void:
	var outside := _root.path_join("nested-outside")
	_write(outside.path_join("project.godot"))
	_write(outside.path_join("sub/file.txt"))
	var install := _root.path_join("nested-versions/Godot_v4_3-stable_linux_x86_64")
	_write(install.path_join("Godot_v4.3-stable_linux.x86_64"))
	_link(outside, install.path_join("editor_data"))

	_check(edir.remove_recursive(install) == OK, "Expected the install with a link to be removed")
	_check(not DirAccess.dir_exists_absolute(install), "Expected the install to be gone")
	_check(
		FileAccess.file_exists(outside.path_join("project.godot")),
		"Expected the nested link target's files to survive",
	)
	_check(
		FileAccess.file_exists(outside.path_join("sub/file.txt")),
		"Expected the nested link target's folders to survive",
	)


func _test_remove_recursive_keeps_top_level_link_target() -> void:
	var outside := _root.path_join("top-outside")
	_write(outside.path_join("src/main.cpp"))
	var versions := _root.path_join("top-versions")
	DirAccess.make_dir_recursive_absolute(versions)
	for link_name: String in ["my-build", "my-slashed-build"]:
		_link(outside, versions.path_join(link_name))

	_check(
		edir.remove_recursive(versions.path_join("my-build")) == OK,
		"Expected a linked folder to be unlinked",
	)
	# The Orphan Editors Explorer passes linked folders like this one.
	_check(
		edir.remove_recursive(versions.path_join("my-slashed-build") + "/") == OK,
		"Expected a slashed linked folder to be unlinked",
	)
	var versions_dir := DirAccess.open(versions)
	for link_name: String in ["my-build", "my-slashed-build"]:
		_check(not versions_dir.is_link(link_name), "Expected link %s to be gone" % link_name)
	_check(
		FileAccess.file_exists(outside.path_join("src/main.cpp")),
		"Expected the top-level link target's files to survive",
	)


func _test_list_recursive_skips_link_cycle() -> void:
	var scanned := _root.path_join("cycle")
	_write(scanned.path_join("a/Godot_v4.3-stable_linux.x86_64"))
	_link(scanned, scanned.path_join("a/loop"))

	var found := edir.list_recursive(scanned)
	var paths: Array[String] = []
	for result: edir.DirListResult in found:
		paths.append(result.path)
	paths.sort()
	var expected: Array[String] = [
		scanned.path_join("a"),
		scanned.path_join("a/Godot_v4.3-stable_linux.x86_64"),
		scanned.path_join("a/loop"),
	]
	_check(
		paths == expected,
		"Expected %d entries without entering the link, got %d" % [len(expected), len(paths)],
	)
	DirAccess.remove_absolute(scanned.path_join("a/loop"))


func _test_managed_install_dir() -> void:
	var mono_dir := VERSIONS.path_join(
		"Godot_v4_8-dev6_mono_linux_x86_64/Godot_v4.8-dev6_mono_linux_x86_64"
	)
	_check_equal(
		LocalEditors.install_dir_inside(mono_dir.path_join("Godot_v4.8-dev6.x86_64"), VERSIONS),
		mono_dir,
	)
	_check_equal(
		LocalEditors.install_dir_inside(
			VERSIONS.path_join("Godot_v4_7_2-stable_linux_x86_64/Godot_v4.7.2-stable_linux.x86_64"),
			VERSIONS + "/",
		),
		VERSIONS.path_join("Godot_v4_7_2-stable_linux_x86_64"),
	)
	_check_equal(
		LocalEditors.install_dir_inside(
			ProjectSettings.globalize_path("user://versions/Godot_v4/godot.x86_64"),
			"user://versions",
		),
		ProjectSettings.globalize_path("user://versions/Godot_v4"),
	)
	# Only folders strictly inside the versions folder are managed.
	_check_equal(LocalEditors.install_dir_inside("/opt/godot/godot.x86_64", VERSIONS), "")
	_check_equal(
		LocalEditors.install_dir_inside(VERSIONS + "2/Godot_v4/godot.x86_64", VERSIONS), ""
	)
	_check_equal(LocalEditors.install_dir_inside(VERSIONS.path_join("godot.x86_64"), VERSIONS), "")
	_check_equal(
		LocalEditors.install_dir_inside(VERSIONS.path_join("../outside/godot.x86_64"), VERSIONS),
		"",
	)
	if OS.has_feature("linux"):
		_check_equal(
			LocalEditors.install_dir_inside(
				VERSIONS.to_lower().path_join("Godot_v4/godot.x86_64"), VERSIONS
			),
			"",
		)


func _test_remove_empty_parents() -> void:
	var versions := _root.path_join("prune-versions")

	# Mono zips leave the zip folder empty once the editor folder is gone.
	var mono_dir := versions.path_join("Godot_v4_8-dev6_mono_linux_x86_64/Godot_v4.8-dev6_mono")
	DirAccess.make_dir_recursive_absolute(mono_dir)
	DirAccess.remove_absolute(mono_dir)
	# The versions_path setting is usually not globalized.
	var user_versions := "user://%s/prune-versions" % _root.get_file()
	LocalEditors.remove_empty_parents(mono_dir, user_versions)
	_check(
		not DirAccess.dir_exists_absolute(mono_dir.get_base_dir()),
		"Expected the empty zip folder to go",
	)
	_check(DirAccess.dir_exists_absolute(versions), "Expected the versions folder to stay")

	# A folder that still holds something stays.
	var group_dir := versions.path_join("group")
	_write(group_dir.path_join("4.3/Godot_v4.3-stable_linux.x86_64"))
	LocalEditors.remove_empty_parents(group_dir.path_join("4.2"), versions)
	_check(DirAccess.dir_exists_absolute(group_dir), "Expected the non-empty folder to stay")

	# A linked folder is never unlinked, even when its target is empty.
	for target_name: String in ["linked-full", "linked-empty"]:
		var target := _root.path_join(target_name)
		DirAccess.make_dir_recursive_absolute(target.path_join("4.2"))
		if target_name == "linked-full":
			_write(target.path_join("4.3/Godot_v4.3-stable_linux.x86_64"))
		var link := versions.path_join(target_name)
		_link(target, link)
		_check(edir.remove_recursive(link.path_join("4.2")) == OK, "Could not remove %s/4.2" % link)
		LocalEditors.remove_empty_parents(link.path_join("4.2"), versions)
		_check(
			DirAccess.open(versions).is_link(target_name),
			"Expected the linked folder %s to stay" % target_name,
		)
		DirAccess.remove_absolute(link)


func _write(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Could not write %s" % path)
	if file:
		file.store_string("x")
		file.close()


func _link(target: String, link: String) -> void:
	var dir := DirAccess.open(link.get_base_dir())
	_check(dir != null and dir.create_link(target, link) == OK, "Could not link %s" % link)


func _check_equal(actual: String, expected: String) -> void:
	_check(actual == expected, "Expected '%s', got '%s'" % [expected, actual])


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
