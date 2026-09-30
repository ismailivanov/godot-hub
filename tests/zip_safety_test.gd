extends Node


var _failures := 0
var _root := ""


func _ready() -> void:
	_root = ProjectSettings.globalize_path("user://zip-safety-test-%s" % Time.get_ticks_msec())
	DirAccess.make_dir_recursive_absolute(_root)
	_test_zip_slip_is_rejected()
	_test_top_level_files()
	_test_folder_prefixed()
	_test_no_dir_entries()
	_test_macosx_metadata_is_skipped()
	_check(edir.remove_recursive(_root) == OK, "Could not remove the test directory")
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Zip safety tests passed.")
	get_tree().quit()


func _test_zip_slip_is_rejected() -> void:
	_check_slip_rejected("slip.zip", "proj/../../ESCAPED.txt")
	# Windows resolves backslashes as separators too.
	_check_slip_rejected("slip_backslash.zip", "proj\\..\\..\\ESCAPED.txt")


func _check_slip_rejected(file_name: String, slip_entry: String) -> void:
	# The installer creates the project folder before extracting into it.
	var slip_root := _root.path_join(file_name.get_basename())
	var dest := slip_root.path_join("a/b/dest")
	var zip_path := _make_zip(file_name, ["proj/", "proj/project.godot", slip_entry])
	_check(_extract(zip_path, dest) != OK, "Expected %s to be rejected" % slip_entry)
	# Nothing may be written, neither inside the target folder nor above it.
	var written := _list(slip_root)
	_check(written.is_empty(), "Expected nothing written from %s, got %s" % [file_name, written])


func _test_top_level_files() -> void:
	var dest := _root.path_join("top_level")
	var entries: Array[String] = ["project.godot", "icon.svg", "scenes/main.tscn"]
	var zip_path := _make_zip("top_level.zip", entries)
	_check(_extract(zip_path, dest) == OK, "Could not extract a zip with top-level files")
	_check_extracted(dest, entries, "")


func _test_folder_prefixed() -> void:
	var dest := _root.path_join("prefixed")
	var zip_path := _make_zip("prefixed.zip", [
		"proj/",
		"proj/project.godot",
		"proj/scenes/",
		"proj/scenes/main.tscn",
	])
	_check(_extract(zip_path, dest) == OK, "Could not extract a folder-prefixed zip")
	_check_extracted(dest, ["proj/project.godot", "proj/scenes/main.tscn"], "proj/")


func _test_no_dir_entries() -> void:
	var dest := _root.path_join("no_dirs")
	var entries: Array[String] = ["proj/project.godot", "proj/scenes/main.tscn"]
	var zip_path := _make_zip("no_dirs.zip", entries)
	_check(_extract(zip_path, dest) == OK, "Could not extract a zip without folder entries")
	_check_extracted(dest, entries, "proj/")


func _test_macosx_metadata_is_skipped() -> void:
	var dest := _root.path_join("macosx")
	var zip_path := _make_zip("macosx.zip", [
		"proj/",
		"proj/project.godot",
		"__MACOSX/",
		"__MACOSX/proj/",
		"__MACOSX/proj/._project.godot",
	])
	_check(_extract(zip_path, dest) == OK, "Could not extract a zip with __MACOSX entries")
	_check_extracted(dest, ["proj/project.godot"], "proj/")


