class_name ThemeCorners
extends RefCounted
## The corner radius of the Hub theme, for styles made in code.
##
## Godot's editor theme squares dialogs and popups, which are OS windows there; panels,
## rows and badges drawn inside the Hub window round their corners like its buttons
## and panels instead. The radius comes from the theme (the Modern style's corner
## radius setting, or the Classic one's), never a fixed number.


## Height before EDSCALE of the thin progress bars of the Installs page, see
## [method style_thin_progress_bar].
const THIN_PROGRESS_HEIGHT := 4.0


## The theme's corner radius in pixels (scale included) for [param control]: that of its
## buttons, or of its trees when buttons are not drawn with flat styles, else 0.
static func radius(control: Control) -> int:
	var flat := _themed_flat(control)
	return flat.corner_radius_top_left if flat != null else 0


## Rounds every corner of [param style] by [param corner_radius] pixels, as smooth as
## the theme draws its own corners.
static func apply(style: StyleBoxFlat, corner_radius: int) -> void:
	style.set_corner_radius_all(corner_radius)
	style.corner_detail = maxi(1, ceili(0.8 * corner_radius))


## A copy of [param style] with the theme's corners for [param control], or
## [param style] itself when it is not a [StyleBoxFlat] (a custom theme's texture).
static func rounded(style: StyleBox, control: Control) -> StyleBox:
	var flat := style as StyleBoxFlat
	if flat == null:
		return style
	var copy := flat.duplicate() as StyleBoxFlat
	apply(copy, radius(control))
	return copy


## A new [StyleBoxFlat] with the theme's corners for [param control], anti-aliased only
## when the theme's own flat styles are: the Classic style draws them without.
static func new_flat(control: Control) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	apply(style, radius(control))
	var themed := _themed_flat(control)
	if themed != null:
		style.anti_aliasing = themed.anti_aliasing
	return style


## Makes [param bar] a thin bar in the theme's ProgressBar look for [param control], as
## the Installs page draws downloads and export templates jobs: flat styles rounded
## like the theme, without the margins that make the bar taller. A textured style, as
## in the Classic style, keeps its look, as tall as its texture's edges.
static func style_thin_progress_bar(bar: ProgressBar, control: Control) -> void:
	var height := THIN_PROGRESS_HEIGHT * Config.EDSCALE
	for style_name: String in ["background", "fill"]:
		bar.remove_theme_stylebox_override(style_name)
		var style := bar.get_theme_stylebox(style_name).duplicate() as StyleBox
		var flat := style as StyleBoxFlat
		if flat != null:
			apply(flat, radius(control))
			flat.expand_margin_top = 0
			flat.expand_margin_bottom = 0
		var textured := style as StyleBoxTexture
		if textured != null:
			# Shorter than its edges, the texture would only show its top edge: no fill.
			height = maxf(height, textured.texture_margin_top + textured.texture_margin_bottom)
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		bar.add_theme_stylebox_override(style_name, style)
	bar.custom_minimum_size.y = height
	# No room for it; the status text next to the bar says it instead.
	bar.show_percentage = false


## The theme's flat style the corners follow: the buttons', else the trees'.
static func _themed_flat(control: Control) -> StyleBoxFlat:
	var flat := control.get_theme_stylebox("normal", "Button") as StyleBoxFlat
	if flat == null:
		flat = control.get_theme_stylebox("panel", "Tree") as StyleBoxFlat
	return flat
