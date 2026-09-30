extends Node


const VERSIONS := "/home/user/.local/share/godot/app_userdata/GodotHub/versions"
const DEV_PATH := VERSIONS + "/Godot_v4_8-dev6_linux_x86_64/Godot_v4.8-dev6_linux.x86_64"
const MONO_PATH := (
	VERSIONS + "/Godot_v4_8-dev6_mono_linux_x86_64-e7b5af12"
	+ "/Godot_v4.8-dev6_mono_linux_x86_64/Godot_v4.8-dev6_mono_linux.x86_64"
)

var _failures := 0


func _ready() -> void:
	_test_guess_download_names()
	_test_legacy_guess_is_frozen()
	_test_repaired_guessed_name()
	_test_repaired_guessed_version_hint()
	_test_load_repairs_guessed_names()
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Editor name tests passed.")
	get_tree().quit()


# The full guess_editor_name matrix is in tests/cases/guess_editor_name_test.gd.
func _test_guess_download_names() -> void:
	# remote_editors.gd strips ".zip" before guessing.
	_check_equal(utils.guess_editor_name("Godot_v4.8-dev6_linux.x86_64"), "Godot v4.8 dev6")
	_check_equal(
		utils.guess_editor_name("Godot_v4.8-dev6_mono_linux_x86_64"), "Godot v4.8 dev6 mono"
	)


func _test_legacy_guess_is_frozen() -> void:
	# These are the names older releases stored in editors.cfg.
	_check_equal(utils.legacy_guess_editor_name("Godot_v4.8-dev6_linux.x86_64"), "Godot v4.8")
	_check_equal(utils.legacy_guess_editor_name("Godot_v4.8-dev6_mono_linux_x86_64"), "Godot_v4")
	_check_equal(
		utils.legacy_guess_editor_name("Godot_v4.7.2-stable_mono_linux_x86_64"), "Godot v4.7"
	)
	_check_equal(
		utils.legacy_guess_editor_name("/home/user/Downloads/Godot_v4.8-dev6_mono_linux_x86_64"),
		"/home/user/Downloads/Godot_v4",
	)


func _test_repaired_guessed_name() -> void:
	_check_equal(LocalEditors.repaired_guessed_name(DEV_PATH, "Godot v4.8"), "Godot v4.8 dev6")
	_check_equal(
		LocalEditors.repaired_guessed_name(MONO_PATH, "Godot_v4"), "Godot v4.8 dev6 mono"
	)
	_check_equal(
		LocalEditors.repaired_guessed_name(
			VERSIONS.path_join(
				"Godot_v4_7_2-stable_mono_linux_x86_64/Godot_v4.7.2-stable_mono_linux_x86_64"
				+ "/Godot_v4.7.2-stable_mono_linux.x86_64"
			),
			"Godot v4.7",
		),
		"Godot v4.7.2 stable mono",
	)
	# Drag and drop named the editor after the full path of the zip.
	_check_equal(
		LocalEditors.repaired_guessed_name(
			VERSIONS.path_join(
				"Godot_v4.8-dev6_mono_linux_x86_64/Godot_v4.8-dev6_mono_linux_x86_64"
				+ "/Godot_v4.8-dev6_mono_linux.x86_64"
			),
			"/home/user/Downloads/Godot_v4",
		),
		"Godot v4.8 dev6 mono",
	)
	_check_equal(
		LocalEditors.repaired_guessed_name(
			"C:/Users/user/AppData/Roaming/Godot/app_userdata/GodotHub/versions"
			+ "/Godot_v4.5-stable_mono_win64/Godot_v4.5-stable_mono_win64"
			+ "/Godot_v4.5-stable_mono_win64.exe",
			"C:/Users/user/Downloads/Godot_v4",
		),
		"Godot v4.5 stable mono",
	)

	# Correct names and names chosen by the user stay as they are.
	_check_equal(
		LocalEditors.repaired_guessed_name(
			VERSIONS.path_join(
				"Godot_v4_7_2-stable_linux_x86_64/Godot_v4.7.2-stable_linux.x86_64"
			),
			"Godot v4.7.2 stable",
		),
		"",
	)
	_check_equal(LocalEditors.repaired_guessed_name(DEV_PATH, "My dev build"), "")
	_check_equal(
		LocalEditors.repaired_guessed_name(
			"/home/user/Apps/Godot 4.3/Godot_v4.3-stable_linux.x86_64", "Godot 4"
		),
		"",
	)
	_check_equal(
		LocalEditors.repaired_guessed_name(
			"/home/user/Apps/Godot v4.3/Godot_v4.3-stable_linux.x86_64", "Godot v4"
		),
		"",
	)
	_check_equal(
		LocalEditors.repaired_guessed_name(
			"/home/user/Apps/godot-4.2.1/Godot_v4.2.1-stable_linux.x86_64", "Godot v4.2"
		),
		"",
	)
	_check_equal(
		LocalEditors.repaired_guessed_name(
			"/home/user/Apps/Godot v4.3-mono/godot.linuxbsd.editor.x86_64", "Godot v4"
		),
		"",
	)
	_check_equal(LocalEditors.repaired_guessed_name("/opt/godot-3.5/godot", "godot-3"), "")
	_check_equal(LocalEditors.repaired_guessed_name("/usr/bin/godot", "godot"), "")
	_check_equal(
		LocalEditors.repaired_guessed_name(
			VERSIONS.path_join("Godot_v4_8-dev6_macos_universal/Godot.app"), "Godot v4.8"
		),
		"",
	)


