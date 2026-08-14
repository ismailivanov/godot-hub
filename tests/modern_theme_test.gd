extends Node


const ModernTheme := preload("res://theme/modern_theme.gd")


func _ready() -> void:
	var theme := _make_theme()
	ModernTheme.apply(
		theme,
		Color(0.161, 0.161, 0.161),
		Color(0.337, 0.62, 1.0),
		0.3,
		true,
		false,
		0.0,
		4.0,
		2.0,
		2.0
	)

	assert(theme.get_color(&"highlight_disabled_color", &"Editor").a > 0.0)
	assert(theme.get_color(&"font_hover_color", &"Editor").a > 0.0)
	assert(theme.get_constant(&"base_margin", &"Editor") == 4)
	assert(theme.get_constant(&"increased_margin", &"Editor") == 6)
	assert(theme.get_stylebox(&"button_pressed", &"Tree") is StyleBoxFlat)
	assert(theme.get_stylebox(&"custom_button_pressed", &"Tree") is StyleBoxFlat)
	assert(theme.get_stylebox(&"title_button_normal", &"Tree") is StyleBoxFlat)
	assert(theme.get_icon(&"up", &"SpinBox") is AtlasTexture)
	assert(theme.get_icon(&"down", &"SpinBox") is AtlasTexture)
	assert(theme.get_icon(&"up", &"SpinBox").get_size() == Vector2(32, 16))
	assert(theme.get_icon(&"updown", &"SpinBox").get_size() == Vector2.ZERO)
	assert(theme.get_constant(&"buttons_width", &"SpinBox") == 16)

	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ar")
	var rtl_theme := _make_theme()
	ModernTheme.apply(
		rtl_theme,
		Color(0.161, 0.161, 0.161),
		Color(0.337, 0.62, 1.0),
		0.3,
		true,
		false,
		0.0,
		4.0,
		0.0,
		1.0
	)
	var rtl_sidebar := rtl_theme.get_stylebox(
		&"SidebarPanel", &"EditorStyles"
	) as StyleBoxFlat
	var rtl_nav := rtl_theme.get_stylebox(
		&"pressed", &"SidebarNavButton"
	) as StyleBoxFlat
	var rtl_content := rtl_theme.get_stylebox(&"panel", &"TabContainer") as StyleBoxFlat
	assert(rtl_sidebar.get_border_width(SIDE_LEFT) > 0)
	assert(rtl_sidebar.get_border_width(SIDE_RIGHT) == 0)
	assert(rtl_nav.get_border_width(SIDE_RIGHT) > 0)
	assert(rtl_nav.get_border_width(SIDE_LEFT) == 0)
	assert(rtl_content.corner_radius_bottom_right == 0)
	assert(rtl_content.corner_radius_bottom_left > 0)
	TranslationServer.set_locale(previous_locale)

	print("Modern theme tests passed.")
	get_tree().quit()


func _make_theme() -> Theme:
	var theme := Theme.new()
	var combined_image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	combined_image.fill(Color.WHITE)
	theme.set_icon(
		&"GuiSpinboxUpdown",
		&"EditorIcons",
		ImageTexture.create_from_image(combined_image)
	)
	return theme
