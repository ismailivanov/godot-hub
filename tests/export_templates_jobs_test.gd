extends Node
## Offline tests of export template jobs: adding and removing templates of installed
## editors from a local archive, cleaning up version folders, cancel, retry and
## dismiss, one job per editor, and the signals the Installs list follows.


const TEMPLATES_DIR := "templates/"
const FOLDER := "4.7.2.stable"
const EDITOR_A := "/editors/godot-a/Godot_v4.7.2-stable_linux.x86_64"
const EDITOR_B := "/editors/godot-b/Godot_v4.7.2-stable_linux.x86_64"
const RUNNING := ExportTemplatesJobs.Job.State.RUNNING
const FAILED := ExportTemplatesJobs.Job.State.FAILED
const DONE := ExportTemplatesJobs.Job.State.DONE

var _failures := 0
var _root := ""
var _tpz := ""
## Contents of the fixture archive by path in it.
var _files: Dictionary[String, PackedByteArray] = {}
var _jobs: ExportTemplatesJobs
## Editor paths of job_changed, in order.
var _changes: Array[String] = []
## Reads of the next sources the jobs make go through these.
var _fail_with := ""
var _on_read := Callable()
var _download_pause_sec := 0.0
var _last_source: FileRangeSource


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_root = ProjectSettings.globalize_path(
		"user://export-templates-jobs-test-%s" % Time.get_ticks_msec()
	)
	DirAccess.make_dir_recursive_absolute(_root)
	ExportTemplates.data_dir_override = _root.path_join("data")
	_tpz = _make_fixture_tpz()
	_jobs = ExportTemplatesJobs.new()
	_jobs.work_dir = _root.path_join("work")
	_jobs.set_source_factory(_make_source)
	_jobs.job_changed.connect(func(editor_path: String) -> void: _changes.append(editor_path))
	add_child(_jobs)

	await _test_add()
	await _test_one_job_per_editor()
	await _test_all_files()
	_test_remove_and_folder_cleanup()
	await _test_remove_and_add_in_one_job()
	_test_unsafe_removals_are_skipped()
	await _test_cancel_leaves_no_partial_file()
	await _test_failure_retry_and_dismiss()
	await _test_dismiss_running_job()
	await _test_busy_folder()
	await _test_quit_while_installing()

	ExportTemplates.data_dir_override = ""
	_jobs.queue_free()
	_check(edir.remove_recursive(_root) == OK, "Could not remove the test directory")
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Export templates jobs tests passed.")
	get_tree().quit()


func _test_add() -> void:
	_changes.clear()
	_jobs.start(EDITOR_A, _add_request(["linux_debug.x86_64", "android_source.zip"]))
	var job := _jobs.get_job(EDITOR_A)
	_check(job != null and job.state == RUNNING, "The job should run after start()")
	_check(_jobs.get_job(EDITOR_B) == null, "Another editor has no job")
	_check(_jobs.is_folder_busy(FOLDER), "The job's folder should be busy while it runs")
	_check(not _jobs.is_folder_busy("4.8.dev6.mono"), "Other folders are not busy")
	await _wait_job_end(EDITOR_A)
	_check(job.state == DONE, "The job should be done, got: %s" % job.status_text)
	_check(job.error.is_empty() and is_equal_approx(job.progress, 1.0), "A done job is complete")
	_check(not _jobs.is_folder_busy(FOLDER), "The folder is not busy after the job")
	_check_installed(["linux_debug.x86_64", "android_source.zip", "version.txt"], "an add")
	_check(_changes.size() >= 3, "Expected start, progress and end signals: %s" % [_changes])
	_check(_changes.all(func(path: String) -> bool: return path == EDITOR_A), "Wrong editor")
	_check(job.status_text.length() > 0, "A done job says so")


## A second start for an editor whose job runs is ignored; one that ended is replaced.
func _test_one_job_per_editor() -> void:
	_clear_installs()
	_jobs.start(EDITOR_A, _add_request(["linux_debug.x86_64"]))
	var job := _jobs.get_job(EDITOR_A)
	_jobs.start(EDITOR_A, _add_request(["macos.zip"]))
	_check(_jobs.get_job(EDITOR_A) == job, "A running job should not be replaced")
	await _wait_job_end(EDITOR_A)
	_check_installed(["linux_debug.x86_64", "version.txt"], "a start while running")

	_jobs.start(EDITOR_A, _add_request(["macos.zip"]))
	var next := _jobs.get_job(EDITOR_A)
	_check(next != job and next.state == RUNNING, "A done job should be replaced")
	await _wait_job_end(EDITOR_A)
	_check_installed(["linux_debug.x86_64", "macos.zip", "version.txt"], "a second job")


