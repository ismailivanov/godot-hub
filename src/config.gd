extends Node
## Global configuration settings and constants for the application.


## Emitted when configuration is saved.
signal saved

## VERSION constant.
const VERSION = "v1.2"
## APP CONFIG PATH constant.
const APP_CONFIG_PATH = "user://godots.cfg"
## EDITORS CONFIG PATH constant.
const EDITORS_CONFIG_PATH = "user://editors.cfg"
## PROJECTS CONFIG PATH constant.
const PROJECTS_CONFIG_PATH = "user://projects.cfg"
## DEFAULT VERSIONS PATH constant.
const DEFAULT_VERSIONS_PATH = "user://versions"
## DEFAULT DOWNLOADS PATH constant.
const DEFAULT_DOWNLOADS_PATH = "user://downloads"
## DEFAULT UPDATES PATH constant.
const DEFAULT_UPDATES_PATH = "user://updates"
## DEFAULT CACHE DIR PATH constant.
const DEFAULT_CACHE_DIR_PATH = "user://cache"
## RELEASES URL constant.
const RELEASES_URL = "https://github.com/ismailivanov/godot-hub/releases"
## RELEASES LATEST API ENDPOINT constant.
const RELEASES_LATEST_API_ENDPOINT = "https://api.github.com/repos/ismailivanov/godot-hub/releases/latest"
## RELEASES API ENDPOINT constant.
const RELEASES_API_ENDPOINT = "https://api.github.com/repos/ismailivanov/godot-hub/releases"
## Configuration section name.
const _EDITOR_PROXY_SECTION_NAME = "theme"

var auto_edscale := 1.
var edscale := 1.
var EDSCALE: float:
	get: return edscale
var agent := ""
var _random_project_names := RandomProjectNames.new()
var _cfg := ConfigFile.new()
var _cfg_auto_save := ConfigFileSaveOnSet.new(
	IConfigFileLike.of_config(_cfg), 
	APP_CONFIG_PATH, 
	func(err: Error) -> void:
		if err == OK:
			saved.emit() 
		pass\
)
var agent_header: String:
	get: return "User-Agent: %s" % agent
var versions_path := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"versions_path",
	DEFAULT_VERSIONS_PATH
).map_return_value(_simplify_path): 
	set(_v): _readonly()
var downloads_path := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"downloads_path",
	DEFAULT_DOWNLOADS_PATH
).map_return_value(_simplify_path): 
	set(_v): _readonly()
var cache_dir_path := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"cache_dir_path",
	DEFAULT_CACHE_DIR_PATH
).map_return_value(_simplify_path): 
	set(_v): _readonly()
var updates_path := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"updates_path",
	DEFAULT_UPDATES_PATH
).map_return_value(_simplify_path): 
	set(_v): _readonly()
var default_projects_path := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"projects_path",
	OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
).map_return_value(_simplify_path): 
	set(_v): _readonly()
var language := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(),
	"app",
	"language",
	"en"
):
	set(_v): _readonly()
var saved_edscale := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	_EDITOR_PROXY_SECTION_NAME, 
	"interface/editor/custom_display_scale"
): 
	set(_v): _readonly()
var default_editor_tags := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"default_editor_tags",
	["dev", "rc", "alpha", "4.x", "3.x", "stable", "mono"]
): 
	set(_v): _readonly()
var default_project_tags := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"default_project_tags",
	[]
): 
	set(_v): _readonly()
var auto_close := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"auto_close",
	true
): 
	set(_v): _readonly()
var show_orphan_editor := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"show_orphan_editor",
	false
): 
	set(_v): _readonly()
var use_system_title_bar := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"use_system_titlebar",
	false
): 
	set(_v): _readonly()
var use_native_file_dialog := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(),
	"app",
	"use_native_file_dialog",
	false
):
	set(_v): _readonly()
var last_window_rect := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"last_window_rect",
	Rect2i()
): 
	set(_v): _readonly()
var remember_window_size := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"remember_window_size",
	false
): 
	set(_v): _readonly()
var allow_install_to_not_empty_dir := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"allow_install_to_not_empty_dir",
	false
): 
	set(_v): _readonly()
var random_project_prefixes := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"random-project-names", 
	"prefixes",
	[]
): 
	set(_v): _readonly()
var random_project_topics := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"random-project-names", 
	"topics",
	[]
): 
	set(_v): _readonly()
var random_project_suffixes := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"random-project-names", 
	"suffixes",
	[]
): 
	set(_v): _readonly()
var global_custom_commands_projects := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"global-custom-commands-v2", 
	"projects",
	[]
): 
	set(_v): _readonly()
var global_custom_commands_editors := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"global-custom-commands-v2", 
	"editors",
	[]
): 
	set(_v): _readonly()
var http_proxy_host := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(),
	"network",
	"http_proxy_host",
	""
):
	set(_v): _readonly()
var http_proxy_port := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(),
	"network",
	"http_proxy_port",
	8080
):
	set(_v): _readonly()
var directory_naming_convention := ConfigFileValue.new(
	_cfg_auto_save.as_config_like(), 
	"app", 
	"directory_naming_convention",
	"snake_case"
): 
	set(_v): _readonly()

# Uppercase aliases for backward compatibility with existing codebase references.
var LANGUAGE: ConfigFileValue:
	get: return language
