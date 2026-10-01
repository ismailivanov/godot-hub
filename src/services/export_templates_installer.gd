class_name ExportTemplatesInstaller
extends Node
## Installs chosen export templates out of a .tpz archive without downloading all of
## it, like Godot's Export Template Manager.
##
## Reads the archive's central directory from its last 64 KB (or all of it when it is
## bigger, as in Godot 3 .NET archives), then version.txt, which names the version
## folder, then each file: its bytes are downloaded to a fragment, completed into a
## one-entry ZIP and unpacked on a worker thread. When every file is wanted (Godot 3
## archives offer nothing else, and the .NET ones hold over 1300 files) and the disk
## has room for the archive next to them, the archive is downloaded once to the work
## folder instead, its files unpacked from it on a worker thread, and removed. Files
## are written under a temporary name and renamed when complete, so a canceled or
## failed install never leaves a truncated template that Godot would take as
## installed.


## Emitted when one or more files are installed.
signal progressed
## Emitted once when the install ends, after [method start] returns: [param error] is
## empty on success.
signal finished(error: String)
## Emitted every frame while a worker thread unpacks.
signal _ticked

## What an install does, for its progress.
enum Stage {
	## Reads the archive's central directory and version.txt.
	READING,
	## Downloads and unpacks the files one by one.
	INSTALLING,
	## Downloads the whole archive.
	DOWNLOADING,
	## Unpacks the files of the downloaded archive.
	UNPACKING,
}

## Suffix of files being written, renamed away when complete.
const PART_SUFFIX := ".hub-part"
## Times a failed read is tried again, like Godot's template downloader.
const MAX_RETRIES := 3
## Biggest archive downloaded whole: Godot's HTTPRequest counts the bytes it got in 32
## bits. Bigger ones are read file by file.
const MAX_DOWNLOAD_SIZE := 0x7FFFFFFF
## Folder in the Hub's downloads folder that is the work folder by default.
const WORK_FOLDER := "export-templates-parts"
## Seconds after which a file an install left in the work folder is taken as
## abandoned (the Hub was killed): one in use is written or read much sooner.
const STALE_AGE_SEC := 3600
## Uuid constant.
const uuid = preload("res://addons/uuid.gd")

## Folder the templates went to once version.txt is read, e.g.
## ~/.local/share/godot/export_templates/4.7.2.stable.
var install_dir := ""
## Files to install and installed, version.txt included.
var files_total := 0
var files_done := 0
## Compressed bytes of the files to install, or the size of the archive when it is
## downloaded whole.
var bytes_total := 0
## Files asked for that the archive does not have.
var missing_files := PackedStringArray()
## What the install does now.
var stage := Stage.READING
## Returns the free bytes of the disk holding a folder, or -1 when unknown:
## [code](path: String) -> int[/code]. Tests replace it.
var space_left := disk_space_left
## [constant STALE_AGE_SEC]; tests lower it.
var stale_age_sec := STALE_AGE_SEC

var _source: RangeSource
var _running := false
var _cancelled := false
var _bytes_finished := 0
## Downloaded parts and unfinished files to remove when the install stops.
var _temp_paths: Array[String] = []
var _task_id := -1
## Unpacks a whole archive on a worker thread while it runs.
var _unpack_job: UnpackJob
var _work_dir := ""


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	_ticked.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		# Dismissed while running: nothing may stay half written.
		if _running:
			_cancelled = true
			_source.cancel()
			if _unpack_job != null:
				_unpack_job.cancel()
		_wait_for_task()
		_remove_temp_files()


