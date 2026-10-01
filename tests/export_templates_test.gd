extends Node
## Offline tests of export template installs: reading a .tpz central directory,
## unpacking single files from byte ranges, installs of whole archives downloaded at
## once, the template table, version folders, disk space, installs that stop early and
## what they leave.


const TEMPLATES_DIR := "templates/"
## Files in the Godot 3 .NET-like fixture, which real ones have over 1300 of.
const DOTNET_FILE_COUNT := 1500
## Version folder of the Godot 3 .NET-like fixture.
const DOTNET_FOLDER := "3.6.stable.mono"
## A file of the Godot 3 .NET-like fixture halfway through it.
const DOTNET_MIDDLE_FILE := "GodotSharp/Api/Release/GodotSharp.dll"

var _failures := 0
var _root := ""
## Contents of the 4.x fixture archive by path in it.
var _files: Dictionary[String, PackedByteArray] = {}
var _tpz := ""
## Contents of the Godot 3 .NET-like fixture archive by path in it.
var _dotnet_files: Dictionary[String, PackedByteArray] = {}
var _dotnet_tpz := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_root = ProjectSettings.globalize_path(
		"user://export-templates-test-%s" % Time.get_ticks_msec()
	)
	DirAccess.make_dir_recursive_absolute(_root)
	ExportTemplates.data_dir_override = _root.path_join("data")
	_tpz = _make_fixture_tpz()
	_dotnet_tpz = _make_dotnet_tpz()

	_test_parse_index()
	_test_mini_zip_is_byte_exact()
	_test_parse_errors()
	_test_template_table()
	_test_folder_names()
	await _test_install_selected()
	await _test_already_installed()
	await _test_cancel_leaves_no_partial_file()
	await _test_failed_read_leaves_no_partial_file()
	await _test_dropped_read_is_tried_again()
	await _test_dismiss_while_unpacking()
	await _test_server_without_ranges()
	await _test_all_files_of_old_archive()
	await _test_directory_bigger_than_tail()
	await _test_two_installs_of_one_version()
	await _test_all_files_download_archive_once()
	await _test_whole_selection_downloads_archive_once()
	await _test_cancel_archive_download()
	await _test_failed_archive_download()
	await _test_cancel_while_unpacking_archive()
	await _test_dismiss_while_unpacking_archive()
	await _test_archive_unpack_failure()
	await _test_version_read_before_download()
	await _test_disk_space()
	await _test_stale_files_are_removed()
	await _test_http_stall_and_cancel()

	ExportTemplates.data_dir_override = ""
	_check(edir.remove_recursive(_root) == OK, "Could not remove the test directory")
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Export templates tests passed.")
	get_tree().quit()


func _test_parse_index() -> void:
	var size := FileAccess.get_file_as_bytes(_tpz).size()
	_check(size > TemplateArchive.TAIL_SIZE, "The fixture should be bigger than the tail")
	var index := _index_of(_tpz)
	_check(index.error.is_empty(), "Could not parse the fixture: %s" % index.error)
	var reader := ZIPReader.new()
	reader.open(_tpz)
	var names := PackedStringArray(index.entries.keys())
	_check(names == reader.get_files(), "Entries differ from ZIPReader's:\n%s\n%s" % [
		names, reader.get_files(),
	])
	_check(index.contents_dir() == TEMPLATES_DIR, "Wrong contents dir %s" % index.contents_dir())
	var expected := PackedStringArray(_files.keys())
	var files := index.files()
	files.sort()
	expected.sort()
	_check(files == expected, "Wrong files, got %s" % files)
	_check(index.entry_of("linux_debug.x86_64").method == 8, "Linux templates are deflated")
	for path in _files:
		var entry := index.entry_of(path)
		_check(entry.uncompressed_size == _files[path].size(), "Wrong size of %s" % path)
	reader.close()


func _test_mini_zip_is_byte_exact() -> void:
	var index := _index_of(_tpz)
	var archive := FileAccess.get_file_as_bytes(_tpz)
	var reader := ZIPReader.new()
	reader.open(_tpz)
	var mini_path := _root.path_join("mini.zip")
	for path in _files:
		var entry := index.entry_of(path)
		var bounds := TemplateArchive.fragment_range(index, entry)
		_check(bounds[1] < index.cd_offset, "%s's range runs into the directory" % path)
		var fragment := archive.slice(bounds[0], bounds[1] + 1)
		var mini := TemplateArchive.mini_zip(fragment, entry)
		var file := FileAccess.open(mini_path, FileAccess.WRITE)
		file.store_buffer(mini)
		file.close()
		var mini_reader := ZIPReader.new()
		_check(mini_reader.open(mini_path) == OK, "Could not open the mini zip of %s" % path)
		var data := mini_reader.read_file(entry.name)
		mini_reader.close()
		_check(data == reader.read_file(entry.name), "Mini zip of %s differs" % path)
		_check(data == _files[path], "Unpacked %s differs from the original" % path)

		# The same on disk, as the installer's worker thread does it.
		var fragment_path := _root.path_join("fragment.zip")
		file = FileAccess.open(fragment_path, FileAccess.WRITE)
		file.store_buffer(fragment)
		file.close()
		var out_path := _root.path_join("out.bin")
		var error := TemplateArchive.extract_fragment(fragment_path, entry, out_path)
		_check(error.is_empty(), "Could not unpack %s: %s" % [path, error])
		_check(FileAccess.get_file_as_bytes(out_path) == _files[path], "%s differs on disk" % path)
	reader.close()

	var entry := index.entry_of("linux_debug.x86_64")
	var bounds := TemplateArchive.fragment_range(index, entry)
	var short := archive.slice(bounds[0], bounds[0] + 40)
	_check(TemplateArchive.mini_zip(short, entry).is_empty(), "A cut fragment must be rejected")
	var shifted := archive.slice(bounds[0] + 1, bounds[1] + 1)
	_check(TemplateArchive.mini_zip(shifted, entry).is_empty(), "A wrong offset must be rejected")


