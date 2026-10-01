extends Node
## Tests that [method RemoteEditorsControl.install_zip] installs a downloaded editor
## without asking: it finds the editor in the extracted archive, makes it runnable and
## reports it once, under the version its archive or its own file is named after. Only
## an archive without a single editor for this platform, without a version to name it
## by, or with an editor installed already asks which file it is and how to name it,
## and a broken archive says so.


const THEME_SOURCE := preload("res://theme/theme.gd")
const MODAL_SCENE := preload("res://src/components/editors/remote/remote_editors.tscn")
## Nothing listens there, so a started download fails without using the network.
const OFFLINE_URL := "http://127.0.0.1:9/"
const EDITOR_NAME := "Godot 4.8 dev6"

var _failures := 0
var _root := ""
var _modal: RemoteEditorsControl
var _download_items: Array[AssetDownload] = []
## What the modal reported, in order: [code]["installed", name, path][/code],
## [code]["on_install"][/code] and [code]["on_installed", name, path][/code].
var _calls: Array[Array] = []
## Folders of the versions folder the tests extracted to, removed at the end.
var _extracted: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not OS.get_name() in ["Linux", "Windows", "macOS"]:
		print("Editor auto install tests skipped on %s." % OS.get_name())
		get_tree().quit()
		return
	await _setup()
	await _test_standard_build()
	await _test_dotnet_build()
	await _test_download_row()
	await _test_name_from_editor()
	await _test_unversioned_editor()
	await _test_exported_game()
	await _test_installed_build()
	await _test_archive_without_editor()
	await _test_archive_with_two_editors()
	await _test_broken_archive()
	_test_direct_link_names()
	for folder in _extracted:
		edir.remove_recursive(folder)
	edir.remove_recursive(_root)
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Editor auto install tests passed.")
	get_tree().quit()


func _setup() -> void:
	_root = ProjectSettings.globalize_path(
		"user://editor-auto-install-test-%s" % Time.get_ticks_usec()
	)
	DirAccess.make_dir_recursive_absolute(_root)
	var root := get_tree().root
	# Popups become embedded subwindows, which headless runs can show.
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 800)

	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.theme = THEME_SOURCE.create_custom_theme(null)
	add_child(frame)
	var downloads := VBoxContainer.new()
	frame.add_child(downloads)
	# Added hidden like in GuiMain, above the page.
	_modal = MODAL_SCENE.instantiate() as RemoteEditorsControl
	frame.add_child(_modal)
	_modal.init(func(item: Control) -> void:
		_download_items.append(item as AssetDownload)
		downloads.add_child(item)
	)
	_modal.installed.connect(func(editor_name: String, path: String) -> void:
		_calls.append(["installed", editor_name, path])
	)
	await _wait_frames(2)


func _test_standard_build() -> void:
	var build := _standard_build()
	var folder := _new_folder("standard")
	_calls.clear()
	_modal.install_zip(
		_make_zip("standard.zip", build.files), folder, EDITOR_NAME, _on_install, _on_installed
	)
	await _wait_frames(2)
	_check_installed("Standard", EDITOR_NAME, _versions_path(folder).path_join(build.editor))


func _test_dotnet_build() -> void:
	var build := _dotnet_build()
	var folder := _new_folder("dotnet")
	_calls.clear()
	_modal.install_zip(
		_make_zip("dotnet.zip", build.files), folder, EDITOR_NAME, _on_install, _on_installed
	)
	await _wait_frames(2)
	_check_installed(".NET", EDITOR_NAME, _versions_path(folder).path_join(build.editor))


## A finished download installs on its own and its row goes away, like a
## download from the modal, the latest stable button or a project's missing editor.
func _test_download_row() -> void:
	var build := _standard_build()
	var file_name := build.download_name
	var zip_path := _make_zip("row.zip", build.files)
	_calls.clear()
	_modal.download_zip(OFFLINE_URL, file_name, Callable(), _on_installed)
	await _wait_frames(1)
	if _download_items.is_empty():
		_check(false, "Expected a download row")
		return
	var row := _download_items[-1]
	row.downloaded.emit(zip_path)
	await _wait_frames(2)
	var path := ""
	if _calls.size() == 2:
		path = str(_calls[0][2])
		_extracted.append(path.trim_suffix(build.editor).simplify_path())
	_check(
		path.begins_with(_versions_path("")) and path.ends_with("/" + build.editor),
		"The row's editor should be in the versions folder, got %s" % path,
	)
	var editor_name := utils.guess_editor_name(file_name.replace(".zip", ""))
	_check(
		_calls == [["installed", editor_name, path], ["on_installed", editor_name, path]],
		"The row should report the editor once, got %s" % [_calls],
	)
	_check(_install_dialogs().is_empty(), "A downloaded editor should install without a dialog")
	_check(not is_instance_valid(row), "The download row should go away once installed")
	_check_runnable(path)


