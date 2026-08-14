extends RefCounted
## Focused runtime overlay for Godot Hub's Modern UI style.
##
## The palette and control treatment are adapted from Godot 4.7's editor theme:
## https://github.com/godotengine/godot/blob/5b4e0cb0f/editor/themes/theme_modern.cpp
## This intentionally covers the controls used by Godot Hub instead of mirroring the
## editor-only theme surface in full.


const BASE_MARGIN := 4.0


class Palette:
	var scale := 1.0
	var corner_radius := 4.0
	var border_width := 0.0
	var contrast := 0.3
	var draw_extra_borders := false
	var dark_theme := true
	var dark_icon_and_font := true

	var base_color := Color.TRANSPARENT
	var accent_color := Color.TRANSPARENT
	var mono_color := Color.TRANSPARENT
	var mono_color_inv := Color.TRANSPARENT
	var mono_color_font := Color.TRANSPARENT
	var dark_color_1 := Color.TRANSPARENT
	var dark_color_2 := Color.TRANSPARENT
	var dark_color_3 := Color.TRANSPARENT
	var contrast_color_1 := Color.TRANSPARENT
	var contrast_color_2 := Color.TRANSPARENT
	var highlight_color := Color.TRANSPARENT
	var highlight_disabled_color := Color.TRANSPARENT
	var selection_color := Color.TRANSPARENT
	var separator_color := Color.TRANSPARENT

	var font_color := Color.TRANSPARENT
	var font_secondary_color := Color.TRANSPARENT
	var font_focus_color := Color.TRANSPARENT
	var font_hover_color := Color.TRANSPARENT
	var font_pressed_color := Color.TRANSPARENT
	var font_hover_pressed_color := Color.TRANSPARENT
	var font_disabled_color := Color.TRANSPARENT
	var font_readonly_color := Color.TRANSPARENT
	var font_placeholder_color := Color.TRANSPARENT
	var font_outline_color := Color.TRANSPARENT

	var icon_normal_color := Color.TRANSPARENT
	var icon_secondary_color := Color.TRANSPARENT
	var icon_focus_color := Color.TRANSPARENT
	var icon_hover_color := Color.TRANSPARENT
	var icon_pressed_color := Color.TRANSPARENT
	var icon_disabled_color := Color.TRANSPARENT

	var surface_popup_color := Color.TRANSPARENT
	var surface_lowest_color := Color.TRANSPARENT
	var surface_lower_color := Color.TRANSPARENT
	var surface_low_color := Color.TRANSPARENT
	var surface_base_color := Color.TRANSPARENT
	var surface_high_color := Color.TRANSPARENT
	var surface_higher_color := Color.TRANSPARENT
	var surface_highest_color := Color.TRANSPARENT

	var button_normal_color := Color.TRANSPARENT
	var button_hover_color := Color.TRANSPARENT
	var button_pressed_color := Color.TRANSPARENT
	var button_disabled_color := Color.TRANSPARENT
	var button_border_normal_color := Color.TRANSPARENT
	var button_border_hover_color := Color.TRANSPARENT
	var button_border_pressed_color := Color.TRANSPARENT
	var flat_button_hover_color := Color.TRANSPARENT
	var flat_button_pressed_color := Color.TRANSPARENT
	var flat_button_hover_pressed_color := Color.TRANSPARENT
	var extra_border_color_1 := Color.TRANSPARENT
	var extra_border_color_2 := Color.TRANSPARENT


class Styles:
	var base: StyleBoxFlat
	var focus: StyleBoxFlat
	var empty: StyleBoxEmpty
	var empty_wide: StyleBoxEmpty
	var button: StyleBoxFlat
	var button_hover: StyleBoxFlat
	var button_pressed: StyleBoxFlat
	var button_disabled: StyleBoxFlat
	var flat_button: StyleBoxFlat
	var flat_button_hover: StyleBoxFlat
	var flat_button_pressed: StyleBoxFlat
	var flat_button_hover_pressed: StyleBoxFlat
	var panel_container: StyleBoxFlat
	var popup_panel: StyleBoxFlat
	var dialog: StyleBoxFlat
	var window: StyleBoxFlat
	var tree_panel: StyleBoxFlat
	var tab_container: StyleBoxFlat


static func apply(
	theme: Theme,
	base_color: Color,
	accent_color: Color,
	contrast: float,
	dark_icon_and_font: bool,
	draw_extra_borders: bool,
	border_width: float,
	corner_radius: float,
	extra_spacing: float,
	scale: float
) -> void:
	var palette := _make_palette(
		base_color,
		accent_color,
		contrast,
		dark_icon_and_font,
		draw_extra_borders,
		border_width,
		corner_radius,
		scale
	)
	var styles := _make_styles(palette, extra_spacing)

	_apply_shared_colors(theme, palette, extra_spacing)
	_apply_panels_and_windows(theme, palette, styles)
	_apply_buttons(theme, palette, styles)
	_apply_lists(theme, palette, styles, extra_spacing)
	_apply_tabs(theme, palette, styles)
	_apply_text_inputs(theme, palette, styles)
	_apply_popup_menu(theme, palette, styles)
	_apply_scrollbars_and_sliders(theme, palette, styles)
	_apply_labels_and_progress(theme, palette, styles)
	_apply_containers(theme, palette, extra_spacing)
	_apply_hub_styles(theme, palette, styles)


