extends Node
## Offline tests of export templates in the Install Editor modal: the templates step
## (the tree and its checks, Standard and .NET archives, installed and missing
## templates, the footer size), the templates job Install starts once the editor is
## installed, and the manage page of an installed editor's templates.


const THEME_SOURCE := preload("res://theme/theme.gd")
const MODAL_SCENE := preload("res://src/components/editors/remote/remote_editors.tscn")
const VERSIONS_YML := "res://tests/assets/editor_catalog_versions.yml"
const RELEASE_JSON := "res://tests/assets/editor_catalog_release.json"
## Nothing listens there, so a started editor download fails without the network.
const OFFLINE_URL := "http://127.0.0.1:9/"
const STANDARD_TPZ := "Godot_v4.7.2-stable_export_templates.tpz"
const MONO_TPZ := "Godot_v4.7.2-stable_mono_export_templates.tpz"
const OLD_TPZ := "Godot_v3.6.3-stable_export_templates.tpz"
## Of a release candidate of a version that is stable now.
const RC_TPZ := "Godot_v4.7.2-rc1_export_templates.tpz"
## Of a release whose fixture has no Linux editor.
const WINDOWS_ONLY_TPZ := "Godot_v4.7.1-stable_export_templates.tpz"
## Lists so many files that its central directory does not fit in the last 64 KB.
const OLD_MONO_TPZ := "Godot_v3.6.3-stable_mono_export_templates.tpz"
const STANDARD_EDITOR := "Godot_v4.7.2-stable_linux.x86_64"
const MONO_EDITOR_DIR := "Godot_v4.7.2-stable_mono_linux_x86_64/"
const OLD_EDITOR := "Godot_v3.6.3-stable_x11.64"
const OLD_MONO_EDITOR := "Godot_v3.6.3-stable_mono_x11_64"
const MANAGE_HINT := (
	"Check templates to download them, uncheck installed ones to remove them. "
	+ "Every editor of this version uses the same templates."
)

var _failures := 0
var _root := ""
var _modal: RemoteEditorsControl
var _jobs: RecordingJobs
var _downloads: VBoxContainer
var _download_items: Array[Control] = []
## Paths the modal reported installed editors at, newest last.
var _installed_paths: Array[String] = []
## Folders of the versions folder the tests installed editors to, removed at the end.
var _extracted: Array[String] = []
## Local archives by release file name.
var _archives: Dictionary[String, String] = {}
## Contents of the Standard archive by path in its templates folder.
var _standard_files: Dictionary[String, PackedByteArray] = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _setup()
	await _test_tree_layout()
	_test_missing_and_installed()
	_test_tri_state()
	await _test_follows_build()
	await _test_small_window()
	await _test_scroll_resets()
	await _test_next_rereads_installed()
	await _test_install_without_templates()
	await _test_install_with_templates()
	await _test_old_archive()
	await _test_old_mono_archive()
	await _test_manage()
	await _test_manage_mono()
	await _test_manage_other_releases()
	await _test_manage_busy()
	await _test_manage_old_archive()
	await _test_manage_unavailable()
	await _test_install_after_manage_message()
	await _test_unreadable_archive()
	ExportTemplates.data_dir_override = ""
	for folder in _extracted:
		edir.remove_recursive(folder)
	edir.remove_recursive(_root)
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Export templates modal tests passed.")
	get_tree().quit()


func _setup() -> void:
	_root = ProjectSettings.globalize_path(
		"user://export-templates-modal-%s" % Time.get_ticks_msec()
	)
	DirAccess.make_dir_recursive_absolute(_root)
	ExportTemplates.data_dir_override = _root.path_join("data")
	_make_archives()
	# Installed before: Godot's ICU data and macOS template of 4.7.2.
	var installed_dir := ExportTemplates.version_dir("4.7.2.stable")
	DirAccess.make_dir_recursive_absolute(installed_dir)
	for file: String in ["icudt_godot.dat", "macos.zip"]:
		FileAccess.open(installed_dir.path_join(file), FileAccess.WRITE).store_buffer(
			_standard_files[file]
		)

	var root := get_tree().root
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 800)
	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.theme = THEME_SOURCE.create_custom_theme(null)
	add_child(frame)
	_downloads = VBoxContainer.new()
	frame.add_child(_downloads)
	_modal = MODAL_SCENE.instantiate() as RemoteEditorsControl
	frame.add_child(_modal)
	_modal.init(func(item: Control) -> void:
		_download_items.append(item)
		_downloads.add_child(item)
	)
	_modal.installed.connect(func(_editor_name: String, path: String) -> void:
		_installed_paths.append(path)
	)
	var assets := TemplatesAssetSource.new()
	var catalog := EditorCatalog.new(
		RemoteEditorsTreeDataSourceGithub.GithubVersionSourceParseYml.new(
			RemoteEditorsTreeDataSourceGithub.YmlSourceFile.new(VERSIONS_YML), assets
		),
		assets,
	)
	catalog.use_platform("linux", "x86_64")
	_modal.use_catalog(catalog)
	var local_archives := func(url: String, _known_size: int) -> RangeSource:
		return FileRangeSource.new(_archive_path(url))
	_modal.set_templates_source_factory(local_archives)
	_jobs = RecordingJobs.new()
	_jobs.work_dir = _root.path_join("work")
	_jobs.set_source_factory(local_archives)
	add_child(_jobs)
	_modal.set_templates_jobs(_jobs)
	await _wait_frames(2)