## Installs [param files] (paths in the archive's templates folder, e.g.
## "linux_debug.x86_64") from the archive [param source] reads, or every file with
## [param all_files]. Emits [signal finished] when done. Downloaded parts go to
## [param work_dir] (a [constant WORK_FOLDER] in the Hub's downloads folder when empty),
## where parts that installs left long ago are removed.
func start(
	source: RangeSource, files: PackedStringArray, all_files := false, work_dir := ""
) -> void:
	assert(not _running)
	_source = source
	_running = true
	_cancelled = false
	install_dir = ""
	files_total = 0
	files_done = 0
	bytes_total = 0
	_bytes_finished = 0
	missing_files.clear()
	stage = Stage.READING
	_work_dir = work_dir
	if _work_dir.is_empty():
		_work_dir = ProjectSettings.globalize_path(
			Config.DOWNLOADS_PATH.ret() as String
		).path_join(WORK_FOLDER)
	DirAccess.make_dir_recursive_absolute(_work_dir)
	_remove_stale_files()
	var error := await _install(files, all_files)
	_remove_temp_files()
	_running = false
	if _cancelled and error.is_empty():
		error = tr("canceled")
	# Deferred: an install that fails at once still finishes after start() returns.
	finished.emit.call_deferred(error)


## Stops the install; [signal finished] follows with an error.
func cancel() -> void:
	if not _running:
		return
	_cancelled = true
	_source.cancel()
	if _unpack_job != null:
		_unpack_job.cancel()


func is_running() -> bool:
	return _running


## Compressed bytes downloaded so far, of [member bytes_total].
func bytes_done() -> int:
	return mini(_bytes_finished + (_source.downloaded_bytes() if _running else 0), bytes_total)


func _install(files: PackedStringArray, all_files: bool) -> String:
	var size := await _source.async_size()
	if _cancelled or not size.error.is_empty():
		return size.error
	var archive_size := size.total_size
	var tail_range := TemplateArchive.tail_range(archive_size)
	var tail := await _read(tail_range[0], tail_range[1])
	if _cancelled or not tail.error.is_empty():
		return tail.error
	var index := TemplateArchive.parse_index(tail.bytes, archive_size)
	var directory_range := TemplateArchive.directory_range(index)
	if not directory_range.is_empty():
		# Bigger than the last 64 KB: Godot 3 .NET archives list over 1300 files.
		var directory := await _read(directory_range[0], directory_range[1])
		if _cancelled or not directory.error.is_empty():
			return directory.error
		index = TemplateArchive.parse_index(directory.bytes, archive_size)
	if not index.error.is_empty():
		return tr("could not read the archive: %s") % index.error
	var version_entry := index.entry_of("version.txt")
	if version_entry == null:
		return tr("the archive has no version.txt")

	var wanted := index.files() if all_files else files
	var entries: Array[TemplateArchive.Entry] = []
	for file in wanted:
		var entry := index.entry_of(file)
		if entry == null:
			missing_files.append(file)
		elif file != "version.txt" and is_safe_path(file):
			entries.append(entry)
			bytes_total += entry.compressed_size
	files_total = entries.size() + 1
	bytes_total += version_entry.compressed_size

	# version.txt names the folder; unpacked into the work folder first, before
	# anything big is downloaded.
	var version_path := _work_dir.path_join("version-%s.txt" % uuid.v4().substr(0, 8))
	var error := await _fetch(index, version_entry, version_path)
	if _cancelled or not error.is_empty():
		return error
	var version_bytes := FileAccess.get_file_as_bytes(version_path)
	DirAccess.remove_absolute(version_path)
	var version := version_bytes.get_string_from_utf8().strip_edges()
	if not ExportTemplates.is_valid_folder_name(version):
		return tr("the archive's version.txt is not valid: \"%s\"") % version.left(40)
	install_dir = ExportTemplates.version_dir(version)
	var made := DirAccess.make_dir_recursive_absolute(install_dir)
	if made != OK:
		return tr("could not create %s: %s") % [install_dir, error_string(made)]
	var needed := 0
	for entry in entries:
		needed += entry.uncompressed_size
	if not _has_room(archive_size + needed):
		# The files replace those installed, so less room may do. Only looked at now:
		# their sizes took 17 ms to read for the 1400 files of a .NET-like archive.
		needed = maxi(needed - _installed_size(index, entries), 0)
	var space := space_left.call(install_dir) as int
	if space != -1 and space < needed:
		return tr("not enough disk space: %s needed, %s free") % [
			String.humanize_size(needed), String.humanize_size(space),
		]
	# One request instead of one per file, each of which follows GitHub's redirect.
	var whole := (
		(all_files or _wants_every_file(index, wanted))
		and archive_size <= MAX_DOWNLOAD_SIZE
		and _has_room(archive_size + needed)
	)
	# Like Godot's install from a .tpz file, which copies version.txt too.
	var version_target := install_dir.path_join("version.txt")
	var version_part := _part_path(version_target)
	_temp_paths.append(version_part)
	var version_file := FileAccess.open(version_part, FileAccess.WRITE)
	if version_file == null or not version_file.store_buffer(version_bytes):
		return tr("could not write %s") % version_target
	version_file.close()
	error = _move_into_place(version_part, version_target, 0)
	if not error.is_empty():
		return error
	_file_done(version_entry)

	if whole:
		var archive_path := _work_dir.path_join("templates-%s.tpz" % uuid.v4().substr(0, 8))
		stage = Stage.DOWNLOADING
		bytes_total = archive_size
		_bytes_finished = 0
		error = await _download_archive(archive_path, archive_size)
		if _cancelled or not error.is_empty():
			return error
		stage = Stage.UNPACKING
		return await _unpack_archive(archive_path, index, entries)
	stage = Stage.INSTALLING
	for entry in entries:
		if _cancelled:
			return ""
		var target := _target_of(index, entry)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var part := _part_path(target)
		error = await _fetch(index, entry, part)
		if not error.is_empty():
			return error
		if _cancelled:
			return ""
		error = _move_into_place(part, target, entry.unix_permissions)
		if not error.is_empty():
			return error
		_file_done(entry)
	return ""


