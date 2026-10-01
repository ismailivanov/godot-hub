class_name EditorsVBoxList
extends VBoxList
## Editors inventory list with sort, search, and empty state.


## Emitted when an editor row is removed.
signal item_removed(item_data: LocalEditors.Item, remove_dir: bool)
## Emitted when an editor row is edited.
signal item_edited(item_data: LocalEditors.Item)
## Emitted when tag management is requested for a row.
signal item_manage_tags_requested(item_data: LocalEditors.Item)
## Emitted when a row's Export Templates action is pressed.
signal item_export_templates_requested(item_data: LocalEditors.Item)
## Emitted when the empty state install action is pressed.
signal install_editor_requested
## Emitted when the empty state stable download action is pressed.
signal recommended_stable_download_requested

var _empty_state_root: Control
var _empty_state_actions: Control
var _install_editor_button: Button
var _recommended_stable_button: Button


func _ready() -> void:
	super._ready()
	_setup_list_overlay_and_empty()


func refresh(data: Array) -> void:
	super.refresh(data)


func add(item_data: Object) -> void:
	super.add(item_data)


## Adds [param item_data] in sorted order, filtered like the other rows, and scrolls
## its row into view: a new install's row shows its export templates being installed.
func add_in_view(item_data: Object) -> void:
	add(item_data)
	var row := _items_container.get_child(_items_container.get_child_count() - 1) as Control
	sort_items()
	_update_filters()
	# The row is laid out on the next frame.
	await get_tree().process_frame
	if is_instance_valid(row) and row.visible:
		(%ScrollContainer as ScrollContainer).ensure_control_visible(row)


func set_recommended_stable_button_disabled(disabled: bool) -> void:
	if not _recommended_stable_button: return
	_recommended_stable_button.disabled = disabled


## Shows or hides the empty state's Install Editor and Download latest stable buttons.
func set_empty_state_actions_visible(actions_visible: bool) -> void:
	if not _empty_state_actions: return
	_empty_state_actions.visible = actions_visible


func _update_filters() -> void:
	super._update_filters()


func _setup_list_overlay_and_empty() -> void:
	var hb2 := $HBoxContainer2 as HBoxContainer
	var scroll := %ScrollContainer as ScrollContainer
	var wrapper := Control.new()
	wrapper.name = "ListMainArea"
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb2.add_child(wrapper)
	hb2.move_child(wrapper, 0)
	scroll.reparent(wrapper)
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 0
	scroll.offset_top = 0
	scroll.offset_right = 0
	scroll.offset_bottom = 0

	var empty_cc := CenterContainer.new()
	empty_cc.name = "LocalEditorsEmptyState"
	empty_cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	empty_cc.mouse_filter = Control.MOUSE_FILTER_STOP
	wrapper.add_child(empty_cc)
	_empty_state_root = empty_cc

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", roundi(8 * Config.EDSCALE))
	# Room for the hint on one or two lines.
	vbox.custom_minimum_size.x = 420.0 * Config.EDSCALE
	empty_cc.add_child(vbox)

	var icon := TextureRect.new()
	icon.texture = preload("res://assets/Godot128x128.svg")
	icon.custom_minimum_size = Vector2(64, 64) * Config.EDSCALE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1, 1, 1, 0.38)
	vbox.add_child(icon)

	var title := Label.new()
	title.theme_type_variation = "HeaderSmall"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = tr("No installs")
	vbox.add_child(title)

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = tr("To get started, install or locate a Godot editor.")
	vbox.add_child(hint)

	# Side by side at their own width, centered under the hint.
	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	actions.add_theme_constant_override("separation", roundi(8 * Config.EDSCALE))
	vbox.add_child(actions)
	_empty_state_actions = actions

	var btn := Button.new()
	btn.text = tr("Install Editor")
	btn.tooltip_text = tr("Choose a Godot version to download and install.")
	btn.pressed.connect(func() -> void: install_editor_requested.emit())
	actions.add_child(btn)
	_install_editor_button = btn

	var stable_btn := Button.new()
	stable_btn.text = tr("Download latest stable")
	stable_btn.tooltip_text = tr("Downloads the newest stable Godot build for this OS.")
	stable_btn.pressed.connect(func() -> void: recommended_stable_download_requested.emit())
	actions.add_child(stable_btn)
	_recommended_stable_button = stable_btn

	_update_empty_state_icons()
	theme_changed.connect(_update_empty_state_icons)
	apply_install_prompt_for_inventory_empty(true)


## The Install Editor button matches the header's; the direct download has its own icon.
func _update_empty_state_icons() -> void:
	_install_editor_button.icon = get_theme_icon("AssetLib", "EditorIcons")
	_recommended_stable_button.icon = get_theme_icon("Godot", "EditorIcons")


## Shows or hides the empty install prompt from inventory state.
func apply_install_prompt_for_inventory_empty(is_inventory_empty: bool) -> void:
	if not _empty_state_root: return
	var scroll := %ScrollContainer as ScrollContainer
	_empty_state_root.visible = is_inventory_empty
	scroll.visible = not is_inventory_empty


func _post_add(raw_item_data: Object, raw_item_control: Control) -> void:
	var item_data := raw_item_data as LocalEditors.Item
	var item_control := raw_item_control as EditorListItemControl
	item_control.removed.connect(
		func(remove_dir: bool) -> void:
			item_removed.emit(item_data, remove_dir)
	)
	item_control.edited.connect(
		func() -> void: item_edited.emit(item_data)
	)
	item_control.manage_tags_requested.connect(
		func() -> void: item_manage_tags_requested.emit(item_data)
	)
	item_control.export_templates_requested.connect(
		func() -> void: item_export_templates_requested.emit(item_data)
	)


func _item_comparator(a: Dictionary, b: Dictionary) -> bool:
	if a.favorite and not b.favorite: return true
	if b.favorite and not a.favorite: return false
	match _sort_option_button.selected:
		1: return str(a.path) < str(b.path)
		2: return str(a.tag_sort_string) < str(b.tag_sort_string)
		_: return (a.name as String).naturalcasecmp_to(b.name as String) > 0


func _fill_sort_options(btn: OptionButton) -> void:
	btn.add_item(tr("Name"))
	btn.add_item(tr("Path"))
	btn.add_item(tr("Tags"))
	var last_checked_sort := Cache.smart_value(self, "last_checked_sort", true)
	btn.select(last_checked_sort.ret(0) as int)
	btn.item_selected.connect(func(idx: int) -> void: last_checked_sort.put(idx))