## Everything comes in one download of the archive, which the job's row shows before
## the files are unpacked.
func _test_all_files() -> void:
	_clear_installs()
	var request := _add_request([])
	request.all_files = true
	var texts: Array[String] = []
	var progress: Array[float] = []
	var record := func(editor_path: String) -> void:
		var job := _jobs.get_job(editor_path)
		if job != null and job.state == RUNNING:
			texts.append(job.status_text)
			progress.append(job.progress)
	_jobs.job_changed.connect(record)
	_download_pause_sec = 0.3
	_jobs.start(EDITOR_A, request)
	await _wait_job_end(EDITOR_A)
	_download_pause_sec = 0.0
	_jobs.job_changed.disconnect(record)
	_check(_jobs.get_job(EDITOR_A).state == DONE, "Installing everything failed")
	_check_installed(_files.keys(), "an install of everything")
	_check(_last_source.download_count == 1, "Everything should come in one download")
	_check(_listing(_jobs.work_dir).is_empty(), "The downloaded archive should be removed")

	var downloading := texts.find_custom(func(text: String) -> bool:
		return text.begins_with("Downloading export templates (")
	)
	var unpacking := texts.find_custom(func(text: String) -> bool:
		return text.begins_with("Unpacking export templates (")
	)
	_check(
		texts[0] == "Reading the export templates archive..."
			and downloading > 0
			and unpacking > downloading,
		"Expected reading, downloading, then unpacking: %s" % [texts],
	)
	for i in progress.size():
		var unpacking_share := i >= unpacking
		_check(
			(progress[i] >= 1.0 - ExportTemplatesJobs.UNPACK_SHARE) == unpacking_share
				and progress[i] <= 1.0
				and (i == 0 or progress[i] >= progress[i - 1]),
			"Wrong progress %f of \"%s\": %s" % [progress[i], texts[i], progress],
		)


## Removing is synchronous; the version folder goes with its last template.
func _test_remove_and_folder_cleanup() -> void:
	_install_directly(["linux_debug.x86_64", "macos.zip"])
	_changes.clear()
	_jobs.start(EDITOR_A, _remove_request(["macos.zip"]))
	var job := _jobs.get_job(EDITOR_A)
	_check(job.state == DONE, "A removal should be done at once: %s" % job.status_text)
	_check_installed(["linux_debug.x86_64", "version.txt"], "a removal")
	_check(_changes.size() >= 2 and _changes[-1] == EDITOR_A, "A removal should signal")

	_jobs.start(EDITOR_A, _remove_request(["linux_debug.x86_64"]))
	_check(_jobs.get_job(EDITOR_A).state == DONE, "The last removal should be done")
	_check(
		not DirAccess.dir_exists_absolute(ExportTemplates.version_dir(FOLDER)),
		"A version folder with only version.txt should be removed",
	)

	# Files in subfolders (Godot 3 .NET templates) take their empty folders along.
	_install_directly(["linux_debug.x86_64"])
	var nested := ExportTemplates.version_dir(FOLDER).path_join("GodotSharp/Api")
	DirAccess.make_dir_recursive_absolute(nested)
	_write(nested.path_join("GodotSharp.dll"), _text(100))
	_jobs.start(
		EDITOR_A, _remove_request(["GodotSharp/Api/GodotSharp.dll", "linux_debug.x86_64"])
	)
	_check(_jobs.get_job(EDITOR_A).state == DONE, "Removing nested files failed")
	_check(
		not DirAccess.dir_exists_absolute(ExportTemplates.version_dir(FOLDER)),
		"Emptied subfolders and the version folder should be removed",
	)


func _test_remove_and_add_in_one_job() -> void:
	_install_directly(["linux_debug.x86_64", "macos.zip"])
	var request := _add_request(["android_source.zip"])
	request.remove_files = PackedStringArray(["macos.zip"])
	_jobs.start(EDITOR_A, request)
	_check(
		not FileAccess.file_exists(ExportTemplates.version_dir(FOLDER).path_join("macos.zip")),
		"Removals should happen before the download starts",
	)
	await _wait_job_end(EDITOR_A)
	_check(_jobs.get_job(EDITOR_A).state == DONE, "Removing and adding failed")
	_check_installed(
		["linux_debug.x86_64", "android_source.zip", "version.txt"], "a removal and an add"
	)


