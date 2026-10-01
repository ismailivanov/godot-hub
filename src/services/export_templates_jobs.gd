class_name ExportTemplatesJobs
extends Node
## Adds and removes the export templates of installed editors, one job per editor,
## without a dialog: the Installs list shows a job's progress in its editor's row.
##
## A job first removes the files it is asked to remove from the version folder, then
## installs the files it is asked to add with an [ExportTemplatesInstaller]. A version
## folder left with nothing but version.txt is removed, as Godot would take it for
## installed templates. Jobs are keyed by the editor's path; a failed or finished job
## stays until it is dismissed or replaced.


## Emitted when the job of the editor at [param editor_path] starts, progresses, ends
## or goes away.
signal job_changed(editor_path: String)

## Seconds between progress updates of running jobs.
const PROGRESS_INTERVAL := 0.1
## Share of the progress bar for unpacking an archive downloaded whole.
const UNPACK_SHARE := 0.05
## The file naming the version of a version folder.
const VERSION_FILE := "version.txt"

## Folder downloaded parts go to; the Hub's downloads folder when empty.
var work_dir := ""

## Jobs by editor path.
var _runs: Dictionary[String, _Run] = {}
## Runs whose installer has not stopped yet, canceled ones included: they may still
## write to their version folder.
var _active: Array[_Run] = []
## Makes the sources archives are read from, see [method set_source_factory].
var _source_factory := Callable()
var _since_update := 0.0


func _ready() -> void:
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		# The Hub quits. The installers left the tree first, which stopped them and
		# removed what they half wrote, but no run finishes: a version folder they
		# made holds only version.txt, which Godot would take for installed templates.
		for run in _active:
			var folder := run.folder
			if folder.is_empty() and run.installer != null:
				folder = run.installer.install_dir.get_file()
			_remove_version_folder_if_unused(folder)


func _process(delta: float) -> void:
	_since_update += delta
	if _since_update < PROGRESS_INTERVAL:
		return
	_since_update = 0.0
	# A listener may cancel or dismiss jobs while this loop emits.
	for editor_path: String in _runs.keys():
		var run := _runs.get(editor_path) as _Run
		if run != null and run.job.state == Job.State.RUNNING and run.installer != null:
			_update_progress(run)
			job_changed.emit(editor_path)


## Starts [param request] for the editor at [param editor_path], replacing its failed
## or finished job. Does nothing while the editor has a running job.
func start(editor_path: String, request: Request) -> void:
	var current := get_job(editor_path)
	if current != null and current.state == Job.State.RUNNING:
		return
	var run := _Run.new()
	run.request = request
	run.folder = request.folder
	run.job = Job.new()
	run.job.state = Job.State.RUNNING
	_runs[editor_path] = run
	_active.append(run)
	_run_job(editor_path, run)


## The job of the editor at [param editor_path], or null when it has none.
func get_job(editor_path: String) -> Job:
	var run := _runs.get(editor_path) as _Run
	return run.job if run != null else null


## Stops the running job of the editor at [param editor_path], which goes away at
## once. Files it installed completely stay; half written ones are removed.
func cancel(editor_path: String) -> void:
	var run := _runs.get(editor_path) as _Run
	if run == null or run.job.state != Job.State.RUNNING:
		return
	run.cancelled = true
	_runs.erase(editor_path)
	if run.installer != null:
		run.installer.cancel()
	job_changed.emit(editor_path)


## Runs the failed job of the editor at [param editor_path] again.
func retry(editor_path: String) -> void:
	var run := _runs.get(editor_path) as _Run
	if run != null and run.job.state == Job.State.FAILED:
		start(editor_path, run.request)


## Forgets the job of the editor at [param editor_path], canceling it when it runs.
func dismiss(editor_path: String) -> void:
	var run := _runs.get(editor_path) as _Run
	if run == null:
		return
	if run.job.state == Job.State.RUNNING:
		cancel(editor_path)
		return
	_runs.erase(editor_path)
	job_changed.emit(editor_path)


## True while a job adds or removes templates in the version folder [param folder]
## (e.g. "4.7.2.stable"), or a canceled one still stops there.
func is_folder_busy(folder: String) -> bool:
	for run in _active:
		if not folder.is_empty() and run.folder == folder:
			return true
	return false