static func _make_palette(
	base_color: Color,
	accent_color: Color,
	contrast: float,
	dark_icon_and_font: bool,
	draw_extra_borders: bool,
	border_width: float,
	corner_radius: float,
	scale: float
) -> Palette:
	var palette := Palette.new()
	palette.scale = scale
	palette.corner_radius = clampf(corner_radius, 0.0, 12.0)
	palette.border_width = border_width
	palette.contrast = contrast
	palette.draw_extra_borders = draw_extra_borders
	palette.dark_theme = base_color.get_luminance() < 0.5
	palette.dark_icon_and_font = dark_icon_and_font
	palette.base_color = base_color
	palette.accent_color = accent_color
	palette.mono_color = Color.WHITE if palette.dark_theme else Color.BLACK
	palette.mono_color_inv = Color.BLACK if palette.dark_theme else Color.WHITE
	palette.mono_color_font = Color.WHITE if dark_icon_and_font else Color.BLACK

	palette.dark_color_1 = base_color.lerp(Color.BLACK, contrast * 1.15).clamp()
	palette.dark_color_2 = Color(0, 0, 0, 0.3) if palette.dark_theme else Color(1, 1, 1, 0.3)
	palette.dark_color_3 = _get_base_color(base_color, contrast, 0.8, 0.9)
	palette.contrast_color_1 = base_color.lerp(
		palette.mono_color, maxf(contrast * 1.15, 0.3 * 1.15)
	)
	palette.contrast_color_2 = base_color.lerp(
		palette.mono_color, maxf(contrast * 1.725, 0.3 * 1.725)
	)
	palette.highlight_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.275)
	palette.highlight_disabled_color = palette.highlight_color.lerp(
		Color.BLACK if palette.dark_theme else Color.WHITE, 0.5
	)
	palette.selection_color = accent_color * Color(1, 1, 1, 0.4)
	palette.separator_color = Color(0, 0, 0, 0.4 if palette.dark_theme else 0.2)

	palette.font_color = Color(palette.mono_color_font, 0.75)
	palette.font_secondary_color = Color(palette.mono_color_font, 0.55)
	palette.font_focus_color = palette.mono_color_font
	palette.font_hover_color = Color(palette.mono_color_font, 0.85)
	palette.font_pressed_color = Color(palette.mono_color_font, 0.85)
	palette.font_hover_pressed_color = palette.mono_color_font
	palette.font_disabled_color = Color(
		palette.mono_color_font, 0.35 if dark_icon_and_font else 0.5
	)
	palette.font_readonly_color = Color(palette.mono_color_font, 0.65)
	palette.font_placeholder_color = palette.font_disabled_color
	palette.font_outline_color = Color(1, 1, 1, 0)

	palette.icon_normal_color = Color(1, 1, 1, 0.85 if dark_icon_and_font else 0.95)
	palette.icon_secondary_color = Color(1, 1, 1, 0.6 if dark_icon_and_font else 0.75)
	palette.icon_focus_color = Color.WHITE
	palette.icon_hover_color = Color.WHITE
	palette.icon_pressed_color = accent_color * (1.15 if dark_icon_and_font else 3.5)
	palette.icon_pressed_color.a = 1.0
	palette.icon_disabled_color = Color(1, 1, 1, 0.35 if dark_icon_and_font else 0.5)

	palette.surface_popup_color = _get_base_color(base_color, contrast, 1.9, 0.9)
	palette.surface_lowest_color = _get_base_color(base_color, contrast, 1.7, 0.9)
	palette.surface_lower_color = _get_base_color(base_color, contrast, 1.1, 0.9)
	palette.surface_low_color = _get_base_color(base_color, contrast, 0.8, 1.0)
	palette.surface_base_color = _get_base_color(base_color, contrast, 0.0, 1.0)
	palette.surface_high_color = _get_base_color(base_color, contrast, -1.3, 0.8)
	palette.surface_higher_color = _get_base_color(base_color, contrast, -1.5, 0.8)
	palette.surface_highest_color = _get_base_color(base_color, contrast, -2.2, 0.6)

	palette.button_normal_color = _get_base_color(base_color, contrast, -2.0, 0.85)
	palette.button_hover_color = _get_base_color(base_color, contrast, -2.9, 0.75)
	palette.button_pressed_color = _get_base_color(base_color, contrast, -3.2, 0.75)
	palette.button_disabled_color = _get_base_color(base_color, contrast, -1.4, 0.75)
	palette.button_border_normal_color = _get_base_color(base_color, contrast, -2.5, 0.75)
	palette.button_border_hover_color = _get_base_color(base_color, contrast, -3.4, 0.75)
	palette.button_border_pressed_color = _get_base_color(base_color, contrast, -3.7, 0.75)
	palette.flat_button_hover_color = _get_base_color(base_color, contrast, -1.2, 0.75)
	palette.flat_button_pressed_color = _get_base_color(base_color, contrast, -2.0, 0.75)
	palette.flat_button_hover_pressed_color = _get_base_color(base_color, contrast, -2.4, 0.75)
	palette.extra_border_color_1 = Color(1, 1, 1, 0.4) if palette.dark_theme else Color(0, 0, 0, 0.4)
	palette.extra_border_color_2 = Color(1, 1, 1, 0.2) if palette.dark_theme else Color(0, 0, 0, 0.2)
	return palette


static func _get_base_color(
	base_color: Color,
	contrast: float,
	dimness_offset: float,
	saturation_multiplier: float
) -> Color:
	var color := base_color
	var final_contrast := clampf(contrast, -0.1, 0.5) if dimness_offset < 0.0 else contrast
	color.v = clampf(lerpf(color.v, 0.0, final_contrast * dimness_offset), 0.0, 1.0)
	color.s *= saturation_multiplier
	return color


static func _make_styles(palette: Palette, extra_spacing: float) -> Styles:
	var styles := Styles.new()
	var increased_margin := BASE_MARGIN + extra_spacing * 0.75
	styles.base = _flat(
		palette.base_color,
		increased_margin * 1.5,
		increased_margin * 1.5,
		increased_margin * 1.5,
		increased_margin * 1.5,
		palette.corner_radius,
		palette.scale
	)

	styles.focus = styles.base.duplicate() as StyleBoxFlat
	styles.focus.draw_center = false
	styles.focus.border_color = palette.accent_color * Color(1, 1, 1, 0.8)
	styles.focus.set_border_width_all(maxi(2, roundi(2.0 * palette.scale)))

	styles.empty = _empty()
	var wide_margin := maxf(BASE_MARGIN, 3.0)
	styles.empty_wide = _empty(
		wide_margin * 1.5, wide_margin, wide_margin * 1.5, wide_margin, palette.scale
	)

	styles.button = styles.base.duplicate() as StyleBoxFlat
	_set_margins(
		styles.button,
		BASE_MARGIN * 2.0 * palette.scale,
		BASE_MARGIN * 1.5 * palette.scale,
		BASE_MARGIN * 2.0 * palette.scale,
		BASE_MARGIN * 1.5 * palette.scale
	)
	styles.button.bg_color = palette.button_normal_color
	styles.button.set_border_width_all(maxi(1, roundi(palette.scale)))
	styles.button.shadow_color = Color(0, 0, 0, 0.005) if palette.dark_theme else Color(1, 1, 1, 0.005)
	styles.button.shadow_size = ceili(8.0 * palette.scale)
	styles.button.shadow_offset = Vector2(0, 4) * palette.scale
	styles.button.border_color = (
		palette.extra_border_color_1
		if palette.draw_extra_borders
		else palette.button_border_normal_color
	)

	styles.button_hover = styles.button.duplicate() as StyleBoxFlat
	styles.button_hover.bg_color = palette.button_hover_color
	styles.button_hover.border_color = (
		palette.extra_border_color_1
		if palette.draw_extra_borders
		else palette.button_border_hover_color
	)

	styles.button_pressed = styles.button.duplicate() as StyleBoxFlat
	styles.button_pressed.bg_color = palette.button_pressed_color
	styles.button_pressed.border_color = (
		palette.extra_border_color_1
		if palette.draw_extra_borders
		else palette.button_border_pressed_color
	)

	styles.button_disabled = styles.button.duplicate() as StyleBoxFlat
	styles.button_disabled.bg_color = palette.button_disabled_color
	if palette.draw_extra_borders:
		styles.button_disabled.border_color = palette.extra_border_color_2 * Color(1, 1, 1, 0.5)
	else:
		styles.button_disabled.set_border_width_all(0)

	styles.flat_button_hover = styles.base.duplicate() as StyleBoxFlat
	styles.flat_button_hover.bg_color = palette.flat_button_hover_color
	_set_margins(
		styles.flat_button_hover,
		BASE_MARGIN * 1.5 * palette.scale,
		BASE_MARGIN * 0.9 * palette.scale,
		BASE_MARGIN * 1.5 * palette.scale,
		BASE_MARGIN * 0.9 * palette.scale
	)
	styles.flat_button_pressed = styles.flat_button_hover.duplicate() as StyleBoxFlat
	styles.flat_button_pressed.bg_color = palette.flat_button_pressed_color
	styles.flat_button_hover_pressed = styles.flat_button_hover.duplicate() as StyleBoxFlat
	styles.flat_button_hover_pressed.bg_color = palette.flat_button_hover_pressed_color
	styles.flat_button = styles.flat_button_hover.duplicate() as StyleBoxFlat
	styles.flat_button.draw_center = false

	styles.panel_container = styles.button.duplicate() as StyleBoxFlat
	styles.panel_container.draw_center = false
	styles.panel_container.set_border_width_all(0)

	styles.popup_panel = styles.base.duplicate() as StyleBoxFlat
	styles.popup_panel.bg_color = palette.surface_popup_color
	styles.popup_panel.shadow_color = Color(0, 0, 0, 0.3)
	styles.popup_panel.shadow_size = ceili(BASE_MARGIN * 0.75 * palette.scale)
	styles.popup_panel.set_content_margin_all(BASE_MARGIN * 2.4 * palette.scale)
	styles.popup_panel.set_corner_radius_all(0)
	if palette.draw_extra_borders:
		styles.popup_panel.set_border_width_all(maxi(1, roundi(palette.scale)))
		styles.popup_panel.border_color = palette.extra_border_color_2

	styles.dialog = styles.base.duplicate() as StyleBoxFlat
	styles.dialog.set_content_margin_all(BASE_MARGIN * 2.4 * palette.scale)
	styles.dialog.set_corner_radius_all(0)

	styles.window = styles.dialog.duplicate() as StyleBoxFlat
	styles.window.shadow_color = Color(0, 0, 0, 0.3 if palette.dark_theme else 0.1)
	styles.window.shadow_size = roundi(4.0 * palette.scale)
	styles.window.border_color = palette.base_color
	styles.window.set_border_width(SIDE_TOP, roundi(24.0 * palette.scale))
	styles.window.set_expand_margin(SIDE_TOP, 24.0 * palette.scale)

	styles.tree_panel = styles.base.duplicate() as StyleBoxFlat
	styles.tree_panel.bg_color = palette.dark_color_1.lerp(palette.dark_color_2, 0.5)
	if palette.draw_extra_borders:
		styles.tree_panel.set_border_width_all(maxi(1, roundi(palette.scale)))
		styles.tree_panel.border_color = palette.extra_border_color_2
	else:
		styles.tree_panel.border_color = palette.dark_color_3

	styles.tab_container = styles.base.duplicate() as StyleBoxFlat
	styles.tab_container.set_content_margin_all(increased_margin * 1.5 * palette.scale)
	_set_corners(
		styles.tab_container,
		0, 0,
		roundi(palette.corner_radius * palette.scale),
		roundi(palette.corner_radius * palette.scale)
	)
	return styles


