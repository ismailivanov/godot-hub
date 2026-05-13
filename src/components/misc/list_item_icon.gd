class_name ListItemIcon
extends TextureRect
## Icon display for list items with consistent sizing.


@export var _stretch_mode: StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
@export var _expand_mode: ExpandMode = TextureRect.EXPAND_IGNORE_SIZE


func _ready() -> void:
	expand_mode = _expand_mode
	custom_minimum_size = Vector2(64, 64) * Config.edscale
	stretch_mode = _stretch_mode
