class_name TemplateArchive
extends RefCounted
## Reads single files out of a ZIP archive fetched in byte ranges, the way Godot's
## Export Template Manager downloads one template out of a .tpz.
##
## Works on bytes and files only, so it runs on any thread: [method parse_index] reads
## the central directory from the archive's last bytes (or, when it is bigger than
## those, from the range [method directory_range] gives), [method fragment_range] says
## which bytes hold an entry, and [method extract_fragment] turns those bytes into the
## entry's content by completing them into a one-entry ZIP that [ZIPReader] reads.
## [method extract_entry] reads entries out of a whole archive downloaded at once
## instead.


## Bytes read from the end of the archive for its central directory, like Godot.
const TAIL_SIZE := 0x10000
## Biggest central directory read when it does not fit in [constant TAIL_SIZE]: Godot 3
## .NET archives list over 1300 files in about 170 KB; more means a broken archive.
const MAX_DIRECTORY_SIZE := 16 * 1024 * 1024
## Bytes fetched for an entry's local extra field on top of its central one: Info-ZIP
## writes longer extra fields in local headers.
const LOCAL_EXTRA_SLACK := 1024

const _EOCD_SIGNATURE := 0x06054b50
const _CD_SIGNATURE := 0x02014b50
const _LOCAL_SIGNATURE := 0x04034b50
const _EOCD_SIZE := 22
const _CD_HEADER_SIZE := 46
const _LOCAL_HEADER_SIZE := 30
## Sizes and offsets of ZIP64 archives, which Godot's templates are not.
const _ZIP64_MARKER := 0xFFFFFFFF


## Byte range (first and last byte) holding the central directory of an archive of
## [param archive_size] bytes.
static func tail_range(archive_size: int) -> PackedInt64Array:
	return PackedInt64Array([maxi(0, archive_size - TAIL_SIZE), archive_size - 1])


## Reads the central directory from [param tail], the last bytes of an archive of
## [param archive_size] bytes. Check [member Index.error]: when the directory starts
## before [param tail], [method directory_range] gives the bytes to parse instead.
static func parse_index(tail: PackedByteArray, archive_size: int) -> Index:
	var index := Index.new()
	index.archive_size = archive_size
	var eocd := -1
	for pos in range(tail.size() - _EOCD_SIZE, -1, -1):
		if tail.decode_u32(pos) == _EOCD_SIGNATURE:
			eocd = pos
			break
	if eocd == -1:
		index.error = "no ZIP end of central directory"
		return index
	var count := tail.decode_u16(eocd + 10)
	index.cd_offset = tail.decode_u32(eocd + 16)
	if count == 0xFFFF or index.cd_offset == _ZIP64_MARKER:
		index.error = "ZIP64 archives are not supported"
		return index
	var at := index.cd_offset - (archive_size - tail.size())
	if at < 0:
		index.error = "the central directory does not fit in the last %d bytes" % tail.size()
		if archive_size - index.cd_offset <= MAX_DIRECTORY_SIZE:
			index.directory_start = index.cd_offset
		return index
	for i in count:
		if at + _CD_HEADER_SIZE > tail.size() or tail.decode_u32(at) != _CD_SIGNATURE:
			index.error = "broken central directory record %d" % i
			return index
		var entry := Entry.new()
		entry.method = tail.decode_u16(at + 10)
		entry.compressed_size = tail.decode_u32(at + 20)
		entry.uncompressed_size = tail.decode_u32(at + 24)
		entry.name_length = tail.decode_u16(at + 28)
		var extra_length := tail.decode_u16(at + 30)
		var comment_length := tail.decode_u16(at + 32)
		entry.unix_permissions = (tail.decode_u32(at + 38) >> 16) & 0x1FF
		entry.local_offset = tail.decode_u32(at + 42)
		var record_size := _CD_HEADER_SIZE + entry.name_length + extra_length + comment_length
		if at + record_size > tail.size():
			index.error = "broken central directory record %d" % i
			return index
		if _ZIP64_MARKER in [entry.compressed_size, entry.uncompressed_size, entry.local_offset]:
			index.error = "ZIP64 archives are not supported"
			return index
		entry.name = tail.slice(
			at + _CD_HEADER_SIZE, at + _CD_HEADER_SIZE + entry.name_length
		).get_string_from_utf8()
		entry.record = tail.slice(at, at + record_size)
		index.entries[entry.name] = entry
		at += record_size
	return index


