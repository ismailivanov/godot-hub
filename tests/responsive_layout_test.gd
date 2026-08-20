extends Node


const THEME_SOURCE := preload("res://theme/theme.gd")
const PROJECTS_LIST_SCENE := preload(
	"res://src/components/projects/projects_list/projects_list.tscn"
)
const PROJECT_ITEM_SCENE := preload(
	"res://src/components/projects/project_item/project_item.tscn"
)
const EDITOR_ITEM_SCENE := preload(
	"res://src/components/editors/local/editor_item/editor_item.tscn"
)
const ASSET_LIBRARY_SCENE := preload(
	"res://src/components/asset_lib_projects/asset_lib_projects.tscn"
)
const WINDOW_BORDER_MARGIN := 8.0

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scale := float(args[0]) if not args.is_empty() else 1.0
	var use_rtl := args.size() > 1 and args[1] == "rtl"
	Config.edscale = scale
	THEME_SOURCE.set_scale(scale)

	var main_window := get_window()
	main_window.size = Vector2i(
		roundi(GuiMain.WINDOW_BASE_MIN_SIZE.x * scale),
		roundi(GuiMain.WINDOW_BASE_MIN_SIZE.y * scale)
	)

	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.layout_direction = (
		Control.LAYOUT_DIRECTION_RTL
		if use_rtl
		else Control.LAYOUT_DIRECTION_LTR
	)
	frame.theme = THEME_SOURCE.create_custom_theme(null)
	var border_margin := roundi(WINDOW_BORDER_MARGIN * scale)
	for side: StringName in [
		&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"
	]:
		frame.add_theme_constant_override(side, border_margin)
	main_window.add_child(frame)

	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override(&"separation", 0)
	frame.add_child(content_hbox)

	var sidebar := Control.new()
	sidebar.custom_minimum_size.x = 276.0 * scale
	content_hbox.add_child(sidebar)

	var projects_list := PROJECTS_LIST_SCENE.instantiate() as VBoxList
	projects_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	projects_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(projects_list.get_node("HBoxContainer2/VBoxContainer") as Control).hide()
	content_hbox.add_child(projects_list)
	_populate_toolbar(projects_list)

	var items_scroll := projects_list.get_node(
		"HBoxContainer2/ScrollContainer"
	) as ScrollContainer
	var items_container := items_scroll.get_node(
		"ItemsContainer"
	) as VBoxContainer
	var project_item := PROJECT_ITEM_SCENE.instantiate() as Control
	_populate_project_item(project_item)
	items_container.add_child(project_item)
	await _wait_frames(4)

	var toolbar := projects_list.get_node("HBoxContainer") as HFlowContainer
	var project_actions_scroll := project_item.get_node(
		"InfoVBox/TitleContainer/ActionsContainer/ScrollContainer"
	) as ScrollContainer
	var project_info_scroll := project_item.get_node(
		"InfoVBox/ScrollContainer"
	) as ScrollContainer
	var project_info_body := project_info_scroll.get_node("InfoBody") as Control
	var window_rect := Rect2(Vector2.ZERO, Vector2(main_window.size))

	_check(
		GuiMain.WINDOW_BASE_MIN_SIZE.x >= 700.0
		and GuiMain.WINDOW_BASE_MIN_SIZE.y >= 370.0,
		"The base window minimum must preserve the responsive layout budget"
	)
	_check(
		_rect_contains(window_rect, frame.get_global_rect()),
		"The application frame must remain inside the client area"
	)
	_check(
		content_hbox.get_combined_minimum_size().x <= content_hbox.size.x + 1.0,
		"Responsive content must fit the minimum window width at scale %s" % scale
	)
	_check(
		_rect_contains(frame.get_global_rect(), sidebar.get_global_rect()),
		"The sidebar must not be clipped at scale %s" % scale
	)
	_check(
		_rect_contains(frame.get_global_rect(), projects_list.get_global_rect()),
		"The projects area must not extend past the window at scale %s" % scale
	)

	var tallest_toolbar_child := _check_toolbar_children(toolbar)
	_check(
		toolbar.size.y > tallest_toolbar_child,
		"The toolbar should wrap at the minimum window width for scale %s" % scale
	)
	_check(
		_rect_contains(items_scroll.get_global_rect(), project_item.get_global_rect()),
		"Project rows must fit the list viewport at scale %s" % scale
	)
	_check(
		project_info_body.size.x <= project_info_scroll.size.x + 1.0,
		"Project metadata must fit without clipping a representative tag"
	)
	_check_action_scroller(project_actions_scroll, "project")
	_check(
		not project_item.has_node(
			"InfoVBox/ScrollContainer/InfoBody/Path/PathLabel/CustomMinimumSize"
		),
		"Project paths must be allowed to yield horizontal space"
	)

	var narrow_toolbar_height := toolbar.size.y
	main_window.size = Vector2i(
		roundi(1000.0 * scale),
		main_window.size.y
	)
	await _wait_frames(4)
	_check(
		toolbar.size.y < narrow_toolbar_height,
		"The toolbar should return to one row when the window grows"
	)
	_check(
		_rect_contains(
			Rect2(Vector2.ZERO, Vector2(main_window.size)),
			frame.get_global_rect()
		),
		"Resized content must remain inside the client area"
	)

	project_item.queue_free()
	await _wait_frames(2)
	main_window.size = Vector2i(
		roundi(GuiMain.WINDOW_BASE_MIN_SIZE.x * scale),
		roundi(GuiMain.WINDOW_BASE_MIN_SIZE.y * scale)
	)
	var editor_item := EDITOR_ITEM_SCENE.instantiate() as Control
	_populate_editor_item(editor_item)
	items_container.add_child(editor_item)
	await _wait_frames(4)
	var editor_actions_scroll := editor_item.get_node(
		"InfoVBox/Title/ActionsContainer/ScrollContainer"
	) as ScrollContainer
	_check(
		_rect_contains(items_scroll.get_global_rect(), editor_item.get_global_rect()),
		"Editor rows must fit the list viewport at scale %s" % scale
	)
	_check_action_scroller(editor_actions_scroll, "editor")
	_check(
		not editor_item.has_node(
			"InfoVBox/ScrollContainer/Path/PathLabel/CustomMinimumSize"
		),
		"Editor paths must be allowed to yield horizontal space"
	)

	projects_list.queue_free()
	await _wait_frames(2)
	var asset_library := ASSET_LIBRARY_SCENE.instantiate() as Control
	asset_library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(asset_library)
	_populate_asset_filters(asset_library)
	await _wait_frames(4)
	var asset_filters := asset_library.get_node(
		"Container/HBoxContainer"
	) as HFlowContainer
	_check(
		content_hbox.get_combined_minimum_size().x <= content_hbox.size.x + 1.0,
		"Asset Library filters must fit the minimum window width at scale %s" % scale
	)
	_check(
		_rect_contains(frame.get_global_rect(), asset_library.get_global_rect()),
		"The Asset Library must not extend past the window at scale %s" % scale
	)
	var tallest_asset_filter := _check_toolbar_children(asset_filters)
	_check(
		asset_filters.size.y > tallest_asset_filter,
		"Asset Library filters should wrap at the minimum window width"
	)

	frame.queue_free()
	await _wait_frames(3)
	if _failures == 0:
		print("Responsive layout tests passed at scale %s (%s)." % [
			scale,
			"RTL" if use_rtl else "LTR",
		])
	get_tree().quit(1 if _failures > 0 else 0)


