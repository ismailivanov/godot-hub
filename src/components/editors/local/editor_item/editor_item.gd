class_name EditorListItemControl
extends HBoxListItem
## Provides editor list item control.
##
## Under the path, a line follows the editor's export templates job (see
## [ExportTemplatesJobs]): its progress with Cancel while it runs, the error with Retry
## and Dismiss when it fails. Jobs outlive the rows, so a rebuilt list shows them again.


#region Properties
## Emitted when the item is edited.
signal edited
## Emitted when removed.
signal removed(remove_dir: bool)
## Emitted when manage tags is requested.
signal manage_tags_requested
## Emitted when tag clicked.
signal tag_clicked(tag: String)
## Emitted when the user asks to add or remove the editor's export templates.
signal export_templates_requested

## Size before EDSCALE of the row's icon.
const ICON_SIZE := 64.0

## Inline action bar settings.
static var settings := EditorItemActions.Settings.new(
	'editor-item-inline-actions',
	['run', 'remove']
)

## Rename dialog scene.
@export var _rename_dialog_scene: PackedScene
## View owners dialog scene.
@export var _view_owners_dialog_scene: PackedScene
## Add extra arguments dialog scene.
@export var _add_extra_arguments_scene: PackedScene

var _actions: Action.List
var _tags: Array = []
var _item: LocalEditors.Item = null
var _sort_data: Dictionary = {
	'ref': self
}
## Export templates jobs of the editors, from the Context; null outside the Hub.
var _templates_jobs: ExportTemplatesJobs

@onready var _path_label: Label = %PathLabel
@onready var _title_label: Label = %TitleLabel
@onready var _list_icon: TextureRect = %Icon
@onready var _explore_button: Button = %ExploreButton
@onready var _favorite_button: TextureButton = %FavoriteButton
@onready var _tag_container: ItemTagContainer = %TagContainer
@onready var _editor_features: Label = %EditorFeatures
@onready var _actions_h_box: HBoxContainer = %ActionsHBox
@onready var _actions_container: HBoxContainer = %ActionsContainer
@onready var _templates_job: PanelContainer = %TemplatesJob
@onready var _templates_icon: TextureRect = %TemplatesIcon
@onready var _templates_status: Label = %TemplatesStatus
@onready var _templates_retry_button: Button = %TemplatesRetryButton
@onready var _templates_close_button: Button = %TemplatesCloseButton
@onready var _templates_progress: ProgressBar = %TemplatesProgress
#endregion


func _ready() -> void:
	super._ready()
	_tag_container.tag_clicked.connect(func(tag: String) -> void: tag_clicked.emit(tag))

	_editor_features.add_theme_font_override("font", get_theme_font("title", "EditorFonts"))
	_editor_features.add_theme_color_override("font_color", get_theme_color("warning_color", "Editor"))
	if _item:
		_apply_list_icon(_item)

	_templates_retry_button.text = tr("Retry")
	_templates_retry_button.pressed.connect(func() -> void:
		if _templates_jobs != null and _item != null:
			_templates_jobs.retry(_item.path)
	)
	_templates_close_button.pressed.connect(_close_templates_job)
	_update_templates_job_theme()
	# Deferred: the signal comes before the previous theme's styles are dropped.
	theme_changed.connect(_update_templates_job_theme, CONNECT_DEFERRED)