func _test_parse_errors() -> void:
	var noise := PackedByteArray()
	noise.resize(4096)
	_check(not TemplateArchive.parse_index(noise, 4096).error.is_empty(), "Expected no EOCD")
	var archive := FileAccess.get_file_as_bytes(_tpz)
	# Only the last bytes: the directory starts before them.
	var cut := archive.slice(archive.size() - 64)
	_check(
		not TemplateArchive.parse_index(cut, archive.size()).error.is_empty(),
		"Expected an error for a directory outside the tail",
	)


func _test_template_table() -> void:
	var names := PackedStringArray()
	var groups := PackedStringArray()
	for platform in ExportTemplates.platforms():
		names.append(platform.name)
		if not platform.group in groups:
			groups.append(platform.group)
	_check(names == PackedStringArray([
		"Windows", "Linux", "macOS", "Android", "iOS", "visionOS", "Web", "Common",
	]), "Wrong platforms %s" % names)
	_check(groups == PackedStringArray(["Desktop", "Mobile", "Web", ""]), "Wrong groups %s" % groups)
	var linux := _template("Linux x86_64")
	_check(
		linux.files == PackedStringArray(["linux_debug.x86_64", "linux_release.x86_64"]),
		"Wrong Linux x86_64 files %s" % linux.files,
	)
	_check(_template("Windows arm64").files == PackedStringArray([
		"windows_debug_arm64.exe", "windows_debug_arm64_console.exe",
		"windows_release_arm64.exe", "windows_release_arm64_console.exe",
	]), "Wrong Windows arm64 files")
	_check(
		_template("Web with Extensions Single-Threaded").files == PackedStringArray([
			"web_dlink_nothreads_debug.zip", "web_dlink_nothreads_release.zip",
		]),
		"Wrong web files",
	)
	_check(_template("ICU Data").files == PackedStringArray(["icudt_godot.dat"]), "Wrong ICU file")
	# Every file of the 4.7.2 archive but version.txt has a template.
	var table := ExportTemplates.table_files()
	for path in _files:
		if path != "version.txt":
			_check(path in table, "%s has no template" % path)
	for platform in ExportTemplates.platforms():
		var standard_only := platform.name in ["Web", "visionOS"]
		_check(platform.standard_only == standard_only, "Wrong .NET exclusion of %s" % platform.name)
	_check(ExportTemplates.archive_uses_table(PackedStringArray(_files.keys())), "4.x uses the table")
	_check(
		not ExportTemplates.archive_uses_table(PackedStringArray([
			"linux_x11_64_debug", "osx.zip", "android_debug.apk", "version.txt",
		])),
		"3.x archives do not use the table",
	)


func _test_folder_names() -> void:
	_check(ExportTemplates.folder_name("4.7.2", "stable", false) == "4.7.2.stable", "Wrong folder")
	_check(ExportTemplates.folder_name("4.8", "dev6", true) == "4.8.dev6.mono", "Wrong mono folder")
	_check(ExportTemplates.major_of("3.6.stable.mono") == 3, "Wrong major")
	for valid: String in ["4.7.2.stable", "4.8.dev6.mono", "3.6.stable"]:
		_check(ExportTemplates.is_valid_folder_name(valid), "%s should be valid" % valid)
	for invalid: String in ["", "4.7", "../4.7.stable", "4.7/x.stable", ".4.7.stable"]:
		_check(not ExportTemplates.is_valid_folder_name(invalid), "%s should be invalid" % invalid)
	var data := _root.path_join("data")
	var godot_dir := ExportTemplates.godot_dir_name(OS.get_name())
	_check(
		ExportTemplates.version_dir("4.7.2.stable")
			== data.path_join(godot_dir).path_join("export_templates/4.7.2.stable"),
		"Wrong 4.x folder %s" % ExportTemplates.version_dir("4.7.2.stable"),
	)
	_check(
		ExportTemplates.version_dir("3.6.stable")
			== data.path_join(godot_dir).path_join("templates/3.6.stable"),
		"Godot 3 reads templates from templates/",
	)
	_check(ExportTemplates.godot_dir_name("Windows") == "Godot", "Windows uses Godot")
	_check(ExportTemplates.godot_dir_name("macOS") == "Godot", "macOS uses Godot")
	_check(ExportTemplates.godot_dir_name("Linux") == "godot", "Linux uses godot")
	ExportTemplates.data_dir_override = ""
	var linux_dir := ExportTemplates.templates_root(4)
	ExportTemplates.data_dir_override = data
	_check(
		linux_dir == OS.get_data_dir().path_join(godot_dir).path_join("export_templates"),
		"The default folder is Godot's, got %s" % linux_dir,
	)