static func _apply_shared_colors(
	theme: Theme, palette: Palette, extra_spacing: float
) -> void:
	var editor := &"Editor"
	theme.set_color(&"base_color", editor, palette.base_color)
	theme.set_color(&"accent_color", editor, palette.accent_color)
	theme.set_color(&"mono_color", editor, palette.mono_color)
	theme.set_color(&"dark_color_1", editor, palette.dark_color_1)
	theme.set_color(&"dark_color_2", editor, palette.dark_color_2)
	theme.set_color(&"dark_color_3", editor, palette.dark_color_3)
	theme.set_color(&"contrast_color_1", editor, palette.contrast_color_1)
	theme.set_color(&"contrast_color_2", editor, palette.contrast_color_2)
	theme.set_color(&"highlight_color", editor, palette.highlight_color)
	theme.set_color(&"highlight_disabled_color", editor, palette.highlight_disabled_color)
	theme.set_color(&"disabled_highlight_color", editor, palette.highlight_disabled_color)
	theme.set_color(&"selection_color", editor, palette.selection_color)
	theme.set_color(&"separator_color", editor, palette.separator_color)
	theme.set_color(&"font_color", editor, palette.font_color)
	theme.set_color(&"font_focus_color", editor, palette.font_focus_color)
	theme.set_color(&"font_hover_color", editor, palette.font_hover_color)
	theme.set_color(&"font_pressed_color", editor, palette.font_pressed_color)
	theme.set_color(&"font_hover_pressed_color", editor, palette.font_hover_pressed_color)
	theme.set_color(&"font_disabled_color", editor, palette.font_disabled_color)
	theme.set_color(&"font_readonly_color", editor, palette.font_readonly_color)
	theme.set_color(&"font_placeholder_color", editor, palette.font_placeholder_color)
	theme.set_color(&"font_outline_color", editor, palette.font_outline_color)
	theme.set_color(&"highlighted_font_color", editor, palette.font_hover_color)
	theme.set_color(&"disabled_font_color", editor, palette.font_disabled_color)
	theme.set_color(&"readonly_font_color", editor, palette.font_readonly_color)
	theme.set_color(&"surface_popup", editor, palette.surface_popup_color)
	theme.set_color(&"surface_lowest", editor, palette.surface_lowest_color)
	theme.set_color(&"surface_lower", editor, palette.surface_lower_color)
	theme.set_color(&"surface_low", editor, palette.surface_low_color)
	theme.set_color(&"surface_base", editor, palette.surface_base_color)
	theme.set_color(&"surface_high", editor, palette.surface_high_color)
	theme.set_color(&"surface_higher", editor, palette.surface_higher_color)
	theme.set_color(&"surface_highest", editor, palette.surface_highest_color)
	theme.set_constant(&"base_margin", editor, roundi(BASE_MARGIN))
	theme.set_constant(
		&"increased_margin", editor, roundi(BASE_MARGIN + extra_spacing * 0.75)
	)


static func _apply_panels_and_windows(theme: Theme, palette: Palette, styles: Styles) -> void:
	var panel := _flat(
		palette.dark_color_1, 6, 4, 6, 4, palette.corner_radius, palette.scale
	)
	theme.set_stylebox(&"panel", &"Panel", panel)
	theme.set_stylebox(&"panel", &"PanelContainer", styles.empty_wide)
	theme.set_stylebox(&"panel", &"PopupPanel", styles.popup_panel)
	theme.set_stylebox(&"panel", &"PopupDialog", styles.dialog)
	theme.set_stylebox(&"panel", &"AcceptDialog", styles.dialog)
	theme.set_stylebox(&"embedded_border", &"Window", styles.window)
	theme.set_stylebox(&"embedded_unfocused_border", &"Window", styles.window)
	theme.set_constant(&"buttons_separation", &"AcceptDialog", roundi(8.0 * palette.scale))
	theme.set_constant(&"buttons_min_width", &"AcceptDialog", roundi(105.0 * palette.scale))
	theme.set_constant(&"buttons_min_height", &"AcceptDialog", roundi(34.0 * palette.scale))

	var tooltip: StyleBoxFlat = styles.base.duplicate()
	tooltip.bg_color = palette.surface_popup_color
	tooltip.set_content_margin_all(0)
	tooltip.set_corner_radius_all(0)
	if palette.draw_extra_borders:
		tooltip.set_border_width_all(maxi(1, roundi(palette.scale)))
		tooltip.border_color = palette.extra_border_color_2
	theme.set_stylebox(&"panel", &"TooltipPanel", tooltip)
	theme.set_color(&"font_color", &"TooltipLabel", palette.font_hover_color)
	theme.set_color(&"font_shadow_color", &"TooltipLabel", Color.TRANSPARENT)

	theme.set_stylebox(&"panel", &"ScrollContainer", styles.empty)
	theme.set_stylebox(&"focus", &"ScrollContainer", styles.focus)
	var scroll_hint := Color(0, 0, 0, 1.0 if palette.dark_theme else 0.5)
	theme.set_color(&"scroll_hint_vertical_color", &"ScrollContainer", scroll_hint)
	theme.set_color(&"scroll_hint_horizontal_color", &"ScrollContainer", scroll_hint)

	var background: StyleBoxFlat = styles.base.duplicate()
	background.bg_color = palette.surface_lowest_color
	background.set_content_margin_all(0)
	background.set_corner_radius_all(0)
	theme.set_color(&"background", &"Editor", palette.surface_lowest_color)
	theme.set_stylebox(&"Background", &"EditorStyles", background)
	theme.set_stylebox(&"PanelForeground", &"EditorStyles", styles.base)
	theme.set_stylebox(&"Focus", &"EditorStyles", styles.focus)

	var content: StyleBoxFlat = styles.base.duplicate()
	content.border_color = palette.dark_color_3
	content.set_border_width_all(roundi(palette.border_width))
	content.set_border_width(SIDE_TOP, 0)
	content.set_corner_radius(CORNER_TOP_LEFT, 0)
	content.set_corner_radius(CORNER_BOTTOM_LEFT, 0)
	_set_margins(
		content,
		BASE_MARGIN * palette.scale + palette.border_width,
		(BASE_MARGIN + 2.0) * palette.scale + palette.border_width,
		BASE_MARGIN * palette.scale + palette.border_width,
		BASE_MARGIN * palette.scale + palette.border_width
	)
	theme.set_stylebox(&"Content", &"EditorStyles", content)


