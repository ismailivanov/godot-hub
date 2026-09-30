extends Node


# Scenes instantiated and added at runtime. A root saved visible shows its Window as soon as
# add_child() runs, before popup_centered() positions it.
const RUNTIME_DIALOG_SCENES: Array[String] = [
	"res://src/components/editors/local/editor_item/rename_editor_dialog.tscn",
	"res://src/components/editors/local/editor_item/add_extra_arguments_editor_dialog.tscn",
	"res://src/components/editors/remote/remote_editor_direct_link/remote_editor_direct_link.tscn",
	"res://src/components/editors/remote/remote_editor_install/remote_editor_install.tscn",
]
const ASSET_DETAILS_SCENE := preload(
	"res://src/components/asset_lib_projects/asset_lib_item_details/asset_lib_item_details.tscn"
)
# Smaller than the asset details dialog's 1100x600 minimum.
const GAME_VIEW_SIZES: Array[Vector2i] = [Vector2i(900, 520), Vector2i(700, 400)]

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_runtime_dialog_scenes_start_hidden()
	for view_size in GAME_VIEW_SIZES:
		await _test_asset_details_fits_embedder(view_size)
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Embedded dialogs tests passed.")
	get_tree().quit()


func _test_runtime_dialog_scenes_start_hidden() -> void:
	for path in RUNTIME_DIALOG_SCENES:
		var scene := load(path) as PackedScene
		if scene == null:
			_check(false, "Could not load %s" % path)
			continue
		var dialog := scene.instantiate() as Window
		if dialog == null:
			_check(false, "Expected a Window root in %s" % path)
			continue
		_check(not dialog.visible, "Expected %s to be saved hidden" % path)
		dialog.free()


func _test_asset_details_fits_embedder(view_size: Vector2i) -> void:
	# This is what Config does when the Hub runs embedded in the editor.
	var root := get_tree().root
	root.gui_embed_subwindows = true
	root.size = view_size
	await _wait_frames(2)

	var dialog := ASSET_DETAILS_SCENE.instantiate() as AssetLibItemDetailsDialog
	dialog.init("", AssetLib.I.new(), RemoteImageSrc.I.new())
	add_child(dialog)
	var view := Rect2i(root.get_visible_rect())
	var title_bar := Vector2i(0, dialog.get_theme_constant("title_height", "Window"))
	# popup_centered() centers the current size. Headless clips popups to a zero-size screen,
	# which would hide an oversized dialog, so check the size it starts from as well.
	_check_fits(view, Rect2i(view.position, dialog.size + title_bar), "before popup")
	dialog.popup_centered()
	await _wait_frames(4)

	_check(dialog.is_embedded(), "Expected the asset details dialog to be embedded")
	_check_fits(view, Rect2i(dialog.position - title_bar, dialog.size + title_bar), "after popup")

	# Thumbnails arrive after the popup at a fixed height (see add_preview()).
	var thumbnail := Button.new()
	thumbnail.icon = ImageTexture.create_from_image(
		Image.create_empty(150, roundi(85 * Config.EDSCALE), false, Image.FORMAT_RGBA8)
	)
	(dialog.get_node("%PreviewsContainer") as HBoxContainer).add_child(thumbnail)
	await _wait_frames(4)
	_check_fits(
		view, Rect2i(dialog.position - title_bar, dialog.size + title_bar), "with a thumbnail"
	)
	dialog.free()


func _check_fits(view: Rect2i, frame: Rect2i, when: String) -> void:
	_check(
		view.encloses(frame),
		"Expected the asset details dialog %s %s to fit the game view %s" % [frame, when, view]
	)


func _wait_frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