func _test_tree_layout() -> void:
	await _open_options("4.7.2")
	var picker := _picker()
	_check(picker.is_visible_in_tree(), "The templates step should show the export templates")
	_check(_children_text(_tree().get_root()) == PackedStringArray([
		"Desktop", "Mobile", "Web", "Common",
	]), "Wrong groups %s" % _children_text(_tree().get_root()))
	_check(_children_text(_item(["Desktop"])) == PackedStringArray([
		"Windows", "Linux", "macOS",
	]), "Wrong desktop platforms")
	_check(_children_text(_item(["Desktop", "Windows"])) == PackedStringArray([
		"Windows x86_32", "Windows x86_64", "Windows arm64",
	]), "Wrong Windows templates")
	_check(_children_text(_item(["Mobile"])) == PackedStringArray([
		"Android", "iOS", "visionOS",
	]), "Wrong mobile platforms")
	_check(_children_text(_item(["Web", "Web"])) == PackedStringArray([
		"Web", "Web with Extensions", "Web Single-Threaded", "Web with Extensions Single-Threaded",
	]), "Wrong web templates")
	_check(_children_text(_item(["Common"])) == PackedStringArray(["ICU Data"]), "Wrong common")
	var linux_x64 := _item(["Desktop", "Linux", "Linux x86_64"])
	_check(_children_text(linux_x64) == PackedStringArray([
		"linux_debug.x86_64", "linux_release.x86_64",
	]), "Templates list their files")
	_check(linux_x64.collapsed, "Template files start folded, like Godot")
	_check(not _item(["Desktop", "Linux"]).collapsed, "Platforms start unfolded")

	# Nothing is chosen: the editor alone is installed unless the user asks.
	for item in _all_items():
		if item.is_editable(0):
			_check(
				not item.is_checked(0) and not item.is_indeterminate(0),
				"%s should start unchecked" % item.get_text(0),
			)
	_check(not picker.has_selection(), "Nothing should be selected at first")
	_check(picker.selection() == null, "No selection at first")
	_check(not _footer().contains("+"), "The footer has no templates yet: %s" % _footer())
	_check(
		_item(["Desktop", "Linux", "Linux x86_64"]).get_text(1) == String.humanize_size(
			_compressed_size(STANDARD_TPZ, ["linux_debug.x86_64", "linux_release.x86_64"])
		),
		"Templates show their download size",
	)


func _test_missing_and_installed() -> void:
	# The Standard fixture has no visionOS and no Linux arm32 templates.
	for path: Array in [
		["Mobile", "visionOS"],
		["Mobile", "visionOS", "visionos.zip"],
		["Desktop", "Linux", "Linux arm32"],
	]:
		var item := _item(path)
		_check(
			not item.is_editable(0) and not item.is_checked(0),
			"%s is not in the archive and should be disabled" % _path_text(path),
		)
	_check(_item(["Desktop", "Linux"]).is_editable(0), "Linux still has templates")
	for path: Array in [["Common"], ["Common", "ICU Data"], ["Desktop", "macOS"]]:
		var item := _item(path)
		_check(
			item.is_checked(0) and not item.is_editable(0),
			"%s is installed and should be checked and disabled" % _path_text(path),
		)
		_check(item.get_text(1) == "Installed", "%s should say Installed" % _path_text(path))
	_check(
		not _item(["Desktop"]).is_indeterminate(0) and not _item(["Desktop"]).is_checked(0),
		"Installed templates do not make their group look chosen",
	)


func _test_tri_state() -> void:
	var picker := _picker()
	_toggle(["Desktop", "Linux", "Linux x86_64"])
	var linux_x64 := _item(["Desktop", "Linux", "Linux x86_64"])
	_check(linux_x64.is_checked(0), "Linux x86_64 should be checked")
	for file in linux_x64.get_children():
		_check(file.is_checked(0), "Checking a template checks its files")
	_check(_item(["Desktop", "Linux"]).is_indeterminate(0), "Linux should be indeterminate")
	_check(_item(["Desktop"]).is_indeterminate(0), "Desktop should be indeterminate")
	_check(
		picker.selection().files
			== PackedStringArray(["linux_debug.x86_64", "linux_release.x86_64"]),
		"Wrong selected files %s" % picker.selection().files,
	)
	var linux_size := _compressed_size(
		STANDARD_TPZ, ["linux_debug.x86_64", "linux_release.x86_64"]
	)
	_check(picker.selected_size() == linux_size, "Wrong selected size")
	_check(
		_footer().contains("+ %s templates" % String.humanize_size(linux_size)),
		"The footer should add the templates size: %s" % _footer(),
	)

	_toggle(["Desktop", "Linux", "Linux x86_64", "linux_debug.x86_64"])
	_check(linux_x64.is_indeterminate(0), "One of two files makes the template indeterminate")
	_check(
		picker.selection().files == PackedStringArray(["linux_release.x86_64"]),
		"Only the release file should be left",
	)

	# An indeterminate platform checks everything it has.
	_toggle(["Desktop", "Linux"])
	_check(_item(["Desktop", "Linux"]).is_checked(0), "Linux should be checked")
	_check(
		not _item(["Desktop", "Linux", "Linux arm32"]).is_checked(0),
		"A template the archive lacks stays unchecked",
	)
	_toggle(["Desktop"])
	_check(_item(["Desktop"]).is_checked(0), "Checking Desktop checks it all")
	_check(_item(["Desktop", "Windows", "Windows arm64"]).is_checked(0), "Windows arm64 checked")
	_check(not "macos.zip" in picker.selection().files, "Installed templates are not downloaded")
	_toggle(["Desktop"])
	_check(not picker.has_selection(), "Unchecking Desktop drops everything")
	_check(not _item(["Desktop"]).is_indeterminate(0), "Desktop should be unchecked")
	_check(_item(["Desktop", "macOS"]).is_checked(0), "Installed macOS stays checked")

	# Unchecking the last checked file clears its parents' indeterminate look.
	var debug_file := ["Desktop", "Linux", "Linux x86_64", "linux_debug.x86_64"]
	_toggle(debug_file)
	_check(_item(["Desktop", "Linux"]).is_indeterminate(0), "One file makes Linux indeterminate")
	_toggle(debug_file)
	for path: Array in [["Desktop", "Linux", "Linux x86_64"], ["Desktop", "Linux"], ["Desktop"]]:
		var item := _item(path)
		_check(
			not item.is_indeterminate(0) and not item.is_checked(0),
			"%s should be unchecked again" % _path_text(path),
		)
	_check(not picker.has_selection(), "Nothing is selected again")
	_toggle(["Desktop", "Linux", "Linux x86_64"])