## An archive whose name has no version, e.g. from a direct link that does not end with
## the archive's name, installs under the version in its editor's name. App bundles are
## named Godot.app whatever their version, so the user names those.
func _test_name_from_editor() -> void:
	for build_and_name: Array in [
		[_standard_build(), "Godot v4.8 dev6"],
		[_dotnet_build(), "Godot v4.8 dev6 mono"],
	]:
		var build := build_and_name[0] as Build
		var what := "Unnamed %s" % build.download_name
		var folder := _new_folder("unnamed")
		var path := _versions_path(folder).path_join(build.editor)
		_calls.clear()
		_modal.install_zip(
			_make_zip("unnamed.zip", build.files),
			folder,
			"custom_editor",
			_on_install,
			_on_installed,
		)
		await _wait_frames(2)
		if OS.get_name() != "macOS":
			_check_installed(what, build_and_name[1] as String, path)
			continue
		_check(_calls.is_empty(), "%s: nothing should be installed before asking" % what)
		var dialog := _single_dialog(what, "custom_editor", build.editor.get_file())
		if dialog != null:
			await _confirm(dialog)
			_check_installed(what, "custom_editor", path)


## A custom build in an archive without a version asks for the name, its file checked,
## and installs the way an editor found on its own is installed.
func _test_unversioned_editor() -> void:
	var build := _custom_build()
	var folder := _new_folder("custom")
	_calls.clear()
	_modal.install_zip(
		_make_zip("custom.zip", build.files), folder, "custom_editor", _on_install, _on_installed
	)
	await _wait_frames(2)
	_check(_calls.is_empty(), "A build without a version should not install before asking")
	var dialog := _single_dialog("Custom build", "custom_editor", build.editor.get_file())
	if dialog == null:
		return
	(dialog.get_node("%EditorNameEdit") as LineEdit).text = "My Godot"
	await _confirm(dialog)
	_check_installed("Custom build", "My Godot", _versions_path(folder).path_join(build.editor))


## A game exported for this platform is not installed as an editor without asking, even
## from an archive named like an editor.
func _test_exported_game() -> void:
	var build := _game_build()
	var folder := _new_folder("game")
	_calls.clear()
	_modal.install_zip(
		_make_zip("game.zip", build.files), folder, EDITOR_NAME, _on_install, _on_installed
	)
	await _wait_frames(2)
	_check(_calls.is_empty(), "A game should not be installed without asking")
	var dialog := _single_dialog("Game", EDITOR_NAME, build.editor.get_file())
	if dialog != null:
		await _cancel(dialog, folder)


## An editor of the same version and build is installed already, e.g. after the same
## download was started twice: another one installs only if the user wants it.
func _test_installed_build() -> void:
	var others: Array[LocalEditors.Item] = [
		_editor("Godot v4.8 dev6 mono", "/editors/dotnet", EditorEngineBrand.GODOT),
		_editor("Redot v4.8 dev6", "/editors/redot", EditorEngineBrand.REDOT),
		_editor("Godot v4.8 dev5", "/editors/dev5", EditorEngineBrand.GODOT),
	]
	_modal.set_installed_editors(others)
	var build := _standard_build()
	var folder := _new_folder("other-installed")
	_calls.clear()
	_modal.install_zip(
		_make_zip("other.zip", build.files), folder, EDITOR_NAME, _on_install, _on_installed
	)
	await _wait_frames(2)
	_check_installed(
		"Other builds installed", EDITOR_NAME, _versions_path(folder).path_join(build.editor)
	)

	var same := _editor("Godot v4.8 dev6", "/editors/standard", EditorEngineBrand.GODOT)
	var installed: Array[LocalEditors.Item] = [same]
	_modal.set_installed_editors(installed)
	folder = _new_folder("installed")
	_calls.clear()
	_modal.install_zip(
		_make_zip("same.zip", build.files), folder, EDITOR_NAME, _on_install, _on_installed
	)
	await _wait_frames(2)
	_check(_calls.is_empty(), "An installed build should not install again without asking")
	var dialog := _single_dialog("Installed build", EDITOR_NAME, build.editor.get_file())
	if dialog != null:
		await _cancel(dialog, folder)

	var none: Array[LocalEditors.Item] = []
	_modal.set_installed_editors(none)
	for editor: LocalEditors.Item in others + installed:
		editor.free()


