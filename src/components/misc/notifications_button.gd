class_name NotificationsButton
extends LinkButton


var has_notifications := false:
	set(value):
		has_notifications = value
		if value:
			modulate = Color.WHITE
		else:
			modulate = Color(1, 1, 1, 0.6)
		queue_redraw()


func _ready() -> void:
	has_notifications = false


func _draw() -> void:
	if not has_notifications:
		return
	var color := get_theme_color("warning_color", "Editor")
	var button_radius := 4.0
	var pos := Vector2(size.x + button_radius * 1.5, size.y / 2.0)
	draw_circle(pos, button_radius, color)