## Going back to the build step and picking the other build shows its templates, with
## the checks it has too.
func _test_follows_build() -> void:
	_toggle(["Web", "Web", "Web"])
	await _pick_build(1)
	await _wait_until(func() -> bool: return _tree().get_root().get_child_count() == 3)
	await _wait_frames(1)
	_check(_children_text(_tree().get_root()) == PackedStringArray([
		"Desktop", "Mobile", "Common",
	]), ".NET archives have no web templates, got %s" % _children_text(_tree().get_root()))
	_check(
		_children_text(_item(["Mobile"])) == PackedStringArray(["Android", "iOS"]),
		".NET archives have no visionOS templates",
	)
	_check(
		_item(["Desktop", "Linux", "Linux x86_64"]).is_checked(0),
		"The checked templates follow the build",
	)
	_check(
		_item(["Common", "ICU Data"]).is_editable(0),
		"The Standard ICU data does not count as installed for .NET",
	)
	var selection := _picker().selection()
	_check(
		selection.files == PackedStringArray(["linux_debug.x86_64", "linux_release.x86_64"]),
		"Templates the .NET archive lacks are not selected: %s" % selection.files,
	)
	_check(selection.url.ends_with(MONO_TPZ), "The .NET archive should be used: %s" % selection.url)
	_check(
		_picker().selected_size() == _compressed_size(
			MONO_TPZ, ["linux_debug.x86_64", "linux_release.x86_64"]
		),
		"The size should be the .NET archive's",
	)
	await _pick_build(0)
	await _wait_until(func() -> bool: return _tree().get_root().get_child_count() == 4)
	_check(_picker().selection().url.ends_with(STANDARD_TPZ), "Back to the Standard archive")
	_check(_item(["Web", "Web", "Web"]).is_checked(0), "Web is checked again on Standard")

	# Only templates the .NET archive lacks are checked: nothing to install with it.
	_toggle(["Desktop", "Linux", "Linux x86_64"])
	await _pick_build(1)
	await _wait_until(func() -> bool: return _tree().get_root().get_child_count() == 3)
	_check(not _picker().has_selection(), "Templates the tree does not show are not selected")
	_check(not _footer().contains("+"), "The footer has no hidden templates: %s" % _footer())
	var rows_before := _download_items.size()
	var jobs_before := _jobs.started.size()
	(_part("InstallButton") as Button).pressed.emit()
	await _wait_frames(2)
	_check(_download_items.size() == rows_before + 1, "Install adds the editor's row")
	_check(not _picker().has_selection(), "Closing the modal forgets the templates")
	await _complete_editor_download([
		MONO_EDITOR_DIR + "Godot_v4.7.2-stable_mono_linux.x86_64",
		MONO_EDITOR_DIR + "GodotSharp/Api/Release/GodotSharp.dll",
	])
	_check(_jobs.started.size() == jobs_before, "Hidden templates are not installed")


## The templates step fits the Hub's smallest window: the tree scrolls, the footer stays.
func _test_small_window() -> void:
	var root := get_tree().root
	root.size = Vector2i(700, 370)
	await _open_options("4.7.2")
	await _wait_frames(2)
	_check(_picker().is_visible_in_tree(), "The templates should show")
	var window := root.get_visible_rect()
	for part: String in ["Title", "BackButton", "InstallButton"]:
		var rect := _part(part).get_global_rect()
		_check(window.encloses(rect), "%s should be in a 700x370 window: %s" % [part, rect])
	_modal.close()
	root.size = Vector2i(1280, 800)
	await _wait_frames(2)


## Reopening the step shows the templates from the top, like a fresh Template Manager.
func _test_scroll_resets() -> void:
	await _open_options("4.7.2")
	_tree().scroll_to_item(_item(["Common", "ICU Data"]))
	await _wait_frames(1)
	_check(_tree().get_scroll().y > 0, "The templates should scroll to ICU Data")
	_modal.close()
	await _open_options("4.7.2")
	_check(
		_tree().get_scroll().y == 0,
		"Reopened templates should start at the top: %s" % _tree().get_scroll(),
	)
	_modal.close()


## Templates another editor's job installed or removed while the build step showed are
## shown as they are now after Next.
func _test_next_rereads_installed() -> void:
	await _open_options("4.7.2")
	var x86_32 := ["Desktop", "Linux", "Linux x86_32"]
	var files: Array[String] = ["linux_debug.x86_32", "linux_release.x86_32"]
	_check(_item(x86_32).is_editable(0), "Linux x86_32 is not installed yet")
	(_part("BackButton") as Button).pressed.emit()
	var dir := ExportTemplates.version_dir("4.7.2.stable")
	for file in files:
		FileAccess.open(dir.path_join(file), FileAccess.WRITE).store_buffer(_standard_files[file])
	(_part("NextButton") as Button).pressed.emit()
	await _wait_frames(1)
	_check(
		not _item(x86_32).is_editable(0) and _item(x86_32).get_text(1) == "Installed",
		"Templates installed meanwhile should show installed after Next",
	)
	(_part("BackButton") as Button).pressed.emit()
	for file in files:
		DirAccess.remove_absolute(dir.path_join(file))
	(_part("NextButton") as Button).pressed.emit()
	await _wait_frames(1)
	_check(
		_item(x86_32).is_editable(0) and not _item(x86_32).is_checked(0),
		"Templates removed meanwhile can be picked again after Next",
	)
	_modal.close()


func _test_install_without_templates() -> void:
	await _open_options("4.7.2")
	var rows_before := _download_items.size()
	var jobs_before := _jobs.started.size()
	(_part("InstallButton") as Button).pressed.emit()
	await _wait_frames(2)
	_check(_download_items.size() == rows_before + 1, "Install without templates adds one row")
	await _complete_editor_download([STANDARD_EDITOR])
	_check(_jobs.started.size() == jobs_before, "Without templates, Install starts no job")