func _populate_toolbar(projects_list: Control) -> void:
	var toolbar := projects_list.get_node("HBoxContainer") as HFlowContainer
	var tab_actions := toolbar.get_node("TabActions") as HBoxContainer
	for label: String in ["New", "Import", "Clone", "Scan"]:
		var button := Button.new()
		button.text = label
		tab_actions.add_child(button)
	for icon_name: StringName in [&"Clear", &"Reload", &"GuiTabMenuHl"]:
		var button := Button.new()
		button.icon = projects_list.get_theme_icon(icon_name, &"EditorIcons")
		toolbar.add_child(button)


func _populate_project_item(item: Control) -> void:
	(item.get_node("InfoVBox/TitleContainer/TitleLabel") as Label).text = (
		"The MAGNUS Directive With A Long Project Name"
	)
	(item.get_node(
		"InfoVBox/ScrollContainer/InfoBody/Editor/EditorPathLabel"
	) as Label).text = "Godot v4.7 stable"
	(item.get_node(
		"InfoVBox/ScrollContainer/InfoBody/Path/PathLabel"
	) as Label).text = "/Users/example/Documents/GitHub/Galactic-Guild"
	(item.get_node(
		"InfoVBox/ScrollContainer/InfoBody/Path/ProjectFeatures"
	) as Label).text = "4.7"
	_add_tag(
		item.get_node(
			"InfoVBox/ScrollContainer/InfoBody/Path/TagContainer"
		) as Container
	)
	_add_inline_actions(
		item.get_node(
			"InfoVBox/TitleContainer/ActionsContainer"
		) as HBoxContainer,
		item.get_node(
			"InfoVBox/TitleContainer/ActionsContainer/ScrollContainer/ActionsHBox"
		) as HBoxContainer
	)