func init(item: LocalEditors.Item) -> void:
	_item = item
	_fill_actions(item)
	_update_actions_availability(item)
	_setup_actions_view(item)

	if not item.is_valid:
		_explore_button.icon = get_theme_icon("FileBroken", "EditorIcons")
		modulate = Color(1, 1, 1, 0.498)

	item.tags_edited.connect(func() -> void:
		_tag_container.set_tags(item.tags)
		_tags = item.tags
		_sort_data.tag_sort_string = "".join(item.tags)
	)

	_title_label.text = item.name
	_path_label.text = item.path
	_favorite_button.button_pressed = item.favorite
	_tag_container.set_tags(item.tags)
	_tags = item.tags

	if item.is_self_contained():
		_editor_features.text = tr("Self-contained")
		_editor_features.show()
	else:
		_editor_features.hide()

	_sort_data.favorite = item.favorite
	_sort_data.name = item.name
	_sort_data.path = item.path
	_sort_data.tag_sort_string = "".join(item.tags)

	call_deferred("_apply_list_icon", item)

	_explore_button.pressed.connect(_show_in_file_manager.bind(item))
	_favorite_button.toggled.connect(func(is_favorite: bool) -> void:
		_sort_data.favorite = is_favorite
		item.favorite = is_favorite
		edited.emit()
	)
	double_clicked.connect(func() -> void:
		if item.is_valid:
			_on_run_editor(item)
	)

	if is_inside_tree():
		_templates_jobs = Context.use_or_null(self, ExportTemplatesJobs) as ExportTemplatesJobs
	if _templates_jobs != null:
		_templates_jobs.job_changed.connect(_on_templates_job_changed)
	_show_templates_job()


func _setup_actions_view(item: LocalEditors.Item) -> void:
	var action_views := EditorItemActions.Menu.new(
		_actions.without(['view-command']).all(),
		settings,
		CustomCommandsPopupItems.Self.new(
			_actions.by_key('view-command'),
			_get_commands(item)
		)
	)
	action_views.icon = get_theme_icon("GuiTabMenuHl", "EditorIcons")
	action_views.add_controls_to_node(_actions_h_box)
	_actions_container.add_child(action_views)

	var set_actions_visible := func(v: bool) -> void:
		_actions_h_box.visible = v
		action_views.visible = v
	right_clicked.connect(func() -> void:
		action_views.refill_popup()
		var popup := action_views.get_popup()
		var rect := Rect2(get_screen_transform() * get_local_mouse_position(), Vector2.ZERO)
		popup.size = rect.size
		if is_layout_rtl():
			# TODO popup.y
			rect.position.x += rect.size.y - popup.size.y
		popup.position = rect.position
		popup.popup()
	)
	selected_changed.connect(func(is_selected: bool) -> void:
		if settings.is_show_always(): return
		set_actions_visible.call(_is_hovering or is_selected)
	)
	set_actions_visible.call(settings.is_show_always())
	hover_changed.connect(func(is_hovered: bool) -> void:
		if settings.is_show_always(): return
		set_actions_visible.call(is_hovered or _is_selected)
	)
	var sync_settings := func() -> void:
		if settings.is_show_always():
			set_actions_visible.call(true)
		else:
			set_actions_visible.call(_is_hovering or _is_selected)
		_actions_h_box.remove_theme_constant_override("separation")
		_actions_container.remove_theme_constant_override("separation")
		_actions_h_box.modulate = Color.WHITE
		action_views.modulate = Color.WHITE
		if settings.is_flat() and not settings.is_show_text():
			_actions_h_box.add_theme_constant_override("separation", int(-4 * Config.EDSCALE))
			_actions_container.add_theme_constant_override("separation", int(-4 * Config.EDSCALE))
			_actions_h_box.modulate = Color(1, 1, 1, 0.498)
			action_views.modulate = Color(1, 1, 1, 0.498)
		_tag_container.visible = settings.is_show_tags()
		_editor_features.visible = settings.is_show_features()
	sync_settings.call()
	settings.changed.connect(sync_settings)