var AUTO_CLOSE: ConfigFileValue:
	get: return auto_close
var SAVED_EDSCALE: ConfigFileValue:
	get: return saved_edscale
var DEFAULT_PROJECTS_PATH: ConfigFileValue:
	get: return default_projects_path
var DIRECTORY_NAMING_CONVENTION: ConfigFileValue:
	get: return directory_naming_convention
var USE_SYSTEM_TITLE_BAR: ConfigFileValue:
	get: return use_system_title_bar
var USE_NATIVE_FILE_DIALOG: ConfigFileValue:
	get: return use_native_file_dialog
var REMEMBER_WINDOW_SIZE: ConfigFileValue:
	get: return remember_window_size
var DOWNLOADS_PATH: ConfigFileValue:
	get: return downloads_path
var VERSIONS_PATH: ConfigFileValue:
	get: return versions_path
var SHOW_ORPHAN_EDITOR: ConfigFileValue:
	get: return show_orphan_editor
var ALLOW_INSTALL_TO_NOT_EMPTY_DIR: ConfigFileValue:
	get: return allow_install_to_not_empty_dir
var HTTP_PROXY_HOST: ConfigFileValue:
	get: return http_proxy_host
var HTTP_PROXY_PORT: ConfigFileValue:
	get: return http_proxy_port
var GLOBAL_CUSTOM_COMMANDS_PROJECTS: ConfigFileValue:
	get: return global_custom_commands_projects
var GLOBAL_CUSTOM_COMMANDS_EDITORS: ConfigFileValue:
	get: return global_custom_commands_editors
var DEFAULT_PROJECT_TAGS: ConfigFileValue:
	get: return default_project_tags
var AGENT_HEADER: String:
	get: return agent_header
var UPDATES_PATH: ConfigFileValue:
	get: return updates_path
var AUTO_EDSCALE: float:
	get: return auto_edscale
var CACHE_DIR_PATH: ConfigFileValue:
	get: return cache_dir_path
var cfg: ConfigFile:
	get: return _cfg


func _enter_tree() -> void:	
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(DEFAULT_VERSIONS_PATH))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(DEFAULT_DOWNLOADS_PATH))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(DEFAULT_UPDATES_PATH))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(DEFAULT_CACHE_DIR_PATH))
	_cfg.load(APP_CONFIG_PATH)
	assert(not DEFAULT_VERSIONS_PATH.ends_with("/"))
	assert(not DEFAULT_DOWNLOADS_PATH.ends_with("/"))
	
	_random_project_names.set_prefixes(random_project_prefixes.ret() as Array)
	_random_project_names.set_suffixes(random_project_suffixes.ret() as Array)
	_random_project_names.set_topics(random_project_topics.ret() as Array)

	agent = "GodotHub/%s (%s) Godot/%s" % [
		VERSION,
		OS.get_name(),
		Engine.get_version_info().string
	]
	_setup_scale()


func _setup_scale() -> void:
	auto_edscale = _get_auto_display_scale()
	var saved_scale := saved_edscale.ret(-1) as float
	if saved_scale == -1:
		saved_scale = auto_edscale
	edscale = clamp(saved_scale, 0.75, 4)


#https://github.com/godotengine/godot/blob/master/editor/editor_settings.cpp#L1400


func _get_auto_display_scale() -> float:
#	if OS.has_feature("macos"):
#		return DisplayServer.screen_get_max_scale()
#	else:
	var screen := DisplayServer.window_get_current_screen()
	if DisplayServer.screen_get_size(screen) == Vector2i():
		return 1.0

	# Use the smallest dimension to use a correct display scale on portrait displays.
	var smallest_dimension := minf(DisplayServer.screen_get_size(screen).x, DisplayServer.screen_get_size(screen).y);
	if DisplayServer.screen_get_dpi(screen) >= 192 and smallest_dimension >= 1400:
		# hiDPI display.
		return 2.0
	elif smallest_dimension >= 1700:
		# Likely a hiDPI display, but we aren't certain due to the returned DPI.
		# Use an intermediate scale to handle this situation.
		return 1.5
	elif smallest_dimension <= 800:
		# Small loDPI display. Use a smaller display scale so that editor elements fit more easily.
		# Icons won't look great, but this is better than having editor elements overflow from its window.
		return 0.75
	return 1.0


func save() -> Error:
	var err := _cfg.save(APP_CONFIG_PATH)
	if err == OK:
		saved.emit() 
	return err


func editor_settings_proxy_get(key: String, default: Variant) -> Variant:
	return _cfg.get_value(_EDITOR_PROXY_SECTION_NAME, key, default)


func editor_settings_proxy_set(key: String, value: Variant) -> void:
	_cfg.set_value(_EDITOR_PROXY_SECTION_NAME, key, value)


func next_random_project_name() -> String:
	return _random_project_names.next()


func _readonly() -> void:
	utils.prop_is_readonly()


func _simplify_path(s: String) -> String:
	return s.simplify_path()


class CustomCommandsSourceConfig extends CommandViewer.CustomCommandsSource:
	var _val: ConfigFileValue
	
	func _init(val: ConfigFileValue) -> void:
		_val = val
	
	func _get_custom_commands() -> Array:
		return _val.ret()
	
	func _set_custom_commands(value: Array) -> void:
		_val.put(value)