func _test_install_selected() -> void:
	var source := FileRangeSource.new(_tpz)
	var installer := _installer()
	var wanted := PackedStringArray([
		"linux_debug.x86_64", "linux_release.x86_64", "android_source.zip", "visionos.zip",
	])
	installer.start(source, wanted, false, _work_dir())
	var error: String = await installer.finished
	_check(error.is_empty(), "Install failed: %s" % error)
	var dir := ExportTemplates.version_dir("4.7.2.stable")
	_check(installer.install_dir == dir, "Wrong install dir %s" % installer.install_dir)
	_check(installer.missing_files == PackedStringArray(["visionos.zip"]), "visionOS is missing")
	_check(
		installer.files_total == 4 and installer.files_done == 4,
		"Expected 3 files and version.txt",
	)
	_check(installer.bytes_done() == installer.bytes_total, "Progress should be complete")
	for path in wanted:
		if path == "visionos.zip":
			continue
		_check(
			FileAccess.get_file_as_bytes(dir.path_join(path)) == _files[path],
			"Installed %s differs" % path,
		)
	_check(
		FileAccess.get_file_as_bytes(dir.path_join("version.txt")) == _files["version.txt"],
		"version.txt should be installed",
	)
	_check(_listing(dir).size() == 4, "Only the chosen files, got %s" % _listing(dir))
	_check(_listing(_work_dir()).is_empty(), "Downloaded parts left: %s" % _listing(_work_dir()))
	# Size, directory, version.txt, then one read per file; no download of everything.
	_check(source.read_count == 6, "Expected a read per file, got %d" % source.read_count)
	_check(source.download_count == 0, "A few templates should not download the archive")
	installer.queue_free()


func _test_already_installed() -> void:
	var installed := ExportTemplates.installed_files("4.7.2.stable")
	_check("linux_debug.x86_64" in installed, "Installed files should be found")
	_check(not "macos.zip" in installed, "macOS was not installed")
	_check(ExportTemplates.installed_files("4.7.2.stable.mono").is_empty(), ".NET is not installed")
	_clear_installs()


func _test_cancel_leaves_no_partial_file() -> void:
	var source := FileRangeSource.new(_tpz)
	var installer := _installer()
	# Reads: size, directory, version.txt, then one per file.
	source.on_read = func(_start: int, _end: int) -> void:
		if source.read_count == 5:
			installer.cancel()
	installer.start(source, _wanted_two(), false, _work_dir())
	var error: String = await installer.finished
	_check(error == "canceled", "Expected a canceled install, got %s" % error)
	_check_no_partial_files(["linux_debug.x86_64", "version.txt"], "a canceled install")
	installer.queue_free()
	_clear_installs()
	# The hook refers to its source.
	source.on_read = Callable()


func _test_failed_read_leaves_no_partial_file() -> void:
	var source := FileRangeSource.new(_tpz)
	var installer := _installer()
	source.on_read = func(_start: int, _end: int) -> void:
		if source.read_count == 5:
			source.fail_with = "connection lost"
	installer.start(source, _wanted_two(), false, _work_dir())
	var error: String = await installer.finished
	_check(error == "connection lost", "Expected the read error, got %s" % error)
	_check_no_partial_files(["linux_debug.x86_64", "version.txt"], "a failed install")
	installer.queue_free()
	_clear_installs()
	# The hook refers to its source.
	source.on_read = Callable()

	# A full disk stays full: the read is not tried again.
	source = FileRangeSource.new(_tpz)
	installer = _installer()
	source.on_read = func(_start: int, _end: int) -> void:
		source.disk_full = source.read_count == 5
	installer.start(source, _wanted_two(), false, _work_dir())
	error = await installer.finished
	_check(error.begins_with("could not write"), "Expected a write error, got %s" % error)
	_check(source.read_count == 5, "A full disk is not read again: %d reads" % source.read_count)
	_check_no_partial_files(["linux_debug.x86_64", "version.txt"], "a full disk")
	installer.queue_free()
	_clear_installs()
	source.on_read = Callable()


func _test_dropped_read_is_tried_again() -> void:
	var source := FileRangeSource.new(_tpz)
	var installer := _installer()
	source.on_read = func(_start: int, _end: int) -> void:
		source.fail_with = "connection lost" if source.read_count == 5 else ""
	installer.start(source, _wanted_two(), false, _work_dir())
	var error: String = await installer.finished
	_check(error.is_empty(), "A read that fails once should be tried again: %s" % error)
	_check(source.read_count == 6, "Expected one more read, got %d" % source.read_count)
	_check_no_partial_files(
		["linux_debug.x86_64", "android_source.zip", "version.txt"], "a retried read"
	)
	installer.queue_free()
	_clear_installs()
	# The hook refers to its source.
	source.on_read = Callable()


func _test_dismiss_while_unpacking() -> void:
	var source := FileRangeSource.new(_tpz)
	var installer := _installer()
	var ended := [false]
	installer.finished.connect(func(_error: String) -> void: ended[0] = true)
	# Freed at the end of the frame, while a worker thread unpacks the second file.
	source.on_read = func(_start: int, _end: int) -> void:
		if source.read_count == 5:
			installer.queue_free()
	installer.start(source, _wanted_two(), false, _work_dir())
	for _frame: int in 60:
		if not is_instance_valid(installer):
			break
		await get_tree().process_frame
	_check(not is_instance_valid(installer), "The installer should be freed")
	_check(not (ended[0] as bool), "A freed installer does not finish")
	_check_no_partial_files(["linux_debug.x86_64", "version.txt"], "a dismissed install")
	_clear_installs()
	# The hook refers to its source.
	source.on_read = Callable()


func _test_server_without_ranges() -> void:
	var source := FileRangeSource.new(_tpz)
	source.honor_range = false
	var installer := _installer()
	installer.start(source, _wanted_two(), false, _work_dir())
	var error: String = await installer.finished
	_check(error == HttpRangeSource.NO_RANGE_ERROR, "Expected the no-range error, got %s" % error)
	_check(installer.install_dir.is_empty(), "Nothing should be installed")
	_check(
		not DirAccess.dir_exists_absolute(ExportTemplates.templates_root(4)),
		"No templates folder should be created",
	)
	installer.queue_free()