static func _apply_buttons(theme: Theme, palette: Palette, styles: Styles) -> void:
	for type_name: StringName in [&"Button", &"MenuBar", &"MenuButton", &"OptionButton"]:
		_set_button_style_family(theme, type_name, palette, styles)

	theme.set_constant(&"arrow_margin", &"OptionButton", roundi(BASE_MARGIN * 2.0 * palette.scale))
	theme.set_constant(&"modulate_arrow", &"OptionButton", 1)
	theme.set_constant(&"h_separation", &"OptionButton", roundi(4.0 * palette.scale))

	for type_name: StringName in [&"CheckButton", &"CheckBox"]:
		var checkbox: StyleBoxFlat = styles.panel_container.duplicate()
		_set_margins(
			checkbox,
			BASE_MARGIN * 1.5 * palette.scale,
			BASE_MARGIN * 0.75 * palette.scale,
			BASE_MARGIN * 1.5 * palette.scale,
			BASE_MARGIN * 0.75 * palette.scale
		)
		var checkbox_normal: StyleBoxFlat = checkbox.duplicate()
		checkbox_normal.draw_center = false
		for state: StringName in [&"normal", &"normal_mirrored"]:
			theme.set_stylebox(state, type_name, checkbox_normal)
		for state: StringName in [
			&"hover", &"pressed", &"hover_pressed", &"disabled",
			&"hover_mirrored", &"pressed_mirrored", &"hover_pressed_mirrored", &"disabled_mirrored"
		]:
			theme.set_stylebox(state, type_name, checkbox)
		_set_button_colors(theme, type_name, palette)
		theme.set_constant(&"h_separation", type_name, roundi(8.0 * palette.scale))
		theme.set_constant(&"check_v_offset", type_name, 0)
		theme.set_constant(&"outline_size", type_name, 0)

	theme.set_stylebox(&"focus", &"LinkButton", styles.empty)
	_set_button_colors(theme, &"LinkButton", palette)
	theme.set_constant(&"outline_size", &"LinkButton", 0)


static func _set_button_style_family(
	theme: Theme, type_name: StringName, palette: Palette, styles: Styles
) -> void:
	for state: StringName in [&"normal", &"normal_mirrored"]:
		theme.set_stylebox(state, type_name, styles.button)
	for state: StringName in [&"hover", &"hover_mirrored"]:
		theme.set_stylebox(state, type_name, styles.button_hover)
	for state: StringName in [&"pressed", &"hover_pressed", &"pressed_mirrored", &"hover_pressed_mirrored"]:
		theme.set_stylebox(state, type_name, styles.button_pressed)
	for state: StringName in [&"disabled", &"disabled_mirrored"]:
		theme.set_stylebox(state, type_name, styles.button_disabled)
	theme.set_stylebox(&"focus", type_name, styles.focus)
	_set_button_colors(theme, type_name, palette)
	theme.set_constant(&"h_separation", type_name, roundi(4.0 * palette.scale))
	theme.set_constant(&"outline_size", type_name, 0)
	theme.set_constant(&"align_to_largest_stylebox", type_name, 1)


static func _set_button_colors(theme: Theme, type_name: StringName, palette: Palette) -> void:
	theme.set_color(&"font_color", type_name, palette.font_color)
	theme.set_color(&"font_hover_color", type_name, palette.font_hover_color)
	theme.set_color(&"font_hover_pressed_color", type_name, palette.font_hover_pressed_color)
	theme.set_color(&"font_focus_color", type_name, palette.font_focus_color)
	theme.set_color(&"font_pressed_color", type_name, palette.font_pressed_color)
	theme.set_color(&"font_disabled_color", type_name, palette.font_disabled_color)
	theme.set_color(&"font_outline_color", type_name, palette.font_outline_color)
	theme.set_color(&"icon_normal_color", type_name, palette.icon_normal_color)
	theme.set_color(&"icon_hover_color", type_name, palette.icon_hover_color)
	theme.set_color(&"icon_focus_color", type_name, palette.icon_focus_color)
	theme.set_color(&"icon_hover_pressed_color", type_name, palette.icon_pressed_color)
	theme.set_color(&"icon_pressed_color", type_name, palette.icon_pressed_color)
	theme.set_color(&"icon_disabled_color", type_name, palette.icon_disabled_color)