## The editor downloads alone; once it is installed, a job keyed by its path installs
## the templates, shown on its row in the Installs list: no second download row.
func _test_install_with_templates() -> void:
	await _open_options("4.7.2")
	_toggle(["Desktop", "Linux", "Linux x86_64"])
	_toggle(["Web", "Web", "Web"])
	var rows_before := _download_items.size()
	var jobs_before := _jobs.started.size()
	(_part("InstallButton") as Button).pressed.emit()
	await _wait_frames(2)
	_check(_download_items.size() == rows_before + 1, "Install adds only the editor's row")
	_check(_jobs.started.size() == jobs_before, "The templates wait for the editor")
	var path := await _complete_editor_download([STANDARD_EDITOR])
	if path.is_empty():
		await _install_without_editor(STANDARD_TPZ, [
			"linux_debug.x86_64", "linux_release.x86_64", "web_debug.zip", "web_release.zip",
		])
		return
	_check(_jobs.started.size() == jobs_before + 1, "The installed editor starts the templates")
	if _jobs.started.size() != jobs_before + 1:
		return
	var started := _jobs.started[-1]
	_check(str(started[0]) == path, "The job is the editor's, got %s" % started[0])
	var request := started[1] as ExportTemplatesJobs.Request
	_check(
		request.add_files == PackedStringArray([
			"linux_debug.x86_64", "linux_release.x86_64", "web_debug.zip", "web_release.zip",
		]),
		"Wrong files to add %s" % request.add_files,
	)
	_check(not request.all_files and request.remove_files.is_empty(), "Only files to add")
	_check(request.archive_url.ends_with(STANDARD_TPZ), "Wrong archive %s" % request.archive_url)
	_check(request.folder == "4.7.2.stable", "Wrong folder %s" % request.folder)
	_check(
		request.editor_name == utils.guess_editor_name(STANDARD_EDITOR),
		"Wrong editor name %s" % request.editor_name,
	)
	await _wait_for_job(path)
	var dir := ExportTemplates.version_dir("4.7.2.stable")
	for file: String in [
		"linux_debug.x86_64", "linux_release.x86_64", "web_debug.zip", "web_release.zip",
	]:
		_check(
			FileAccess.get_file_as_bytes(dir.path_join(file)) == _standard_files[file],
			"%s should be installed" % file,
		)
	_check(FileAccess.file_exists(dir.path_join("version.txt")), "version.txt is installed")

	# Installed now: the next visit shows them checked and disabled.
	await _open_options("4.7.2")
	var linux_x64 := _item(["Desktop", "Linux", "Linux x86_64"])
	_check(
		linux_x64.is_checked(0) and not linux_x64.is_editable(0),
		"Installed templates show checked and disabled",
	)
	_modal.close()


func _test_old_archive() -> void:
	await _open_options("3.6.3")
	_check(
		_children_text(_tree().get_root()) == PackedStringArray(["All export templates"]),
		"Godot 3 archives are offered whole, got %s" % _children_text(_tree().get_root()),
	)
	_toggle(["All export templates"])
	var selection := _picker().selection()
	_check(selection != null and selection.all_files, "All export templates should be selected")
	_check(
		_picker().selected_size() == _compressed_size(
			OLD_TPZ, ["version.txt", "linux_x11_64_debug", "osx.zip"]
		),
		"The size should be the whole archive's",
	)
	(_part("InstallButton") as Button).pressed.emit()
	await _wait_frames(2)
	var path := await _complete_editor_download([OLD_EDITOR])
	if path.is_empty():
		await _install_without_editor(OLD_TPZ, [])
		return
	var request := _jobs.started[-1][1] as ExportTemplatesJobs.Request
	_check(request.all_files and request.add_files.is_empty(), "The whole archive is installed")
	await _wait_for_job(path)
	var dir := ExportTemplates.version_dir("3.6.3.stable")
	_check(dir.ends_with("templates/3.6.3.stable"), "Godot 3 folder %s" % dir)
	for file: String in ["linux_x11_64_debug", "osx.zip", "version.txt"]:
		_check(FileAccess.file_exists(dir.path_join(file)), "%s should be installed" % file)


## Godot 3 .NET archives list over 1300 files: their central directory is read whole,
## not only the last 64 KB, so they are offered like the other old archives.
func _test_old_mono_archive() -> void:
	await _open_options("3.6.3")
	await _pick_build(1)
	await _wait_until(func() -> bool:
		return not (_picker().get_node("%Status") as Control).visible
	)
	_check(
		_children_text(_tree().get_root()) == PackedStringArray(["All export templates"]),
		"Godot 3 .NET archives are offered whole, got %s" % _children_text(_tree().get_root()),
	)
	var all := _item(["All export templates"])
	var archive_size := _compressed_size(OLD_MONO_TPZ, Array(_old_mono_files().keys()))
	_check(
		all != null
			and all.is_editable(0)
			and all.get_text(1) == String.humanize_size(archive_size),
		"The whole archive can be picked, with its size",
	)
	_toggle(["All export templates"])
	_check(_picker().selection().url.ends_with(OLD_MONO_TPZ), "Expected the .NET archive")
	_check(_picker().selected_size() == archive_size, "The size should be the whole archive's")
	_modal.close()