func _test_archive_without_editor() -> void:
	var folder := _new_folder("no-editor")
	_calls.clear()
	_modal.install_zip(
		_make_zip("no_editor.zip", ["README.txt", "data/editor.pck"]),
		folder,
		"Custom",
		_on_install,
		_on_installed,
	)
	await _wait_frames(2)
	_check(_calls.is_empty(), "Nothing should be installed from an archive without an editor")
	var dialog := _single_dialog("No editor", "Custom", "")
	if dialog == null:
		return
	# None has the form of an editor, so any file may be it.
	var listed := _listed_files(dialog)
	listed.sort()
	_check(
		listed == PackedStringArray(["README.txt", "editor.pck"]),
		"Every file should be offered when none looks like an editor, got %s" % listed,
	)
	await _cancel(dialog, folder)


## Two builds that fit as well: the dialog asks, checking neither, and installs the one
## the user checks the way an editor found on its own is installed.
func _test_archive_with_two_editors() -> void:
	var build := _two_editors_build()
	var folder := _new_folder("two-editors")
	_calls.clear()
	_modal.install_zip(
		_make_zip("two_editors.zip", build.files), folder, EDITOR_NAME, _on_install, _on_installed
	)
	await _wait_frames(2)
	_check(_calls.is_empty(), "Nothing should be installed before the user picks a build")
	var dialog := _single_dialog("Two builds", EDITOR_NAME, "")
	if dialog == null:
		return
	var tree := dialog.get_node("%SelectExecFileTree") as Tree
	var pick: TreeItem = null
	for item in tree.get_root().get_children():
		if item.get_text(0) == build.editor.get_file():
			pick = item
	if pick == null:
		_check(false, "The dialog should list %s" % build.editor)
		return
	pick.set_checked(0, true)
	pick.select(0)
	await _confirm(dialog)
	_check_installed("Picked", EDITOR_NAME, _versions_path(folder).path_join(build.editor))


func _test_broken_archive() -> void:
	var zip_path := _root.path_join("broken.zip")
	var file := FileAccess.open(zip_path, FileAccess.WRITE)
	file.store_string("not a zip")
	file.close()
	var folder := _new_folder("broken")
	_calls.clear()
	_modal.install_zip(zip_path, folder, EDITOR_NAME, _on_install, _on_installed)
	await _wait_frames(2)
	_check(_calls.is_empty(), "A broken archive should install nothing")
	_check(_install_dialogs().is_empty(), "A broken archive should not ask for an editor")
	var errors: Array[AcceptDialog] = []
	for child in _modal.get_children():
		var dialog := child as AcceptDialog
		if dialog != null and dialog.dialog_text == "Error extracting archive.":
			errors.append(dialog)
	_check(errors.size() == 1, "A broken archive should say it could not be extracted")
	_check(
		not DirAccess.dir_exists_absolute(_versions_path(folder)),
		"A broken archive should leave no folder behind",
	)
	for dialog in errors:
		dialog.queue_free()
	await _wait_frames(1)


func _test_direct_link_names() -> void:
	var release := "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/"
	var linux := "Godot_v4.7.2-stable_linux.x86_64.zip"
	var mono := "Godot_v4.7.2-stable_mono_win64.zip"
	for link_and_name: Array in [
		[release + linux, linux],
		[" %s%s?raw=1#files " % [release, mono], mono],
		["https://example.com/Godot%20v4.7.2.zip", "Godot v4.7.2.zip"],
		["https://example.com/download?file=%s" % linux, "custom_editor.zip"],
		["https://example.com/", "custom_editor.zip"],
		["https://example.com/.zip", "custom_editor.zip"],
		["https://example.com/a%2Fb.zip", "custom_editor.zip"],
	]:
		var link := link_and_name[0] as String
		var file_name := link_and_name[1] as String
		var got := RemoteEditorsControl._direct_link_file_name(link)
		_check(
			got == file_name, "The link %s should download %s, got %s" % [link, file_name, got]
		)


## Checks that [param editor_name] at [param path] was installed once, in order, with
## no dialog, and can run.
func _check_installed(what: String, editor_name: String, path: String) -> void:
	_check(
		_calls == [
			["installed", editor_name, path],
			["on_install"],
			["on_installed", editor_name, path],
		],
		"%s: expected the editor %s reported once, got %s" % [what, path, _calls],
	)
	_check(
		path.is_absolute_path() and not path.begins_with("user://"),
		"%s: expected an absolute path, got %s" % [what, path],
	)
	_check(edir.path_is_valid(path), "%s: the editor should exist at %s" % [what, path])
	_check(_install_dialogs().is_empty(), "%s: no dialog should be left" % what)
	_check_runnable(path)