func _test_all_files_of_old_archive() -> void:
	var files: Dictionary[String, PackedByteArray] = {
		"version.txt": "3.6.stable.mono\n".to_utf8_buffer(),
		"linux_x11_64_debug": _noise(3000, 7),
		"osx.zip": _text(5000),
		"GodotSharp/Api/GodotSharp.dll": _text(700),
	}
	var tpz := _root.path_join("old.tpz")
	_pack(tpz, files, [])
	var index := _index_of(tpz)
	_check(not ExportTemplates.archive_uses_table(index.files()), "3.x names are not the table's")
	var installer := _installer()
	installer.start(FileRangeSource.new(tpz), PackedStringArray(), true, _work_dir())
	var error: String = await installer.finished
	_check(error.is_empty(), "Install of everything failed: %s" % error)
	var dir := _root.path_join("data").path_join(
		ExportTemplates.godot_dir_name(OS.get_name())
	).path_join("templates/3.6.stable.mono")
	_check(
		installer.install_dir == dir,
		"Godot 3 templates go to templates/, got %s" % installer.install_dir,
	)
	for path in files:
		_check(
			FileAccess.get_file_as_bytes(dir.path_join(path)) == files[path],
			"%s of the old archive differs" % path,
		)
	installer.queue_free()
	_clear_installs()


## Godot 3 .NET archives list over 1300 files: their central directory (about 170 KB)
## does not fit in the last 64 KB, so it is read again from where it starts.
func _test_directory_bigger_than_tail() -> void:
	var files: Dictionary[String, PackedByteArray] = {
		"version.txt": "3.6.stable.mono\n".to_utf8_buffer(),
	}
	for i in 600:
		var assembly := "data.mono.x11.64.release/Mono/lib/mono/4.5/Facades/%s.%03d.dll" % [
			"System.Runtime.InteropServices.WindowsRuntime.Extensions.Generated", i,
		]
		files[assembly] = ("assembly %d" % i).to_utf8_buffer()
	var tpz := _root.path_join("big-directory.tpz")
	_pack(tpz, files, [])

	var tail_index := _index_of(tpz)
	_check(not tail_index.error.is_empty(), "The directory should not fit in the tail")
	var whole := TemplateArchive.directory_range(tail_index)
	_check(
		whole.size() == 2 and whole[0] == tail_index.cd_offset,
		"The whole directory should be read from its start: %s" % whole,
	)
	var archive := FileAccess.get_file_as_bytes(tpz)
	_check(
		archive.size() - tail_index.cd_offset > TemplateArchive.TAIL_SIZE,
		"The fixture's directory should be bigger than the tail",
	)
	var index := TemplateArchive.parse_index(
		archive.slice(whole[0], whole[1] + 1), archive.size()
	)
	_check(index.error.is_empty(), "Could not parse the whole directory: %s" % index.error)
	_check(index.files().size() == files.size(), "Expected %d files" % files.size())
	_check(TemplateArchive.directory_range(index).is_empty(), "Nothing more to read")

	var source := FileRangeSource.new(tpz)
	var installer := _installer()
	installer.start(source, PackedStringArray(), true, _work_dir())
	var error: String = await installer.finished
	_check(error.is_empty(), "Install of a big archive failed: %s" % error)
	for path in files:
		_check(
			FileAccess.get_file_as_bytes(installer.install_dir.path_join(path)) == files[path],
			"%s of the big archive differs" % path,
		)
		if _failures > 0:
			break
	installer.queue_free()
	_clear_installs()


## Two rows installing the same templates at once (Install pressed again while the
## first runs) both succeed and leave every file complete.
func _test_two_installs_of_one_version() -> void:
	var wanted := PackedStringArray(["linux_debug.x86_64", "android_source.zip"])
	var errors: Array[String] = []
	var installers: Array[ExportTemplatesInstaller] = []
	for i: int in 2:
		var installer := _installer()
		installer.finished.connect(func(error: String) -> void: errors.append(error))
		installers.append(installer)
		installer.start(
			FileRangeSource.new(_tpz), wanted, false, _work_dir().path_join(str(i))
		)
	for _frame: int in 300:
		if errors.size() == 2:
			break
		await get_tree().process_frame
	_check(errors == ["", ""], "Both installs should succeed: %s" % [errors])
	_check_no_partial_files(
		["linux_debug.x86_64", "android_source.zip", "version.txt"], "two installs at once"
	)
	for installer in installers:
		installer.queue_free()
	_clear_installs()


## Every file of a Godot 3 .NET archive comes with one download of the archive, not a
## request per file: they hold over 1300 files, and each request follows a redirect.
func _test_all_files_download_archive_once() -> void:
	var source := FileRangeSource.new(_dotnet_tpz)
	var installer := _installer()
	var stages: Array[ExportTemplatesInstaller.Stage] = []
	installer.progressed.connect(func() -> void: stages.append(installer.stage))
	source.on_download = func(_bytes: int) -> void: stages.append(installer.stage)
	installer.start(source, PackedStringArray(), true, _work_dir())
	var error: String = await installer.finished
	_check(error.is_empty(), "Install of a whole .NET archive failed: %s" % error)
	_check(source.download_count == 1, "Expected one download, got %d" % source.download_count)
	# Size, last bytes, the whole central directory and version.txt: no read per file.
	_check(source.read_count == 4, "Expected only the directory reads, got %d" % source.read_count)
	var unpacking := stages.slice(2).all(func(stage: ExportTemplatesInstaller.Stage) -> bool:
		return stage == ExportTemplatesInstaller.Stage.UNPACKING
	)
	_check(
		stages.size() > 2
			and stages[0] == ExportTemplatesInstaller.Stage.READING
			and stages[1] == ExportTemplatesInstaller.Stage.DOWNLOADING
			and unpacking,
		"Expected version.txt, the download, then unpacking: %s" % [stages],
	)
	var dir := ExportTemplates.version_dir(DOTNET_FOLDER)
	_check(installer.install_dir == dir, "Wrong install dir %s" % installer.install_dir)
	_check(
		dir.get_base_dir().get_file() == "templates",
		"Godot 3 templates go to templates/, got %s" % dir,
	)
	_check_dotnet_files(_dotnet_files.size(), "an install of everything")
	_check(
		installer.files_total == _dotnet_files.size()
			and installer.files_done == installer.files_total,
		"Expected %d files done, got %d of %d" % [
			_dotnet_files.size(), installer.files_done, installer.files_total,
		],
	)
	_check(
		installer.bytes_total == FileAccess.get_size(_dotnet_tpz)
			and installer.bytes_done() == installer.bytes_total,
		"Progress should be the archive's download: %d of %d" % [
			installer.bytes_done(), installer.bytes_total,
		],
	)
	installer.queue_free()
	_clear_installs()