## The editor's menu opens its templates: installed ones checked, unchecking marks them
## for removal, checking others adds them, and Apply hands that to the jobs.
func _test_manage() -> void:
	var editor := _editor("Godot v4.7.2 stable", "/editors/4.7.2")
	await _open_manage(editor)
	var title := (_part("Title") as Label).text
	_check(title == "Export templates · Godot v4.7.2 stable", "Wrong manage title %s" % title)
	_check(
		_part("TemplatesPage").visible
			and not _part("VersionsPage").visible
			and not _part("OptionsPage").visible,
		"The manage page shows the templates alone",
	)
	_check(_picker().visible and not _part("ManageState").visible, "Expected the tree alone")
	var hint := (_picker().get_node("%HintLabel") as Label).text
	_check(hint == MANAGE_HINT, "Wrong manage hint %s" % hint)
	for path: Array in [
		["Common", "ICU Data"], ["Desktop", "macOS"], ["Desktop", "Linux", "Linux x86_64"],
	]:
		var item := _item(path)
		_check(
			item.is_checked(0) and item.is_editable(0) and item.get_text(1) == "Installed",
			"%s is installed: checked, and can be unchecked" % _path_text(path),
		)
	var arm64 := _item(["Desktop", "Linux", "Linux arm64"])
	_check(arm64.is_editable(0) and not arm64.is_checked(0), "Linux arm64 can be added")
	var apply := _part("ApplyButton") as Button
	_check(apply.visible and apply.disabled, "Apply waits for a change")
	_check((_part("BackButton") as Button).text == "Cancel", "Expected Cancel")
	for part: String in ["NextButton", "InstallButton"]:
		_check(not _part(part).visible, "No %s on the manage page" % part)
	_check(_footer() == "No changes", "Wrong footer %s" % _footer())
	_check(
		_modal.get_viewport().gui_get_focus_owner() == _tree(),
		"The manage page gives the tree the keyboard",
	)

	var macos := ["Desktop", "macOS"]
	_toggle(macos)
	_check(
		not _item(macos).is_checked(0) and _item(macos).get_text(1) == "Will be removed",
		"Unchecking an installed template marks it for removal",
	)
	_check(_item(["Desktop"]).is_indeterminate(0), "Desktop is partly kept")
	_check(not apply.disabled, "A removal can be applied")
	var macos_size := _standard_files["macos.zip"].size()
	_check(
		_footer() == "%s to remove" % String.humanize_size(macos_size),
		"The footer says what goes: %s" % _footer(),
	)
	_toggle(macos)
	_check(_item(macos).get_text(1) == "Installed", "Checking it again keeps it")
	_check(apply.disabled and _footer() == "No changes", "Nothing to apply again")

	_toggle(macos)
	_toggle(["Common"])
	_check(
		_item(["Common", "ICU Data"]).get_text(1) == "Will be removed"
			and _item(["Common"]).get_text(1) == "Will be removed",
		"Unchecking a group marks what it has for removal",
	)
	_toggle(["Desktop", "Linux", "Linux arm64"])
	var arm64_files := PackedStringArray(["linux_debug.arm64", "linux_release.arm64"])
	var removed_size := macos_size + _standard_files["icudt_godot.dat"].size()
	var expected_footer := "+%s to download, %s to remove" % [
		String.humanize_size(_compressed_size(STANDARD_TPZ, Array(arm64_files))),
		String.humanize_size(removed_size),
	]
	_check(_footer() == expected_footer, "Expected %s, got %s" % [expected_footer, _footer()])
	var changes := _picker().pending_changes()
	_check(changes.add_files == arm64_files, "Wrong files to add %s" % changes.add_files)
	_check(
		changes.remove_files == PackedStringArray(["macos.zip", "icudt_godot.dat"]),
		"Wrong files to remove %s" % changes.remove_files,
	)

	var jobs_before := _jobs.started.size()
	apply.pressed.emit()
	_check(not _modal.is_open(), "Apply closes the modal")
	_check(_jobs.started.size() == jobs_before + 1, "Apply starts a job")
	if _jobs.started.size() != jobs_before + 1:
		editor.free()
		return
	_check(str(_jobs.started[-1][0]) == "/editors/4.7.2", "The job is the editor's")
	var request := _jobs.started[-1][1] as ExportTemplatesJobs.Request
	_check(
		request.add_files == arm64_files
			and request.remove_files == changes.remove_files
			and not request.all_files,
		"The job should add and remove what was picked",
	)
	_check(request.folder == "4.7.2.stable", "Wrong folder %s" % request.folder)
	_check(request.archive_url.ends_with(STANDARD_TPZ), "Wrong archive %s" % request.archive_url)
	_check(request.editor_name == "Godot v4.7.2 stable", "Wrong name %s" % request.editor_name)
	await _wait_for_job("/editors/4.7.2")
	var dir := ExportTemplates.version_dir("4.7.2.stable")
	for file: String in ["macos.zip", "icudt_godot.dat"]:
		_check(not FileAccess.file_exists(dir.path_join(file)), "%s should be removed" % file)
	for file in arm64_files:
		_check(FileAccess.file_exists(dir.path_join(file)), "%s should be installed" % file)

	# The next visit shows what is installed now; Esc closes.
	await _open_manage(editor)
	_check(not _item(macos).is_checked(0), "macOS is not installed any more")
	_check(_item(["Desktop", "Linux", "Linux arm64"]).is_checked(0), "Linux arm64 is installed")
	_press_escape()
	_check(not _modal.is_open(), "Esc closes the manage page")
	editor.free()


## A .NET editor manages the .NET templates, in their own folder.
func _test_manage_mono() -> void:
	var editor := _editor("Godot v4.7.2 stable mono", "/editors/4.7.2-mono")
	await _open_manage(editor)
	_check(
		_children_text(_tree().get_root()) == PackedStringArray(["Desktop", "Mobile", "Common"]),
		"Expected the .NET templates, got %s" % _children_text(_tree().get_root()),
	)
	_check(
		not _item(["Common", "ICU Data"]).is_checked(0),
		"The Standard templates are not the .NET editor's",
	)
	_toggle(["Common", "ICU Data"])
	(_part("ApplyButton") as Button).pressed.emit()
	var request := _jobs.started[-1][1] as ExportTemplatesJobs.Request
	_check(request.archive_url.ends_with(MONO_TPZ), "Expected the .NET archive")
	_check(request.folder == "4.7.2.stable.mono", "Wrong folder %s" % request.folder)
	await _wait_for_job("/editors/4.7.2-mono")
	editor.free()


## The templates of an rc editor whose version went stable since (the tabs leave its
## release out) and of a release without an editor for this platform are found too.
func _test_manage_other_releases() -> void:
	for case: Array in [
		["Godot v4.7.2 rc1", "4.7.2.rc1"], ["Godot v4.7.1 stable", "4.7.1.stable"],
	]:
		var editor := _editor(case[0] as String, "/editors/other-release")
		await _open_manage(editor)
		var what := case[0] as String
		_check(
			_picker().visible and not _part("ManageState").visible,
			"%s: expected its templates, got %s" % [what, (_part("ManageStatus") as Label).text],
		)
		_check(
			_picker().get_folder() == (case[1] as String),
			"%s: wrong folder %s" % [what, _picker().get_folder()],
		)
		if _picker().visible:
			_check(_item(["Desktop", "Linux", "Linux x86_64"]) != null, "%s: no tree" % what)
		_modal.close()
		editor.free()


## While a job changes the templates of this version, Apply waits; changes picked meanwhile
## stay.
func _test_manage_busy() -> void:
	var editor := _editor("Godot v4.7.2 stable", "/editors/busy")
	_jobs.busy_folders = PackedStringArray(["4.7.2.stable"])
	await _open_manage(editor)
	var status := _part("ManageStatus") as Label
	_check(
		_part("ManageState").visible and status.text.begins_with("These export templates are"),
		"The page should say the templates are being changed, got %s" % status.text,
	)
	_toggle(["Desktop", "Linux", "Linux x86_32"])
	var apply := _part("ApplyButton") as Button
	_check(apply.disabled, "Apply waits for the running job")
	_jobs.busy_folders = PackedStringArray()
	_jobs.job_changed.emit("/editors/other")
	_check(not _part("ManageState").visible, "The note goes once the job is done")
	_check(not apply.disabled, "Apply works again")
	_check(_item(["Desktop", "Linux", "Linux x86_32"]).is_checked(0), "The pick stays")
	(_part("BackButton") as Button).pressed.emit()
	_check(not _modal.is_open(), "Cancel closes the manage page")
	editor.free()


