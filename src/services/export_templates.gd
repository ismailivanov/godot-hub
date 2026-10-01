class_name ExportTemplates
extends RefCounted
## Godot's export templates: the template table of Godot 4.8's Export Template
## Manager and the folders the Godot editor reads them from.
##
## Templates are installed per version into
## [code]<data dir>/godot/export_templates/<version.txt>/[/code] ("Godot" on Windows and
## macOS, "templates" before Godot 4), so every editor of that version finds them.


## Godot 4 file names start at this major; older archives are installed whole.
const TABLE_MIN_MAJOR := 4
## Platform group of the Desktop platforms, as in Godot.
const GROUP_DESKTOP := "Desktop"
const GROUP_MOBILE := "Mobile"
const GROUP_WEB := "Web"

## Replaces the user data folder (e.g. ~/.local/share), for tests.
static var data_dir_override := ""


## Platforms in the order and groups of Godot 4.8's Export Template Manager. Names are
## not translated here, like Godot's platform and architecture names.
static func platforms() -> Array[Platform]:
	var windows := Platform.new("Windows", GROUP_DESKTOP)
	for arch: String in ["x86_32", "x86_64", "arm64"]:
		var files := PackedStringArray()
		for kind: String in ["debug", "release"]:
			files.append("windows_%s_%s.exe" % [kind, arch])
			files.append("windows_%s_%s_console.exe" % [kind, arch])
		windows.add("Windows " + arch, _windows_description(arch), files)
	var linux := Platform.new("Linux", GROUP_DESKTOP)
	for arch: String in ["x86_32", "x86_64", "arm32", "arm64"]:
		linux.add("Linux " + arch, _linux_description(arch), PackedStringArray([
			"linux_debug." + arch, "linux_release." + arch,
		]))
	var macos := Platform.new("macOS", GROUP_DESKTOP)
	macos.add("macOS", "Universal build for macOS.", PackedStringArray(["macos.zip"]))
	var android := Platform.new("Android", GROUP_MOBILE)
	android.add(
		"Android",
		"Android APK template and source for Gradle builds.",
		PackedStringArray(["android_debug.apk", "android_release.apk", "android_source.zip"]),
	)
	var ios := Platform.new("iOS", GROUP_MOBILE)
	ios.add("iOS", "Build for Apple's iOS.", PackedStringArray(["ios.zip"]))
	# Godot's .NET builds have no visionOS and Web templates.
	var visionos := Platform.new("visionOS", GROUP_MOBILE, true)
	visionos.add("visionOS", "Build for Apple's visionOS.", PackedStringArray(["visionos.zip"]))
	var web := Platform.new("Web", GROUP_WEB, true)
	web.add(
		"Web",
		"Regular web build with threading support. Threads improve performance, but "
			+ "require \"cross-origin isolated\" website to run.",
		PackedStringArray(["web_debug.zip", "web_release.zip"]),
	)
	web.add(
		"Web with Extensions",
		"Web build with support for GDExtensions. Only useful if you use GDExtensions, "
			+ "otherwise it only increases build size.",
		PackedStringArray(["web_dlink_debug.zip", "web_dlink_release.zip"]),
	)
	web.add(
		"Web Single-Threaded",
		"Web build without threading support.",
		PackedStringArray(["web_nothreads_debug.zip", "web_nothreads_release.zip"]),
	)
	web.add(
		"Web with Extensions Single-Threaded",
		"Web build with GDExtension support and no threading support.",
		PackedStringArray(["web_dlink_nothreads_debug.zip", "web_dlink_nothreads_release.zip"]),
	)
	# No group: Godot lists it at the top level.
	var common := Platform.new("Common", "")
	common.add(
		"ICU Data",
		"Line breaking dictionaries for TextServer, used by certain languages.",
		PackedStringArray(["icudt_godot.dat"]),
	)
	var result: Array[Platform] = [windows, linux, macos, android, ios, visionos, web, common]
	return result


## Files of every template in the table.
static func table_files() -> PackedStringArray:
	var result := PackedStringArray()
	for platform in platforms():
		for template in platform.templates:
			result.append_array(template.files)
	return result


