class_name RangeSource
extends RefCounted
## Reads byte ranges of a file, e.g. single templates out of a remote .tpz archive, or
## downloads all of it at once.
##
## [HttpRangeSource] reads them with HTTP Range requests, [FileRangeSource] from a
## file on disk (tests, local archives). One read or download runs at a time. Errors
## are in the user's language: the Installs list shows them.


## Returns the file's size in bytes, or a [member Result.error].
func async_size() -> Result:
	@warning_ignore("redundant_await")
	var result := await async_read(0, 0)
	if result.error.is_empty() and result.total_size < 0:
		result.error = tr("the file size is unknown")
	return result


## Reads bytes [param start] to [param end] (both included). With an empty
## [param target_path] they come back in [member Result.bytes], else they are written
## to that file.
func async_read(start: int, end: int, target_path := "") -> Result:
	var result := Result.new()
	result.error = "not implemented"
	return result


## Downloads the whole file to [param target_path] with one request: quicker than a
## read per file when every file of an archive is wanted. A failed or canceled
## download may leave part of the file there.
func async_download(target_path: String) -> Result:
	var result := Result.new()
	result.error = "not implemented"
	return result


## Bytes of the running read or download received so far.
func downloaded_bytes() -> int:
	return 0


## Stops the running read or download, which then returns [member Result.cancelled].
func cancel() -> void:
	pass


## What a read or download returned.
class Result:
	## Why the read failed, or empty.
	var error := ""
	## True when [method RangeSource.cancel] stopped the read.
	var cancelled := false
	## True when the server sent the whole file instead of the range: trying again
	## would not help, see [constant HttpRangeSource.NO_RANGE_ERROR].
	var range_ignored := false
	## True when the bytes could not be written to disk, e.g. a full disk: trying again
	## would download them again for nothing.
	var write_failed := false
	var bytes := PackedByteArray()
	## Size of the whole file when the source said, else -1.
	var total_size := -1
