class_name EditorCatalogRow
extends MarginContainer
## One Godot build in the Install Editor modal's version list.
##
## Shows the build name with a Recommended, Latest 3.x or pre-release badge, its
## release date and release notes link, then an Install button, an Installed mark when
## a local editor already has this build, or a dimmed Not available when it is known
## to have no editor for this platform.


## Emitted when the Install button is pressed.
signal install_requested(entry: EditorCatalog.CatalogEntry)

## Row height before EDSCALE, the same for every row so lists line up. It is the
## height the name and date lines take with the editor Label margins.
const ROW_HEIGHT := 64.0
## Width before EDSCALE kept for the Install button or the Installed mark.
const ACTION_WIDTH := 96.0
## Width before EDSCALE of the Install button, the same in every row.
const INSTALL_WIDTH := 80.0
const ICON_SIZE := 32.0

var _entry: EditorCatalog.CatalogEntry
var _installed := false
## Why the build cannot be installed here, or empty.
var _unavailable_reason := ""
var _unavailable_text := ""
var _hovered := false
## The theme's hover highlight with the Hub's rounded corners.
var _hover_style: StyleBox

@onready var _icon: TextureRect = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _badge: PanelContainer = %Badge
@onready var _badge_label: Label = %BadgeLabel
@onready var _title_row: HBoxContainer = %TitleRow
@onready var _meta_row: HBoxContainer = %MetaRow
@onready var _date_label: Label = %DateLabel
@onready var _release_notes_button: LinkButton = %ReleaseNotesButton
@onready var _action_box: HBoxContainer = %ActionBox
@onready var _install_button: Button = %InstallButton
@onready var _installed_box: HBoxContainer = %InstalledBox
@onready var _installed_icon: TextureRect = %InstalledIcon
@onready var _installed_label: Label = %InstalledLabel
@onready var _unavailable_label: Label = %UnavailableLabel


func _ready() -> void:
	# Set before connecting theme_changed: overrides on self emit it.
	var margin_h := roundi(8 * Config.EDSCALE)
	var margin_v := roundi(4 * Config.EDSCALE)
	add_theme_constant_override("margin_left", margin_h)
	add_theme_constant_override("margin_right", margin_h)
	add_theme_constant_override("margin_top", margin_v)
	add_theme_constant_override("margin_bottom", margin_v)
	custom_minimum_size.y = ROW_HEIGHT * Config.EDSCALE

	_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE) * Config.EDSCALE
	_action_box.custom_minimum_size.x = ACTION_WIDTH * Config.EDSCALE
	_install_button.custom_minimum_size.x = INSTALL_WIDTH * Config.EDSCALE
	_install_button.text = tr("Install")
	_installed_label.text = tr("Installed")
	# Without the Label margin, "Installed" ends where the Install buttons do.
	_installed_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_unavailable_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_release_notes_button.text = tr("Release notes")

	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	_install_button.pressed.connect(func() -> void: install_requested.emit(_entry))
	_release_notes_button.pressed.connect(func() -> void:
		OS.shell_open(_entry.release_notes_url)
	)

	_update_theme()
	# Deferred: theme_changed comes before the cached theme items are dropped.
	theme_changed.connect(_update_theme, CONNECT_DEFERRED)
	if _entry != null:
		_update_view()


func _draw() -> void:
	# Hover and row separator the same way as the Installs list rows (the modern
	# theme hides guide_color there too).
	if _hovered:
		draw_style_box(_hover_style, Rect2(Vector2.ZERO, size))
	draw_line(
		Vector2(0, size.y - 1),
		Vector2(size.x, size.y - 1),
		get_theme_color("guide_color", "Tree")
	)


## Shows [param entry]. When [param installed] is true, an Installed mark takes the
## place of the Install button.
func init(entry: EditorCatalog.CatalogEntry, installed: bool) -> void:
	_entry = entry
	_installed = installed
	if is_node_ready():
		_update_view()


## Replaces the Install button with a dimmed [param label] (Not available when
## empty), with [param reason] as its tooltip. An empty reason brings the Install
## button back. Installed rows keep their Installed mark.
func set_unavailable_reason(reason: String, label := "") -> void:
	_unavailable_reason = reason
	_unavailable_text = label if not label.is_empty() else tr("Not available")
	if is_node_ready() and _entry != null:
		_update_view()