## True when [param archive_files] (paths from [method TemplateArchive.Index.files])
## use the file names of the table: Godot 4 archives, but not the first 4.0 alphas.
static func archive_uses_table(archive_files: PackedStringArray) -> bool:
	for platform in platforms():
		if platform.group != GROUP_DESKTOP:
			continue
		for template in platform.templates:
			for file in template.files:
				if file in archive_files:
					return true
	return false


## The version folder Godot reads templates of [param version] and [param release]
## from, as their version.txt says, e.g. "4.7.2.stable" or "4.8.dev6.mono".
static func folder_name(version: String, release: String, mono: bool) -> String:
	return "%s.%s%s" % [version, release, ".mono" if mono else ""]


## The major version of a [method folder_name].
static func major_of(folder: String) -> int:
	return folder.get_slice(".", 0).to_int()


## True when [param text], a version.txt content, can name a version folder.
static func is_valid_folder_name(text: String) -> bool:
	return (
		text.get_slice_count(".") >= 3
		and text.is_valid_filename()
		and not text.begins_with(".")
		and major_of(text) > 0
	)


## Absolute folder of the templates of [param folder], a [method folder_name].
static func version_dir(folder: String) -> String:
	return templates_root(major_of(folder)).path_join(folder)


## Absolute folder holding the template versions of Godot [param major].
static func templates_root(major: int) -> String:
	var data_dir := data_dir_override
	if data_dir.is_empty():
		data_dir = OS.get_data_dir()
	var subfolder := "export_templates" if major >= TABLE_MIN_MAJOR else "templates"
	return data_dir.path_join(godot_dir_name(OS.get_name())).path_join(subfolder)


## Godot's own folder in the user data folder on [param os_name] (an [method
## OS.get_name]): capitalized on Windows and macOS, lowercase elsewhere.
static func godot_dir_name(os_name: String) -> String:
	return "Godot" if os_name in ["Windows", "macOS"] else "godot"


## Files installed in the version folder [param folder], relative to it, those in
## subfolders too (e.g. "bcl/mscorlib.dll" of old .NET templates).
static func installed_files(folder: String) -> PackedStringArray:
	var dir := version_dir(folder)
	if not DirAccess.dir_exists_absolute(dir):
		return PackedStringArray()
	return _files_under(dir, "")


## The files under [param dir] and its subfolders, prefixed with [param prefix].
static func _files_under(dir: String, prefix: String) -> PackedStringArray:
	var result := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		result.append(prefix + file)
	for subdir in DirAccess.get_directories_at(dir):
		result.append_array(_files_under(dir.path_join(subdir), prefix + subdir + "/"))
	return result


static func _windows_description(arch: String) -> String:
	match arch:
		"x86_32":
			return "32-bit build for Microsoft Windows, including console wrapper."
		"arm64":
			return (
				"64-bit build for Microsoft Windows on ARM architecture, including console "
				+ "wrapper."
			)
	return "64-bit build for Microsoft Windows, including console wrapper."


static func _linux_description(arch: String) -> String:
	match arch:
		"x86_32":
			return "32-bit build for Linux systems."
		"arm32":
			return "32-bit build for Linux systems on ARM architecture."
		"arm64":
			return "64-bit build for Linux systems on ARM architecture."
	return "64-bit build for Linux systems."


## A platform of the template table, e.g. Linux with its four architectures.
class Platform:
	var name: String
	## "Desktop", "Mobile", "Web", or empty for the top level.
	var group: String
	## True when only Standard (not .NET) archives have its templates.
	var standard_only: bool
	var templates: Array[Template] = []

	func _init(p_name: String, p_group: String, p_standard_only := false) -> void:
		name = p_name
		group = p_group
		standard_only = p_standard_only

	func add(template_name: String, description: String, files: PackedStringArray) -> void:
		var template := Template.new()
		template.name = template_name
		template.description = description
		template.files = files
		templates.append(template)


## One template, e.g. Linux x86_64 with its debug and release files.
class Template:
	var name: String
	## English, like Godot's; translated where shown.
	var description: String
	var files: PackedStringArray
