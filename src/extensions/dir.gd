class_name edir
extends RefCounted
## Provides edir.


# https://www.davidepesce.com/?p=1365


static func remove_recursive(path: String) -> Error:
	path = path.simplify_path()
	# Never descend into a symlink or junction: only unlink it.
	var parent := DirAccess.open(path.get_base_dir())
	if parent and parent.is_link(path.get_file()):
		return parent.remove(path.get_file())
	var directory := DirAccess.open(path)
	if directory == null:
		return DirAccess.get_open_error()
	directory.include_hidden = true
	directory.include_navigational = false
	# Keep going past a failed entry so one locked file leaves little behind.
	var first_error := OK
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while file_name != "":
		var err := OK
		if directory.current_is_dir() and not directory.is_link(file_name):
			err = remove_recursive(path.path_join(file_name))
		else:
			err = directory.remove(file_name)  # unlinks links, deletes files
		if err != OK and first_error == OK:
			first_error = err
		file_name = directory.get_next()
	directory.list_dir_end()
	directory = null
	if first_error != OK:
		return first_error
	return DirAccess.remove_absolute(path)


static func path_is_valid(abs_path: String) -> bool:
	return DirAccess.dir_exists_absolute(abs_path) or FileAccess.file_exists(abs_path)


static func list_recursive(
	path: String, 
	include_hidden := false, 
	result_filter: Variant = null,
	dir_filter: Variant = null,
) -> Array[DirListResult]:
	if not result_filter:
		result_filter = func(x: DirListResult) -> bool: return true
	if not dir_filter:
		dir_filter = func(x: String) -> bool: return true
	var dirs_to_visit: Array[String] = [path]
	var result: Array[DirListResult]
	while len(dirs_to_visit) > 0:
		var dir_to_visit := dirs_to_visit.pop_front() as String
		var directory := DirAccess.open(dir_to_visit)
		var error := DirAccess.get_open_error()
		if error != OK:
			continue
		directory.include_hidden = include_hidden
		directory.include_navigational = false
		directory.list_dir_begin()
		var file_name := directory.get_next()
		while file_name != "":
			var file_path := dir_to_visit.simplify_path() + "/" + file_name
			var item := DirListResult.new(
				file_path, directory.current_is_dir()
			)
			if (result_filter as Callable).call(item):
				result.push_back(item)
			# Linked folders are listed but not entered, so link cycles cannot hang a scan.
			if (
					directory.current_is_dir()
					and not directory.is_link(file_name)
					and (dir_filter as Callable).call(file_path)
			):
				dirs_to_visit.push_back(file_path)
			file_name = directory.get_next()
		directory.list_dir_end()
	return result


class DirListResult:
	var _path: String
	var _is_dir: bool
	
	var path: String: 
		get: return _path
	
	var is_dir: bool:
		get: return _is_dir
	
	var is_file: bool:
		get: return not _is_dir
	
	var extension: String:
		get: return _path.get_extension()
	
	var file: String:
		get: return _path.get_file()
	
	func _init(path: String, is_dir: bool) -> void:
		_path = path
		_is_dir = is_dir
	
	func _to_string() -> String:
		return _path