## Byte range (first and last byte) of the whole central directory and its end record,
## to read and parse again when [param index], parsed from the archive's last bytes,
## says the directory starts before them. Empty when there is nothing more to read.
static func directory_range(index: Index) -> PackedInt64Array:
	if index.directory_start < 0:
		return PackedInt64Array()
	return PackedInt64Array([index.directory_start, index.archive_size - 1])


## Byte range (first and last byte) of the archive holding [param entry]: its local
## header, name, extra field and data, with room for a longer local extra field.
static func fragment_range(index: Index, entry: Entry) -> PackedInt64Array:
	var start := entry.local_offset
	var end := (
		start + _LOCAL_HEADER_SIZE + entry.name_length + entry.record.size()
		+ LOCAL_EXTRA_SLACK + entry.compressed_size - 1
	)
	# File data ends where the central directory starts.
	if index.cd_offset > start:
		end = mini(end, index.cd_offset - 1)
	return PackedInt64Array([start, mini(end, index.archive_size - 1)])


## Returns [param fragment] (bytes from [method fragment_range]) completed into a ZIP
## holding only [param entry], or an empty array when the bytes do not hold it.
static func mini_zip(fragment: PackedByteArray, entry: Entry) -> PackedByteArray:
	if not _fragment_error(fragment.slice(0, _LOCAL_HEADER_SIZE), fragment.size(), entry).is_empty():
		return PackedByteArray()
	var result := fragment.duplicate()
	result.append_array(_directory_of(entry, fragment.size()))
	return result


## Completes the fragment at [param fragment_path] into a one-entry ZIP, reads
## [param entry] from it and writes its content to [param out_path]. Returns an error
## message, or an empty string. Leaves the fragment in place. Touches files only, so
## it runs on any thread.
static func extract_fragment(fragment_path: String, entry: Entry, out_path: String) -> String:
	var fragment := FileAccess.open(fragment_path, FileAccess.READ_WRITE)
	if fragment == null:
		return "could not open the downloaded part of %s" % entry.name
	var header := fragment.get_buffer(_LOCAL_HEADER_SIZE)
	var error := _fragment_error(header, fragment.get_length(), entry)
	if not error.is_empty():
		return error
	var fragment_size := fragment.get_length()
	fragment.seek_end()
	fragment.store_buffer(_directory_of(entry, fragment_size))
	fragment.close()

	var data := PackedByteArray()
	if entry.uncompressed_size > 0:
		var reader := ZIPReader.new()
		if reader.open(fragment_path) != OK:
			return "could not open the downloaded part of %s" % entry.name
		data = reader.read_file(entry.name)
		reader.close()
		if data.size() != entry.uncompressed_size:
			return "could not unpack %s" % entry.name
	return _write_file(data, out_path)


## Reads [param entry] with [param reader], open on the whole archive, and writes its
## content to [param out_path]. Returns an error message, or an empty string. Touches
## files only, so it runs on any thread that has [param reader] to itself.
static func extract_entry(reader: ZIPReader, entry: Entry, out_path: String) -> String:
	var data := PackedByteArray()
	if entry.uncompressed_size > 0:
		data = reader.read_file(entry.name)
		if data.size() != entry.uncompressed_size:
			return "could not unpack %s" % entry.name
	return _write_file(data, out_path)


## Writes [param data] to [param out_path]. Returns an error message, or an empty
## string.
static func _write_file(data: PackedByteArray, out_path: String) -> String:
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	if out == null:
		return "could not write %s: %s" % [
			out_path, error_string(FileAccess.get_open_error()),
		]
	var stored := out.store_buffer(data)
	out.close()
	if not stored:
		return "could not write %s" % out_path
	return ""


