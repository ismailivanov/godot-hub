class_name EditorsVBoxList
extends VBoxList

signal item_removed(item_data: LocalEditors.Item, remove_dir: bool)
signal item_edited(item_data: LocalEditors.Item)
signal item_manage_tags_requested(item_data: LocalEditors.Item)
signal install_editor_requested
signal recommended_stable_download_requested

var _empty_state_root: Control
var _recommended_stable_button: Button


func _ready() -> void:
	super._ready()
	_setup_list_overlay_and_empty()


func refresh(data: Array) -> void:
	super.refresh(data)


func add(item_data: Object) -> void:
	super.add(item_data)


func set_recommended_stable_button_disabled(disabled: bool) -> void:
	if _recommended_stable_button != null:
		_recommended_stable_button.disabled = disabled


func _update_filters() -> void:
	super._update_filters()


func _setup_list_overlay_and_empty() -> void:
	var hb2 := $HBoxContainer2 as HBoxContainer
	var scroll := %ScrollContainer as ScrollContainer
	var wrapper := Control.new()
	wrapper.name = "ListMainArea"
	wrapper.layout_mode = 2
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb2.add_child(wrapper)
	hb2.move_child(wrapper, 0)
	scroll.reparent(wrapper)
	scroll.layout_mode = 1
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 0
	scroll.offset_top = 0
	scroll.offset_right = 0
	scroll.offset_bottom = 0

	var empty_cc := CenterContainer.new()
	empty_cc.name = "LocalEditorsEmptyState"
	empty_cc.layout_mode = 1
	empty_cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	empty_cc.mouse_filter = Control.MOUSE_FILTER_STOP
	wrapper.add_child(empty_cc)
	_empty_state_root = empty_cc

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size.x = 420.0 * Config.EDSCALE
	empty_cc.add_child(vbox)

	var icon := TextureRect.new()
	icon.texture = preload("res://assets/Godot128x128.svg")
	icon.custom_minimum_size = Vector2(72, 72)
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

	var btn := Button.new()
	btn.text = tr("Install Editor")
	btn.icon = get_theme_icon("AssetLib", "EditorIcons")
	btn.pressed.connect(func() -> void: install_editor_requested.emit())
	vbox.add_child(btn)

	var stable_btn := Button.new()
	stable_btn.text = tr("Download latest stable")
	stable_btn.tooltip_text = tr("Downloads the newest stable Godot build for this OS.")
	stable_btn.icon = get_theme_icon("AssetLib", "EditorIcons")
	stable_btn.pressed.connect(func() -> void: recommended_stable_download_requested.emit())
	vbox.add_child(stable_btn)
	_recommended_stable_button = stable_btn

	apply_install_prompt_for_inventory_empty(true)


## Driven only by LocalEditors inventory (not tree child_count — queue_free keeps nodes until frame end).
func apply_install_prompt_for_inventory_empty(is_inventory_empty: bool) -> void:
	if _empty_state_root == null:
		return
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


func _item_comparator(a: Dictionary, b: Dictionary) -> bool:
	if a.favorite && !b.favorite:
		return true
	if b.favorite && !a.favorite:
		return false
	match _sort_option_button.selected:
		1: return a.path < b.path
		2: return a.tag_sort_string < b.tag_sort_string
		_: return a.name < b.name
	return a.name < b.name


func _fill_sort_options(btn: OptionButton) -> void:
	btn.add_item(tr("Name"))
	btn.add_item(tr("Path"))
	btn.add_item(tr("Tags"))
	
	var last_checked_sort := Cache.smart_value(self, "last_checked_sort", true)
	btn.select(last_checked_sort.ret(0) as int)
	btn.item_selected.connect(func(idx: int) -> void: last_checked_sort.put(idx))