static func _apply_lists(
	theme: Theme, palette: Palette, styles: Styles, extra_spacing: float
) -> void:
	var hover: StyleBoxFlat = styles.flat_button_hover.duplicate()
	hover.set_content_margin_all(0)
	var selected: StyleBoxFlat = styles.flat_button_pressed.duplicate()
	selected.set_content_margin_all(0)
	var hovered_selected: StyleBoxFlat = styles.flat_button_hover_pressed.duplicate()
	hovered_selected.set_content_margin_all(0)
	var cursor: StyleBoxFlat = styles.base.duplicate()
	cursor.bg_color = palette.mono_color * Color(1, 1, 1, 0.04)
	cursor.set_content_margin_all(0)
	var button_pressed: StyleBoxFlat = styles.flat_button_pressed.duplicate()
	_set_margins(
		button_pressed,
		BASE_MARGIN * palette.scale,
		0,
		BASE_MARGIN * palette.scale,
		0
	)
	var title_button: StyleBoxFlat = styles.base.duplicate()
	title_button.bg_color = palette.surface_lower_color
	title_button.border_color = Color(palette.surface_lower_color, 0)
	title_button.set_border_width(SIDE_LEFT, ceili(palette.scale))
	title_button.set_border_width(SIDE_RIGHT, ceili(palette.scale))

	theme.set_stylebox(&"panel", &"Tree", styles.tree_panel)
	theme.set_stylebox(&"focus", &"Tree", styles.focus)
	theme.set_stylebox(&"button_pressed", &"Tree", button_pressed)
	theme.set_stylebox(&"custom_button", &"Tree", styles.flat_button)
	theme.set_stylebox(&"custom_button_pressed", &"Tree", button_pressed)
	for state: StringName in [&"button_hover", &"hovered", &"hovered_dimmed", &"custom_button_hover"]:
		theme.set_stylebox(state, &"Tree", hover)
	theme.set_stylebox(&"selected", &"Tree", selected)
	theme.set_stylebox(&"selected_focus", &"Tree", styles.focus)
	theme.set_stylebox(&"hovered_selected", &"Tree", hovered_selected)
	theme.set_stylebox(&"hovered_selected_focus", &"Tree", styles.focus)
	theme.set_stylebox(&"cursor", &"Tree", cursor)
	theme.set_stylebox(&"cursor_unfocused", &"Tree", cursor)
	for state: StringName in [
		&"title_button_normal", &"title_button_hover", &"title_button_pressed"
	]:
		theme.set_stylebox(state, &"Tree", title_button)
	theme.set_color(&"custom_button_font_highlight", &"Tree", palette.font_hover_color)
	theme.set_color(&"font_color", &"Tree", palette.font_color)
	theme.set_color(&"font_hovered_color", &"Tree", palette.font_hover_color)
	theme.set_color(&"font_hovered_dimmed_color", &"Tree", palette.font_hover_color)
	theme.set_color(&"font_hovered_selected_color", &"Tree", palette.mono_color_font)
	theme.set_color(&"font_selected_color", &"Tree", palette.mono_color_font)
	theme.set_color(&"font_disabled_color", &"Tree", palette.font_disabled_color)
	theme.set_color(&"font_outline_color", &"Tree", palette.font_outline_color)
	theme.set_color(&"title_button_color", &"Tree", palette.font_color)
	theme.set_color(&"guide_color", &"Tree", Color.TRANSPARENT)
	theme.set_color(&"drop_on_item_color", &"Tree", palette.accent_color)
	theme.set_color(&"drop_position_color", &"Tree", palette.icon_normal_color)
	var increased_margin := BASE_MARGIN + extra_spacing * 0.75
	theme.set_constant(&"v_separation", &"Tree", roundi(pow(BASE_MARGIN * 0.175 * palette.scale, 3)))
	theme.set_constant(&"h_separation", &"Tree", roundi((increased_margin + 2.0) * palette.scale))
	theme.set_constant(&"item_margin", &"Tree", roundi(maxf(3.0 * increased_margin, 12.0) * palette.scale))
	for side_name: StringName in [
		&"inner_item_margin_top", &"inner_item_margin_bottom"
	]:
		theme.set_constant(side_name, &"Tree", roundi(BASE_MARGIN * 0.75 * palette.scale))
	for side_name: StringName in [
		&"inner_item_margin_left", &"inner_item_margin_right", &"button_margin"
	]:
		theme.set_constant(side_name, &"Tree", roundi(BASE_MARGIN * palette.scale))
	theme.set_constant(&"icon_h_separation", &"Tree", roundi(BASE_MARGIN * 1.5 * palette.scale))
	theme.set_constant(&"check_h_separation", &"Tree", roundi(BASE_MARGIN * 1.5 * palette.scale))
	theme.set_constant(&"outline_size", &"Tree", 0)
	theme.set_constant(&"draw_guides", &"Tree", 0)

	var item_panel: StyleBoxFlat = styles.base.duplicate()
	item_panel.set_content_margin_all(BASE_MARGIN * 2.0 * palette.scale)
	theme.set_stylebox(&"panel", &"ItemList", item_panel)
	theme.set_stylebox(&"focus", &"ItemList", styles.focus)
	theme.set_stylebox(&"cursor", &"ItemList", cursor)
	theme.set_stylebox(&"cursor_unfocused", &"ItemList", cursor)
	theme.set_stylebox(&"selected", &"ItemList", styles.flat_button_pressed)
	theme.set_stylebox(&"selected_focus", &"ItemList", styles.focus)
	theme.set_stylebox(&"hovered", &"ItemList", styles.flat_button_hover)
	theme.set_stylebox(&"hovered_selected", &"ItemList", styles.flat_button_hover_pressed)
	theme.set_stylebox(&"hovered_selected_focus", &"ItemList", styles.focus)
	theme.set_color(&"font_color", &"ItemList", palette.font_color)
	theme.set_color(&"font_hovered_color", &"ItemList", palette.font_hover_color)
	theme.set_color(&"font_hovered_selected_color", &"ItemList", palette.font_hover_pressed_color)
	theme.set_color(&"font_selected_color", &"ItemList", palette.font_pressed_color)
	theme.set_color(&"font_outline_color", &"ItemList", palette.font_outline_color)
	theme.set_color(&"guide_color", &"ItemList", Color.TRANSPARENT)
	theme.set_constant(&"v_separation", &"ItemList", roundi(BASE_MARGIN * 1.5 * palette.scale))
	theme.set_constant(&"h_separation", &"ItemList", roundi((increased_margin + 2.0) * palette.scale))
	theme.set_constant(&"icon_margin", &"ItemList", roundi((increased_margin + 2.0) * palette.scale))
	theme.set_constant(&"line_separation", &"ItemList", roundi(BASE_MARGIN * palette.scale))
	theme.set_constant(&"outline_size", &"ItemList", 0)


static func _apply_tabs(theme: Theme, palette: Palette, styles: Styles) -> void:
	var is_rtl := _is_layout_rtl()
	var selected: StyleBoxFlat = styles.base.duplicate()
	_set_margins(
		selected,
		BASE_MARGIN * 4.0 * palette.scale,
		BASE_MARGIN * 2.1 * palette.scale,
		BASE_MARGIN * 4.0 * palette.scale,
		BASE_MARGIN * 2.1 * palette.scale
	)
	_set_corners(
		selected,
		roundi(palette.corner_radius * palette.scale),
		roundi(palette.corner_radius * palette.scale), 0, 0
	)
	var unselected: StyleBoxFlat = selected.duplicate()
	unselected.bg_color = palette.surface_lowest_color
	unselected.set_border_width_all(0)
	var hovered: StyleBoxFlat = unselected.duplicate()
	hovered.bg_color = palette.surface_base_color * Color(1, 1, 1, 0.6)
	var tabbar_background: StyleBoxFlat = styles.base.duplicate()
	tabbar_background.bg_color = palette.surface_lowest_color
	tabbar_background.set_corner_radius(CORNER_BOTTOM_LEFT, 0)
	tabbar_background.set_corner_radius(CORNER_BOTTOM_RIGHT, 0)
	_set_margins(tabbar_background, 0, 0, BASE_MARGIN * 0.25 * palette.scale, 0)

	# The Hub's main tabs are hidden and meet the sidebar, so keep the inner edge flush.
	var content: StyleBoxFlat = styles.tab_container.duplicate()
	content.set_corner_radius(CORNER_TOP_RIGHT if is_rtl else CORNER_TOP_LEFT, 0)
	content.set_corner_radius(CORNER_BOTTOM_RIGHT if is_rtl else CORNER_BOTTOM_LEFT, 0)
	for type_name: StringName in [&"TabContainer", &"TabBar"]:
		theme.set_stylebox(&"tab_selected", type_name, selected)
		theme.set_stylebox(&"tab_hovered", type_name, hovered)
		theme.set_stylebox(&"tab_unselected", type_name, unselected)
		theme.set_stylebox(&"tab_disabled", type_name, unselected)
		theme.set_stylebox(&"tab_focus", type_name, styles.focus)
		theme.set_color(&"font_selected_color", type_name, palette.font_color)
		theme.set_color(&"font_hovered_color", type_name, palette.font_hover_color)
		theme.set_color(&"font_unselected_color", type_name, palette.font_secondary_color)
		theme.set_color(&"font_disabled_color", type_name, palette.font_disabled_color * Color(1, 1, 1, 0.55))
		theme.set_color(&"font_outline_color", type_name, palette.font_outline_color)
		theme.set_color(&"icon_selected_color", type_name, palette.icon_normal_color)
		theme.set_color(&"icon_hovered_color", type_name, palette.icon_hover_color)
		theme.set_color(&"icon_unselected_color", type_name, palette.icon_secondary_color)
		theme.set_color(&"icon_disabled_color", type_name, palette.icon_disabled_color * Color(1, 1, 1, 0.55))
		theme.set_color(&"drop_mark_color", type_name, palette.dark_color_2.lerp(palette.accent_color, 0.75))
	theme.set_stylebox(&"tabbar_background", &"TabContainer", tabbar_background)
	theme.set_stylebox(&"panel", &"TabContainer", content)
	theme.set_stylebox(&"button_pressed", &"TabBar", styles.panel_container)
	theme.set_stylebox(&"button_highlight", &"TabBar", styles.panel_container)
	theme.set_constant(&"side_margin", &"TabContainer", 0)
	theme.set_constant(&"outline_size", &"TabContainer", 0)
	theme.set_constant(&"h_separation", &"TabBar", roundi(4.0 * palette.scale))
	theme.set_constant(&"outline_size", &"TabBar", 0)