## The single item of an old archive stands for the whole folder.
func _test_manage_old_archive() -> void:
	# Old .NET templates keep their assemblies in subfolders.
	var assemblies := ExportTemplates.version_dir("3.6.3.stable").path_join("bcl")
	DirAccess.make_dir_recursive_absolute(assemblies)
	FileAccess.open(assemblies.path_join("mscorlib.dll"), FileAccess.WRITE).store_string("dll")
	var editor := _editor("Godot v3.6.3 stable", "/editors/3.6.3")
	await _open_manage(editor)
	var all := ["All export templates"]
	_check(
		_item(all).is_checked(0) and _item(all).is_editable(0),
		"Installed old templates show checked and can be unchecked",
	)
	_toggle(all)
	_check(_item(all).get_text(1) == "Will be removed", "Unchecked: marked for removal")
	var removed := _picker().pending_changes().remove_files
	removed.sort()
	_check(
		removed == PackedStringArray([
			"bcl/mscorlib.dll", "linux_x11_64_debug", "osx.zip", "version.txt",
		]),
		"Every installed file goes, got %s" % removed,
	)
	(_part("ApplyButton") as Button).pressed.emit()
	await _wait_for_job("/editors/3.6.3")
	_check(
		not DirAccess.dir_exists_absolute(ExportTemplates.version_dir("3.6.3.stable")),
		"The emptied version folder goes",
	)
	editor.free()


## Editors the catalog has no templates for get a reason instead of a tree.
func _test_manage_unavailable() -> void:
	for case: Array in [
		["Godot v9.9 stable", EditorEngineBrand.GODOT, "is not an official Godot release"],
		["Redot v4.7.2 stable", EditorEngineBrand.REDOT, "is not an official Godot release"],
		["My Godot", EditorEngineBrand.GODOT, "is not an official Godot release"],
		["Godot v4.6.3 stable", EditorEngineBrand.GODOT, "has no export templates"],
		["Godot v4.6.2 stable", EditorEngineBrand.GODOT, "Could not load"],
	]:
		var editor := _editor(case[0] as String, "/editors/unavailable", case[1] as String)
		_modal.open_manage_templates(editor)
		await _wait_until(func() -> bool: return not _modal.is_processing())
		var status := (_part("ManageStatus") as Label).text
		var what := case[0] as String
		_check(status.contains(case[2] as String), "%s: wrong reason %s" % [what, status])
		_check(not _picker().visible, "%s: no tree without templates" % what)
		_check((_part("ApplyButton") as Button).disabled, "%s: nothing to apply" % what)
		_check(
			_part("ManageRetryButton").visible == (what == "Godot v4.6.2 stable"),
			"%s: Retry only after a failed load" % what,
		)
		_modal.close()
		editor.free()


## The manage page's message and the tree it hides are its own: the templates step of
## the next install shows the tree, also after a page closed while still loading.
func _test_install_after_manage_message() -> void:
	var editor := _editor("Godot v4.6.3 stable", "/editors/after-message")
	_modal.open_manage_templates(editor)
	await _wait_until(func() -> bool: return not _modal.is_processing())
	_check(_part("ManageState").visible, "Expected the no templates message")
	_modal.close()
	await _open_options("4.7.2")
	_check(_picker().is_visible_in_tree(), "The templates step should show its tree")
	_check(not _part("ManageState").visible, "The manage message should stay on its page")
	_modal.close()

	# Closed while it looks for the release's files, which come a few frames later.
	var catalog := _modal.get("_catalog") as EditorCatalog
	var slow := SlowAssetSource.new()
	var slow_catalog := EditorCatalog.new(
		RemoteEditorsTreeDataSourceGithub.GithubVersionSourceParseYml.new(
			RemoteEditorsTreeDataSourceGithub.YmlSourceFile.new(VERSIONS_YML), slow
		),
		slow,
	)
	slow_catalog.use_platform("linux", "x86_64")
	_modal.use_catalog(slow_catalog)
	_modal.open_manage_templates(editor)
	await _wait_frames(1)
	_check(
		(_part("ManageStatus") as Label).text.begins_with("Looking for the export templates"),
		"The manage page should be loading",
	)
	_modal.close()
	await _open_options("4.7.2")
	_check(_picker().is_visible_in_tree(), "The tree shows after a page closed while loading")
	_check(not _part("ManageState").visible, "No loading message on the templates step")
	_modal.close()
	_modal.use_catalog(catalog)
	editor.free()


func _test_unreadable_archive() -> void:
	var path := _archives[STANDARD_TPZ]
	_archives.erase(STANDARD_TPZ)
	# A new modal, so the archive's directory is not cached.
	var fresh := MODAL_SCENE.instantiate() as RemoteEditorsControl
	_modal.add_sibling(fresh)
	fresh.init(func(_item: Control) -> void: pass)
	fresh.use_catalog(_modal.get("_catalog") as EditorCatalog)
	fresh.set_templates_source_factory(func(url: String, _known_size: int) -> RangeSource:
		return FileRangeSource.new(_archive_path(url))
	)
	_modal = fresh
	await _open_options("4.7.2", false)
	var status := _picker().get_node("%Status") as Control
	_check(status.visible, "A failed read should say so")
	_check((_picker().get_node("%RetryButton") as Control).visible, "A failed read can be retried")
	_check(
		_item(["Desktop", "Linux", "Linux x86_32"]).is_editable(0),
		"Templates stay selectable without the archive's directory",
	)
	_toggle(["Desktop", "Linux", "Linux x86_32"])
	_check(_picker().selected_size() == -1, "The size is unknown")
	_check(_footer().contains("+ templates"), "The footer says templates: %s" % _footer())
	_archives[STANDARD_TPZ] = path
	(_picker().get_node("%RetryButton") as Button).pressed.emit()
	await _wait_frames(1)
	_check(not status.visible, "Retry should read the archive")
	_check(
		_item(["Desktop", "Linux", "Linux x86_32"]).is_checked(0),
		"Retry keeps the checked templates",
	)
	_check(_picker().selected_size() > 0, "The size is known after Retry")
	_modal.close()


## Opens the templates step of Godot [param version] and waits for its templates.
func _open_options(version: String, wait_for_index := true) -> void:
	_modal.open()
	await _wait_until(func() -> bool: return _find_row(version) != null)
	_find_row(version).get_install_button().pressed.emit()
	var next := _part("NextButton") as Button
	await _wait_until(func() -> bool: return next.visible and not next.disabled)
	next.pressed.emit()
	await _wait_until(func() -> bool: return _picker().is_visible_in_tree())
	if wait_for_index:
		await _wait_until(func() -> bool:
			return not (_picker().get_node("%Status") as Control).visible
		)
	await _wait_frames(1)


