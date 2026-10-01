class_name FileRangeSource
extends RangeSource
## Reads byte ranges of a file on disk or copies all of it, e.g. a local .tpz, or one
## in tests.


## Bytes copied per step of a download.
const DOWNLOAD_CHUNK_SIZE := 1 << 20

## Called with the start and end of each read before it runs, e.g. to cancel or fail
## an install at a given read in tests.
var on_read := Callable()
## Called halfway through each download with the bytes written so far, e.g. to cancel
## or fail it in tests.
var on_download := Callable()
## When set, reads fail with this error, like a server that is down, and downloads
## fail halfway.
var fail_with := ""
## When false, reads fail like a server answering a Range request with the whole file.
var honor_range := true
## When true, reads to a file and downloads (halfway) fail like a full disk.
var disk_full := false
## Seconds each download waits halfway, like a slow network.
var download_pause_sec := 0.0
## Number of reads done.
var read_count := 0
## Number of downloads done.
var download_count := 0

var _path: String
var _cancelled := false
var _downloaded := 0


func _init(path: String) -> void:
	_path = path


func async_read(start: int, end: int, target_path := "") -> RangeSource.Result:
	read_count += 1
	_cancelled = false
	if on_read.is_valid():
		on_read.call(start, end)
	var result := RangeSource.Result.new()
	if _cancelled:
		result.cancelled = true
		result.error = tr("canceled")
		return result
	if not fail_with.is_empty():
		result.error = fail_with
		return result
	if not honor_range:
		result.error = tr(HttpRangeSource.NO_RANGE_ERROR)
		result.range_ignored = true
		return result
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		result.error = tr("could not open %s") % _path
		return result
	result.total_size = file.get_length()
	if start < 0 or end < start or end >= result.total_size:
		result.error = tr("range %d-%d is outside the file") % [start, end]
		return result
	file.seek(start)
	var bytes := file.get_buffer(end - start + 1)
	if target_path.is_empty():
		result.bytes = bytes
		return result
	var out := FileAccess.open(target_path, FileAccess.WRITE)
	if out == null or disk_full or not out.store_buffer(bytes):
		_write_failed(result, target_path)
	return result


## Copies the file in steps, failing or stopping halfway like a dropped or canceled
## network download, which leaves part of the file.
func async_download(target_path: String) -> RangeSource.Result:
	download_count += 1
	_cancelled = false
	_downloaded = 0
	var result := RangeSource.Result.new()
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		result.error = tr("could not open %s") % _path
		return result
	var out := FileAccess.open(target_path, FileAccess.WRITE)
	if out == null:
		_write_failed(result, target_path)
		return result
	result.total_size = file.get_length()
	await _async_copy(file, out, target_path, result)
	# Closed now, not when this coroutine's variables go: the caller reads the size.
	out.close()
	return result


func downloaded_bytes() -> int:
	return _downloaded


func cancel() -> void:
	_cancelled = true


## Fails [param result] like a write to [param target_path] that did not go through.
func _write_failed(result: RangeSource.Result, target_path: String) -> void:
	result.error = tr("could not write %s") % target_path
	result.write_failed = true


## Copies [param from] to [param to] (at [param target_path]) for
## [method async_download], into [param result], stopping or failing halfway as the
## hooks say.
func _async_copy(
	from: FileAccess, to: FileAccess, target_path: String, result: RangeSource.Result
) -> void:
	var half := result.total_size >> 1
	if not _copy(from, to, half):
		_write_failed(result, target_path)
		return
	if on_download.is_valid():
		on_download.call(_downloaded)
	if download_pause_sec > 0.0:
		await (Engine.get_main_loop() as SceneTree).create_timer(download_pause_sec).timeout
	if _cancelled:
		result.cancelled = true
		result.error = tr("canceled")
		return
	if not fail_with.is_empty():
		result.error = fail_with
		return
	if disk_full or not _copy(from, to, result.total_size - half):
		_write_failed(result, target_path)


## Copies [param size] bytes from [param from] to [param to]. Returns false when
## writing fails.
func _copy(from: FileAccess, to: FileAccess, size: int) -> bool:
	var left := size
	while left > 0:
		var chunk := from.get_buffer(mini(left, DOWNLOAD_CHUNK_SIZE))
		if chunk.is_empty() or not to.store_buffer(chunk):
			return false
		left -= chunk.size()
		_downloaded += chunk.size()
	return true
