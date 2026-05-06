class_name NotificationsButton
extends Button


var has_notifications := false:
	set(value):
		has_notifications = value
		visible = value
		disabled = not value
		modulate = Color.WHITE if value else Color(1, 1, 1, 0.6)


func _ready() -> void:
	has_notifications = false
