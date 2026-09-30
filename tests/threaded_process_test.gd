extends Node


const COMMAND_VIEWER_SCENE := preload(
	"res://src/components/command_viewer/command_viewer.tscn"
)
const DUPLICATE_DIALOG_SCENE := preload(
	"res://src/components/projects/duplicate_project_dialog/duplicate_project_dialog.tscn"
)
const CLONE_DIALOG_SCENE := preload(
	"res://src/components/projects/clone_project_dialog/clone_project_dialog.tscn"
)
const InstallProjectDialog := preload(
	"res://src/components/projects/install_project_dialog/install_project_dialog.gd"
)
## Every stubbed process sleeps this long, so a blocked main thread is visible.
const PROCESS_SECONDS := 1
## A handler that returns sooner than this did not wait for the process.
const MAX_BLOCK_MSEC := 300
## A longer gap between two frames means the main thread was blocked.
const MAX_FRAME_GAP_MSEC := 300
const TIMEOUT_MSEC := 20000

var _failures := 0
var _root := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if OS.has_feature("windows"):
		print("Threaded process tests skipped on Windows.")
		get_tree().quit()
		return

	_root = ProjectSettings.globalize_path(
		"user://threaded-process-test-%s" % Time.get_ticks_msec()
	)
	DirAccess.make_dir_recursive_absolute(_root.path_join("bin"))
	var repo_dir := _create_git_repo()
	# The stubs log their call and sleep before running the real program.
	_install_slow_stub("cp")
	_install_slow_stub("git")
	var original_path := OS.get_environment("PATH")
	OS.set_environment("PATH", _root.path_join("bin") + ":" + original_path)

	await _test_command_viewer_execute()
	await _test_duplicate_copies_off_main_thread()
	await _test_duplicate_dialog_reused_during_copy()
	await _test_clone_off_main_thread(repo_dir)

	OS.set_environment("PATH", original_path)
	_check(edir.remove_recursive(_root) == OK, "Could not remove the test directory")
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Threaded process tests passed.")
	get_tree().quit()


func _test_command_viewer_execute() -> void:
	var viewer := COMMAND_VIEWER_SCENE.instantiate() as CommandViewer
	add_child(viewer)
	var commands := CommandViewer.CommandsInMemory.new(OSProcessSchema.Source.new())
	commands.add(
		"Slow",
		"sh",
		["-c", "sleep %s; echo done" % PROCESS_SECONDS],
		false,
		"Terminal",
		[CommandViewer.Actions.EXECUTE],
	)
	viewer.raise(commands)
	var output_dialog := viewer.get_node("ExecuteOutputDialog") as AcceptDialog
	var output_label := viewer.get_node("%OutputLabel") as RichTextLabel
	var error_code_label := viewer.get_node("%ErrorCodeLabel") as Label

	var execute_btn := _command_view(viewer).execute_btn
	var started := Time.get_ticks_msec()
	execute_btn.pressed.emit()
	_check_not_blocked(started, "Execute")
	_check(execute_btn.disabled, "Expected Execute to be disabled while the command runs")
	_check(not output_dialog.visible, "The output dialog opened before the command ended")
	await _check_frames_until("the command output", started, func() -> bool:
		return output_dialog.visible
	)
	_check(not execute_btn.disabled, "Expected Execute to be enabled again")
	_check(output_label.get_parsed_text().contains("done"), "Missing the command output")
	_check_equal(error_code_label.text, "0")

	# Rebuilding the list frees the button while the command is still running.
	output_dialog.hide()
	started = Time.get_ticks_msec()
	_command_view(viewer).execute_btn.pressed.emit()
	viewer.raise(commands)
	await _check_frames_until("the output after a rebuild", started, func() -> bool:
		return output_dialog.visible
	)
	await _free_window(viewer)


func _test_duplicate_copies_off_main_thread() -> void:
	var editors := LocalEditors.List.new(_root.path_join("editors.cfg"))
	var projects := Projects.List.new(_root.path_join("projects.cfg"), editors, null)
	var project := _add_project(projects, "source")

	var dialog := DUPLICATE_DIALOG_SCENE.instantiate() as DuplicateProjectDialog
	add_child(dialog)
	dialog.raise(project.name, project)
	var target_dir := _root.path_join("copy")
	dialog._project_path_line_edit.text = target_dir
	var ok_button := dialog.get_ok_button()
	ok_button.disabled = false
	var duplicated_paths: Array[String] = []
	dialog.duplicated.connect(func(path: String, _callback: Callable) -> void:
		duplicated_paths.append(path)
	)

	var started := Time.get_ticks_msec()
	ok_button.pressed.emit()
	_check_not_blocked(started, "Duplicate")
	_check(ok_button.disabled, "Expected OK to be disabled while copying")
	# Focus changes and edits validate again while the copy fills the target.
	_check_validation_while_busy(dialog, target_dir, dialog.tr("Copying..."))
	await _check_frames_until("the duplicate", started, func() -> bool:
		return not duplicated_paths.is_empty()
	)
	if not duplicated_paths.is_empty():
		_check_equal(duplicated_paths[0], target_dir.path_join("project.godot"))
	_check(FileAccess.file_exists(target_dir.path_join("data.txt")), "The copy is incomplete")
	_check(not dialog.visible, "Expected the dialog to close after the copy")
	await _free_window(dialog)
	projects.cleanup()


