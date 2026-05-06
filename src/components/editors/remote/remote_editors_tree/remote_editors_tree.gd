class_name RemoteEditorsTreeControl
extends VBoxContainer


signal _loadings_number_changed(value: int)
signal catalogue_visibility_changed(has_visible_versions: bool)
signal recommended_stable_download_requested

const uuid = preload("res://addons/uuid.gd")

@onready var _tree: Tree = %Tree
@onready var _channel_tab_bar: TabBar = %ChannelTabBar
@onready var _check_box_container: HFlowContainer = %CheckBoxContainer
@onready var _empty_state: Control = %EmptyState
@onready var _empty_install_button: Button = %EmptyInstallButton
@onready var _empty_recommended_stable_button: Button = %EmptyRecommendedStableButton

var _refresh_button: Button
var _remote_assets: RemoteEditorsTreeDataSource.RemoteAssets

var _src: RemoteEditorsTreeDataSource.I
var _i_remote_tree: RemoteEditorsTreeDataSource.RemoteTree
var _root_loaded := false
var _channel_tab: int = RemoteEditorsTreeDataSourceGithub.CHANNEL_TAB_ALL
var _row_filters: Array[RowFilter] = [NotRelatedFilter.new()]
var _current_loadings_number := 0:
	set(value): 
		_current_loadings_number = value
		_loadings_number_changed.emit(value)
var _remote_editors_checkbox_checked := Cache.smart_section(
	Cache.section_of(self) + ".checkbox_checked", true
)
var _release_channel_tab_cache := Cache.smart_section(
	Cache.section_of(self) + ".release_channel_tab_v2", true
)
var _has_installed_editors := false


func post_ready(refresh_button: Button) -> void:
	_refresh_button = refresh_button
	
	_setup_tree()
	_setup_release_channel_tabs()
	var channel_hide := func(row: RemoteEditorsTreeDataSource.FilterTarget) -> bool:
		return row.channel_tab_should_hide(_channel_tab)
	_row_filters.insert(1, RowFilter.new(channel_hide))
	_setup_checkboxes()

	_empty_install_button.pressed.connect(func() -> void:
		focus_install_catalogue()
	)
	_empty_recommended_stable_button.pressed.connect(func() -> void:
		recommended_stable_download_requested.emit()
	)

	_refresh_button.pressed.connect(_on_refresh_pressed)

	_loadings_number_changed.connect(func(value: int) -> void:
		_refresh_button.disabled = value != 0
	)


func _ready() -> void:
	(%EmptyVBox as VBoxContainer).custom_minimum_size.x = 420.0 * Config.EDSCALE
	(%EmptyTitle as Label).text = tr("No installs")
	(%EmptyHint as Label).text = tr("To get started, install or locate a Godot editor.")
	_empty_install_button.text = tr("Install Editor")
	_empty_install_button.icon = get_theme_icon("AssetLib", "EditorIcons")
	_empty_recommended_stable_button.text = tr("Download latest stable")
	_empty_recommended_stable_button.tooltip_text = tr("Downloads the newest stable Godot build for this OS.")
	_empty_recommended_stable_button.icon = get_theme_icon("AssetLib", "EditorIcons")
	visibility_changed.connect(_on_visibility_changed)


func set_has_installed_editors(has_any: bool) -> void:
	if _has_installed_editors == has_any:
		return
	_has_installed_editors = has_any
	_emit_catalogue_visibility()


func set_recommended_stable_button_disabled(disabled: bool) -> void:
	_empty_recommended_stable_button.disabled = disabled


func set_data_source(src: RemoteEditorsTreeDataSource.I) -> void:
	if _src != null:
		_src.cleanup(_tree)
	_src = src
	_src.setup(_tree)
	if is_visible_in_tree():
		await _refresh()
	else:
		_emit_catalogue_visibility()


func focus_install_catalogue() -> void:
	var all_tab: int = RemoteEditorsTreeDataSourceGithub.CHANNEL_TAB_ALL
	_channel_tab_bar.current_tab = all_tab
	_channel_tab = all_tab
	_release_channel_tab_cache.set_value("tab", _channel_tab)
	_refresh_visibility_from_root()
	_tree.grab_focus()


func _on_refresh_pressed() -> void:
	await _refresh()


