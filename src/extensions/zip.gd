class_name zip
extends RefCounted
## Provides zip.


static func unzip(zip_path: String, target_dir: String) -> Error:
	var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_dir))
	if mkdir_error != OK:
		return mkdir_error

	var source := ProjectSettings.globalize_path(zip_path)
	var target := ProjectSettings.globalize_path(target_dir)
	var output: Array = []
	var exit_code := FAILED
	if OS.has_feature("windows"):
		var command := "Expand-Archive -LiteralPath %s -DestinationPath %s -Force" % [
			_ps_quote(source),
			_ps_quote(target),
		]
		exit_code = OS.execute(
			"powershell.exe", 
			[
				"-NoProfile",
				"-NonInteractive",
				"-Command",
				command,
			], output, true
		)
	elif OS.has_feature("macos"):
		exit_code = OS.execute(
			"ditto",
			["-x", "-k", source, target],
			output,
			true,
		)
	elif OS.has_feature("linux"):
		exit_code = OS.execute(
			"unzip",
			["-o", source, "-d", target],
			output,
			true,
		)
	for line: Variant in output:
		Output.push(str(line))
	Output.push("unzip executed with exit code: %s" % exit_code)
	return OK if exit_code == 0 else FAILED


static func _ps_quote(value: String) -> String:
	return "'%s'" % value.replace("'", "''")


## A procedure that unzips a zip file to a target directory, keeping the
## target directory as root, rather than the zip's root directory (if it has one).
## Fails with ERR_FILE_BAD_PATH before writing anything if an entry would land
## outside the target directory.
static func unzip_to_path(zip_reader: ZIPReader, destiny: String) -> Error:
	var root := destiny.simplify_path()
	var entries: Array[String] = []
	for zip_file_name: String in zip_reader.get_files():
		# Resource forks added by the macOS archiver.
		if not zip_file_name.begins_with("__MACOSX/"):
			entries.append(zip_file_name)

	# Strip the root folder only when every entry is inside it.
	var prefix := ""
	if not entries.is_empty() and entries[0].contains("/"):
		prefix = entries[0].get_slice("/", 0) + "/"
		for zip_file_name: String in entries:
			if not zip_file_name.begins_with(prefix):
				prefix = ""
				break

	# Validate every entry first so a malicious zip leaves no partial files.
	var targets: Array[String] = []
	for zip_file_name: String in entries:
		var rel := zip_file_name.trim_prefix(prefix)
		var target := "" if rel.is_empty() else root.path_join(rel).simplify_path()
		if not target.is_empty() and not target.begins_with(root + "/"):
			return ERR_FILE_BAD_PATH
		targets.append(target)

	for i: int in entries.size():
		var target := targets[i]
		if target.is_empty():
			continue
		if entries[i].ends_with("/"):
			var dir_err := DirAccess.make_dir_recursive_absolute(target)
			if dir_err != OK:
				return dir_err
			continue
		# Zips without folder entries still need the parent folders.
		var parent_err := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if parent_err != OK:
			return parent_err
		var file := FileAccess.open(target, FileAccess.WRITE)
		if not file:
			return FileAccess.get_open_error()
		file.store_buffer(zip_reader.read_file(entries[i]))
		file.close()
	return OK