## Why [param fragment] cannot hold [param entry], or empty: [param header] is its
## first bytes and [param length] its size.
static func _fragment_error(header: PackedByteArray, length: int, entry: Entry) -> String:
	if header.size() < _LOCAL_HEADER_SIZE or header.decode_u32(0) != _LOCAL_SIGNATURE:
		return "the downloaded part of %s is not a ZIP entry" % entry.name
	var needed := (
		_LOCAL_HEADER_SIZE + header.decode_u16(26) + header.decode_u16(28)
		+ entry.compressed_size
	)
	if length < needed:
		return "the downloaded part of %s is too small: %d of %d bytes" % [
			entry.name, length, needed,
		]
	return ""


## The central directory and its end record of a ZIP with [param entry] alone, at the
## start, followed by [param data_size] bytes before the directory.
static func _directory_of(entry: Entry, data_size: int) -> PackedByteArray:
	var record := entry.record.duplicate()
	# The entry is at the very start of the mini ZIP.
	record.encode_u32(42, 0)
	var end := PackedByteArray()
	end.resize(_EOCD_SIZE)
	end.encode_u32(0, _EOCD_SIGNATURE)
	end.encode_u16(8, 1)
	end.encode_u16(10, 1)
	end.encode_u32(12, record.size())
	end.encode_u32(16, data_size)
	record.append_array(end)
	return record


## The central directory of an archive.
class Index:
	var archive_size: int
	## Where the central directory starts.
	var cd_offset: int
	## Where to read the directory from when it does not fit in the bytes parsed, see
	## [method TemplateArchive.directory_range]; -1 otherwise.
	var directory_start := -1
	## Entries by name, e.g. "templates/version.txt", in archive order.
	var entries: Dictionary[String, Entry] = {}
	## Why the directory could not be read, or empty.
	var error := ""

	## [method contents_dir] once found: looked up per file, it took a third of a
	## second for the 1300 files of Godot 3 .NET archives.
	var _contents_dir := ""
	var _contents_dir_known := false

	## The folder holding version.txt in the archive, with a trailing slash, e.g.
	## "templates/", or empty when it is at the top or missing.
	func contents_dir() -> String:
		if _contents_dir_known:
			return _contents_dir
		var best := ""
		var found := false
		for entry_name in entries:
			if entry_name.get_file() != "version.txt":
				continue
			var dir := entry_name.get_base_dir()
			if not found or dir.length() < best.length():
				best = dir
				found = true
		_contents_dir = best + "/" if not best.is_empty() else ""
		_contents_dir_known = true
		return _contents_dir

	## Paths of the files under [method contents_dir], relative to it, e.g.
	## "linux_debug.x86_64". Leaves out folders and macOS metadata.
	func files() -> PackedStringArray:
		var prefix := contents_dir()
		var result := PackedStringArray()
		for entry_name in entries:
			if entry_name.ends_with("/") or not entry_name.begins_with(prefix):
				continue
			var path := entry_name.substr(prefix.length())
			if path.is_empty() or path.begins_with("__MACOSX") or path.contains("/__MACOSX"):
				continue
			result.append(path)
		return result

	## The entry of [param path], a path relative to [method contents_dir], or null.
	func entry_of(path: String) -> Entry:
		return entries.get(contents_dir() + path) as Entry

	## Compressed size of [param path], relative to [method contents_dir], or 0.
	func compressed_size_of(path: String) -> int:
		var entry := entry_of(path)
		return entry.compressed_size if entry != null else 0


## One file of an archive, as its central directory describes it.
class Entry:
	var name: String
	## Bytes of the name in UTF-8.
	var name_length: int
	## 0 stored, 8 deflated.
	var method: int
	var compressed_size: int
	var uncompressed_size: int
	## Where the entry's local header starts in the archive.
	var local_offset: int
	## Unix permission bits (0 when the archive was not made on Unix).
	var unix_permissions: int
	## The entry's whole central directory record.
	var record: PackedByteArray