func _refresh() -> void:
	var root_item := _tree.get_root()
	if root_item == null:
		_emit_catalogue_visibility()
		return
	for c in root_item.get_children():
		c.free()
	await _expand(_delegate_of(root_item))


func _refresh_visibility_from_root() -> void:
	var root := _tree.get_root()
	if root != null and root.has_meta("delegate"):
		_update_whole_tree_visibility(_delegate_of(root))
		for i in range(root.get_child_count()):
			_prune_empty_folder_visibility(root.get_child(i))
	_emit_catalogue_visibility()


## Hide branch roots whose subtree has no visible rows after filters (e.g. Official + only prerelease children).
func _prune_empty_folder_visibility(item: TreeItem) -> bool:
	if item.get_child_count() == 0:
		return item.visible
	var any_child_visible := false
	for i in range(item.get_child_count()):
		var ch := item.get_child(i)
		if _prune_empty_folder_visibility(ch):
			any_child_visible = true
	item.visible = item.visible and any_child_visible
	return item.visible


func _emit_catalogue_visibility() -> void:
	var has_visible_catalog := false
	var root := _tree.get_root()
	if root != null:
		for c in root.get_children():
			if c.visible:
				has_visible_catalog = true
				break
	var show_install_prompt := not _has_installed_editors and not has_visible_catalog
	_empty_state.visible = show_install_prompt
	_tree.visible = has_visible_catalog or _has_installed_editors
	catalogue_visibility_changed.emit(has_visible_catalog)


func _setup_release_channel_tabs() -> void:
	_channel_tab_bar.clip_tabs = false
	_channel_tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_NEVER
	_channel_tab_bar.add_tab(tr("All"))
	_channel_tab_bar.add_tab(tr("Official releases"))
	_channel_tab_bar.add_tab(tr("Pre-releases"))
	var saved_raw: Variant = _release_channel_tab_cache.get_value(
		"tab",
		RemoteEditorsTreeDataSourceGithub.CHANNEL_TAB_ALL
	)
	var saved_tab: int = RemoteEditorsTreeDataSourceGithub.CHANNEL_TAB_ALL
	if saved_raw is int:
		saved_tab = saved_raw as int
	saved_tab = clampi(saved_tab, 0, _channel_tab_bar.tab_count - 1)
	_channel_tab_bar.current_tab = saved_tab
	_channel_tab = saved_tab
	_channel_tab_bar.tab_selected.connect(func(tab: int) -> void:
		_channel_tab = tab
		_release_channel_tab_cache.set_value("tab", tab)
		_refresh_visibility_from_root()
	)


func _setup_checkboxes() -> void:
	(%CheckBoxPanelContainer as PanelContainer).add_theme_stylebox_override("panel", get_theme_stylebox("panel", "Tree"))
	
	var checkbox := func(text: String, filter: RowFilter, button_pressed:=false) -> CheckBox:
		var box := CheckBox.new()
		box.text = text
		box.button_pressed = button_pressed
		if button_pressed:
			_row_filters.append(filter)
		box.toggled.connect(func(pressed: bool) -> void:
			if pressed: 
				_row_filters.append(filter)
			else:
				var idx := _row_filters.find(filter)
				_row_filters.remove_at(idx)
			_remote_editors_checkbox_checked.set_value(text, pressed)
			_refresh_visibility_from_root()
		)
		return box

	var inverted_checkbox := func(text: String, filter: RowFilter, button_pressed:=false) -> CheckBox:
		var box := CheckBox.new()
		box.text = text
		box.button_pressed = button_pressed
		if not button_pressed:
			_row_filters.append(filter)
		box.toggled.connect(func(pressed: bool) -> void:
			if pressed: 
				var idx := _row_filters.find(filter)
				if idx >= 0:
					_row_filters.remove_at(idx)
			else:
				_row_filters.append(filter)
			_remote_editors_checkbox_checked.set_value(text, pressed)
			_refresh_visibility_from_root()
		)
		return box

	var contains_any := func(words: Array) -> Callable:
		return func(row: RemoteEditorsTreeDataSource.FilterTarget) -> bool: 
			return words.any(func(x: String) -> bool: return row.get_name().to_lower().contains(x.to_lower()))
	
	var _not := func(original: Callable) -> Callable:
		return func(row: RemoteEditorsTreeDataSource.FilterTarget) -> Callable: return not original.call(row)
	
	_check_box_container.add_child(
		inverted_checkbox.call(
			tr("mono"), 
			RowFilter.new(contains_any.call(["mono"]) as Callable),
			_remote_editors_checkbox_checked.get_value("mono", true)
		) as CheckBox
	)
	
	_check_box_container.add_child(
		inverted_checkbox.call(
			tr("any platform"), 
			RowFilter.new(func(row: RemoteEditorsTreeDataSource.FilterTarget) -> bool: 
				return row.is_file() and row.is_for_different_platform(_src.get_platform_suffixes())),
			_remote_editors_checkbox_checked.get_value("any platform", false)
		) as CheckBox
	)

	if not OS.has_feature("macos"):
		var bit: String
		var opposite: String
		if OS.has_feature("32"):
			bit = "32"
			opposite = "64"
		elif OS.has_feature("64"):
			bit = "64"
			opposite = "32"
		if bit:
			_check_box_container.add_child(
				checkbox.call(
					"%s-bit" % bit, 
					RowFilter.new(contains_any.call([opposite]) as Callable),
					_remote_editors_checkbox_checked.get_value("%s-bit" % bit, true)
				) as CheckBox
			)