## Downloads [param entry] and unpacks it to [param out_path], which is removed when the
## install stops early.
func _fetch(index: TemplateArchive.Index, entry: TemplateArchive.Entry, out_path: String) -> String:
	var fragment_path := _work_dir.path_join("template-%s.zip" % uuid.v4().substr(0, 8))
	_temp_paths.append(fragment_path)
	_temp_paths.append(out_path)
	var fragment_range := TemplateArchive.fragment_range(index, entry)
	var read := await _read(fragment_range[0], fragment_range[1], fragment_path)
	if _cancelled or not read.error.is_empty():
		return read.error
	var error := await _extract_off_thread(func() -> String:
		return TemplateArchive.extract_fragment(fragment_path, entry, out_path)
	)
	DirAccess.remove_absolute(fragment_path)
	_temp_paths.erase(fragment_path)
	return error


## Reads a byte range, trying again after errors a later try may not have (a dropped
## connection), but not after a cancel, a server without Range support or a full disk.
func _read(start: int, end: int, target_path := "") -> RangeSource.Result:
	var result: RangeSource.Result
	for _try: int in MAX_RETRIES + 1:
		result = await _source.async_read(start, end, target_path)
		if (
			result.error.is_empty()
			or result.cancelled
			or _cancelled
			or result.range_ignored
			or result.write_failed
		):
			break
		Output.push("Export templates read failed, trying again: %s" % result.error)
	return result


## Downloads the whole archive of [param archive_size] bytes to [param path] in one
## request, trying again like [method _read]. Returns an error, or an empty string.
func _download_archive(path: String, archive_size: int) -> String:
	_temp_paths.append(path)
	var error := ""
	for _try: int in MAX_RETRIES + 1:
		var result := await _source.async_download(path)
		error = result.error
		if error.is_empty():
			# E.g. an answer without a length whose connection closed early.
			var size := FileAccess.get_size(path) if FileAccess.file_exists(path) else 0
			if size != archive_size:
				error = tr("got %d bytes instead of %d") % [size, archive_size]
		# A full disk stays full: each try would download the whole archive again.
		if error.is_empty() or result.cancelled or _cancelled or result.write_failed:
			break
		Output.push("Export templates download failed, trying again: %s" % error)
	if error.is_empty():
		_bytes_finished = archive_size
	return error