## The dialog stays usable during a copy, so it can be cancelled and opened for
## another project before the first copy ends.
func _test_duplicate_dialog_reused_during_copy() -> void:
	var editors := LocalEditors.List.new(_root.path_join("reuse-editors.cfg"))
	var projects := Projects.List.new(_root.path_join("reuse-projects.cfg"), editors, null)
	var first := _add_project(projects, "first")
	var second := _add_project(projects, "second")

	var dialog := DUPLICATE_DIALOG_SCENE.instantiate() as DuplicateProjectDialog
	add_child(dialog)
	dialog.raise(first.name, first)
	var first_target := _root.path_join("first-copy")
	dialog._project_path_line_edit.text = first_target
	var ok_button := dialog.get_ok_button()
	ok_button.disabled = false
	var duplicated_paths: Array[String] = []
	dialog.duplicated.connect(func(path: String, _callback: Callable) -> void:
		duplicated_paths.append(path)
	)

	var started := Time.get_ticks_msec()
	ok_button.pressed.emit()
	dialog.get_cancel_button().pressed.emit()
	# Cancel hides the dialog deferred.
	await get_tree().process_frame
	_check(not dialog.visible, "Expected Cancel to close the dialog")
	dialog.raise(second.name, second)
	dialog._project_path_line_edit.text = _root.path_join("second-copy")
	await _check_frames_until("the cancelled duplicate", started, func() -> bool:
		return not duplicated_paths.is_empty()
	)
	if not duplicated_paths.is_empty():
		_check_equal(duplicated_paths[0], first_target.path_join("project.godot"))
	_check(dialog.visible, "The first copy closed the dialog opened for another project")
	_check(not ok_button.disabled, "Expected OK to be enabled again for the other project")
	await _free_window(dialog)
	projects.cleanup()


func _test_clone_off_main_thread(repo_dir: String) -> void:
	var dialog := CLONE_DIALOG_SCENE.instantiate() as CloneProjectDialog
	add_child(dialog)
	dialog.raise()
	dialog._repository_edit.text = repo_dir
	var target_dir := _root.path_join("clone")
	dialog._project_path_line_edit.text = target_dir
	var ok_button := dialog.get_ok_button()
	ok_button.disabled = false
	var cloned_paths: Array[String] = []
	dialog.cloned.connect(func(path: String) -> void:
		cloned_paths.append(path)
	)
	var had_prompt_variable := OS.has_environment("GIT_TERMINAL_PROMPT")

	var started := Time.get_ticks_msec()
	ok_button.pressed.emit()
	var clone_thread := dialog.get("_clone_thread") as Thread
	_check_not_blocked(started, "Clone")
	_check(ok_button.disabled, "Expected OK to be disabled while cloning")
	var message := dialog._message_label.text
	_check_validation_while_busy(dialog, target_dir, message)
	await _check_frames_until("the clone", started, func() -> bool:
		return not cloned_paths.is_empty()
	)
	if not cloned_paths.is_empty():
		_check_equal(cloned_paths[0], target_dir.path_join("project.godot"))
	# wait_to_finish() is the only thing that makes a started Thread report
	# is_started() as false again.
	_check(
		clone_thread != null and not clone_thread.is_started(),
		"Expected the clone thread to be joined"
	)
	_check(
		"_clone_thread" in dialog and dialog.get("_clone_thread") == null,
		"Expected the dialog to drop the joined clone thread"
	)

	var call_log := FileAccess.get_file_as_string(_log_path("git"))
	_check(
		call_log.begins_with("GIT_TERMINAL_PROMPT=0\n"),
		"Expected git to run without terminal prompts, got:\n%s" % call_log
	)
	_check(
		call_log.contains("-c\nhttp.lowSpeedLimit=1000\n-c\nhttp.lowSpeedTime=60\nclone\n"),
		"Expected git to give up on stalled transfers, got:\n%s" % call_log
	)
	_check(
		OS.has_environment("GIT_TERMINAL_PROMPT") == had_prompt_variable,
		"The clone changed the Hub's own environment"
	)
	await _free_window(dialog)


