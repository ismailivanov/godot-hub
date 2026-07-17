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
	for line in output:
		Output.push(str(line))
	Output.push("unzip executed with exit code: %s" % exit_code)
	return OK if exit_code == 0 else FAILED


static func _ps_quote(value: String) -> String:
	return "'%s'" % value.replace("'", "''")


## A procedure that unzips a zip file to a target directory, keeping the
## target directory as root, rather than the zip's root directory.
static func unzip_to_path(zip_reader: ZIPReader, destiny: String) -> Error:
	var files := zip_reader.get_files()
	var err: int

	for zip_file_name in files:
		if zip_file_name == files[0]:
			continue
		var target_file_name := destiny.path_join(zip_file_name.split("/", false, 1)[1])
		if zip_file_name.ends_with("/"):
			err = DirAccess.make_dir_recursive_absolute(target_file_name)
			if err != OK:
				return err as Error
		else:
			var file_contents := zip_reader.read_file(zip_file_name)
			var file := FileAccess.open(target_file_name, FileAccess.WRITE)
			if not file:
				return FileAccess.get_open_error()
			file.store_buffer(file_contents)
			file.close()
	return OK