## A 4.x selection of every template downloads the archive once too; leaving one out
## reads each file again.
func _test_whole_selection_downloads_archive_once() -> void:
	var wanted := PackedStringArray(_files.keys())
	wanted.remove_at(wanted.find("version.txt"))
	var source := FileRangeSource.new(_tpz)
	var installer := _installer()
	installer.start(source, wanted, false, _work_dir())
	var error: String = await installer.finished
	_check(error.is_empty(), "Install of every template failed: %s" % error)
	_check(
		source.download_count == 1 and source.read_count == 3,
		"Expected one download after the directory and version.txt, got %d and %d reads" % [
			source.download_count, source.read_count,
		],
	)
	var all: Array[String] = []
	all.assign(_files.keys())
	_check_no_partial_files(all, "an install of every template")
	installer.queue_free()
	_clear_installs()

	wanted.remove_at(wanted.find("macos.zip"))
	source = FileRangeSource.new(_tpz)
	installer = _installer()
	installer.start(source, wanted, false, _work_dir())
	error = await installer.finished
	_check(error.is_empty(), "Install of all templates but one failed: %s" % error)
	_check(
		source.download_count == 0 and source.read_count == 3 + wanted.size(),
		"Expected a read per file, got %d reads and %d downloads" % [
			source.read_count, source.download_count,
		],
	)
	all.erase("macos.zip")
	_check_no_partial_files(all, "an install of all templates but one")
	installer.queue_free()
	_clear_installs()


func _test_cancel_archive_download() -> void:
	var source := FileRangeSource.new(_dotnet_tpz)
	var installer := _installer()
	var downloaded := [0]
	source.on_download = func(bytes: int) -> void:
		downloaded[0] = bytes
		_check(_listing(_work_dir()).size() == 1, "The archive should download to the work folder")
		installer.cancel()
	installer.start(source, PackedStringArray(), true, _work_dir())
	var error: String = await installer.finished
	_check(error == "canceled", "Expected a canceled install, got %s" % error)
	_check((downloaded[0] as int) > 0, "The download should have started")
	_check(source.download_count == 1, "A canceled download is not tried again")
	# Only version.txt, read first, as when files are read one by one.
	_check_dotnet_files(1, "a canceled download")
	installer.queue_free()
	_clear_installs()
	# The hook refers to its source.
	source.on_download = Callable()


func _test_failed_archive_download() -> void:
	var source := FileRangeSource.new(_dotnet_tpz)
	var installer := _installer()
	source.on_download = func(_bytes: int) -> void:
		source.fail_with = "connection lost"
	installer.start(source, PackedStringArray(), true, _work_dir())
	var error: String = await installer.finished
	_check(error == "connection lost", "Expected the download error, got %s" % error)
	_check(
		source.download_count == ExportTemplatesInstaller.MAX_RETRIES + 1,
		"A failed download should be tried again, got %d tries" % source.download_count,
	)
	_check_dotnet_files(1, "a failed download")
	installer.queue_free()
	source.on_download = Callable()
	_clear_installs()

	# A full disk stays full: each try would download the whole archive again.
	source = FileRangeSource.new(_dotnet_tpz)
	installer = _installer()
	source.on_download = func(_bytes: int) -> void:
		source.disk_full = true
	installer.start(source, PackedStringArray(), true, _work_dir())
	error = await installer.finished
	_check(error.begins_with("could not write"), "Expected a write error, got %s" % error)
	_check(source.download_count == 1, "A full disk should not download again")
	_check_dotnet_files(1, "a full disk")
	installer.queue_free()
	source.on_download = Callable()
	_clear_installs()

	# Dropped once, then complete.
	source = FileRangeSource.new(_tpz)
	installer = _installer()
	source.on_download = func(_bytes: int) -> void:
		source.fail_with = "connection lost" if source.download_count == 1 else ""
	installer.start(source, PackedStringArray(), true, _work_dir())
	error = await installer.finished
	_check(error.is_empty(), "A download that fails once should be tried again: %s" % error)
	_check(source.download_count == 2, "Expected two downloads, got %d" % source.download_count)
	var all: Array[String] = []
	all.assign(_files.keys())
	_check_no_partial_files(all, "a download tried again")
	installer.queue_free()
	source.on_download = Callable()
	_clear_installs()