func _fill_actions(item: LocalEditors.Item) -> void:
	var run := Action.from_dict({
		"key": "run",
		"icon": Action.IconTheme.new(self, "Play", "EditorIcons"),
		"act": _on_run_editor.bind(item),
		"label": tr("Run"),
	})

	var rename := Action.from_dict({
		"key": "rename",
		"icon": Action.IconTheme.new(self, "Rename", "EditorIcons"),
		"act": _on_rename.bind(item),
		"label": tr("Rename"),
	})

	var manage_tags := Action.from_dict({
		"key": "manage-tags",
		"icon": Action.IconTheme.new(self, "Script", "EditorIcons"),
		"act": func() -> void: manage_tags_requested.emit(),
		"label": tr("Manage Tags"),
	})

	var add_extra_arguments := Action.from_dict({
		"key": "add-extra-args",
		"icon": Action.IconTheme.new(self, "ConfirmationDialog", "EditorIcons"),
		"act": _on_add_extra_arguments.bind(item),
		"label": tr("Add Extra Args"),
	})

	var view_command := Action.from_dict({
		"key": "view-command",
		"icon": Action.IconTheme.new(self, "Edit", "EditorIcons"),
		"act": _view_command.bind(item),
		"label": tr("Edit Commands"),
	})

	var view_owners := Action.from_dict({
		"key": "view-owners",
		"icon": Action.IconTheme.new(self, "FileList", "EditorIcons"),
		"act": _view_owners.bind(item),
		"label": tr("View References"),
	})

	var export_templates := Action.from_dict({
		"key": "export-templates",
		"icon": Action.IconTheme.new(self, "EditAddRemove", "EditorIcons"),
		"act": func() -> void: export_templates_requested.emit(),
		"label": tr("Export Templates..."),
		"tooltip": tr(
			"Self-contained editors keep their export templates in their own editor_data "
			+ "folder. Use the editor's Export Template Manager."
		) if item.is_self_contained() else tr(
			"Add or remove the export templates of this editor's Godot version."
		),
	})

	var remove := Action.from_dict({
		"key": "remove",
		"icon": Action.IconTheme.new(self, "Remove", "EditorIcons"),
		"act": _on_remove.bind(item),
		"label": tr("Remove"),
	})

	var show_in_file_manager := Action.from_dict({
		"key": "show-in-file-manager",
		"icon": Action.IconTheme.new(self, "Filesystem", "EditorIcons"),
		"act": _show_in_file_manager.bind(item),
		"label": tr("Show in File Manager"),
	})

	_actions = Action.List.new([
		run,
		rename,
		manage_tags,
		add_extra_arguments,
		view_command,
		view_owners,
		export_templates,
		show_in_file_manager,
		remove
	])


func _update_actions_availability(item: LocalEditors.Item) -> void:
	for action: Action.Self in _actions.sub_list([
		'run',
		'manage-tags',
		'rename',
		'add-extra-args',
		'view-command',
		'view-owners'
	]).all():
		action.disable(not item.is_valid)
	_actions.by_key('export-templates').disable(not _has_release_templates(item))


## True when the editor names a Godot release, whose export templates the Export
## Templates action can add and remove: its version hint has a version (and a stage,
## "stable" when it names none). Not for a self-contained editor, which reads them from
## its own editor_data folder rather than the shared one the Hub installs to.
static func _has_release_templates(item: LocalEditors.Item) -> bool:
	return (
		item.is_valid
		and item.engine_brand == EditorEngineBrand.GODOT
		and VersionHint.parse(item.version_hint).is_valid
		and not item.is_self_contained()
	)


func _view_owners(item: LocalEditors.Item) -> void:
	var scene: ShowOwnersDialog = _view_owners_dialog_scene.instantiate()
	add_child(scene)
	scene.raise(item)


func _view_command(item: LocalEditors.Item) -> void:
	var command_viewer := Context.use(self, CommandViewer) as CommandViewer
	if command_viewer:
		command_viewer.raise(
			_get_commands(item), true
		)


func _get_commands(item: LocalEditors.Item) -> CommandViewer.Commands:
	var base_process_src := OSProcessSchema.FmtSource.new(item)
	var cmd_src := CommandViewer.CustomCommandsSourceDynamic.new(item)
	cmd_src.edited.connect(func() -> void: edited.emit())
	var commands := CommandViewer.CommandsDuo.new(
		CommandViewer.CommandsGeneric.new(
			base_process_src,
			cmd_src,
			true
		),
		CommandViewer.CommandsGeneric.new(
			base_process_src,
			Config.CustomCommandsSourceConfig.new(
				Config.GLOBAL_CUSTOM_COMMANDS_EDITORS
			),
			false
		)
	)
	return commands


func _on_run_editor(item: LocalEditors.Item) -> void:
	item.run()
	AutoClose.close_if_should()


