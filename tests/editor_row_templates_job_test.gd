extends Node
## Tests the export templates line of the Installs rows: it follows the editor's job
## (progress and Cancel, the error with Retry and Dismiss, hidden when done), outlives
## list rebuilds, lines up with the row's title without moving its icon, is rounded
## like the theme's buttons in both themes, and the Export Templates action is offered
## for editors of a Godot release. A new install's row is sorted in and scrolled to.


const THEME_SOURCE := preload("res://theme/theme.gd")
const LOCAL_EDITORS_SCENE := preload("res://src/components/editors/local/local_editors.tscn")
const RUNNING := ExportTemplatesJobs.Job.State.RUNNING
const FAILED := ExportTemplatesJobs.Job.State.FAILED
const DONE := ExportTemplatesJobs.Job.State.DONE

var _failures := 0
var _root := ""
var _tpz := ""
var _frame: Control
var _jobs: ExportTemplatesJobs
var _local: LocalEditorsControl
var _editors: LocalEditors.List
var _editor_a := ""
var _editor_b := ""
## A self-contained editor of a Godot release.
var _editor_c := ""
var _fail_with := ""
## Reads of the jobs' archives wait while true.
var _stall := false
var _requested: Array[LocalEditors.Item] = []
var _previous_style: Variant
var _previous_radius: Variant


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _setup()
	_test_action_availability()
	await _test_progress_line()
	await _test_line_lines_up()
	await _test_failure_retry_and_dismiss()
	await _test_cancel()
	await _test_rounded_like_the_theme()
	await _test_new_install_in_view()
	await _teardown()
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Editor row templates job tests passed.")
	get_tree().quit()


func _setup() -> void:
	_root = ProjectSettings.globalize_path("user://editor-row-job-test-%s" % Time.get_ticks_msec())
	DirAccess.make_dir_recursive_absolute(_root)
	ExportTemplates.data_dir_override = _root.path_join("data")
	_tpz = _make_fixture_tpz()
	_previous_style = Config.editor_settings_proxy_get("interface/theme/style", "Modern")
	_previous_radius = Config.editor_settings_proxy_get("interface/theme/corner_radius", 4)

	var root := get_tree().root
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 800)
	_frame = MarginContainer.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.theme = THEME_SOURCE.create_custom_theme(null)
	add_child(_frame)

	_jobs = ExportTemplatesJobs.new()
	_jobs.work_dir = _root.path_join("work")
	_jobs.set_source_factory(func(url: String, _size: int) -> RangeSource:
		var source := StallSource.new(url)
		source.fail_with = _fail_with
		source.is_stalled = func() -> bool: return _stall
		return source
	)
	add_child(_jobs)
	# Like GuiMain, which the rows look the jobs up under.
	Context.add(_frame, _jobs)

	_editor_a = _fake_editor("a/Godot_v4.7.2-stable_linux.x86_64")
	_editor_b = _fake_editor("b/my_engine.x86_64")
	_editor_c = _fake_editor("c/Godot_v4.7.2-stable_linux.x86_64")
	FileAccess.open(_editor_c.get_base_dir().path_join("_sc_"), FileAccess.WRITE).store_string("")
	_editors = LocalEditors.List.new(_root.path_join("editors.cfg"))
	_editors.add("Godot v4.7.2 stable", _editor_a)
	_editors.add("My Engine", _editor_b)
	_editors.add("Godot v4.7.2 stable self-contained", _editor_c)
	_local = LOCAL_EDITORS_SCENE.instantiate() as LocalEditorsControl
	_frame.add_child(_local)
	_local.export_templates_requested.connect(func(editor: LocalEditors.Item) -> void:
		_requested.append(editor)
	)
	_local.init(_editors)
	await _wait_frames(2)


func _teardown() -> void:
	Context.erase(_frame, _jobs)
	Config.editor_settings_proxy_set("interface/theme/style", _previous_style)
	Config.editor_settings_proxy_set("interface/theme/corner_radius", _previous_radius)
	# Settings saved meanwhile (any setting saves them all) would keep the test's style
	# for the next tests run in the same user folder.
	Config.save()
	ExportTemplates.data_dir_override = ""
	_frame.queue_free()
	_jobs.queue_free()
	await _wait_frames(2)
	# Editor items are Objects, freed by their list.
	_editors.cleanup()
	edir.remove_recursive(_root)