static func _apply_text_inputs(theme: Theme, palette: Palette, styles: Styles) -> void:
	var input: StyleBoxFlat = styles.base.duplicate()
	input.bg_color = palette.surface_lower_color
	_set_margins(
		input,
		BASE_MARGIN * 2.0 * palette.scale,
		(BASE_MARGIN * 0.75 + 1.0) * palette.scale,
		BASE_MARGIN * 2.0 * palette.scale,
		(BASE_MARGIN * 0.75 + 1.0) * palette.scale
	)
	if palette.draw_extra_borders:
		input.set_border_width_all(maxi(1, roundi(palette.scale)))
		input.border_color = palette.extra_border_color_1
	var readonly: StyleBoxFlat = input.duplicate()
	readonly.bg_color = Color(0, 0, 0, 0.2) if palette.dark_theme else Color(1, 1, 1, 0.5)

	for type_name: StringName in [&"LineEdit", &"TextEdit"]:
		theme.set_stylebox(&"normal", type_name, input)
		theme.set_stylebox(&"focus", type_name, styles.focus)
		theme.set_stylebox(&"read_only", type_name, readonly)
		theme.set_color(&"font_color", type_name, palette.font_color)
		theme.set_color(&"font_placeholder_color", type_name, palette.font_placeholder_color)
		theme.set_color(&"font_outline_color", type_name, palette.font_outline_color)
		theme.set_color(&"caret_color", type_name, palette.font_color)
		theme.set_color(&"selection_color", type_name, palette.selection_color)
		theme.set_constant(&"outline_size", type_name, 0)
		theme.set_constant(&"caret_width", type_name, 1)
	theme.set_color(&"font_selected_color", &"LineEdit", palette.font_pressed_color)
	theme.set_color(&"font_uneditable_color", &"LineEdit", palette.font_readonly_color)
	theme.set_color(&"clear_button_color", &"LineEdit", palette.font_color)
	theme.set_color(&"clear_button_color_pressed", &"LineEdit", palette.accent_color)
	theme.set_color(&"font_readonly_color", &"TextEdit", palette.font_readonly_color)
	theme.set_color(&"background_color", &"TextEdit", Color.TRANSPARENT)
	theme.set_constant(&"line_spacing", &"TextEdit", roundi(4.0 * palette.scale))

	# Split the legacy combined texture into Godot 4.7's separate arrow buttons.
	var empty_icon := ImageTexture.new()
	var combined_icon := theme.get_icon(&"GuiSpinboxUpdown", &"EditorIcons")
	var combined_size := combined_icon.get_size()
	var up_icon := AtlasTexture.new()
	up_icon.atlas = combined_icon
	up_icon.region = Rect2(Vector2.ZERO, Vector2(combined_size.x, combined_size.y / 2.0))
	var down_icon := AtlasTexture.new()
	down_icon.atlas = combined_icon
	down_icon.region = Rect2(
		0, combined_size.y / 2.0, combined_size.x, combined_size.y / 2.0
	)
	theme.set_icon(&"updown", &"SpinBox", empty_icon)
	theme.set_icon(&"updown_disabled", &"SpinBox", empty_icon)
	for state: StringName in [&"up", &"up_hover", &"up_pressed", &"up_disabled"]:
		theme.set_icon(state, &"SpinBox", up_icon)
	for state: StringName in [&"down", &"down_hover", &"down_pressed", &"down_disabled"]:
		theme.set_icon(state, &"SpinBox", down_icon)
	for state: StringName in [
		&"up_background", &"down_background",
		&"up_background_disabled", &"down_background_disabled"
	]:
		theme.set_stylebox(state, &"SpinBox", styles.empty)
	for state: StringName in [&"up_background_hovered", &"down_background_hovered"]:
		theme.set_stylebox(state, &"SpinBox", styles.button_hover)
	for state: StringName in [&"up_background_pressed", &"down_background_pressed"]:
		theme.set_stylebox(state, &"SpinBox", styles.button_pressed)
	theme.set_color(&"up_icon_modulate", &"SpinBox", palette.icon_normal_color)
	theme.set_color(&"up_hover_icon_modulate", &"SpinBox", palette.icon_hover_color)
	theme.set_color(&"up_pressed_icon_modulate", &"SpinBox", palette.icon_pressed_color)
	theme.set_color(&"up_disabled_icon_modulate", &"SpinBox", palette.icon_disabled_color)
	theme.set_color(&"down_icon_modulate", &"SpinBox", palette.icon_normal_color)
	theme.set_color(&"down_hover_icon_modulate", &"SpinBox", palette.icon_hover_color)
	theme.set_color(&"down_pressed_icon_modulate", &"SpinBox", palette.icon_pressed_color)
	theme.set_color(&"down_disabled_icon_modulate", &"SpinBox", palette.icon_disabled_color)
	theme.set_stylebox(&"field_and_buttons_separator", &"SpinBox", styles.empty)
	theme.set_stylebox(&"up_down_buttons_separator", &"SpinBox", styles.empty)
	theme.set_constant(&"buttons_vertical_separation", &"SpinBox", 0)
	theme.set_constant(&"field_and_buttons_separation", &"SpinBox", 2)
	theme.set_constant(&"buttons_width", &"SpinBox", 16)
	theme.set_constant(&"set_min_buttons_width_from_icons", &"SpinBox", 1)