## Unpacks [param entries] out of the downloaded archive at [param archive_path] into
## [member install_dir] on a worker thread, like the files fetched one by one: each
## into a part that is renamed into place when complete. Returns an error, or an empty
## string.
func _unpack_archive(
	archive_path: String, index: TemplateArchive.Index, entries: Array[TemplateArchive.Entry]
) -> String:
	if _cancelled:
		return ""
	var job := UnpackJob.new()
	job.archive_path = archive_path
	job.entries = entries
	for entry in entries:
		var target := _target_of(index, entry)
		var part := _part_path(target)
		# The worker thread removes a part it does not complete; removed here too
		# should it not get to.
		_temp_paths.append(part)
		job.targets.append(target)
		job.parts.append(part)
	_unpack_job = job
	_task_id = WorkerThreadPool.add_task(func() -> void:
		job.run()
	, false, "Unpack export templates")
	set_process(true)
	var reported := 0
	while not WorkerThreadPool.is_task_completed(_task_id):
		await _ticked
		reported = _report_unpacked(job, reported)
	set_process(false)
	_wait_for_task()
	_unpack_job = null
	_report_unpacked(job, reported)
	return job.error


## Counts the files [param job] unpacked since [param reported] of them were as done,
## and returns how many it unpacked.
func _report_unpacked(job: UnpackJob, reported: int) -> int:
	var unpacked := job.unpacked()
	if unpacked > reported:
		files_done += unpacked - reported
		progressed.emit()
	return unpacked


## Runs [param extract], which unpacks a file and returns an error, on a worker
## thread, so big templates do not freeze the Hub.
func _extract_off_thread(extract: Callable) -> String:
	var job := ExtractJob.new()
	_task_id = WorkerThreadPool.add_task(func() -> void:
		job.error = extract.call()
	, false, "Unpack export template")
	set_process(true)
	while not WorkerThreadPool.is_task_completed(_task_id):
		await _ticked
	set_process(false)
	_wait_for_task()
	return job.error


## Where [param entry] of [param index] is installed.
func _target_of(index: TemplateArchive.Index, entry: TemplateArchive.Entry) -> String:
	return install_dir.path_join(entry.name.substr(index.contents_dir().length()))


## Bytes of the files installed where [param entries] of [param index] go.
func _installed_size(
	index: TemplateArchive.Index, entries: Array[TemplateArchive.Entry]
) -> int:
	var size := 0
	for entry in entries:
		var target := _target_of(index, entry)
		if FileAccess.file_exists(target):
			size += FileAccess.get_size(target)
	return size


## False when the disk of the work folder or of [member install_dir] has less than
## [param bytes] free. Each is asked for all of them, as they are on one disk as a
## rule.
func _has_room(bytes: int) -> bool:
	for path: String in [_work_dir, install_dir]:
		var space := space_left.call(path) as int
		if space != -1 and space < bytes:
			return false
	return true


func _wait_for_task() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


## Where [param target] is written before it is complete. Unique, so two installs of
## the same version never write or rename each other's parts.
func _part_path(target: String) -> String:
	return "%s.%s%s" % [target, uuid.v4().substr(0, 8), PART_SUFFIX]


## Renames the complete file [param from] to [param to] and sets its Unix permissions
## from the archive (Godot's templates are executable). The rename replaces an
## installed [param to], atomically outside Windows.
func _move_into_place(from: String, to: String, permissions: int) -> String:
	var err := _rename_into_place(from, to, permissions)
	if err != OK:
		return tr("could not write %s: %s") % [to, error_string(err)]
	_temp_paths.erase(from)
	return ""


func _file_done(entry: TemplateArchive.Entry) -> void:
	files_done += 1
	_bytes_finished += entry.compressed_size
	progressed.emit()


func _remove_temp_files() -> void:
	for path in _temp_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_temp_paths.clear()