func _test_action_availability() -> void:
	var action_a := _row(_editor_a)._actions.by_key("export-templates")
	var action_b := _row(_editor_b)._actions.by_key("export-templates")
	var action_c := _row(_editor_c)._actions.by_key("export-templates")
	_check(not action_a.is_disabled(), "A Godot 4.7.2 editor can manage its templates")
	_check(action_b.is_disabled(), "An editor without a version has no templates to manage")
	# Its templates are in its own editor_data folder, not the one the Hub installs to.
	_check(action_c.is_disabled(), "A self-contained editor does not manage shared templates")
	_check(action_c.tooltip.contains("Self-contained"), "The action should say why")
	action_a.act()
	_check(
		_requested.size() == 1 and _requested[0].path == _editor_a,
		"The action should reach the Installs page with its editor",
	)


func _test_progress_line() -> void:
	var row := _row(_editor_a)
	_check(not _line(row).visible, "No job, no line")
	_jobs.start(_editor_a, _request(["linux_debug.x86_64", "macos.zip"]))
	_check(_line(row).visible, "A running job should show its line")
	_check(_progress(row).visible, "A running job shows a progress bar")
	_check(not _retry(row).visible, "A running job has no Retry")
	_check(_close(row).tooltip_text == tr("Cancel"), "A running job can be canceled")
	_check(_status(row).text == _jobs.get_job(_editor_a).status_text, "Wrong status text")
	_check(not _line(_row(_editor_b)).visible, "Other rows show no line")

	# The list rebuilds its rows, e.g. after a rename or a refresh.
	(_local.get_node("%EditorsList") as EditorsVBoxList).refresh(_editors.all())
	await get_tree().process_frame
	_check(not is_instance_valid(row), "The old row should be gone")
	row = _row(_editor_a)
	_check(_line(row).visible, "A rebuilt row should show the running job")

	var seen_progress := 0.0
	for _frame_index: int in 600:
		var job := _jobs.get_job(_editor_a)
		if job.state != RUNNING:
			break
		seen_progress = maxf(seen_progress, _progress(row).value)
		_check(_status(row).text == job.status_text, "The status should follow the job")
		await get_tree().process_frame
	_check(_jobs.get_job(_editor_a).state == DONE, "The job should be done")
	_check(seen_progress > 0.0, "The bar should have moved")
	_check(not _line(row).visible, "The line should go when the job is done")


## The line's text and bar start under the title's text, and the icon and the favorite
## star stay where they are in rows without a line, beside the title and path.
func _test_line_lines_up() -> void:
	_stall = true
	_jobs.start(_editor_a, _request(["linux_debug.x86_64"]))
	await _wait_frames(3)
	var row := _row(_editor_a)
	var plain := _row(_editor_b)
	_check(_line(row).visible and _progress(row).visible, "The job should show its bar")
	var title_x := _text_x(row.get_node("%TitleLabel") as Label)
	var status_x := _text_x(_status(row))
	var bar_x := _progress(row).get_global_rect().position.x
	_check(
		absf(status_x - title_x) < 1.0 and absf(bar_x - title_x) < 1.0,
		"The status text (%s) and bar (%s) should start under the title (%s)" % [
			status_x, bar_x, title_x,
		],
	)
	for part: String in ["Icon", "FavoriteButton"]:
		var with_line := _center_in_row(row, part)
		var without_line := _center_in_row(plain, part)
		_check(
			absf(with_line - without_line) < 1.0,
			"The %s should not move with the line: %s, %s without" % [
				part, with_line, without_line,
			],
		)
	_check(
		row.size.y > plain.size.y,
		"The line makes the row taller: %s, %s without" % [row.size.y, plain.size.y],
	)
	_stall = false
	await _wait_job_end(_editor_a)
	await _wait_frames(2)
	_check(not _line(row).visible, "The line goes when the job is done")
	_check(
		absf(row.size.y - plain.size.y) < 1.0
			and absf(_center_in_row(row, "Icon") - _center_in_row(plain, "Icon")) < 1.0,
		"Without the line the row is as before",
	)