func _test_unsafe_removals_are_skipped() -> void:
	_install_directly(["linux_debug.x86_64"])
	var outside := _root.path_join("data/outside.txt")
	_write(outside, _text(10))
	_jobs.start(
		EDITOR_A,
		_remove_request(["../../outside.txt", "../4.7.2.stable/linux_debug.x86_64", "version.txt"]),
	)
	_check(_jobs.get_job(EDITOR_A).state == DONE, "Skipped removals do not fail")
	_check(FileAccess.file_exists(outside), "Files outside the version folder must stay")
	_check_installed(["linux_debug.x86_64", "version.txt"], "unsafe removals")

	var request := _remove_request(["linux_debug.x86_64"])
	request.folder = "../templates"
	_jobs.start(EDITOR_A, request)
	_check(_jobs.get_job(EDITOR_A).state == FAILED, "A bad folder name should fail")
	_check_installed(["linux_debug.x86_64", "version.txt"], "a bad folder name")
	_jobs.dismiss(EDITOR_A)
	DirAccess.remove_absolute(outside)


func _test_cancel_leaves_no_partial_file() -> void:
	_clear_installs()
	# Reads: size, directory, version.txt, then the first template.
	_on_read = func(_start: int, _end: int) -> void:
		if _last_source.read_count == 4:
			_jobs.cancel(EDITOR_A)
			_check(_jobs.get_job(EDITOR_A) == null, "A canceled job should go away at once")
			_check(_changes[-1] == EDITOR_A, "Canceling should signal")
	_jobs.start(EDITOR_A, _add_request(["linux_debug.x86_64", "android_source.zip"]))
	await _wait_folder_free()
	_on_read = Callable()
	_check(_jobs.get_job(EDITOR_A) == null, "The canceled job should be gone")
	_check(
		not DirAccess.dir_exists_absolute(ExportTemplates.version_dir(FOLDER)),
		"A canceled install should not leave a folder with only version.txt",
	)
	_check(_listing(_jobs.work_dir).is_empty(), "Downloaded parts left after a cancel")

	# Canceled while a template unpacks: complete files stay, nothing half written.
	_on_read = func(_start: int, _end: int) -> void:
		if _last_source.read_count == 5:
			_jobs.cancel.call_deferred(EDITOR_A)
	_jobs.start(EDITOR_A, _add_request(["linux_debug.x86_64", "android_source.zip"]))
	await _wait_folder_free()
	_on_read = Callable()
	_check(_jobs.get_job(EDITOR_A) == null, "The canceled job should be gone")
	var listing := _listing(ExportTemplates.version_dir(FOLDER))
	for file in listing:
		_check(not file.ends_with(ExportTemplatesInstaller.PART_SUFFIX), "Part left: %s" % file)
		_check(
			FileAccess.get_file_as_bytes(ExportTemplates.version_dir(FOLDER).path_join(file))
				== _files[file],
			"%s is not complete after a cancel" % file,
		)
	_check(_listing(_jobs.work_dir).is_empty(), "Downloaded parts left after a late cancel")


func _test_failure_retry_and_dismiss() -> void:
	_clear_installs()
	_fail_with = "the server is down"
	_jobs.start(EDITOR_A, _add_request(["linux_debug.x86_64"]))
	await _wait_job_end(EDITOR_A)
	var job := _jobs.get_job(EDITOR_A)
	_check(job.state == FAILED, "A failing source should fail the job")
	_check(job.error == "the server is down", "Wrong error: %s" % job.error)
	_check(job.status_text.contains("the server is down"), "The status should say why")
	_check(
		not DirAccess.dir_exists_absolute(ExportTemplates.templates_root(4)),
		"A failed job should not create folders",
	)

	_fail_with = ""
	_changes.clear()
	_jobs.retry(EDITOR_A)
	_check(_jobs.get_job(EDITOR_A).state == RUNNING, "Retry should run the job again")
	await _wait_job_end(EDITOR_A)
	_check(_jobs.get_job(EDITOR_A).state == DONE, "The retried job should be done")
	_check_installed(["linux_debug.x86_64", "version.txt"], "a retry")
	_jobs.retry(EDITOR_A)
	_check(_jobs.get_job(EDITOR_A).state == DONE, "Retry only runs failed jobs")

	_fail_with = "the server is down"
	_jobs.start(EDITOR_A, _add_request(["macos.zip"]))
	await _wait_job_end(EDITOR_A)
	_fail_with = ""
	_changes.clear()
	_jobs.dismiss(EDITOR_A)
	_check(_jobs.get_job(EDITOR_A) == null, "A dismissed job should be gone")
	_check(
		_changes.size() == 1 and _changes[0] == EDITOR_A,
		"Dismissing should signal once: %s" % [_changes],
	)
	_check_installed(["linux_debug.x86_64", "version.txt"], "a failed add")