## Removes what installs that could not clean up (the Hub was killed) left in the work
## folder long ago: an archive downloaded whole is over a gigabyte.
func _remove_stale_files() -> void:
	# The names of the downloaded archive, parts of it and version.txt files.
	var temp_name := RegEx.create_from_string(
		"^(templates-[0-9a-f]{8}\\.tpz|template-[0-9a-f]{8}\\.zip|version-[0-9a-f]{8}\\.txt)$"
	)
	var now := Time.get_unix_time_from_system()
	for file in DirAccess.get_files_at(_work_dir):
		var path := _work_dir.path_join(file)
		if (
			temp_name.search(file) != null
			and now - FileAccess.get_modified_time(path) >= stale_age_sec
		):
			DirAccess.remove_absolute(path)


## Free bytes on the disk holding the folder [param path], or -1 when unknown.
static func disk_space_left(path: String) -> int:
	var dir := DirAccess.open(path)
	# 0 is also what an error gives.
	var space := dir.get_space_left() if dir != null else 0
	return space if space > 0 else -1


## True when [param path], relative to the version folder, stays inside it.
static func is_safe_path(path: String) -> bool:
	var simple := path.replace("\\", "/").simplify_path()
	return (
		not simple.is_empty()
		and not simple.is_absolute_path()
		and not simple.begins_with("..")
		and not simple.contains("/../")
		and simple == path
	)


## True when [param wanted] holds every file of [param index] that an install of all
## of them would install, but version.txt, which is always installed.
static func _wants_every_file(index: TemplateArchive.Index, wanted: PackedStringArray) -> bool:
	for file in index.files():
		if file != "version.txt" and is_safe_path(file) and not file in wanted:
			return false
	return true


## Renames [param from] to [param to] and sets the Unix permissions; see
## [method _move_into_place]. Touches files only, so it runs on any thread.
static func _rename_into_place(from: String, to: String, permissions: int) -> Error:
	var err := DirAccess.rename_absolute(from, to)
	if err == OK and permissions != 0 and OS.get_name() != "Windows":
		FileAccess.set_unix_permissions(to, permissions)
	return err


## A file unpacked on a worker thread.
class ExtractJob:
	var error := ""


## The files of a downloaded archive, unpacked on a worker thread by [method run].
class UnpackJob:
	var archive_path: String
	var entries: Array[TemplateArchive.Entry] = []
	## Where each entry goes, and the part it is written to until it is complete.
	var targets := PackedStringArray()
	var parts := PackedStringArray()
	## Why unpacking failed, or empty.
	var error := ""

	var _mutex := Mutex.new()
	var _unpacked := 0
	var _cancelled := false

	## Unpacks the entries in order, each into its part, renamed into place when
	## complete. Runs on a worker thread; a cancel stops it before the next entry.
	func run() -> void:
		var reader := ZIPReader.new()
		var opened := reader.open(archive_path)
		if opened != OK:
			# tr() is thread-safe: it asks TranslationServer, a global singleton.
			error = tr("could not open %s: %s") % [archive_path, error_string(opened)]
			return
		for i in entries.size():
			if _is_cancelled():
				break
			DirAccess.make_dir_recursive_absolute(targets[i].get_base_dir())
			error = TemplateArchive.extract_entry(reader, entries[i], parts[i])
			if error.is_empty():
				var err := ExportTemplatesInstaller._rename_into_place(
					parts[i], targets[i], entries[i].unix_permissions
				)
				if err != OK:
					error = tr("could not write %s: %s") % [targets[i], error_string(err)]
			if not error.is_empty():
				if FileAccess.file_exists(parts[i]):
					DirAccess.remove_absolute(parts[i])
				break
			_mutex.lock()
			_unpacked += 1
			_mutex.unlock()
		reader.close()

	## Files unpacked so far.
	func unpacked() -> int:
		_mutex.lock()
		var count := _unpacked
		_mutex.unlock()
		return count

	func cancel() -> void:
		_mutex.lock()
		_cancelled = true
		_mutex.unlock()

	func _is_cancelled() -> bool:
		_mutex.lock()
		var cancelled := _cancelled
		_mutex.unlock()
		return cancelled