## Goes back to the build step, picks the build at [param index] and comes back.
func _pick_build(index: int) -> void:
	(_part("BackButton") as Button).pressed.emit()
	_variant_buttons()[index].button_pressed = true
	(_part("NextButton") as Button).pressed.emit()
	await _wait_frames(1)


## Opens the manage page of [param editor] and waits for its templates.
func _open_manage(editor: LocalEditors.Item) -> void:
	_modal.open_manage_templates(editor)
	await _wait_until(func() -> bool: return _picker().visible)
	await _wait_until(func() -> bool:
		return not (_picker().get_node("%Status") as Control).visible
	)
	await _wait_frames(1)


## Finishes the newest editor download with an archive of [param files], the first
## being the editor, and returns where it was installed, or "" when it was not. The
## catalog's builds are Linux ones: elsewhere the Hub would ask which file is the editor.
func _complete_editor_download(files: Array[String]) -> String:
	var row := _download_items[-1] as AssetDownload
	if OS.get_name() != "Linux":
		row.queue_free()
		await _wait_frames(1)
		return ""
	var zip_path := _root.path_join("editor-%d.zip" % _download_items.size())
	var packer := ZIPPacker.new()
	packer.open(zip_path)
	for file in files:
		packer.start_file(file)
		packer.write_file("#!/bin/sh\nexit 0\n".to_utf8_buffer())
		packer.close_file()
	packer.close()
	_installed_paths.clear()
	row.downloaded.emit(zip_path)
	await _wait_frames(2)
	_check(_installed_paths.size() == 1, "The downloaded editor should install")
	if _installed_paths.size() != 1:
		return ""
	var path := _installed_paths[0]
	_check(path.ends_with("/" + files[0]), "Wrong editor %s" % path)
	_extracted.append(path.trim_suffix(files[0]).simplify_path())
	return path


## Installs [param files] of [param archive] (all of them when empty) like the job of an
## installed editor, where [method _complete_editor_download] cannot install one: the
## manage tests expect them.
func _install_without_editor(archive: String, files: Array[String]) -> void:
	var request := ExportTemplatesJobs.Request.new()
	request.editor_name = "Not emulated"
	request.archive_url = OFFLINE_URL + archive
	request.add_files = PackedStringArray(files)
	request.all_files = files.is_empty()
	_jobs.start("/editors/not-emulated", request)
	await _wait_for_job("/editors/not-emulated")


func _wait_for_job(editor_path: String) -> void:
	await _wait_until(func() -> bool:
		var job := _jobs.get_job(editor_path)
		return job != null and job.state != ExportTemplatesJobs.Job.State.RUNNING
	, 300)
	var job := _jobs.get_job(editor_path)
	_check(
		job != null and job.state == ExportTemplatesJobs.Job.State.DONE,
		"The job of %s should be done: %s" % [editor_path, job.status_text if job else "none"],
	)
	await _wait_frames(1)


func _find_row(version: String) -> EditorCatalogRow:
	for child in _part("Rows").get_children():
		var row := child as EditorCatalogRow
		if row.get_entry().version == version and row.get_entry().is_stable():
			return row
	return null


## The local archive of a release file [param url], or a missing file.
func _archive_path(url: String) -> String:
	return _archives.get(url.get_file(), _root.path_join("missing.tpz")) as String


func _picker() -> ExportTemplatesPicker:
	return _part("ExportTemplates") as ExportTemplatesPicker


func _tree() -> Tree:
	return _picker().get_node("%Tree") as Tree


func _footer() -> String:
	return (_part("FooterInfo") as Label).text


func _part(unique_name: String) -> Control:
	return _modal.get_node("%" + unique_name) as Control


## Toggles the check of the item at [param path], as a click or Space does.
func _toggle(path: Array) -> void:
	var item := _item(path)
	if item == null:
		return
	_tree().set_selected(item, 0)
	_check(_tree().edit_selected(), "Could not toggle %s" % _path_text(path))


## The tree item reached by the texts of [param path] from the top.
func _item(path: Array) -> TreeItem:
	var item := _tree().get_root()
	for text: String in path:
		var found: TreeItem = null
		for child in item.get_children():
			if child.get_text(0) == text:
				found = child
				break
		if found == null:
			_check(false, "No tree item %s" % _path_text(path))
			return null
		item = found
	return item


func _path_text(path: Array) -> String:
	return "/".join(PackedStringArray(path))


func _all_items() -> Array[TreeItem]:
	var result: Array[TreeItem] = []
	var item := _tree().get_root().get_next_in_tree()
	while item != null:
		result.append(item)
		item = item.get_next_in_tree()
	return result


func _children_text(item: TreeItem) -> PackedStringArray:
	var result := PackedStringArray()
	if item == null:
		return result
	for child in item.get_children():
		result.append(child.get_text(0))
	return result


func _variant_buttons() -> Array[CheckBox]:
	var result: Array[CheckBox] = []
	for node in _part("Variants").find_children("*", "CheckBox", true, false):
		result.append(node as CheckBox)
	return result


func _compressed_size(archive: String, files: Array) -> int:
	var bytes := FileAccess.get_file_as_bytes(_archives[archive])
	var bounds := TemplateArchive.tail_range(bytes.size())
	var index := TemplateArchive.parse_index(bytes.slice(bounds[0], bounds[1] + 1), bytes.size())
	var whole := TemplateArchive.directory_range(index)
	if not whole.is_empty():
		index = TemplateArchive.parse_index(bytes.slice(whole[0], whole[1] + 1), bytes.size())
	var total := 0
	for file: String in files:
		total += index.compressed_size_of(file)
	return total


func _editor(
	editor_name: String, path: String, brand := EditorEngineBrand.GODOT
) -> LocalEditors.Item:
	var cfg := ConfigFile.new()
	cfg.set_value(path, "name", editor_name)
	cfg.set_value(path, "engine_brand", brand)
	return LocalEditors.Item.new(ConfigFileSection.new(path, IConfigFileLike.of_config(cfg)))