## Canceling stops unpacking at the next file: files unpacked stay complete, nothing
## half written stays, nor the downloaded archive.
func _test_cancel_while_unpacking_archive() -> void:
	var installer := _installer()
	var canceled_at := [0]
	installer.progressed.connect(func() -> void:
		if (canceled_at[0] as int) == 0 and installer.files_done > 20:
			canceled_at[0] = Time.get_ticks_msec()
			installer.cancel()
	)
	installer.start(FileRangeSource.new(_dotnet_tpz), PackedStringArray(), true, _work_dir())
	var error: String = await installer.finished
	var waited := Time.get_ticks_msec() - (canceled_at[0] as int)
	_check(error == "canceled", "Expected a canceled install, got %s" % error)
	_check((canceled_at[0] as int) > 0, "The install should be canceled while unpacking")
	_check(waited < 1000, "Unpacking should stop at once, took %d ms" % waited)
	var count := ExportTemplates.installed_files(DOTNET_FOLDER).size()
	_check(count < _dotnet_files.size(), "Unpacking should stop early, got %d files" % count)
	_check_dotnet_files(count, "a cancel while unpacking")
	installer.queue_free()
	_clear_installs()


## The Hub quits while the archive unpacks: the worker thread stops and nothing half
## written stays, nor the downloaded archive.
func _test_dismiss_while_unpacking_archive() -> void:
	var installer := _installer()
	var ended := [false]
	installer.finished.connect(func(_error: String) -> void: ended[0] = true)
	installer.progressed.connect(func() -> void:
		if installer.files_done > 20 and not installer.is_queued_for_deletion():
			installer.queue_free()
	)
	installer.start(FileRangeSource.new(_dotnet_tpz), PackedStringArray(), true, _work_dir())
	for _frame: int in 300:
		if not is_instance_valid(installer):
			break
		await get_tree().process_frame
	_check(not is_instance_valid(installer), "The installer should be freed")
	_check(not (ended[0] as bool), "A freed installer does not finish")
	var count := ExportTemplates.installed_files(DOTNET_FOLDER).size()
	_check(count < _dotnet_files.size(), "Unpacking should stop early, got %d files" % count)
	_check_dotnet_files(count, "a dismiss while unpacking")
	_clear_installs()


## A file that cannot be written fails the install; files unpacked before it stay
## complete, nothing half written stays, nor the downloaded archive.
func _test_archive_unpack_failure() -> void:
	# A folder where the file goes: it cannot be renamed into place.
	var blocker := ExportTemplates.version_dir(DOTNET_FOLDER).path_join(DOTNET_MIDDLE_FILE)
	DirAccess.make_dir_recursive_absolute(blocker)
	FileAccess.open(blocker.path_join("keep"), FileAccess.WRITE).store_string("keep")
	var installer := _installer()
	installer.start(FileRangeSource.new(_dotnet_tpz), PackedStringArray(), true, _work_dir())
	var error: String = await installer.finished
	_check(
		error.begins_with("could not write") and error.contains(DOTNET_MIDDLE_FILE),
		"Expected a write error, got %s" % error,
	)
	var installed := ExportTemplates.installed_files(DOTNET_FOLDER)
	_check(installed.has(DOTNET_MIDDLE_FILE.path_join("keep")), "The blocking folder stays")
	DirAccess.remove_absolute(blocker.path_join("keep"))
	DirAccess.remove_absolute(blocker)
	var count := ExportTemplates.installed_files(DOTNET_FOLDER).size()
	_check(
		count > 1 and count < _dotnet_files.size(),
		"Files before the failure should stay, got %d" % count,
	)
	_check_dotnet_files(count, "a failed unpack")
	installer.queue_free()
	_clear_installs()


## version.txt is read before the archive is downloaded whole: a bad one fails at once.
func _test_version_read_before_download() -> void:
	var files: Dictionary[String, PackedByteArray] = {
		"version.txt": "../3.6.stable\n".to_utf8_buffer(),
		"linux_x11_64_debug": _noise(3000, 7),
	}
	var tpz := _root.path_join("bad-version.tpz")
	_pack(tpz, files, [])
	var source := FileRangeSource.new(tpz)
	var installer := _installer()
	installer.start(source, PackedStringArray(), true, _work_dir())
	var error: String = await installer.finished
	_check(error.contains("version.txt is not valid"), "Expected a version error, got %s" % error)
	_check(source.download_count == 0, "A bad version.txt should fail before the download")
	_check(installer.install_dir.is_empty(), "Nothing should be installed")
	_check(_listing(_work_dir()).is_empty(), "Left in the work folder: %s" % _listing(_work_dir()))
	installer.queue_free()


## Without room for the downloaded archive next to the files, they are read one by one;
## without room for the files, the install fails before reading them.
func _test_disk_space() -> void:
	var archive_size := FileAccess.get_size(_tpz)
	var unpacked := 0
	for path in _files:
		if path != "version.txt":
			unpacked += _files[path].size()
	var all: Array[String] = []
	all.assign(_files.keys())
	var source := FileRangeSource.new(_tpz)
	var installer := _installer()
	var asked: Array[String] = []
	installer.space_left = func(path: String) -> int:
		asked.append(path)
		return archive_size + unpacked - 1
	installer.start(source, PackedStringArray(), true, _work_dir())
	var error: String = await installer.finished
	_check(error.is_empty(), "An install without room for the archive failed: %s" % error)
	_check(
		source.download_count == 0 and source.read_count == 3 + _files.size() - 1,
		"Expected a read per file, got %d reads and %d downloads" % [
			source.read_count, source.download_count,
		],
	)
	_check(
		_work_dir() in asked and installer.install_dir in asked,
		"The disks of the work and version folders should be asked: %s" % [asked],
	)
	_check_no_partial_files(all, "an install without room for the archive")
	installer.queue_free()

	# The files installed are replaced: installing them again needs no more room.
	source = FileRangeSource.new(_tpz)
	installer = _installer()
	installer.space_left = func(_path: String) -> int: return 1
	installer.start(source, PackedStringArray(), true, _work_dir())
	error = await installer.finished
	_check(error.is_empty(), "Installing the same files again failed: %s" % error)
	_check(source.download_count == 0, "No room for the archive, so no download")
	_check_no_partial_files(all, "an install of the same files")
	installer.queue_free()
	_clear_installs()

	source = FileRangeSource.new(_tpz)
	installer = _installer()
	installer.space_left = func(_path: String) -> int: return unpacked - 1
	installer.start(source, PackedStringArray(), true, _work_dir())
	error = await installer.finished
	_check(error.begins_with("not enough disk space"), "Expected a space error, got %s" % error)
	_check(
		source.download_count == 0 and source.read_count == 3,
		"Expected no read of the files, got %d reads and %d downloads" % [
			source.read_count, source.download_count,
		],
	)
	_check_no_partial_files([], "an install without room")
	installer.queue_free()
	_clear_installs()