func _test_dismiss_running_job() -> void:
	_clear_installs()
	_jobs.start(EDITOR_A, _add_request(["android_source.zip"]))
	await get_tree().process_frame
	_jobs.dismiss(EDITOR_A)
	_check(_jobs.get_job(EDITOR_A) == null, "Dismissing a running job cancels it")
	await _wait_folder_free()
	_check(_listing(_jobs.work_dir).is_empty(), "Downloaded parts left after a dismiss")


## Two editors of one version share its folder: adding at once works, removing while
## the other adds fails instead of racing it.
func _test_busy_folder() -> void:
	_clear_installs()
	_jobs.start(EDITOR_A, _add_request(["linux_debug.x86_64"]))
	_jobs.start(EDITOR_B, _add_request(["android_source.zip"]))
	_check(_jobs.get_job(EDITOR_B).state == RUNNING, "Adds to one folder may overlap")
	await _wait_job_end(EDITOR_A)
	await _wait_job_end(EDITOR_B)
	_check_installed(
		["linux_debug.x86_64", "android_source.zip", "version.txt"], "two editors adding"
	)

	_jobs.start(EDITOR_B, _add_request(["macos.zip"]))
	_jobs.start(EDITOR_A, _remove_request(["linux_debug.x86_64"]))
	var job := _jobs.get_job(EDITOR_A)
	_check(job.state == FAILED, "Removing from a busy folder should fail")
	_check(job.status_text.length() > 0, "The busy folder failure should say why")
	await _wait_job_end(EDITOR_B)
	_check_installed(
		["linux_debug.x86_64", "android_source.zip", "macos.zip", "version.txt"],
		"a removal from a busy folder",
	)
	_jobs.retry(EDITOR_A)
	_check(_jobs.get_job(EDITOR_A).state == DONE, "The removal works once idle")
	_check_installed(
		["android_source.zip", "macos.zip", "version.txt"], "a retried removal"
	)
	_jobs.dismiss(EDITOR_A)
	_jobs.dismiss(EDITOR_B)
	_clear_installs()


## Quitting the Hub while a job installs its first template leaves no version folder
## with only version.txt, which Godot would take for installed templates.
func _test_quit_while_installing() -> void:
	_clear_installs()
	var jobs := ExportTemplatesJobs.new()
	jobs.work_dir = _jobs.work_dir
	var source := FileRangeSource.new(_tpz)
	# Reads: size, directory, version.txt, then the first template, which unpacks on
	# a worker thread at the end of this frame, when the jobs are freed.
	source.on_read = func(_start: int, _end: int) -> void:
		if source.read_count == 4:
			_check(
				_listing(ExportTemplates.version_dir(FOLDER)) == PackedStringArray(["version.txt"]),
				"version.txt should be installed before the templates",
			)
			jobs.queue_free()
	jobs.set_source_factory(func(_url: String, _known_size: int) -> RangeSource: return source)
	add_child(jobs)
	jobs.start(EDITOR_A, _add_request(["android_source.zip", "linux_debug.x86_64"]))
	for _frame: int in 120:
		if not is_instance_valid(jobs):
			break
		await get_tree().process_frame
	_check(not is_instance_valid(jobs), "The jobs should be freed")
	_check(
		not DirAccess.dir_exists_absolute(ExportTemplates.version_dir(FOLDER)),
		"Quitting should not leave a version folder with only version.txt: %s"
			% _listing(ExportTemplates.version_dir(FOLDER)),
	)
	_check(_listing(_jobs.work_dir).is_empty(), "Downloaded parts left after quitting")
	# The hook refers to its source.
	source.on_read = Callable()