func _on_rename(item: LocalEditors.Item) -> void:
	var dialog: RenameEditorDialog = _rename_dialog_scene.instantiate()
	add_child(dialog)
	dialog.popup_centered()
	dialog.init(item.name, item.version_hint)
	dialog.editor_renamed.connect(func(new_name: String, version_hint: String) -> void:
		item.name = new_name
		item.version_hint = version_hint
		_title_label.text = item.name
		_sort_data.name = new_name
		item.refresh_engine_brand(false)
		call_deferred("_apply_list_icon", item)
		# The version hint decides whether export templates can be managed.
		_update_actions_availability(item)
		edited.emit()
	)


func _on_add_extra_arguments(item: LocalEditors.Item) -> void:
	var dialog: AddExtraArgumentsEditorDialog = _add_extra_arguments_scene.instantiate()
	add_child(dialog)
	dialog.popup_centered()
	dialog.init(item.extra_arguments)
	dialog.editor_add_extra_arguments.connect(func(new_extra_arguments: PackedStringArray) -> void:
		item.extra_arguments = new_extra_arguments
		edited.emit()
	)


func _on_remove(item: LocalEditors.Item) -> void:
	var confirmation_dialog := ConfirmationDialogAutoFree.new()
	confirmation_dialog.ok_button_text = tr("Remove")
	confirmation_dialog.get_label().hide()

	var label := Label.new()
	label.text = tr("Are you sure to remove the editor from the list?")

	var warning := Label.new()
	var checkbox := CheckBox.new()
	checkbox.text = tr("remove also from the file system")
	# Only folders inside the versions folder are deleted, see LocalEditorsControl.
	if LocalEditors.managed_install_dir(item.path).is_empty():
		checkbox.disabled = true
		warning.text = tr(
			"This editor is outside the Hub's versions folder, so it will only be removed from the list."
		)
	else:
		warning.text = tr("NOTE: the action will remove the parent folder of the editor with all the content.") + "\n%s" % item.path.get_base_dir()
		warning.self_modulate = get_theme_color("warning_color", "Editor")
		warning.hide()
		checkbox.toggled.connect(func(toggled: bool) -> void:
			warning.visible = toggled
		)

	var vb := VBoxContainer.new()
	vb.add_child(label)
	vb.add_child(checkbox)
	vb.add_child(warning)
	vb.add_spacer(false)

	confirmation_dialog.add_child(vb)

	# The list rebuilds the rows, so this one stays until the outcome is known.
	confirmation_dialog.confirmed.connect(func() -> void:
		removed.emit(checkbox.button_pressed)
	)
	add_child(confirmation_dialog)
	confirmation_dialog.popup_centered()


func _show_in_file_manager(item: LocalEditors.Item) -> void:
	OS.shell_show_in_file_manager(ProjectSettings.globalize_path(item.path).get_base_dir())


func get_actions() -> Array[Control]:
	return []


func apply_filter(filter: Callable) -> bool:
	return filter.call({
		'name': _title_label.text,
		'path': _path_label.text,
		'tags': _tags
	})


func get_sort_data() -> Dictionary:
	return _sort_data


func _on_templates_job_changed(editor_path: String) -> void:
	if _item != null and editor_path == _item.path:
		_show_templates_job()


## Shows the editor's running or failed export templates job; hidden without one and
## once it is done.
func _show_templates_job() -> void:
	var job: ExportTemplatesJobs.Job = null
	if _templates_jobs != null and _item != null:
		job = _templates_jobs.get_job(_item.path)
	if job == null or job.state == ExportTemplatesJobs.Job.State.DONE:
		_templates_job.hide()
		_keep_lead_beside_title()
		return
	var failed := job.state == ExportTemplatesJobs.Job.State.FAILED
	_templates_status.text = job.status_text
	_templates_status.tooltip_text = job.status_text
	_templates_status.add_theme_color_override(
		"font_color",
		get_theme_color("font_color" if failed else "readonly_font_color", "Editor"),
	)
	_templates_icon.visible = failed
	_templates_retry_button.visible = failed
	_templates_progress.visible = not failed
	_templates_progress.value = job.progress
	_templates_close_button.tooltip_text = tr("Dismiss") if failed else tr("Cancel")
	var style := _templates_job.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		# A light tint of the text color, or of the error color after a failure.
		var tint := get_theme_color("error_color" if failed else "mono_color", "Editor")
		style.bg_color = Color(tint, 0.14 if failed else 0.05)
	_templates_job.show()
	_keep_lead_beside_title()