## Checks the execute permission the archive leaves out: ZIPPacker stores 644. Whoever
## may read the editor may run it.
func _check_runnable(path: String) -> void:
	if OS.get_name() == "Windows":
		return
	var binary := path.path_join("Contents/MacOS/Godot") if path.ends_with(".app") else path
	var permissions := FileAccess.get_unix_permissions(binary)
	var readable := permissions & (
		FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_READ_OTHER
	)
	var runnable := FileAccess.UNIX_EXECUTE_OWNER | (readable >> 2)
	_check(
		(permissions & runnable) == runnable,
		"%s should be executable, its permissions are %o" % [binary, permissions],
	)


func _on_install() -> void:
	_calls.append(["on_install"])


func _on_installed(editor_name: String, path: String) -> void:
	_calls.append(["on_installed", editor_name, path])


## Returns the one install dialog, after checking that it shows [param editor_name] and
## has only [param checked] checked (nothing when empty), or null when there is none.
func _single_dialog(
	what: String, editor_name: String, checked: String
) -> RemoteEditorInstallControl:
	var dialogs := _install_dialogs()
	_check(dialogs.size() == 1, "%s: expected a dialog asking for the editor" % what)
	if dialogs.size() != 1:
		return null
	var dialog := dialogs[0]
	_check(dialog.visible, "%s: the dialog should show" % what)
	var name_edit := dialog.get_node("%EditorNameEdit") as LineEdit
	_check(
		name_edit.text == editor_name,
		"%s: the dialog should offer the name %s, got %s" % [what, editor_name, name_edit.text],
	)
	var expected := PackedStringArray() if checked.is_empty() else PackedStringArray([checked])
	var tree := dialog.get_node("%SelectExecFileTree") as Tree
	var got := PackedStringArray()
	for item in tree.get_root().get_children():
		if item.is_checked(0):
			got.append(item.get_text(0))
	_check(got == expected, "%s: expected %s checked, got %s" % [what, expected, got])
	return dialog


func _listed_files(dialog: RemoteEditorInstallControl) -> PackedStringArray:
	var tree := dialog.get_node("%SelectExecFileTree") as Tree
	var result := PackedStringArray()
	for item in tree.get_root().get_children():
		result.append(item.get_text(0))
	return result


func _confirm(dialog: RemoteEditorInstallControl) -> void:
	await _wait_frames(1)
	dialog.get_ok_button().pressed.emit()
	await _wait_frames(2)


## Cancels [param dialog], checking that the files extracted to [param folder] go away.
func _cancel(dialog: RemoteEditorInstallControl, folder: String) -> void:
	dialog.get_cancel_button().pressed.emit()
	await _wait_frames(2)
	_check(not is_instance_valid(dialog), "Cancel should close the dialog")
	_check(
		not DirAccess.dir_exists_absolute(_versions_path(folder)),
		"Cancel should remove the extracted files",
	)
	_check(_calls.is_empty(), "Cancel should install nothing")


func _editor(editor_name: String, path: String, brand: String) -> LocalEditors.Item:
	var cfg := ConfigFile.new()
	cfg.set_value(path, "name", editor_name)
	cfg.set_value(path, "engine_brand", brand)
	return LocalEditors.Item.new(ConfigFileSection.new(path, IConfigFileLike.of_config(cfg)))


func _install_dialogs() -> Array[RemoteEditorInstallControl]:
	var result: Array[RemoteEditorInstallControl] = []
	for child in _modal.get_children():
		if child is RemoteEditorInstallControl and not child.is_queued_for_deletion():
			result.append(child as RemoteEditorInstallControl)
	return result


## A folder name in the versions folder for this run, removed at the end.
func _new_folder(what: String) -> String:
	var folder := "editor-auto-install-test-%s-%s" % [what, Time.get_ticks_usec()]
	_extracted.append(_versions_path(folder))
	return folder


func _versions_path(folder: String) -> String:
	var versions := ProjectSettings.globalize_path(Config.VERSIONS_PATH.ret() as String)
	return versions.path_join(folder).simplify_path()


func _make_zip(file_name: String, entries: Array[String]) -> String:
	var zip_path := _root.path_join(file_name)
	var packer := ZIPPacker.new()
	_check(packer.open(zip_path) == OK, "Could not create %s" % zip_path)
	for entry in entries:
		packer.start_file(entry)
		packer.write_file("#!/bin/sh\nexit 0\n".to_utf8_buffer())
		packer.close_file()
	packer.close()
	return zip_path