## Parts installs left in the work folder (the Hub was killed) are removed by a later
## install once they are old; newer ones may belong to an install that runs.
func _test_stale_files_are_removed() -> void:
	var stale: Array[String] = [
		"templates-0123abcd.tpz", "template-89efabcd.zip", "version-00ff00ff.txt",
	]
	var kept: Array[String] = [
		"templates-notours.tpz", "my-templates-0123abcd.tpz", "template-0123abcd.zip.bak",
	]
	DirAccess.make_dir_recursive_absolute(_work_dir())
	for file: String in stale + kept:
		FileAccess.open(_work_dir().path_join(file), FileAccess.WRITE).store_string(file)
	var expected := PackedStringArray(stale + kept)
	expected.sort()
	var installer := _installer()
	installer.start(FileRangeSource.new(_tpz), _wanted_two(), false, _work_dir())
	var error: String = await installer.finished
	_check(error.is_empty(), "Install with files in the work folder failed: %s" % error)
	var listing := _listing(_work_dir())
	listing.sort()
	_check(listing == expected, "Recent files should stay, got %s" % listing)
	installer.queue_free()

	installer = _installer()
	installer.stale_age_sec = 0
	installer.start(FileRangeSource.new(_tpz), _wanted_two(), false, _work_dir())
	error = await installer.finished
	_check(error.is_empty(), "Install with old files in the work folder failed: %s" % error)
	listing = _listing(_work_dir())
	listing.sort()
	expected = PackedStringArray(kept)
	expected.sort()
	_check(listing == expected, "Only old parts should be removed, got %s" % listing)
	installer.queue_free()
	for file in kept:
		DirAccess.remove_absolute(_work_dir().path_join(file))
	_clear_installs()


## A read that stops getting data fails on its own, and canceling a read returns at
## once (a threaded request blocked the Hub until its next chunk came).
func _test_http_stall_and_cancel() -> void:
	# Answers every request with the start of a 206 body, then stalls.
	var server := TCPServer.new()
	_check(server.listen(0, "127.0.0.1") == OK, "Could not start the test server")
	var peers: Array[StreamPeerTCP] = []
	var answer := (
		"HTTP/1.1 206 Partial Content\r\nContent-Range: bytes 0-9999/50000\r\n"
		+ "Content-Length: 10000\r\n\r\n"
	).to_ascii_buffer()
	answer.append_array(_text(100))
	var serve := func() -> void:
		while server.is_connection_available():
			peers.append(server.take_connection())
		for peer in peers:
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				continue
			if peer.get_available_bytes() > 0:
				peer.get_data(peer.get_available_bytes())
				peer.put_data(answer)
	get_tree().process_frame.connect(serve)
	var http := HTTPRequest.new()
	add_child(http)
	var url := "http://127.0.0.1:%d/templates.tpz" % server.get_local_port()
	var source := HttpRangeSource.new(url, http)

	source.stall_timeout_sec = 0.2
	var started := Time.get_ticks_msec()
	var stalled := await source.async_read(0, 9999)
	_check(stalled.error == "timed out", "A stalled read should time out: %s" % stalled.error)
	_check(Time.get_ticks_msec() - started < 3000, "The stalled read took too long")

	source.stall_timeout_sec = HttpRangeSource.STALL_TIMEOUT_SEC
	var results: Array[RangeSource.Result] = []
	var read := func() -> void: results.append(await source.async_read(0, 9999))
	read.call()
	for _frame: int in 120:
		if source.downloaded_bytes() > 0:
			break
		await get_tree().process_frame
	_check(source.downloaded_bytes() > 0, "The read should have started")
	started = Time.get_ticks_msec()
	source.cancel()
	_check(Time.get_ticks_msec() - started < 100, "Canceling a stalled read should not block")
	_check(results.size() == 1 and results[0].cancelled, "The read should end canceled")

	get_tree().process_frame.disconnect(serve)
	for peer in peers:
		peer.disconnect_from_host()
	server.stop()
	http.queue_free()


## Checks that only [param complete] files are in the 4.7.2 folder and nothing half
## written is anywhere.
func _check_no_partial_files(complete: Array[String], what: String) -> void:
	var dir := ExportTemplates.version_dir("4.7.2.stable")
	var listing := _listing(dir)
	listing.sort()
	var expected := PackedStringArray(complete)
	expected.sort()
	_check(listing == expected, "After %s expected %s, got %s" % [what, expected, listing])
	for path in listing:
		_check(
			FileAccess.get_file_as_bytes(dir.path_join(path)) == _files[path],
			"%s is not complete after %s" % [path, what],
		)
	_check(_listing(_work_dir()).is_empty(), "Downloaded parts left after %s" % what)