func _make_source(url: String, _known_size: int) -> RangeSource:
	var source := FileRangeSource.new(url)
	source.fail_with = _fail_with
	source.download_pause_sec = _download_pause_sec
	source.on_read = func(start: int, end: int) -> void:
		if _on_read.is_valid():
			_on_read.call(start, end)
	_last_source = source
	return source


func _add_request(files: Array) -> ExportTemplatesJobs.Request:
	var request := ExportTemplatesJobs.Request.new()
	request.editor_name = "Godot 4.7.2"
	request.archive_url = _tpz
	request.add_files = PackedStringArray(files)
	request.folder = FOLDER
	return request


func _remove_request(files: Array) -> ExportTemplatesJobs.Request:
	var request := ExportTemplatesJobs.Request.new()
	request.editor_name = "Godot 4.7.2"
	request.remove_files = PackedStringArray(files)
	request.folder = FOLDER
	return request


func _wait_job_end(editor_path: String) -> void:
	for _frame: int in 600:
		var job := _jobs.get_job(editor_path)
		if job == null or job.state != RUNNING:
			return
		await get_tree().process_frame
	_check(false, "The job of %s did not end" % editor_path)


## Waits for canceled installs to stop writing to the version folder.
func _wait_folder_free() -> void:
	for _frame: int in 600:
		if not _jobs.is_folder_busy(FOLDER):
			return
		await get_tree().process_frame
	_check(false, "The version folder stayed busy")


func _check_installed(expected: Array, what: String) -> void:
	var dir := ExportTemplates.version_dir(FOLDER)
	var listing := _listing(dir)
	listing.sort()
	var wanted := PackedStringArray(expected)
	wanted.sort()
	_check(listing == wanted, "After %s expected %s, got %s" % [what, wanted, listing])
	for file in listing:
		_check(
			_files.has(file) and FileAccess.get_file_as_bytes(dir.path_join(file)) == _files[file],
			"%s differs after %s" % [file, what],
		)
	_check(_listing(_jobs.work_dir).is_empty(), "Downloaded parts left after %s" % what)


## Puts [param files] and version.txt in the version folder, as an earlier install.
func _install_directly(files: Array) -> void:
	_clear_installs()
	var dir := ExportTemplates.version_dir(FOLDER)
	DirAccess.make_dir_recursive_absolute(dir)
	for file: String in files + ["version.txt"]:
		_write(dir.path_join(file), _files[file])


func _clear_installs() -> void:
	edir.remove_recursive(_root.path_join("data"))


func _listing(dir: String) -> PackedStringArray:
	if not DirAccess.dir_exists_absolute(dir):
		return PackedStringArray()
	return DirAccess.get_files_at(dir)


func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


## A small 4.7.2 archive with the file names of the real one; android_source.zip is
## stored and bigger than the directory tail.
func _make_fixture_tpz() -> String:
	_files["version.txt"] = "4.7.2.stable".to_utf8_buffer()
	for path: String in [
		"linux_debug.x86_64", "linux_release.x86_64", "macos.zip", "web_debug.zip",
		"icudt_godot.dat",
	]:
		_files[path] = _text(3000 + path.length() * 41)
	_files["android_source.zip"] = _noise(TemplateArchive.TAIL_SIZE * 2, 3)
	var path := _root.path_join("fixture.tpz")
	var packer := ZIPPacker.new()
	packer.open(path)
	for file in _files:
		packer.compression_level = (
			ZIPPacker.COMPRESSION_NONE
			if file == "android_source.zip"
			else ZIPPacker.COMPRESSION_DEFAULT
		)
		packer.start_file(TEMPLATES_DIR + file)
		packer.write_file(_files[file])
		packer.close_file()
	packer.close()
	return path


func _text(size: int) -> PackedByteArray:
	var text := ""
	while text.length() < size:
		text += "Godot export template %d. " % text.length()
	return text.left(size).to_utf8_buffer()


func _noise(size: int, noise_seed: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var bytes := PackedByteArray()
	bytes.resize(size)
	for i in size:
		bytes[i] = rng.randi() & 0xFF
	return bytes


func _check(condition: bool, message: String) -> void:
	if condition: return
	_failures += 1
	push_error(message)
