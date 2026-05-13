class_name ThemedButton
extends Button
## Button that uses theme icons for its appearance.


@export var _theme_icon_name: String = "Load"
@export var _theme_type := "EditorIcons"


func _ready() -> void:
	_update_theme()
	theme_changed.connect(_update_theme)


func _update_theme() -> void:
	icon = get_theme_icon(_theme_icon_name, _theme_type)
