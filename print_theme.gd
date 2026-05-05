extends SceneTree

const theme_source = preload("res://theme/theme.gd")

func _init() -> void:
	var dark_theme: bool = theme_source.is_dark_theme()
	print("dark_theme: ", dark_theme)
	var theme: Theme = theme_source.create_custom_theme(null)
	var font_color: Color = theme.get_color("font_color", "SidebarNavButton")
	var font_pressed: Color = theme.get_color("font_pressed_color", "SidebarNavButton")
	var accent: Color = theme.get_color("accent_color", "Editor")
	var base: Color = theme.get_color("base_color", "Editor")
	
	print("font_color: ", font_color)
	print("font_pressed_color: ", font_pressed)
	print("accent: ", accent)
	print("base: ", base)
	quit()
