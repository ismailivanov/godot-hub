extends Node
## Provides application-wide caching functionality using ConfigFile.
##
## This class manages a persistent cache stored in user://.cache.
## It supports both direct value access and smart proxy objects
## that auto-save on modification.


## The file path where cache data persists between sessions.
const APP_CACHE_PATH: String = "user://.cache"

var _cache := ConfigFile.new()
var _cache_auto_save := ConfigFileSaveOnSet.new(IConfigFileLike.of_config(_cache), APP_CACHE_PATH)


func _enter_tree() -> void:
	_cache.load(APP_CACHE_PATH)


func has_value(section: String, key: String) -> bool:
	return _cache.has_section_key(section, key)


func get_value(section: String, key: String, default: Variant = null) -> Variant:
	return _cache.get_value(section, key, default)


func set_value(section: String, key: String, value: Variant) -> void:
	_cache.set_value(section, key, value)


func save() -> void:
	_cache.save(APP_CACHE_PATH)


func smart_value(scope: Variant, key: String, autosave: bool = false) -> ConfigFileValue:
	var section := section_of(scope)
	assert(section != null)
	return ConfigFileValue.new(
		_cache_auto_save.as_config_like() if autosave else IConfigFileLike.of_config(_cache),
		section,
		key
	)


func smart_section(scope: Variant, autosave: bool = false) -> ConfigFileSection:
	var section := section_of(scope)
	assert(section != null)
	return ConfigFileSection.new(
		section,
		_cache_auto_save.as_config_like() if autosave else IConfigFileLike.of_config(_cache),
	)


func section_of(obj: Variant) -> String:
	var section := ""
	if obj is String:
		section = obj
	elif obj is Script:
		section = obj.resource_path
	elif utils.obj_has_method(obj, "get_script"):
		section = (obj as Object).get_script().resource_path
	else:
		assert(false, "Invalid scope type for cache section")
	return section