## Reads archives with [param factory] instead of HTTP, e.g. local files in tests:
## [code](url: String, known_size: int) -> RangeSource[/code].
func set_source_factory(factory: Callable) -> void:
	_source_factory = factory


func _run_job(editor_path: String, run: _Run) -> void:
	var request := run.request
	if not request.remove_files.is_empty():
		run.job.status_text = tr("Removing export templates...")
		job_changed.emit(editor_path)
		var remove_error := _remove_files(run)
		if not remove_error.is_empty():
			_finish(editor_path, run, remove_error, true)
			return
	if request.add_files.is_empty() and not request.all_files:
		_finish(editor_path, run, "", true)
		return
	if request.archive_url.is_empty():
		_finish(editor_path, run, tr("the release has no export templates archive"), false)
		return

	run.installer = ExportTemplatesInstaller.new()
	add_child(run.installer)
	run.installer.progressed.connect(func() -> void:
		if not run.cancelled:
			_update_progress(run)
			job_changed.emit(editor_path)
	)
	_update_progress(run)
	job_changed.emit(editor_path)
	set_process(true)
	run.installer.start(
		_make_source(request, run.installer), request.add_files, request.all_files, work_dir
	)
	var error: String = await run.installer.finished
	if not run.installer.install_dir.is_empty():
		run.folder = run.installer.install_dir.get_file()
	if not run.installer.missing_files.is_empty():
		Output.push(
			"Export templates not in this release: %s" % ", ".join(run.installer.missing_files)
		)
	# The installer's HTTP request goes with it.
	run.installer.queue_free()
	run.installer = null
	_finish(editor_path, run, error, false)


## Removes [member Request.remove_files] of [param run] from its version folder, and
## folders they leave empty. Returns an error, or an empty string.
func _remove_files(run: _Run) -> String:
	var folder := run.request.folder
	if not ExportTemplates.is_valid_folder_name(folder):
		return tr("the export templates folder is not valid: \"%s\"") % folder.left(40)
	if _is_used_by_others(folder, run, false):
		return tr("other export templates of this version are being installed")
	var dir := ExportTemplates.version_dir(folder)
	for file in run.request.remove_files:
		if (
			file == VERSION_FILE
			or file in run.request.add_files
			or not ExportTemplatesInstaller.is_safe_path(file)
		):
			continue
		var path := dir.path_join(file)
		if not FileAccess.file_exists(path):
			continue
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			return tr("could not remove %s: %s") % [path, error_string(err)]
		_remove_empty_dirs(path.get_base_dir(), dir)
	return ""


## Ends [param run] with [param error] (empty on success): its job fails or is done,
## unless it was canceled, and its version folder goes when it holds nothing else.
func _finish(editor_path: String, run: _Run, error: String, removing: bool) -> void:
	_active.erase(run)
	if not _is_used_by_others(run.folder, run, true):
		_remove_version_folder_if_unused(run.folder)
	if _active.is_empty():
		set_process(false)
	if run.cancelled:
		# Gone from the jobs already; listeners may check is_folder_busy() again.
		job_changed.emit(editor_path)
		return
	var job := run.job
	job.error = error
	if error.is_empty():
		job.state = Job.State.DONE
		job.progress = 1.0
		job.status_text = tr("Export templates updated.")
		Output.push("Export templates of %s updated" % run.request.editor_name)
	else:
		job.state = Job.State.FAILED
		if removing:
			job.status_text = tr("Could not remove the export templates: %s.") % error
		else:
			job.status_text = tr("Could not install the export templates: %s.") % error
		Output.push(
			"Export templates of %s failed: %s" % [run.request.editor_name, error]
		)
	job_changed.emit(editor_path)