## Writes a stored (uncompressed) zip holding exactly the given entries.
## ZIPPacker is not used because it adds a folder entry for every parent.
func _make_zip(file_name: String, entries: Array[String]) -> String:
	var zip_path := _root.path_join(file_name)
	var body := StreamPeerBuffer.new()
	var central := StreamPeerBuffer.new()
	for entry: String in entries:
		var name_bytes := entry.to_utf8_buffer()
		var data := PackedByteArray()
		if not entry.ends_with("/"):
			data = _content_of(entry).to_utf8_buffer()
		var crc := _crc32(data)
		var offset := body.get_position()
		body.put_u32(0x04034b50)
		_put_entry_fields(body, crc, data.size(), name_bytes.size())
		body.put_u16(0) # Extra field length.
		body.put_data(name_bytes)
		body.put_data(data)

		central.put_u32(0x02014b50)
		central.put_u16(20) # Version made by.
		_put_entry_fields(central, crc, data.size(), name_bytes.size())
		central.put_u16(0) # Extra field length.
		central.put_u16(0) # Comment length.
		central.put_u16(0) # Disk number.
		central.put_u16(0) # Internal attributes.
		central.put_u32(0x10 if entry.ends_with("/") else 0) # MS-DOS folder attribute.
		central.put_u32(offset)
		central.put_data(name_bytes)

	var central_offset := body.get_position()
	body.put_data(central.data_array)
	body.put_u32(0x06054b50)
	body.put_u16(0) # Disk number.
	body.put_u16(0) # Disk holding the central directory.
	body.put_u16(entries.size())
	body.put_u16(entries.size())
	body.put_u32(central.data_array.size())
	body.put_u32(central_offset)
	body.put_u16(0) # Comment length.

	var file := FileAccess.open(zip_path, FileAccess.WRITE)
	_check(file != null, "Could not create %s" % file_name)
	if file != null:
		file.store_buffer(body.data_array)
		file.close()

	var reader := ZIPReader.new()
	_check(reader.open(zip_path) == OK, "Could not read back %s" % file_name)
	var listed := reader.get_files()
	reader.close()
	_check(listed == PackedStringArray(entries), "Bad fixture %s: %s" % [file_name, listed])
	return zip_path


func _put_entry_fields(
	buffer: StreamPeerBuffer, crc: int, data_size: int, name_size: int
) -> void:
	buffer.put_u16(20) # Version needed to extract.
	buffer.put_u16(0) # Flags.
	buffer.put_u16(0) # Stored, no compression.
	buffer.put_u16(0) # Modification time.
	buffer.put_u16(0x21) # Modification date, 1980-01-01.
	buffer.put_u32(crc)
	buffer.put_u32(data_size)
	buffer.put_u32(data_size)
	buffer.put_u16(name_size)


func _crc32(data: PackedByteArray) -> int:
	var crc := 0xFFFFFFFF
	for byte: int in data:
		crc ^= byte
		for i: int in 8:
			crc = (crc >> 1) ^ 0xEDB88320 if crc & 1 else crc >> 1
	return crc ^ 0xFFFFFFFF


func _extract(zip_path: String, dest: String) -> Error:
	DirAccess.make_dir_recursive_absolute(dest)
	var reader := ZIPReader.new()
	_check(reader.open(zip_path) == OK, "Could not open %s" % zip_path)
	var err := zip.unzip_to_path(reader, dest)
	reader.close()
	return err


## Checks that dest holds exactly the given entries, with prefix stripped.
func _check_extracted(dest: String, entries: Array[String], prefix: String) -> void:
	var expected: Array[String] = []
	for entry: String in entries:
		var rel := entry.trim_prefix(prefix)
		expected.append(rel)
		var path := dest.path_join(rel)
		if not FileAccess.file_exists(path):
			_check(false, "Missing extracted file %s" % path)
			continue
		_check_equal(FileAccess.get_file_as_string(path), _content_of(entry))
	var actual := _list(dest)
	actual.sort()
	expected.sort()
	_check(actual == expected, "Expected files %s, got %s" % [expected, actual])


## Returns the files under dir, relative to it.
func _list(dir: String) -> Array[String]:
	var result: Array[String] = []
	var root := dir.simplify_path() + "/"
	for item: edir.DirListResult in edir.list_recursive(dir, true):
		if item.is_file:
			result.append(item.path.trim_prefix(root))
	return result


func _content_of(entry: String) -> String:
	return "content of %s" % entry


func _check_equal(actual: String, expected: String) -> void:
	_check(actual == expected, "Expected '%s', got '%s'" % [expected, actual])


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