func _test_repaired_guessed_version_hint() -> void:
	# The rename dialog saves the hint it derived from the old name.
	_check_equal(LocalEditors.repaired_guessed_version_hint(MONO_PATH, "_v4"), "v4.8-dev6-mono")
	_check_equal(LocalEditors.repaired_guessed_version_hint(DEV_PATH, "v4.8"), "v4.8-dev6")
	_check_equal(
		LocalEditors.repaired_guessed_version_hint(MONO_PATH, "/home/user/downloads/_v4"),
		"v4.8-dev6-mono",
	)
	_check_equal(LocalEditors.repaired_guessed_version_hint(MONO_PATH, "4.8-dev6-mono"), "")
	_check_equal(LocalEditors.repaired_guessed_version_hint(DEV_PATH, "4.8-dev6"), "")
	_check_equal(
		LocalEditors.repaired_guessed_version_hint(
			"/home/user/Apps/Godot v4.3/Godot_v4.3-stable_linux.x86_64", "v4"
		),
		"",
	)


func _test_load_repairs_guessed_names() -> void:
	var root := ProjectSettings.globalize_path(
		"user://editor-name-test-%s" % Time.get_ticks_msec()
	)
	var cfg_path := root.path_join("editors.cfg")
	var mono_dir := "Godot_v4.8-dev6_mono_linux_x86_64/Godot_v4.8-dev6_mono_linux.x86_64"
	var dev_path := root.path_join("Godot_v4_8-dev6_linux_x86_64/Godot_v4.8-dev6_linux.x86_64")
	var mono_path := root.path_join("download").path_join(mono_dir)
	var renamed_path := root.path_join("renamed").path_join(mono_dir)
	var typed_path := root.path_join("typed").path_join(mono_dir)
	var chosen_path := root.path_join("chosen").path_join(mono_dir)
	var hinted_path := root.path_join("hinted/Godot_v4.8-dev6_linux.x86_64")
	var stable_path := root.path_join(
		"Godot_v4_7_2-stable_linux_x86_64/Godot_v4.7.2-stable_linux.x86_64"
	)
	var cfg := ConfigFile.new()
	cfg.set_value(dev_path, "name", "Godot v4.8")
	cfg.set_value(mono_path, "name", "Godot_v4")
	# The rename dialog saved the hint it showed, with or without a new name.
	cfg.set_value(renamed_path, "name", "Godot_v4")
	cfg.set_value(renamed_path, "version_hint", "_v4")
	cfg.set_value(typed_path, "name", "My Mono build")
	cfg.set_value(typed_path, "version_hint", "_v4")
	# A hint the user set means the name was chosen too, even an old guess.
	cfg.set_value(chosen_path, "name", "Godot_v4")
	cfg.set_value(chosen_path, "version_hint", "4.8-dev6-mono")
	cfg.set_value(hinted_path, "name", "Godot v4.8")
	cfg.set_value(hinted_path, "version_hint", "4.8-dev6")
	cfg.set_value(stable_path, "name", "Godot v4.7.2 stable")
	DirAccess.make_dir_recursive_absolute(root)
	_check(cfg.save(cfg_path) == OK, "Could not write the test editors.cfg")

	var editors := LocalEditors.List.new(cfg_path)
	_check(editors.load() == OK, "Could not load the test editors.cfg")
	_check_editor(editors, dev_path, "Godot v4.8 dev6", "v4.8-dev6")
	_check_editor(editors, mono_path, "Godot v4.8 dev6 mono", "v4.8-dev6-mono")
	_check_editor(editors, renamed_path, "Godot v4.8 dev6 mono", "v4.8-dev6-mono")
	_check_editor(editors, typed_path, "My Mono build", "v4.8-dev6-mono")
	_check_editor(editors, chosen_path, "Godot_v4", "4.8-dev6-mono")
	_check_editor(editors, hinted_path, "Godot v4.8", "4.8-dev6")
	_check_editor(editors, stable_path, "Godot v4.7.2 stable", "v4.7.2-stable")

	var saved := ConfigFile.new()
	_check(saved.load(cfg_path) == OK, "Could not reload the test editors.cfg")
	_check_equal(str(saved.get_value(mono_path, "name", "")), "Godot v4.8 dev6 mono")
	_check(
		not saved.has_section_key(mono_path, "version_hint"),
		"Expected the repair to leave version_hint derived from the name",
	)
	_check_equal(str(saved.get_value(typed_path, "version_hint", "")), "v4.8-dev6-mono")

	for editor: LocalEditors.Item in editors.all():
		editors.erase(editor.path)
	editors.cleanup()
	_check(edir.remove_recursive(root) == OK, "Could not remove the test directory")


func _check_editor(
	editors: LocalEditors.List, editor_path: String, expected_name: String, expected_hint: String
) -> void:
	if not editors.has(editor_path):
		_check(false, "Missing editor %s" % editor_path)
		return
	var editor := editors.retrieve(editor_path)
	_check_equal(editor.name, expected_name)
	_check_equal(editor.version_hint, expected_hint)


func _check_equal(actual: String, expected: String) -> void:
	_check(actual == expected, "Expected '%s', got '%s'" % [expected, actual])


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