func _test_failure_retry_and_dismiss() -> void:
	var row := _row(_editor_a)
	_fail_with = "the server is down"
	_jobs.start(_editor_a, _request(["linux_debug.x86_64"]))
	await _wait_job_end(_editor_a)
	_check(_line(row).visible, "A failed job should show its line")
	_check(_status(row).text.contains("the server is down"), "The line should say why")
	_check(_status(row).tooltip_text == _status(row).text, "The full error is in the tooltip")
	_check(_retry(row).visible and not _progress(row).visible, "A failure offers Retry")
	_check(_close(row).tooltip_text == tr("Dismiss"), "A failure can be dismissed")
	_check((row.get_node("%TemplatesIcon") as Control).visible, "A failure shows an icon")

	_fail_with = ""
	_retry(row).pressed.emit()
	_check(_jobs.get_job(_editor_a).state == RUNNING, "Retry should run the job again")
	_check(_progress(row).visible and not _retry(row).visible, "Retry shows progress again")
	await _wait_job_end(_editor_a)
	_check(not _line(row).visible, "The retried job is done")

	_fail_with = "the server is down"
	_jobs.start(_editor_a, _request(["macos.zip"]))
	await _wait_job_end(_editor_a)
	_fail_with = ""
	_close(row).pressed.emit()
	_check(_jobs.get_job(_editor_a) == null, "Dismiss should forget the job")
	_check(not _line(row).visible, "A dismissed job has no line")


func _test_cancel() -> void:
	var row := _row(_editor_a)
	_jobs.start(_editor_a, _request(["web_debug.zip"]))
	_close(row).pressed.emit()
	_check(_jobs.get_job(_editor_a) == null, "Cancel should stop the job")
	_check(not _line(row).visible, "A canceled job has no line")
	for _frame_index: int in 300:
		if not _jobs.is_folder_busy("4.7.2.stable"):
			break
		await get_tree().process_frame


## The line and its bar take the corner radius of the theme's buttons, in both themes
## and after the radius setting changes.
func _test_rounded_like_the_theme() -> void:
	_fail_with = "the server is down"
	_jobs.start(_editor_a, _request(["linux_debug.x86_64"]))
	await _wait_job_end(_editor_a)
	_fail_with = ""
	# Another radius each time, so a line keeping the previous theme's corners fails.
	var radii: Dictionary[String, int] = {"Modern": 6, "Classic": 3}
	for style: String in radii:
		Config.editor_settings_proxy_set("interface/theme/style", style)
		Config.editor_settings_proxy_set("interface/theme/corner_radius", radii[style])
		_frame.theme = THEME_SOURCE.create_custom_theme(null)
		await get_tree().process_frame
		var row := _row(_editor_a)
		var button := row.get_theme_stylebox("normal", "Button") as StyleBoxFlat
		_check(
			button != null and button.corner_radius_top_left == radii[style],
			"%s buttons should take the corner radius setting" % style,
		)
		var panel := _line(row).get_theme_stylebox("panel") as StyleBoxFlat
		_check(panel != null, "The %s line should have a flat panel" % style)
		if panel != null and button != null:
			_check(
				panel.corner_radius_top_left == button.corner_radius_top_left
					and panel.corner_radius_bottom_right == button.corner_radius_bottom_right,
				"The %s line should be rounded like buttons" % style,
			)
		if panel != null and button != null:
			_check(
				panel.anti_aliasing == button.anti_aliasing,
				"The %s line's corners should be drawn like the buttons'" % style,
			)
		# The theme's ProgressBar look, as the download rows above the list have it.
		var fill := _progress(row).get_theme_stylebox("fill")
		var themed_fill := row.get_theme_stylebox("fill", "ProgressBar")
		var flat_fill := fill as StyleBoxFlat
		if themed_fill is StyleBoxFlat:
			_check(
				flat_fill != null and button != null
					and flat_fill.corner_radius_top_left == button.corner_radius_top_left
					and flat_fill.bg_color == (themed_fill as StyleBoxFlat).bg_color,
				"The %s progress bar should be the theme's, rounded like buttons" % style,
			)
		else:
			_check(
				fill.get_class() == themed_fill.get_class(),
				"The %s progress bar should keep the theme's textured look" % style,
			)
		var bar_height := _progress(row).custom_minimum_size.y
		var textured_fill := fill as StyleBoxTexture
		if textured_fill == null:
			_check(
				is_equal_approx(bar_height, ThemeCorners.THIN_PROGRESS_HEIGHT * Config.EDSCALE),
				"The %s bar should be as thin as the download rows'" % style,
			)
		else:
			_check(
				bar_height >= textured_fill.texture_margin_top + textured_fill.texture_margin_bottom,
				"The %s textured bar should be tall enough to show its fill" % style,
			)
		_check(panel != null and panel.bg_color.a > 0.0, "The failed line keeps its tint")
	_jobs.dismiss(_editor_a)