## Cancels the running job, or dismisses the failed one.
func _close_templates_job() -> void:
	if _templates_jobs == null or _item == null:
		return
	var job := _templates_jobs.get_job(_item.path)
	if job != null and job.state == ExportTemplatesJobs.Job.State.RUNNING:
		_templates_jobs.cancel(_item.path)
	else:
		_templates_jobs.dismiss(_item.path)


## Styles the export templates line like the theme's buttons and panels: rounded by the
## theme's corner radius, with the thin progress bar of the downloads above the list.
## Its text and bar start where the title's text does.
func _update_templates_job_theme() -> void:
	var label_style := get_theme_stylebox("normal", "Label")
	var status_style := label_style.duplicate() as StyleBox
	status_style.content_margin_left = 0
	status_style.content_margin_right = 0
	_templates_status.add_theme_stylebox_override("normal", status_style)
	var panel := ThemeCorners.new_flat(self)
	# The Label margin the status drops; as much on the right, so the bar under the
	# buttons is centered in the line.
	panel.content_margin_left = label_style.get_margin(SIDE_LEFT)
	panel.content_margin_right = label_style.get_margin(SIDE_LEFT)
	panel.content_margin_top = 2 * Config.EDSCALE
	panel.content_margin_bottom = 6 * Config.EDSCALE
	_templates_job.add_theme_stylebox_override("panel", panel)
	(_templates_job.get_node("VBox") as VBoxContainer).add_theme_constant_override(
		"separation", roundi(2 * Config.EDSCALE)
	)
	ThemeCorners.style_thin_progress_bar(_templates_progress, self)

	_templates_icon.texture = get_theme_icon("StatusError", "EditorIcons")
	_templates_retry_button.icon = get_theme_icon("Reload", "EditorIcons")
	_templates_close_button.icon = get_theme_icon("Close", "EditorIcons")
	_show_templates_job()


## Keeps the favorite star and the icon beside the title and path while the export
## templates line makes the row taller: centered on the height the row has without
## the line, as they are then, instead of on the whole row.
func _keep_lead_beside_title() -> void:
	var lead_height := 0.0
	if _templates_job.visible:
		var info := _templates_job.get_parent() as VBoxContainer
		lead_height = maxf(
			ICON_SIZE * Config.EDSCALE,
			info.get_combined_minimum_size().y
				- _templates_job.get_combined_minimum_size().y
				- info.get_theme_constant("separation"),
		)
	var favorite := _favorite_button.get_parent() as Control
	for lead: Control in [favorite, _list_icon]:
		lead.size_flags_vertical = (
			Control.SIZE_SHRINK_BEGIN if lead_height > 0.0 else Control.SIZE_FILL
		)
	favorite.custom_minimum_size.y = lead_height
	_list_icon.custom_minimum_size.y = maxf(ICON_SIZE * Config.EDSCALE, lead_height)


## Applies the engine brand list icon to the row texture rect.
func _apply_list_icon(item: LocalEditors.Item) -> void:
	var icon_rect: TextureRect = _list_icon
	if not icon_rect:
		icon_rect = get_node_or_null("%Icon") as TextureRect
	if not icon_rect:
		icon_rect = get_node_or_null("Icon") as TextureRect
	if not icon_rect:
		return
	icon_rect.visible = true
	icon_rect.modulate = Color.WHITE
	var tex: Texture2D = item.get_list_icon_texture()
	if not tex or tex.get_width() <= 0:
		tex = preload("res://assets/Godot128x128.png")
	icon_rect.texture = tex
	icon_rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE) * Config.EDSCALE
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if icon_rect == _list_icon:
		_keep_lead_beside_title()