func _update_progress(run: _Run) -> void:
	var installer := run.installer
	if run.folder.is_empty() and not installer.install_dir.is_empty():
		run.folder = installer.install_dir.get_file()
	var done := installer.bytes_done()
	var downloaded := clampf(float(done) / maxi(installer.bytes_total, 1), 0.0, 1.0)
	# The file being installed.
	var file := mini(installer.files_done + 1, installer.files_total)
	match installer.stage:
		ExportTemplatesInstaller.Stage.READING:
			run.job.progress = 0.0
			run.job.status_text = tr("Reading the export templates archive...")
		ExportTemplatesInstaller.Stage.DOWNLOADING:
			run.job.progress = downloaded * (1.0 - UNPACK_SHARE)
			run.job.status_text = tr("Downloading export templates (%s / %s)...") % [
				String.humanize_size(done), String.humanize_size(installer.bytes_total),
			]
		ExportTemplatesInstaller.Stage.UNPACKING:
			var unpacked := float(installer.files_done) / maxi(installer.files_total, 1)
			run.job.progress = 1.0 - UNPACK_SHARE + UNPACK_SHARE * unpacked
			run.job.status_text = tr("Unpacking export templates (%d/%d)...") % [
				file, installer.files_total,
			]
		ExportTemplatesInstaller.Stage.INSTALLING:
			run.job.progress = downloaded
			run.job.status_text = tr("Installing export templates (%d/%d, %s / %s)...") % [
				file,
				installer.files_total,
				String.humanize_size(done),
				String.humanize_size(installer.bytes_total),
			]


func _make_source(request: Request, installer: Node) -> RangeSource:
	if _source_factory.is_valid():
		return _source_factory.call(request.archive_url, request.archive_size) as RangeSource
	var http := HTTPRequest.new()
	installer.add_child(http)
	return HttpRangeSource.new(request.archive_url, http, request.archive_size)


## True when a run other than [param run] may write to [param folder]. With
## [param unknown_too], runs that have not read their version.txt yet count too.
func _is_used_by_others(folder: String, run: _Run, unknown_too: bool) -> bool:
	for other in _active:
		if other == run:
			continue
		if other.folder == folder or (unknown_too and other.folder.is_empty()):
			return true
	return false


## Removes the version folder [param folder] when it holds nothing but version.txt.
static func _remove_version_folder_if_unused(folder: String) -> void:
	if not ExportTemplates.is_valid_folder_name(folder):
		return
	var dir := DirAccess.open(ExportTemplates.version_dir(folder))
	if dir == null:
		return
	dir.include_hidden = true
	if not dir.get_directories().is_empty():
		return
	for file in dir.get_files():
		if file != VERSION_FILE:
			return
	dir.remove(VERSION_FILE)
	DirAccess.remove_absolute(ExportTemplates.version_dir(folder))


## Removes [param dir] and its parents up to [param root] (excluded) while empty.
static func _remove_empty_dirs(dir: String, root: String) -> void:
	var current := dir.simplify_path()
	var stop := root.simplify_path().trim_suffix("/") + "/"
	while current.begins_with(stop):
		var opened := DirAccess.open(current)
		if opened == null:
			return
		opened.include_hidden = true
		if not opened.get_files().is_empty() or not opened.get_directories().is_empty():
			return
		if DirAccess.remove_absolute(current) != OK:
			return
		current = current.get_base_dir()


## What a job does: export templates of one version to add and to remove.
class Request extends RefCounted:
	## Name of the editor, for the log.
	var editor_name: String
	## The .tpz archive files are added from.
	var archive_url: String
	## Its size from the release, or 0.
	var archive_size: int
	## Paths in the archive's templates folder, as in
	## [member ExportTemplatesPicker.Selection.files].
	var add_files := PackedStringArray()
	## True to add every file of the archive.
	var all_files: bool
	## Files to remove, relative to the version folder.
	var remove_files := PackedStringArray()
	## The version folder, e.g. "4.7.2.stable". Needed to remove files; when empty,
	## the archive's version.txt names it.
	var folder: String


## The state of a job that the Installs list shows.
class Job extends RefCounted:
	enum State {
		RUNNING,
		FAILED,
		DONE,
	}

	var state: State
	## What the job does or what went wrong, for the editor's row.
	var status_text: String
	## From 0 to 1.
	var progress: float
	## Why the job failed, or empty.
	var error: String


## A started job and what runs it.
class _Run extends RefCounted:
	var request: Request
	var job: Job
	## The version folder, once known.
	var folder: String
	var installer: ExportTemplatesInstaller
	var cancelled := false