func _add_project(projects: Projects.List, dir_name: String) -> Projects.Item:
	var project_dir := _root.path_join(dir_name)
	DirAccess.make_dir_recursive_absolute(project_dir)
	_write(project_dir.path_join("project.godot"), "config_version=5\n")
	_write(project_dir.path_join("data.txt"), "data")
	var project := projects.add(project_dir.path_join("project.godot"), "")
	project.load(false)
	return project


## Validates while the target holds a file, as it does once the process starts
## writing, and expects OK to stay disabled with `expected_message` shown.
func _check_validation_while_busy(
		dialog: InstallProjectDialog, target_dir: String, expected_message: String
) -> void:
	var partial_path := target_dir.path_join("partial.txt")
	_write(partial_path, "partial")
	dialog._validate()
	# The stubbed process is still sleeping, so it never sees this file.
	DirAccess.remove_absolute(partial_path)
	_check(dialog.get_ok_button().disabled, "Validation enabled OK while the process runs")
	_check_equal(dialog._message_label.text, expected_message)


func _create_git_repo() -> String:
	var repo_dir := _root.path_join("repo")
	DirAccess.make_dir_recursive_absolute(repo_dir)
	_write(repo_dir.path_join("project.godot"), "config_version=5\n")
	_run_git(repo_dir, ["-c", "init.defaultBranch=main", "init", "-q"])
	_run_git(repo_dir, ["add", "-A"])
	_run_git(repo_dir, [
		"-c", "user.name=Test", "-c", "user.email=test@example.com",
		"commit", "-q", "-m", "Initial commit",
	])
	return repo_dir


func _run_git(repo_dir: String, args: PackedStringArray) -> void:
	var output := []
	var exit_code := OS.execute("git", PackedStringArray(["-C", repo_dir]) + args, output, true)
	_check(exit_code == 0, "git %s failed: %s" % [" ".join(args), output])


## Puts a stub for `program` first on PATH. It logs the prompt variable and its
## arguments, sleeps, then runs the real program.
func _install_slow_stub(program: String) -> void:
	var output := []
	OS.execute("sh", ["-c", "command -v %s" % program], output)
	var real_path := str(output[0]).strip_edges() if not output.is_empty() else ""
	_check(not real_path.is_empty(), "%s is not installed" % program)
	var stub_path := _root.path_join("bin").path_join(program)
	_write(stub_path, "\n".join([
		"#!/bin/sh",
		'printf "%%s\\n" "GIT_TERMINAL_PROMPT=${GIT_TERMINAL_PROMPT-unset}" "$@" > "%s"'
				% _log_path(program),
		"sleep %s" % PROCESS_SECONDS,
		'exec "%s" "$@"' % real_path,
		"",
	]))
	OS.execute("chmod", ["+x", stub_path])


## Frees a dialog before the next one opens, only one can be exclusive at a time.
func _free_window(window: Window) -> void:
	window.hide()
	window.queue_free()
	await get_tree().process_frame


func _log_path(program: String) -> String:
	return _root.path_join("%s.log" % program)


func _command_view(viewer: CommandViewer) -> CommandTextView:
	for child: Node in viewer.get_node("%VBoxContainer").get_children():
		if not child.is_queued_for_deletion():
			return child as CommandTextView
	return null


## Waits for `done` and fails when the main loop stalls, the wait times out, or
## the result arrives before the stubbed process could have finished.
func _check_frames_until(label: String, started: int, done: Callable) -> void:
	var last_frame := Time.get_ticks_msec()
	var longest_gap := 0
	while not done.call():
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		longest_gap = maxi(longest_gap, now - last_frame)
		last_frame = now
		if now - started > TIMEOUT_MSEC:
			_check(false, "Timed out waiting for %s" % label)
			return
	_check(
		longest_gap < MAX_FRAME_GAP_MSEC,
		"The main loop stalled for %d msec while waiting for %s" % [longest_gap, label]
	)
	_check(
		Time.get_ticks_msec() - started >= PROCESS_SECONDS * 1000,
		"Got %s before the process could have finished" % label
	)


func _check_not_blocked(started: int, label: String) -> void:
	var blocked_msec := Time.get_ticks_msec() - started
	_check(
		blocked_msec < MAX_BLOCK_MSEC,
		"%s blocked the main thread for %d msec" % [label, blocked_msec]
	)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Could not write %s" % path)
	if file:
		file.store_string(text)
		file.close()


func _check_equal(actual: String, expected: String) -> void:
	_check(actual == expected, "Expected '%s', got '%s'" % [expected, actual])


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