## The files of the Standard build download for this platform.
func _standard_build() -> Build:
	match OS.get_name():
		"Windows":
			return Build.new(
				"Godot_v4.8-dev6_win64.exe.zip",
				"Godot_v4.8-dev6_win64.exe",
				["Godot_v4.8-dev6_win64_console.exe", "Godot_v4.8-dev6_win64.exe"],
			)
		"macOS":
			return Build.new(
				"Godot_v4.8-dev6_macos.universal.zip",
				"Godot.app",
				["Godot.app/Contents/Info.plist", "Godot.app/Contents/MacOS/Godot"],
			)
	return Build.new(
		"Godot_v4.8-dev6_linux.x86_64.zip",
		"Godot_v4.8-dev6_linux.x86_64",
		["Godot_v4.8-dev6_linux.x86_64"],
	)


## The files of the .NET build download for this platform.
func _dotnet_build() -> Build:
	match OS.get_name():
		"Windows":
			var win := "Godot_v4.8-dev6_mono_win64/"
			return Build.new(
				"Godot_v4.8-dev6_mono_win64.zip",
				win + "Godot_v4.8-dev6_mono_win64.exe",
				[
					win + "Godot_v4.8-dev6_mono_win64_console.exe",
					win + "Godot_v4.8-dev6_mono_win64.exe",
					win + "GodotSharp/Api/Release/GodotSharp.dll",
				],
			)
		"macOS":
			return Build.new(
				"Godot_v4.8-dev6_mono_macos.universal.zip",
				"Godot_mono.app",
				[
					"Godot_mono.app/Contents/Info.plist",
					"Godot_mono.app/Contents/MacOS/Godot",
					"Godot_mono.app/Contents/Resources/GodotSharp/Api/Release/GodotSharp.dll",
				],
			)
	var linux := "Godot_v4.8-dev6_mono_linux_x86_64/"
	return Build.new(
		"Godot_v4.8-dev6_mono_linux_x86_64.zip",
		linux + "Godot_v4.8-dev6_mono_linux.x86_64",
		[
			linux + "Godot_v4.8-dev6_mono_linux.x86_64",
			linux + "GodotSharp/Api/Release/GodotSharp.dll",
			linux + "GodotSharp/Api/Release/GodotSharp.xml",
		],
	)


## A build made from source, named without a version.
func _custom_build() -> Build:
	match OS.get_name():
		"Windows":
			return Build.new(
				"custom.zip",
				"godot.windows.editor.x86_64.exe",
				["godot.windows.editor.x86_64.console.exe", "godot.windows.editor.x86_64.exe"],
			)
		"macOS":
			return Build.new(
				"custom.zip",
				"Godot.app",
				["Godot.app/Contents/Info.plist", "Godot.app/Contents/MacOS/Godot"],
			)
	return Build.new("custom.zip", "godot.linuxbsd.editor.x86_64", ["godot.linuxbsd.editor.x86_64"])


## A game exported for this platform.
func _game_build() -> Build:
	match OS.get_name():
		"Windows":
			return Build.new("game.zip", "MyGame.exe", ["MyGame.exe", "MyGame.pck"])
		"macOS":
			return Build.new(
				"game.zip",
				"MyGame.app",
				["MyGame.app/Contents/Info.plist", "MyGame.app/Contents/MacOS/MyGame"],
			)
	return Build.new("game.zip", "MyGame.x86_64", ["MyGame.x86_64", "MyGame.pck"])


## Two builds that fit this platform as well, the second one to pick.
func _two_editors_build() -> Build:
	match OS.get_name():
		"Windows":
			return Build.new(
				"two.zip",
				"Godot_v4.8-dev6_win32.exe",
				["Godot_v4.8-dev6_win64.exe", "Godot_v4.8-dev6_win32.exe"],
			)
		"macOS":
			return Build.new(
				"two.zip",
				"Godot_mono.app",
				["Godot.app/Contents/MacOS/Godot", "Godot_mono.app/Contents/MacOS/Godot"],
			)
	return Build.new(
		"two.zip",
		"Godot_v4.8-dev6_linux.arm64",
		["Godot_v4.8-dev6_linux.x86_64", "Godot_v4.8-dev6_linux.arm64"],
	)


func _wait_frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)


## An editor download: its file name, the editor in it and its files.
class Build:
	var download_name: String
	## Relative to the folder the archive is extracted to.
	var editor: String
	var files: Array[String] = []

	func _init(p_download_name: String, p_editor: String, p_files: Array[String]) -> void:
		download_name = p_download_name
		editor = p_editor
		files = p_files