## Checks that [param count] files of the Godot 3 .NET-like fixture are installed, each
## complete, and nothing half written is anywhere, nor the downloaded archive.
func _check_dotnet_files(count: int, what: String) -> void:
	var installed := ExportTemplates.installed_files(DOTNET_FOLDER)
	_check(installed.size() == count, "After %s expected %d files, got %d" % [
		what, count, installed.size(),
	])
	var wrong := PackedStringArray()
	for path in installed:
		if (
			not _dotnet_files.has(path)
			or FileAccess.get_file_as_bytes(
				ExportTemplates.version_dir(DOTNET_FOLDER).path_join(path)
			) != _dotnet_files[path]
		):
			wrong.append(path)
	_check(wrong.is_empty(), "Not complete after %s: %s" % [what, wrong.slice(0, 5)])
	_check(_listing(_work_dir()).is_empty(), "Left in the work folder after %s: %s" % [
		what, _listing(_work_dir()),
	])


func _wanted_two() -> PackedStringArray:
	return PackedStringArray(["linux_debug.x86_64", "android_source.zip"])


func _installer() -> ExportTemplatesInstaller:
	var installer := ExportTemplatesInstaller.new()
	add_child(installer)
	return installer


func _work_dir() -> String:
	return _root.path_join("work")


func _clear_installs() -> void:
	edir.remove_recursive(_root.path_join("data"))


func _listing(dir: String) -> PackedStringArray:
	if not DirAccess.dir_exists_absolute(dir):
		return PackedStringArray()
	return DirAccess.get_files_at(dir)


func _template(template_name: String) -> ExportTemplates.Template:
	for platform in ExportTemplates.platforms():
		for template in platform.templates:
			if template.name == template_name:
				return template
	return ExportTemplates.Template.new()


func _index_of(path: String) -> TemplateArchive.Index:
	var archive := FileAccess.get_file_as_bytes(path)
	var bounds := TemplateArchive.tail_range(archive.size())
	return TemplateArchive.parse_index(archive.slice(bounds[0], bounds[1] + 1), archive.size())


## A small 4.7.2 archive with the file names of the real one, deflated but for a
## stored android_source.zip bigger than the directory tail.
func _make_fixture_tpz() -> String:
	_files["version.txt"] = "4.7.2.stable".to_utf8_buffer()
	for path: String in [
		"linux_debug.x86_64", "linux_release.x86_64", "linux_debug.arm64",
		"windows_debug_x86_64.exe", "windows_debug_x86_64_console.exe", "macos.zip",
		"ios.zip", "web_debug.zip", "web_release.zip", "android_debug.apk", "icudt_godot.dat",
	]:
		_files[path] = _text(2000 + path.length() * 37)
	_files["android_source.zip"] = _noise(TemplateArchive.TAIL_SIZE * 2, 3)
	_files["linux_release.x86_64"] = _noise(4000, 5)
	var path := _root.path_join("fixture.tpz")
	_pack(path, _files, ["android_source.zip"])
	return path


## An archive laid out like a Godot 3 .NET one: version.txt, platform templates and
## [constant DOTNET_FILE_COUNT] files in all, most of them small assemblies in nested
## folders that have folder entries of their own. Its central directory does not fit
## in the last 64 KB.
func _make_dotnet_tpz() -> String:
	_dotnet_files["version.txt"] = (DOTNET_FOLDER + "\n").to_utf8_buffer()
	_dotnet_files["linux_x11_64_debug"] = _noise(6000, 11)
	_dotnet_files["osx.zip"] = _text(9000)
	_dotnet_files["android_source.zip"] = _noise(TemplateArchive.TAIL_SIZE, 13)
	_dotnet_files["data.mono.x11.64.release/Mono/etc/mono/empty.config"] = PackedByteArray()
	var folders: Array[String] = []
	for platform: String in ["x11.64", "windows.64", "osx.64"]:
		for build: String in ["debug", "release"]:
			folders.append("data.mono.%s.%s/Mono/lib/mono/4.5/Facades" % [platform, build])
	var i := 0
	while _dotnet_files.size() < DOTNET_FILE_COUNT:
		if i * 2 == DOTNET_FILE_COUNT:
			_dotnet_files[DOTNET_MIDDLE_FILE] = _text(3000)
		var folder := folders[i % folders.size()]
		_dotnet_files["%s/System.Runtime.%04d.dll" % [folder, i]] = (
			("assembly %d " % i).repeat(i % 9 + 1).to_utf8_buffer()
		)
		i += 1
	var path := _root.path_join("dotnet.tpz")
	_pack(path, _dotnet_files, ["android_source.zip"], true)
	return path


## Packs [param files] under templates/, storing those in [param stored] and deflating
## the others. With [param folder_entries], each folder gets an entry before its files.
func _pack(
	path: String,
	files: Dictionary[String, PackedByteArray],
	stored: Array,
	folder_entries := false,
) -> void:
	var packer := ZIPPacker.new()
	packer.open(path)
	var folders: Dictionary[String, bool] = {}
	for file in files:
		var parts := file.split("/")
		for depth in range(1, parts.size() if folder_entries else 1):
			var folder := "/".join(parts.slice(0, depth)) + "/"
			if not folders.has(folder):
				folders[folder] = true
				packer.start_file(TEMPLATES_DIR + folder)
				packer.close_file()
		packer.compression_level = (
			ZIPPacker.COMPRESSION_NONE if file in stored else ZIPPacker.COMPRESSION_DEFAULT
		)
		packer.start_file(TEMPLATES_DIR + file)
		packer.write_file(files[file])
		packer.close_file()
	packer.close()


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