func get_entry() -> EditorCatalog.CatalogEntry:
	return _entry


func is_installed() -> bool:
	return _installed


## True when the row says Not available instead of offering Install.
func is_unavailable() -> bool:
	return not _installed and not _unavailable_reason.is_empty()


## The Install button, hidden when the build is installed or not available.
func get_install_button() -> Button:
	return _install_button


## Text of the badge next to the name, or empty for none.
static func badge_text(entry: EditorCatalog.CatalogEntry) -> String:
	if entry.recommended:
		return TranslationServer.translate("Recommended")
	if not entry.featured.is_empty():
		# The newest build of an older major that is still featured.
		return TranslationServer.translate("Latest %s.x") % entry.featured
	if entry.is_stable():
		return ""
	return entry.channel


func _update_view() -> void:
	_name_label.text = _entry.display_name
	var badge := badge_text(_entry)
	_badge_label.text = badge
	_badge.visible = not badge.is_empty()
	# Stays shown when empty: an empty label keeps the line height.
	_date_label.text = _entry.release_date
	_release_notes_button.visible = not _entry.release_notes_url.is_empty()
	_release_notes_button.tooltip_text = _entry.release_notes_url
	_install_button.visible = not _installed and not is_unavailable()
	_install_button.tooltip_text = tr("Choose a build of %s to download.") % _entry.display_name
	_installed_box.visible = _installed
	_unavailable_label.visible = is_unavailable()
	_unavailable_label.text = _unavailable_text
	_unavailable_label.tooltip_text = _unavailable_reason
	_update_badge_style()


func _update_theme() -> void:
	var dimmed := get_theme_color("readonly_font_color", "Editor")
	_date_label.add_theme_color_override("font_color", dimmed)
	_installed_label.add_theme_color_override("font_color", dimmed)
	_unavailable_label.add_theme_color_override("font_color", dimmed)
	_installed_icon.texture = get_theme_icon("StatusSuccess", "EditorIcons")
	var link_color := get_theme_color("accent_color", "Editor")
	_release_notes_button.add_theme_color_override("font_color", link_color)
	_release_notes_button.add_theme_color_override("font_hover_color", link_color)
	_release_notes_button.add_theme_color_override("font_pressed_color", link_color)
	_badge_label.add_theme_font_override("font", get_theme_font("bold", "EditorFonts"))
	_badge_label.add_theme_font_size_override(
		"font_size",
		get_theme_font_size("main_size", "EditorFonts") - roundi(2 * Config.EDSCALE)
	)
	# Rows without a date or release notes keep the height of the others.
	_meta_row.custom_minimum_size.y = _release_notes_button.get_combined_minimum_size().y
	_hover_style = ThemeCorners.rounded(get_theme_stylebox("hover", "Tree"), self)
	_update_badge_style()
	queue_redraw()


func _update_badge_style() -> void:
	if _entry == null:
		return
	# Recommended builds stand out, older featured majors stay neutral and
	# pre-releases get a warning tint.
	var color_name := "warning_color"
	if _entry.recommended:
		color_name = "accent_color"
	elif not _entry.featured.is_empty():
		color_name = "readonly_font_color"
	var color := get_theme_color(color_name, "Editor")
	var style := ThemeCorners.new_flat(self)
	style.bg_color = Color(color, 0.15)
	style.border_color = Color(color, 0.5)
	style.set_border_width_all(maxi(1, roundi(Config.EDSCALE)))
	style.content_margin_left = 6 * Config.EDSCALE
	style.content_margin_right = 6 * Config.EDSCALE
	style.content_margin_top = 1 * Config.EDSCALE
	style.content_margin_bottom = 1 * Config.EDSCALE
	_badge.add_theme_stylebox_override("panel", style)
	_badge_label.add_theme_color_override("font_color", color)
	# Rows without a badge keep the height of the others.
	_title_row.custom_minimum_size.y = _badge.get_combined_minimum_size().y


func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	queue_redraw()