## A new install goes where the sort puts it, and its row, which shows its export
## templates being installed, is scrolled into view.
func _test_new_install_in_view() -> void:
	for i in 12:
		_local.add("Godot v4.%d stable" % (20 + i), _fake_editor("n%d/godot.x86_64" % i))
	var list := _local.get_node("%EditorsList") as EditorsVBoxList
	var scroll := list.get_node("%ScrollContainer") as ScrollContainer
	await _wait_frames(2)
	scroll.scroll_vertical = roundi(scroll.get_v_scroll_bar().max_value)
	await _wait_frames(2)
	_check(scroll.scroll_vertical > 0, "The list should scroll")
	var path := _fake_editor("new/Godot_v4.30.5-stable_linux.x86_64")
	_local.add("Godot v4.30.5 stable", path)
	await _wait_frames(2)
	var row := _row(path)
	var names: Array[String] = []
	for child in list.get_node("%ItemsContainer").get_children():
		names.append((child as EditorListItemControl)._item.name)
	var at := names.find("Godot v4.30.5 stable")
	_check(
		at > 0
			and at + 1 < names.size()
			and names[at - 1] == "Godot v4.31 stable"
			and names[at + 1] == "Godot v4.30 stable",
		"A new install should be sorted in, got %s" % [names],
	)
	_check(
		scroll.get_global_rect().encloses(row.get_global_rect()),
		"The new row should be scrolled into view",
	)


## Where the text of [param label] starts in the window.
func _text_x(label: Label) -> float:
	return (
		label.get_global_rect().position.x
		+ label.get_theme_stylebox("normal").get_margin(SIDE_LEFT)
	)


## The vertical center of the row part [param part_name] from the row's top.
func _center_in_row(row: EditorListItemControl, part_name: String) -> float:
	var part := row.get_node("%" + part_name) as Control
	return part.get_global_rect().get_center().y - row.get_global_rect().position.y


func _row(editor_path: String) -> EditorListItemControl:
	var items := _local.get_node("%EditorsList").get_node("%ItemsContainer")
	for child in items.get_children():
		var row := child as EditorListItemControl
		if row != null and not row.is_queued_for_deletion() and row._item.path == editor_path:
			return row
	_check(false, "No row for %s" % editor_path)
	return null


func _line(row: EditorListItemControl) -> PanelContainer:
	return row.get_node("%TemplatesJob") as PanelContainer


func _status(row: EditorListItemControl) -> Label:
	return row.get_node("%TemplatesStatus") as Label


func _progress(row: EditorListItemControl) -> ProgressBar:
	return row.get_node("%TemplatesProgress") as ProgressBar


func _retry(row: EditorListItemControl) -> Button:
	return row.get_node("%TemplatesRetryButton") as Button


func _close(row: EditorListItemControl) -> Button:
	return row.get_node("%TemplatesCloseButton") as Button


func _request(files: Array) -> ExportTemplatesJobs.Request:
	var request := ExportTemplatesJobs.Request.new()
	request.editor_name = "Godot v4.7.2 stable"
	request.archive_url = _tpz
	request.add_files = PackedStringArray(files)
	request.folder = "4.7.2.stable"
	return request


func _wait_job_end(editor_path: String) -> void:
	for _frame_index: int in 600:
		var job := _jobs.get_job(editor_path)
		if job == null or job.state != RUNNING:
			return
		await get_tree().process_frame
	_check(false, "The job of %s did not end" % editor_path)


func _fake_editor(relative_path: String) -> String:
	var path := _root.path_join("versions").path_join(relative_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("#!/bin/sh\n")
	file.close()
	return path


## A small 4.7.2 archive with a few templates big enough to take some frames.
func _make_fixture_tpz() -> String:
	var path := _root.path_join("fixture.tpz")
	var packer := ZIPPacker.new()
	packer.open(path)
	var files := {
		"version.txt": "4.7.2.stable".to_utf8_buffer(),
		"linux_debug.x86_64": _noise(200000, 1),
		"macos.zip": _noise(300000, 2),
		"web_debug.zip": _noise(400000, 3),
	}
	for file: String in files:
		packer.start_file("templates/" + file)
		packer.write_file(files[file] as PackedByteArray)
		packer.close_file()
	packer.close()
	return path


func _noise(size: int, noise_seed: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var bytes := PackedByteArray()
	bytes.resize(size)
	for i in size:
		bytes[i] = rng.randi() & 0xFF
	return bytes


func _wait_frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if condition: return
	_failures += 1
	push_error(message)


## Reads the fixture archive, waiting while [member is_stalled] returns true.
class StallSource extends FileRangeSource:
	var is_stalled := Callable()

	func async_read(start: int, end: int, target_path := "") -> RangeSource.Result:
		while is_stalled.is_valid() and is_stalled.call():
			await (Engine.get_main_loop() as SceneTree).process_frame
		return super.async_read(start, end, target_path)