func _populate_editor_item(item: Control) -> void:
	(item.get_node("InfoVBox/Title/TitleLabel") as Label).text = (
		"Godot 4.7 Stable With A Long Editor Name"
	)
	(item.get_node(
		"InfoVBox/ScrollContainer/Path/PathLabel"
	) as Label).text = "/Applications/Godot 4.7 Stable.app"
	(item.get_node(
		"InfoVBox/ScrollContainer/Path/EditorFeatures"
	) as Label).text = "Universal"
	_add_tag(
		item.get_node(
			"InfoVBox/ScrollContainer/Path/TagContainer"
		) as Container
	)
	_add_inline_actions(
		item.get_node("InfoVBox/Title/ActionsContainer") as HBoxContainer,
		item.get_node(
			"InfoVBox/Title/ActionsContainer/ScrollContainer/ActionsHBox"
		) as HBoxContainer
	)


func _populate_asset_filters(asset_library: Control) -> void:
	var samples := {
		"Container/HBoxContainer/VersionContainer/VersionOptionButton": "4.7",
		"Container/HBoxContainer/SortContainer/SortOptionButton": "Recently Updated",
		"Container/HBoxContainer/CategoryContainer/CategoryOptionButton": "Tools",
		"Container/HBoxContainer/SiteContainer/SiteOptionButton": "Godot Engine",
	}
	for path: String in samples:
		var option := asset_library.get_node(path) as OptionButton
		option.add_item(samples[path] as String)
		option.select(option.item_count - 1)


func _add_inline_actions(container: HBoxContainer, actions: HBoxContainer) -> void:
	for label: String in ["Edit", "Run", "Remove"]:
		var button := Button.new()
		button.text = label
		actions.add_child(button)
	var menu := MenuButton.new()
	menu.text = "⋮"
	container.add_child(menu)


func _add_tag(container: Container) -> void:
	var tag := Button.new()
	tag.text = "Actively Working On"
	container.add_child(tag)


func _check_toolbar_children(toolbar: HFlowContainer) -> float:
	var tallest_child := 0.0
	for node: Node in toolbar.get_children():
		if node is not Control or not (node as Control).visible:
			continue
		var child := node as Control
		tallest_child = maxf(tallest_child, child.size.y)
		_check(
			_rect_contains(toolbar.get_global_rect(), child.get_global_rect()),
			"Toolbar child %s must wrap inside the toolbar" % child.name
		)
	return tallest_child


func _check_action_scroller(scroller: ScrollContainer, item_type: String) -> void:
	_check(
		scroller.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
		"Inline %s actions must remain horizontally reachable" % item_type
	)
	_check(
		scroller.follow_focus,
		"Keyboard focus must reveal horizontally scrolled %s actions" % item_type
	)


func _wait_frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().process_frame


func _rect_contains(outer: Rect2, inner: Rect2) -> bool:
	const TOLERANCE := 1.0
	return (
		inner.position.x >= outer.position.x - TOLERANCE
		and inner.position.y >= outer.position.y - TOLERANCE
		and inner.end.x <= outer.end.x + TOLERANCE
		and inner.end.y <= outer.end.y + TOLERANCE
	)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