func _press_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	_modal.get_viewport().push_input(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	_modal.get_viewport().push_input(release)


func _make_archives() -> void:
	_standard_files["version.txt"] = "4.7.2.stable".to_utf8_buffer()
	for file: String in [
		"linux_debug.x86_64", "linux_release.x86_64", "linux_debug.x86_32", "linux_release.x86_32",
		"linux_debug.arm64", "linux_release.arm64", "macos.zip", "ios.zip",
		"android_debug.apk", "android_release.apk", "android_source.zip", "icudt_godot.dat",
		"web_debug.zip", "web_release.zip", "web_dlink_debug.zip", "web_dlink_release.zip",
		"web_nothreads_debug.zip", "web_nothreads_release.zip", "web_dlink_nothreads_debug.zip",
		"web_dlink_nothreads_release.zip",
	]:
		_standard_files[file] = _text(1500 + file.length() * 53)
	for arch: String in ["x86_32", "x86_64", "arm64"]:
		for kind: String in ["debug", "release"]:
			for suffix: String in [".exe", "_console.exe"]:
				var file := "windows_%s_%s%s" % [kind, arch, suffix]
				_standard_files[file] = _text(1200 + file.length() * 31)
	_archives[STANDARD_TPZ] = _pack("standard.tpz", _standard_files)

	var mono: Dictionary[String, PackedByteArray] = {}
	for file in _standard_files:
		if not file.begins_with("web_"):
			mono[file] = _standard_files[file] + PackedByteArray([1, 2, 3])
	mono["version.txt"] = "4.7.2.stable.mono".to_utf8_buffer()
	_archives[MONO_TPZ] = _pack("mono.tpz", mono)

	var old: Dictionary[String, PackedByteArray] = {
		"version.txt": "3.6.3.stable".to_utf8_buffer(),
		"linux_x11_64_debug": _text(3000),
		"osx.zip": _text(2000),
	}
	_archives[OLD_TPZ] = _pack("old.tpz", old)
	_archives[OLD_MONO_TPZ] = _pack("old-mono.tpz", _old_mono_files())
	_archives[RC_TPZ] = _archives[STANDARD_TPZ]
	_archives[WINDOWS_ONLY_TPZ] = _archives[STANDARD_TPZ]


## Files of the Godot 3 .NET archive: assemblies with long paths, as in the real one.
func _old_mono_files() -> Dictionary[String, PackedByteArray]:
	var files: Dictionary[String, PackedByteArray] = {
		"version.txt": "3.6.3.stable.mono".to_utf8_buffer(),
		"linux_x11_64_debug": _text(3000),
	}
	for i in 600:
		var assembly := "data.mono.x11.64.release/Mono/lib/mono/4.5/Facades/%s.%03d.dll" % [
			"System.Runtime.InteropServices.WindowsRuntime.Extensions.Generated", i,
		]
		files[assembly] = _text(20)
	return files


func _pack(file_name: String, files: Dictionary[String, PackedByteArray]) -> String:
	var path := _root.path_join(file_name)
	var packer := ZIPPacker.new()
	packer.open(path)
	for file in files:
		packer.start_file("templates/" + file)
		packer.write_file(files[file])
		packer.close_file()
	packer.close()
	return path


func _text(size: int) -> PackedByteArray:
	var text := ""
	while text.length() < size:
		text += "Template %d. " % text.length()
	return text.left(size).to_utf8_buffer()


func _wait_frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().process_frame


## Waits until [param condition] returns true, for at most [param max_frames].
func _wait_until(condition: Callable, max_frames := 60) -> void:
	for _frame: int in max_frames:
		if condition.call():
			return
		await get_tree().process_frame
	_check(false, "Timed out waiting for a condition")


func _check(condition: bool, message: String) -> void:
	if condition: return
	_failures += 1
	push_error(message)


## Records the requests it starts, then runs them, and can report folders as busy.
class RecordingJobs extends ExportTemplatesJobs:
	## [code][editor_path, request][/code] of every started job, in order.
	var started: Array[Array] = []
	## Version folders [method is_folder_busy] reports busy whatever runs.
	var busy_folders := PackedStringArray()

	func start(editor_path: String, request: ExportTemplatesJobs.Request) -> void:
		started.append([editor_path, request])
		super.start(editor_path, request)

	func is_folder_busy(folder: String) -> bool:
		return folder in busy_folders or super.is_folder_busy(folder)


## Serves the release files of [TemplatesAssetSource] a few frames late.
class SlowAssetSource extends TemplatesAssetSource:
	func async_load(
		version: String, release: String
	) -> Array[RemoteEditorsTreeDataSourceGithub.GodotAsset]:
		for _frame: int in 3:
			await (Engine.get_main_loop() as SceneTree).process_frame
		return super.async_load(version, release)


## Serves the 4.7.2 release fixture (with its export template archives), a 3.6.3
## release with Linux editors and templates, a 4.6.3 release with a Linux editor and no
## templates, 4.7.2 rc1, and 4.7.1 with a Windows editor only and templates, with
## download urls that stay offline.
class TemplatesAssetSource extends RemoteEditorsTreeDataSourceGithub.GithubAssetSource:
	func async_load(
		version: String, release: String
	) -> Array[RemoteEditorsTreeDataSourceGithub.GodotAsset]:
		var result: Array[RemoteEditorsTreeDataSourceGithub.GodotAsset] = []
		var tag := "%s-%s" % [version, release]
		var assets: Array = []
		if tag == "4.7.2-stable":
			var json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RELEASE_JSON))
			assets = json.get("assets", [])
		elif tag == "3.6.3-stable":
			assets = [
				{"name": OLD_EDITOR + ".zip", "size": 40000000},
				{"name": OLD_TPZ, "size": 900000000},
				{"name": OLD_MONO_EDITOR + ".zip", "size": 70000000},
				{"name": OLD_MONO_TPZ, "size": 1000000000},
			]
		elif tag == "4.6.3-stable":
			assets = [{"name": "Godot_v4.6.3-stable_linux.x86_64.zip", "size": 60000000}]
		elif tag == "4.7.2-rc1":
			assets = [
				{"name": "Godot_v4.7.2-rc1_linux.x86_64.zip", "size": 60000000},
				{"name": RC_TPZ, "size": 1200000000},
			]
		elif tag == "4.7.1-stable":
			assets = [
				{"name": "Godot_v4.7.1-stable_win64.exe.zip", "size": 60000000},
				{"name": WINDOWS_ONLY_TPZ, "size": 1200000000},
			]
		for asset: Dictionary in assets:
			var offline := asset.duplicate()
			offline["browser_download_url"] = OFFLINE_URL + str(asset.get("name", ""))
			result.append(RemoteEditorsTreeDataSourceGithub.GodotAsset.new(offline))
		return result
