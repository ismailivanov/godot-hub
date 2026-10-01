class_name utils
extends RefCounted
## Provides utils.


static var _re_version := _compile_re(r"godot[-_]?v?(\d+(?:\.\d+)+)")
static var _re_channel := _compile_re(r"-(dev|alpha|beta|rc|stable)(\d*)")
static var _re_any_ver := _compile_re(r"(\d+(?:\.\d+)+)")
# An extension starts with a letter, so the dot in "Godot_v4.8-dev6_mono_linux_x86_64" is kept.
static var _re_extension := _compile_re(r"\.[a-zA-Z][a-zA-Z0-9_]*$")
static var _re_legacy_channel := _compile_re(r"-(alpha|beta|rc|stable)(\d*)")
static var _re_legacy_extension := _compile_re(r"\.[^.]*$")

static func _compile_re(pattern: String) -> RegEx:
	var re := RegEx.new()
	re.compile(pattern)
	return re


static func guess_editor_name(file_name: String) -> String:
	# The file name comes first, so a folder such as "game-dev" cannot set the channel.
	var guessed := _guess_editor_name(file_name.get_file(), _re_extension, _re_channel)
	if guessed.is_empty():
		guessed = _guess_editor_name(file_name, _re_extension, _re_channel)
	if guessed.is_empty():
		return _strip_extension(file_name, _re_extension) # fallback
	return guessed


## Whether [param editor_name] has a version, like the names [method guess_editor_name]
## guesses from versioned file names ("Godot v4.7.2 stable"), unlike its fallback to
## the file name itself.
static func names_version(editor_name: String) -> bool:
	return _re_any_ver.search(editor_name) != null


## Guesses a name the way older releases did. They missed "dev" builds and cut
## names without an extension at the version dot. Only used to recognize names
## they stored.
static func legacy_guess_editor_name(file_name: String) -> String:
	var guessed := _guess_editor_name(file_name, _re_legacy_extension, _re_legacy_channel)
	if guessed.is_empty():
		return _strip_extension(file_name, _re_legacy_extension) # fallback
	return guessed


## Returns an empty string when the name has no version.
static func _guess_editor_name(file_name: String, re_extension: RegEx, re_channel: RegEx) -> String:
	var lower := _strip_extension(file_name, re_extension).to_lower()
	var mono := lower.findn("mono") != -1 # detect Mono builds

	var version := ""
	var channel := ""
	var channel_num := ""

	var m := _re_version.search(lower)
	if m:
		version = m.get_string(1)

	var c := re_channel.search(lower)
	if c:
		channel = c.get_string(1)
		channel_num = c.get_string(2)

	if version == "":
		var mv := _re_any_ver.search(lower)
		if mv:
			version = mv.get_string(1)

	if version == "":
		return ""

	var suffix := ""
	if channel != "":
		suffix = " " + channel
		if channel_num != "":
			suffix += channel_num

	var name := "Godot v%s%s" % [version, suffix]
	if mono:
		name += " mono"

	return name


static func _strip_extension(file_name: String, re_extension: RegEx) -> String:
	# Remove only the last extension (.exe, .x86_64, .zip, etc.)
	var ext := re_extension.search(file_name)
	if ext:
		return file_name.substr(0, ext.get_start())
	return file_name


static func find_project_godot_files(dir_path: String) -> Array[edir.DirListResult]:
	var project_configs := edir.list_recursive(
		ProjectSettings.globalize_path(dir_path), 
		false,
		(func(x: edir.DirListResult) -> bool: 
			return x.is_file and x.file == "project.godot"),
		(func(x: String) -> bool: 
			return not x.get_file().begins_with("."))
	)
	return project_configs


static func response_to_json(response: Variant, safe:=true) -> Variant:
	var body := response[3] as PackedByteArray
	var string := body.get_string_from_utf8()
	if safe:
		return parse_json_safe(string)
	else:
		return JSON.parse_string(string)


static func parse_json_safe(string: String) -> Variant:
	var json := JSON.new()
	var err := json.parse(string)
	if err != OK:
		return null
	else:
		return json.data


static func fit_height(max_height: float, cur_size: Vector2i, callback: Callable) -> void:
	var scale_ratio := max_height / (cur_size.y * Config.EDSCALE)
	if scale_ratio < 1:
		callback.call(Vector2i(
			int(cur_size.x * Config.EDSCALE * scale_ratio),
			int(cur_size.y * Config.EDSCALE * scale_ratio)
		))


static func disconnect_all(obj: Object) -> void:
	for obj_signal in obj.get_signal_list():
		for connection in obj.get_signal_connection_list(obj_signal.name as StringName):
			obj.disconnect(obj_signal.name as StringName, connection.callable as Callable)


static func prop_is_readonly() -> void:
	assert(false, "Property is readonly")


static func not_implemeted() -> Variant:
	assert(false, "Not Implemented")
	return null


static func empty_func() -> void:
	pass


static func obj_has_method(obj: Variant, method: StringName) -> bool:
	if obj is Object:
		return (obj as Object).has_method(method)
	else:
		return false
