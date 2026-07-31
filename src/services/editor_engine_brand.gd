class_name EditorEngineBrand
extends RefCounted
## Detects Godot vs Redot editors and resolves list icons.


## Brand id for official Godot builds.
const GODOT := "godot"
## Brand id for Redot builds.
const REDOT := "redot"
## Raster Godot logo for editor list rows.
const _GODOT_LIST_ICON := preload("res://assets/Godot128x128.png")
## Raster Redot logo for editor list rows.
const _REDOT_LIST_ICON := preload("res://assets/Redot128x128.png")


## Resolves brand from a local editor item.
static func detect(item: LocalEditors.Item, use_binary: bool = true) -> String:
	var bin := ""
	if item.is_valid:
		bin = item.bin_path()
	return detect_from_fields(
		item.name,
		item.path,
		item.version_hint,
		bin,
		use_binary
	)


## Resolves brand from plain fields. Safe to call on worker threads.
static func detect_from_fields(
	editor_name: String,
	editor_path: String,
	version_hint: String,
	bin_path: String,
	use_binary: bool = true
) -> String:
	# Name and path win. Redot forks often still print Godot from version output.
	var from_meta := detect_from_metadata(editor_name, editor_path, version_hint)
	if from_meta == REDOT: return REDOT
	if use_binary and not bin_path.is_empty():
		var output_text := version_output_for_bin(bin_path)
		if output_text.findn("redot") >= 0: return REDOT
	return from_meta


## Resolves brand from name, path, and version hint only.
static func detect_from_metadata(editor_name: String, editor_path: String, version_hint: String) -> String:
	var lower := ("%s|%s|%s" % [editor_name, editor_path, version_hint]).to_lower()
	if lower.contains("redot") or lower.contains("rodot"): return REDOT
	return GODOT


## Runs the editor binary version flag and returns combined stdout.
static func version_output_for_bin(bin_path: String) -> String:
	if bin_path.is_empty() or not FileAccess.file_exists(bin_path): return ""
	var output: Array = []
	var exit_code := OS.execute(bin_path, ["--version"], output, true, false)
	if exit_code != 0: return ""
	var lines := PackedStringArray()
	for line: Variant in output:
		if line is String:
			lines.append(line as String)
	return "\n".join(lines)


## Returns the large list logo for the given brand.
static func list_icon_texture(brand: String) -> Texture2D:
	if brand == REDOT: return _REDOT_LIST_ICON
	return _GODOT_LIST_ICON


## Returns a theme icon for the brand, or the raster logo as fallback.
static func resolve_theme_icon(theme_source: Control, brand: String) -> Texture2D:
	var icon_name := monochrome_theme_icon_name(brand)
	if theme_source.has_theme_icon(icon_name, "EditorIcons"):
		var themed := theme_source.get_theme_icon(icon_name, "EditorIcons")
		if themed and themed.get_width() > 0: return themed
	return list_icon_texture(brand)


## Loads a custom list icon from disk, or falls back to the Godot logo.
static func load_list_icon_from_path(path: String) -> Texture2D:
	var global_path := ProjectSettings.globalize_path(path)
	if global_path.is_empty() or not FileAccess.file_exists(global_path):
		return list_icon_texture(GODOT)
	var image := Image.new()
	var err := image.load(global_path)
	if err != OK or image.is_empty(): return list_icon_texture(GODOT)
	image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


## Theme icon name used for compact monochrome editor buttons.
static func monochrome_theme_icon_name(brand: String) -> String:
	if brand == REDOT: return "RedotMonochrome"
	return "GodotMonochrome"


## Theme icon name used for full color editor logos.
static func full_theme_icon_name(brand: String) -> String:
	if brand == REDOT: return "Redot"
	return "Godot"