static func _apply_popup_menu(theme: Theme, palette: Palette, styles: Styles) -> void:
	var popup: StyleBoxFlat = styles.base.duplicate()
	popup.bg_color = palette.surface_popup_color
	popup.set_content_margin_all(BASE_MARGIN * 2.4 * palette.scale)
	popup.set_corner_radius_all(0)
	if palette.draw_extra_borders:
		popup.set_border_width_all(maxi(1, roundi(palette.scale)))
		popup.border_color = palette.extra_border_color_2
	var hover: StyleBoxFlat = styles.flat_button_hover.duplicate()
	hover.bg_color = _get_base_color(palette.base_color, palette.contrast, -0.5, 0.75)
	var separator := _line(
		palette.mono_color * Color(1, 1, 1, 0.075 if palette.dark_theme else 0.125),
		maxi(1, roundi(2.0 * palette.scale)),
		-BASE_MARGIN * 2.0 * palette.scale,
		-BASE_MARGIN * 2.0 * palette.scale
	)
	theme.set_stylebox(&"panel", &"PopupMenu", popup)
	theme.set_stylebox(&"hover", &"PopupMenu", hover)
	for state: StringName in [&"separator", &"labeled_separator_left", &"labeled_separator_right"]:
		theme.set_stylebox(state, &"PopupMenu", separator)
	theme.set_color(&"font_color", &"PopupMenu", palette.font_color)
	theme.set_color(&"font_hover_color", &"PopupMenu", palette.font_hover_color)
	theme.set_color(&"font_accelerator_color", &"PopupMenu", palette.font_disabled_color)
	theme.set_color(&"font_disabled_color", &"PopupMenu", palette.font_disabled_color)
	theme.set_color(&"font_separator_color", &"PopupMenu", palette.font_disabled_color)
	theme.set_color(&"font_outline_color", &"PopupMenu", palette.font_outline_color)
	theme.set_constant(&"h_separation", &"PopupMenu", roundi(BASE_MARGIN * 1.75 * palette.scale))
	theme.set_constant(&"v_separation", &"PopupMenu", roundi(BASE_MARGIN * 1.75 * palette.scale))
	theme.set_constant(&"outline_size", &"PopupMenu", 0)
	theme.set_constant(&"item_start_padding", &"PopupMenu", roundi(BASE_MARGIN * 2.4 * palette.scale))
	theme.set_constant(&"item_end_padding", &"PopupMenu", roundi(BASE_MARGIN * 2.4 * palette.scale))
static func _apply_scrollbars_and_sliders(theme: Theme, palette: Palette, styles: Styles) -> void:
	var grabber: StyleBoxFlat = styles.base.duplicate()
	grabber.bg_color = palette.mono_color * Color(1, 1, 1, 0.225)
	var grabber_highlight: StyleBoxFlat = styles.base.duplicate()
	grabber_highlight.bg_color = palette.mono_color * Color(1, 1, 1, 0.5)
	var empty_icon := ImageTexture.new()
	var scroll_margin := 3.0 * palette.scale
	var h_scroll := _empty(0, scroll_margin / palette.scale, 0, scroll_margin / palette.scale, palette.scale)
	var v_scroll := _empty(scroll_margin / palette.scale, 0, scroll_margin / palette.scale, 0, palette.scale)
	for type_name: StringName in [&"HScrollBar", &"VScrollBar"]:
		theme.set_stylebox(&"scroll", type_name, h_scroll if type_name == &"HScrollBar" else v_scroll)
		theme.set_stylebox(&"scroll_focus", type_name, styles.focus)
		theme.set_stylebox(&"grabber", type_name, grabber)
		theme.set_stylebox(&"grabber_highlight", type_name, grabber_highlight)
		theme.set_stylebox(&"grabber_pressed", type_name, grabber_highlight)
		for icon_name: StringName in [
			&"increment", &"increment_highlight", &"increment_pressed",
			&"decrement", &"decrement_highlight", &"decrement_pressed"
		]:
			theme.set_icon(icon_name, type_name, empty_icon)

	var h_slider: StyleBoxFlat = styles.base.duplicate()
	h_slider.bg_color = palette.mono_color_inv * Color(1, 1, 1, 0.35)
	_set_margins(h_slider, 0, 2.0 * palette.scale, 0, 2.0 * palette.scale)
	var h_fill := _flat(
		palette.contrast_color_1, 0, 2, 0, 2, palette.corner_radius, palette.scale
	)
	theme.set_stylebox(&"slider", &"HSlider", h_slider)
	theme.set_stylebox(&"grabber_area", &"HSlider", h_fill)
	theme.set_stylebox(&"grabber_area_highlight", &"HSlider", h_fill)
	theme.set_constant(&"center_grabber", &"HSlider", 0)
	theme.set_constant(&"grabber_offset", &"HSlider", 0)

	var v_slider: StyleBoxFlat = h_slider.duplicate()
	_set_margins(v_slider, 2.0 * palette.scale, 0, 2.0 * palette.scale, 0)
	var v_fill := _flat(
		palette.contrast_color_1, 2, 0, 2, 0, palette.corner_radius, palette.scale
	)
	theme.set_stylebox(&"slider", &"VSlider", v_slider)
	theme.set_stylebox(&"grabber_area", &"VSlider", v_fill)
	theme.set_stylebox(&"grabber_area_highlight", &"VSlider", v_fill)
	theme.set_constant(&"center_grabber", &"VSlider", 0)
	theme.set_constant(&"grabber_offset", &"VSlider", 0)


static func _apply_labels_and_progress(theme: Theme, palette: Palette, styles: Styles) -> void:
	var label := _empty(8, 4, 8, 4, palette.scale)
	theme.set_stylebox(&"normal", &"Label", label)
	theme.set_stylebox(&"focus", &"Label", styles.focus)
	theme.set_color(&"font_color", &"Label", palette.font_color)
	theme.set_color(&"font_shadow_color", &"Label", Color.TRANSPARENT)
	theme.set_color(&"font_outline_color", &"Label", palette.font_outline_color)
	theme.set_constant(&"line_spacing", &"Label", roundi(3.0 * palette.scale))
	theme.set_constant(&"outline_size", &"Label", 0)

	var rich_text: StyleBoxFlat = styles.base.duplicate()
	rich_text.bg_color = palette.surface_low_color
	rich_text.set_content_margin_all(BASE_MARGIN * 2.0 * palette.scale)
	theme.set_stylebox(&"normal", &"RichTextLabel", rich_text)
	theme.set_stylebox(&"focus", &"RichTextLabel", styles.empty)
	theme.set_color(&"default_color", &"RichTextLabel", palette.font_color)
	theme.set_color(&"font_shadow_color", &"RichTextLabel", Color.TRANSPARENT)
	theme.set_color(&"font_outline_color", &"RichTextLabel", palette.font_outline_color)
	theme.set_color(&"selection_color", &"RichTextLabel", palette.selection_color)
	theme.set_constant(&"outline_size", &"RichTextLabel", 0)

	var progress: StyleBoxFlat = styles.base.duplicate()
	progress.bg_color = palette.surface_lowest_color
	progress.set_expand_margin(SIDE_TOP, BASE_MARGIN * 0.5 * palette.scale)
	progress.set_expand_margin(SIDE_BOTTOM, BASE_MARGIN * 0.5 * palette.scale)
	progress.set_content_margin_all(BASE_MARGIN * palette.scale)
	var fill: StyleBoxFlat = progress.duplicate()
	fill.bg_color = palette.button_normal_color
	if palette.draw_extra_borders:
		progress.set_border_width_all(maxi(1, roundi(palette.scale)))
		progress.border_color = palette.extra_border_color_2
		fill.border_color = palette.extra_border_color_1
	theme.set_stylebox(&"background", &"ProgressBar", progress)
	theme.set_stylebox(&"fill", &"ProgressBar", fill)
	theme.set_color(&"font_color", &"ProgressBar", palette.font_color)
	theme.set_color(&"font_outline_color", &"ProgressBar", palette.font_outline_color)
	theme.set_constant(&"outline_size", &"ProgressBar", 0)