func _delegate_of(item: TreeItem) -> RemoteEditorsTreeDataSource.Item:
	return _src.to_remote_item(item)


func _setup_tree() -> void:
	_i_remote_tree = RemoteEditorsTreeDataSource.RemoteTree.new(_tree, self)
	
	_tree.item_collapsed.connect(
		func(x: TreeItem) -> void: 
			var expanded := not x.collapsed
			var delegate := _delegate_of(x)
			var not_loaded_yet := not delegate.is_loaded()
			if expanded and not_loaded_yet:
				_expand.call_deferred(delegate)
#				_expand(delegate)
	)

	_tree.item_activated.connect(func() -> void:
		var delegate := _delegate_of(_tree.get_selected())
		delegate.handle_item_activated()
	)

	_tree.button_clicked.connect(func(item: TreeItem, col: int, id: int, mouse: int) -> void:
		var delegate := _delegate_of(item)
		delegate.handle_button_clicked(col, id, mouse)
	)


func _expand(remote_tree_item: RemoteEditorsTreeDataSource.Item) -> void:
	_current_loadings_number += 1
	await remote_tree_item.async_expand(_i_remote_tree)
	var root_item := _tree.get_root()
	if root_item != null and root_item.has_meta("delegate"):
		var root_del := _delegate_of(root_item)
		if remote_tree_item == root_del:
			_update_whole_tree_visibility(root_del)
		else:
			_update_whole_tree_visibility(remote_tree_item)
			_update_whole_tree_visibility(root_del)
		for i in range(root_item.get_child_count()):
			_prune_empty_folder_visibility(root_item.get_child(i))
	_current_loadings_number -= 1
	if root_item != null and root_item.has_meta("delegate"):
		if remote_tree_item == _delegate_of(root_item):
			_emit_catalogue_visibility()


func _update_whole_tree_visibility(from: RemoteEditorsTreeDataSource.Item) -> void:
	from.update_visibility(_row_filters)
	for child in from.get_children():
		_update_whole_tree_visibility(child)


func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _root_loaded:
		_root_loaded = true
		await _expand(_delegate_of(_tree.get_root()))


class RowFilter:
	var _delegate: Callable
	
	func _init(delegate: Callable) -> void:
		_delegate = delegate
	
	func test(row: RemoteEditorsTreeDataSource.FilterTarget) -> bool:
		return _delegate.call(row)


class SimpleContainsFilter extends RowFilter:
	func _init(what: String) -> void:
		super._init(
			func(row: RemoteEditorsTreeDataSource.FilterTarget) -> bool: 
				return row.get_name().to_lower().contains(what)
		)


class NotRelatedFilter extends RowFilter:
	func _init() -> void:
		super._init(
			func(row: RemoteEditorsTreeDataSource.FilterTarget) -> bool:
				return ["media", "patreon", "testing", "toolchains"].any(
					func(x: String) -> bool: return row.get_name() == x
				)
		)