static func _apply_containers(theme: Theme, palette: Palette, extra_spacing: float) -> void:
	var separation := roundi((BASE_MARGIN + extra_spacing * 0.5) * palette.scale)
	for type_name: StringName in [&"BoxContainer", &"HBoxContainer", &"VBoxContainer"]:
		theme.set_constant(&"separation", type_name, separation)
	for type_name: StringName in [&"GridContainer", &"FlowContainer", &"HFlowContainer", &"VFlowContainer"]:
		theme.set_constant(&"h_separation", type_name, separation)
		theme.set_constant(&"v_separation", type_name, separation)
	var separator := _line(
		palette.separator_color,
		maxi(1, roundi(2.0 * palette.scale)),
		-BASE_MARGIN * palette.scale,
		-BASE_MARGIN * palette.scale
	)
	theme.set_stylebox(&"separator", &"HSeparator", separator)
	var vertical_separator: StyleBoxLine = separator.duplicate()
	vertical_separator.vertical = true
	theme.set_stylebox(&"separator", &"VSeparator", vertical_separator)
	theme.set_constant(&"separation", &"Separator", roundi(BASE_MARGIN * 2.0 * palette.scale))


static func _apply_hub_styles(theme: Theme, palette: Palette, styles: Styles) -> void:
	var is_rtl := _is_layout_rtl()
	var inner_side := SIDE_LEFT if is_rtl else SIDE_RIGHT
	var outer_side := SIDE_RIGHT if is_rtl else SIDE_LEFT
	var inner_top_corner := CORNER_TOP_LEFT if is_rtl else CORNER_TOP_RIGHT
	var inner_bottom_corner := CORNER_BOTTOM_LEFT if is_rtl else CORNER_BOTTOM_RIGHT
	var sidebar: StyleBoxFlat = styles.base.duplicate()
	sidebar.bg_color = palette.surface_lower_color
	sidebar.set_content_margin_all(0)
	sidebar.set_corner_radius(inner_top_corner, 0)
	sidebar.set_corner_radius(inner_bottom_corner, 0)
	sidebar.set_border_width(inner_side, maxi(1, roundi(palette.scale)))
	sidebar.border_color = palette.surface_lower_color.lerp(palette.surface_lowest_color, 0.6)
	theme.set_stylebox(&"SidebarPanel", &"EditorStyles", sidebar)

	theme.set_type_variation(&"SidebarNavButton", &"Button")
	var nav_normal := _flat(Color.TRANSPARENT, 12, 8, 12, 8, palette.corner_radius, palette.scale)
	var nav_hover: StyleBoxFlat = nav_normal.duplicate()
	nav_hover.bg_color = palette.flat_button_hover_color
	var nav_pressed: StyleBoxFlat = nav_normal.duplicate()
	nav_pressed.bg_color = palette.accent_color * Color(1, 1, 1, 0.16)
	nav_pressed.set_border_width(outer_side, maxi(2, roundi(3.0 * palette.scale)))
	nav_pressed.border_color = palette.accent_color
	for type_name: StringName in [&"SidebarNavButton", &"SidebarBottomButton"]:
		theme.set_stylebox(&"normal", type_name, nav_normal)
		theme.set_stylebox(&"hover", type_name, nav_hover)
		theme.set_stylebox(&"pressed", type_name, nav_pressed if type_name == &"SidebarNavButton" else nav_hover)
		theme.set_stylebox(&"hover_pressed", type_name, nav_pressed if type_name == &"SidebarNavButton" else nav_hover)
		theme.set_stylebox(&"focus", type_name, styles.empty)
		theme.set_stylebox(&"disabled", type_name, nav_normal)
		theme.set_color(&"font_color", type_name, palette.font_color)
		theme.set_color(&"font_hover_color", type_name, palette.font_hover_color)
		theme.set_color(&"font_pressed_color", type_name, palette.accent_color)
		theme.set_color(&"font_focus_color", type_name, palette.font_focus_color)
		theme.set_color(&"font_disabled_color", type_name, palette.font_disabled_color)
		theme.set_color(&"icon_normal_color", type_name, palette.icon_secondary_color)
		theme.set_color(&"icon_hover_color", type_name, palette.icon_hover_color)
		theme.set_color(&"icon_pressed_color", type_name, palette.accent_color)
		theme.set_constant(&"h_separation", type_name, roundi(8.0 * palette.scale))

	# Existing project tag controls use this Hub-specific variation name.
	theme.set_type_variation(&"ProjectTag", &"Button")
	for state: StringName in [&"normal", &"hover", &"pressed"]:
		var tag: StyleBoxFlat
		match state:
			&"hover": tag = styles.button_hover.duplicate() as StyleBoxFlat
			&"pressed": tag = styles.button_pressed.duplicate() as StyleBoxFlat
			_: tag = styles.button.duplicate() as StyleBoxFlat
		tag.set_border_width_all(0)
		tag.set_corner_radius(CORNER_TOP_RIGHT if is_rtl else CORNER_TOP_LEFT, 0)
		tag.set_corner_radius(CORNER_BOTTOM_RIGHT if is_rtl else CORNER_BOTTOM_LEFT, 0)
		theme.set_stylebox(state, &"ProjectTag", tag)

	var asset_panel: StyleBoxFlat = styles.base.duplicate()
	asset_panel.bg_color = palette.surface_base_color
	theme.set_stylebox(&"bg", &"AssetLib", styles.empty)
	theme.set_stylebox(&"panel", &"AssetLib", asset_panel)


static func _flat(
	color: Color,
	left := -1.0,
	top := -1.0,
	right := -1.0,
	bottom := -1.0,
	radius := 0.0,
	scale := 1.0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	_set_margins(style, left * scale, top * scale, right * scale, bottom * scale)
	style.set_corner_radius_all(roundi(radius * scale))
	style.corner_detail = ceili(0.8 * radius * scale)
	return style


static func _is_layout_rtl() -> bool:
	return TextServerManager.get_primary_interface().is_locale_right_to_left(
		TranslationServer.get_locale()
	)


static func _empty(
	left := -1.0,
	top := -1.0,
	right := -1.0,
	bottom := -1.0,
	scale := 1.0
) -> StyleBoxEmpty:
	var style := StyleBoxEmpty.new()
	_set_margins(style, left * scale, top * scale, right * scale, bottom * scale)
	return style


static func _set_margins(
	style: StyleBox, left: float, top: float, right: float, bottom: float
) -> void:
	style.content_margin_left = left
	style.content_margin_top = top
	style.content_margin_right = right
	style.content_margin_bottom = bottom


static func _set_corners(
	style: StyleBoxFlat, top_left: int, top_right: int, bottom_right: int, bottom_left: int
) -> void:
	style.corner_radius_top_left = top_left
	style.corner_radius_top_right = top_right
	style.corner_radius_bottom_right = bottom_right
	style.corner_radius_bottom_left = bottom_left


static func _line(
	color: Color,
	thickness := 1,
	grow_begin := 1.0,
	grow_end := 1.0,
	vertical := false
) -> StyleBoxLine:
	var style := StyleBoxLine.new()
	style.color = color
	style.thickness = thickness
	style.grow_begin = grow_begin
	style.grow_end = grow_end
	style.vertical = vertical
	return style
