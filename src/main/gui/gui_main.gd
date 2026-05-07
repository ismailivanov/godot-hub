extends Control

const theme_source = preload("res://theme/theme.gd")

@export var _remote_editors: RemoteEditorsControl
@export var _local_editors: LocalEditorsControl
@export var _projects: ProjectsControl
@export var _asset_lib_projects: AssetLibProjects
@export var _godots_releases: GodotsReleasesControl
@export var _auto_updates: AutoUpdates
@export var _asset_download: PackedScene
@export var _sidebar_nav: BoxContainer
@export var _updates: Control
@export var _news: Control
@export var _tab_container: TabContainer


@onready var _gui_base: Panel = get_node("%GuiBase")
@onready var _main_v_box: VBoxContainer = get_node("%MainVBox")
@onready var _version_button: LinkButton = %VersionButton
@onready var _update_button: NotificationsButton = %UpdateButton
@onready var _settings_button: Button = %SettingsButton
@onready var _sidebar_panel: PanelContainer = %SidebarPanel


var _on_exit_tree_callbacks: Array[Callable] = []
var _local_remote_switch_context: LocalRemoteEditorsSwitchContext
var _local_editors_service: LocalEditors.List
var _projects_service: Projects.List
var _quick_update_running := false


func _ready() -> void:
	get_tree().root.files_dropped.connect(func(files: PackedStringArray) -> void:
		if len(files) == 0:
			return
		var file := files[0].simplify_path()
		if file.ends_with("project.godot"):
			_projects.import(file)
		elif file.ends_with(".zip"):
			var zip_reader := ZIPReader.new()
			var unzip_err := zip_reader.open(file)
			if unzip_err != OK:
				zip_reader.close()
				return
			var has_project_godot_file := len(
				Array(
					zip_reader.get_files()
				).map(func(x: String) -> bool: return x.get_file() == "project.godot")
			) > 0
			if has_project_godot_file:
				_projects.install_zip(
					zip_reader,
					file.get_file().replace(".zip", "").capitalize()
				)
			else:
				zip_reader.close()
				_remote_editors.install_zip(
					file, 
					file.get_file().replace(".zip", ""), 
					utils.guess_editor_name(file.replace(".zip", ""))
				)
		else:
			_local_editors.import(utils.guess_editor_name(file), file)
	)
	
	# Sidebar navigation buttons
	_sidebar_nav.add_child(SidebarNavButton.new("ProjectList", tr("Projects"), _tab_container, [_projects]))
	_sidebar_nav.add_child(SidebarNavButton.new("AssetLib", tr("Asset Library"), _tab_container, [_asset_lib_projects]))
	_sidebar_nav.add_child(SidebarNavButton.new("GodotMonochrome", tr("Editors"), _tab_container, [_local_editors, _remote_editors]))
	var _news_nav_button := SidebarNavButton.new("Script", tr("News"), _tab_container, [_news])
	_sidebar_nav.add_child(_news_nav_button)
	(_news as NewsControl).has_unread_changed.connect(func(has_unread: bool) -> void:
		_news_nav_button.set_has_badge(has_unread)
	)

	_gui_base.set(
		"theme_override_styles/panel",
		get_theme_stylebox("Background", "EditorStyles")
	)
	_gui_base.set_anchor(SIDE_RIGHT, Control.ANCHOR_END)
	_gui_base.set_anchor(SIDE_BOTTOM, Control.ANCHOR_END)
	_gui_base.set_end(Vector2.ZERO)
	
	_main_v_box.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, 
		Control.PRESET_MODE_MINSIZE, 
		get_theme_constant("window_border_margin", "Editor")
	)
	# No gap between custom title bar and main content (Editor top_bar_separation is for editor chrome).
	_main_v_box.add_theme_constant_override("separation", 0)

	# Apply sidebar panel style
	_sidebar_panel.set(
		"theme_override_styles/panel",
		get_theme_stylebox("SidebarPanel", "EditorStyles")
	)

	var sidebar_logo := %SidebarLogo as Control
	var ed := float(Config.EDSCALE)
	var logo_side := roundi(58.0 * ed)
	var logo_sq := Vector2(logo_side, logo_side)
	sidebar_logo.custom_minimum_size = logo_sq
	sidebar_logo.set(&"custom_maximum_size", logo_sq)

	var sidebar_title := %SidebarTitle as Label
	sidebar_title.text = tr("Godot Hub")
	sidebar_title.tooltip_text = tr("Godot Hub")
	sidebar_title.add_theme_font_override("font", get_theme_font("bold", "EditorFonts"))
	var title_col := get_theme_color("font_color", "Editor").lerp(
		get_theme_color("mono_color", "Editor"), 0.2
	)
	sidebar_title.add_theme_color_override("font_color", title_col)

	_remote_editors.installed.connect(func(name: String, path: String) -> void:
		_local_editors.add(name, path)
	)

	var main_current_tab := Cache.smart_value(
		self, "main_current_tab", true
	)
	_tab_container.tab_changed.connect(func(tab: int) -> void:
		main_current_tab.put(tab)
		var ctl := _tab_container.get_current_tab_control()
		if ctl == _local_editors or ctl == _remote_editors:
			_remote_editors.sync_stable_download_buttons_if_idle()
	)
	_tab_container.current_tab = main_current_tab.ret(0)

	_local_editors.editor_download_pressed.connect(func() -> void:
		_tab_container.current_tab = _tab_container.get_tab_idx_from_control(_remote_editors)
	)

	_local_editors.recommended_stable_download_requested.connect(_on_local_latest_stable_download)

	_local_editors.editor_inventory_changed.connect(func(has_any: bool) -> void:
		_remote_editors.set_has_installed_editors(has_any)
		if not has_any:
			_remote_editors.force_reset_recommended_stable_state()
	)
	_remote_editors.recommended_stable_download_busy.connect(func(busy: bool) -> void:
		_local_editors.set_recommended_stable_download_busy(busy)
	)

	_version_button.text = Config.VERSION
	_version_button.underline = LinkButton.UNDERLINE_MODE_NEVER
	_version_button.focus_mode = Control.FOCUS_NONE
	_version_button.tooltip_text = tr("Current version")
	_update_button.icon = get_theme_icon("Reload", "EditorIcons")
	_update_button.tooltip_text = tr("Download and install latest update")
	
	# Settings button in sidebar
	_settings_button.flat = true
	_settings_button.text = tr("Settings")
	_settings_button.tooltip_text = tr("Settings")
	_settings_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_settings_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_settings_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	_settings_button.icon = get_theme_icon("Tools", "EditorIcons")
	_settings_button.theme_type_variation = "SidebarBottomButton"
	_settings_button.pressed.connect(func() -> void:
		($Settings as SettingsWindow).raise_settings()
	)
	
	_local_editors_service.load()
	_projects_service.load()

	_projects.init(_projects_service, _local_editors_service)
	_local_editors.init(_local_editors_service)
	_remote_editors.init(%DownloadsContainer as DownloadsContainer)
	_remote_editors.sync_stable_download_buttons_if_idle()

	_projects.manage_tags_requested.connect(_popup_manage_tags)
	_local_editors.manage_tags_requested.connect(_popup_manage_tags)

	_setup_godots_releases()
	_setup_asset_lib_projects()
	
	_use_ctx().add(self, %CommandViewer)


func _on_local_latest_stable_download() -> void:
	await _remote_editors.request_latest_stable_editor_download()


func _notification(what: int) -> void:
	if NOTIFICATION_APPLICATION_FOCUS_OUT == what:
		OS.low_processor_usage_mode_sleep_usec = 100000
	elif NOTIFICATION_APPLICATION_FOCUS_IN == what:
		OS.low_processor_usage_mode_sleep_usec = ProjectSettings.get(
			"application/run/low_processor_mode_sleep_usec"
		)
		_remote_editors.sync_stable_download_buttons_if_idle()


func _enter_tree() -> void:
	TranslationServer.set_locale(Config.LANGUAGE.ret("en") as String)
	theme_source.set_scale(Config.EDSCALE)
	theme = theme_source.create_custom_theme(null)
	
	var window := get_window()
	window.min_size = Vector2(520, 370) * Config.EDSCALE
	
	var scale_factor := maxf(1, Config.EDSCALE * 0.75)
	if scale_factor > 1:
		var window_size := DisplayServer.window_get_size()
		var screen_rect := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		
		window_size *= scale_factor
		
		DisplayServer.window_set_size(window_size)
		if screen_rect.size != Vector2i():
			var window_position := Vector2i(
				screen_rect.position.x + (screen_rect.size.x - window_size.x) / 2,
				screen_rect.position.y + (screen_rect.size.y - window_size.y) / 2
			)
			DisplayServer.window_set_position(window_position)

	window.min_size = Vector2(700, 350) * Config.EDSCALE
	if Config.REMEMBER_WINDOW_SIZE.ret():
		var rect := Config.LAST_WINDOW_RECT.ret(Rect2i(
			window.position,
			window.min_size
		)) as Rect2i
		if DisplayServer.get_screen_from_rect(rect) != -1:
			window.size = rect.size
			window.position = rect.position
	
	_local_remote_switch_context = LocalRemoteEditorsSwitchContext.new(
		_local_editors,
		_remote_editors,
		_tab_container
	)
	
	_local_editors_service = LocalEditors.List.new(
		Config.EDITORS_CONFIG_PATH
	)
	_projects_service = Projects.List.new(
		Config.PROJECTS_CONFIG_PATH,
		_local_editors_service,
		preload("res://assets/default_project_icon.svg")
	)
	
	_use_ctx().add(self, _local_remote_switch_context)
	_use_ctx().add(self, _local_editors_service)
	_use_ctx().add(self, _projects_service)
	
	_on_exit_tree_callbacks.append(func() -> void:
		_local_editors_service.cleanup()
		_projects_service.cleanup()
		
		_use_ctx().erase(self, _local_editors_service)
		_use_ctx().erase(self, _projects_service)
		_use_ctx().erase(self, _local_remote_switch_context)
	)


func _use_ctx() -> UseContextAutoload:
	return Context as UseContextAutoload


func _exit_tree() -> void:
	for callback in _on_exit_tree_callbacks:
		callback.call()
	var window := get_window()
	Config.LAST_WINDOW_RECT.put(Rect2i(window.position, window.size))


# TODO type
func _popup_manage_tags(item_tags: Array, all_tags: Array, on_confirm: Callable) -> void:
	var manage_tags := $ManageTags as ManageTagsControl
	manage_tags.popup_centered(Vector2(500, 0) * Config.EDSCALE)
	manage_tags.init(item_tags, all_tags, on_confirm)


func _setup_asset_lib_projects() -> void:
	var version_src := GodotVersionOptionButton.SrcGithubYml.new(
		RemoteEditorsTreeDataSourceGithub.YmlSourceGithub.new()
	)
#	var version_src = GodotVersionOptionButton.SrcMock.new(["4.1"])
	
	var request := HTTPRequest.new()
	add_child(request)
	var asset_lib_factory := AssetLib.FactoryDefault.new(request)
	
	var category_src := AssetCategoryOptionButton.SrcRemote.new()
	
	_asset_lib_projects.download_requested.connect(func(item: AssetLib.Item, icon: Texture2D) -> void:
		var asset_download := _asset_download.instantiate() as AssetDownload
		(%DownloadsContainer as DownloadsContainer).add_download_item(asset_download)
		if icon != null:
			asset_download.icon.texture = icon
		asset_download.start(
			item.download_url, 
			(Config.DOWNLOADS_PATH.ret() as String) + "/", 
			"project.zip",
			item.title
		)
		asset_download.downloaded.connect(func(abs_zip_path: String) -> void:
			if not item.download_hash.is_empty():
				var download_hash := FileAccess.get_sha256(abs_zip_path)
				if item.download_hash != download_hash:
					asset_download.set_status(tr("Failed SHA-256 hash check"))
					var error := tr("Bad download hash, assuming file has been tampered with.") + "\n"
					error += tr("Expected:") + " " + item.download_hash + "\n" + tr("Got:") + " " + download_hash
					asset_download.popup_error_dialog(error)
					return
			var zip_reader := ZIPReader.new()
			var unzip_err := zip_reader.open(abs_zip_path)
			if unzip_err != OK:
				zip_reader.close()
				return
			_projects.install_zip(
				zip_reader,
				item.title
			)
		)
	)
	
	_asset_lib_projects.init(
		asset_lib_factory,
		category_src,
		version_src,
#		RemoteImageSrc.AlwaysBroken.new(self)
		RemoteImageSrc.LoadFileBuffer.new(
#			RemoteImageSrc.FileByUrlSrcAsIs.new(),
			RemoteImageSrc.FileByUrlCachedEtag.new(),
			self.get_theme_icon("FileBrokenBigThumb", "EditorIcons")
		)
	)


func _setup_godots_releases() -> void:
	var godots_releases := GodotsReleases.Default.new(
		GodotsReleases.SrcGithub.new()
	)
	var godots_downloads := GodotsDownloads.Default.new(
		(%DownloadsContainer as DownloadsContainer),
		_asset_download
	)
	var godots_install: GodotsInstall.I
	if OS.has_feature("template"):
		godots_install = GodotsInstall.Default.new(
			OS.get_executable_path(),
			get_tree()
		)
	else:
		godots_install = GodotsInstall.Forbidden.new(self)

	var update_cache := GodotsRecentReleases.Cached.new(
		GodotsRecentReleases.Default.new(godots_releases)
	)
	update_cache.invalidate()
	_auto_updates.init(
		update_cache, 
		func() -> void:
			_run_quick_update(godots_releases, godots_downloads, godots_install)
	)
	_godots_releases.init(
		godots_releases,
		godots_downloads,
		godots_install
	)


func _run_quick_update(
	releases: GodotsReleases.I,
	downloads: GodotsDownloads.I,
	installer: GodotsInstall.I,
) -> void:
	if _quick_update_running:
		return
	_quick_update_running = true
	_update_button.disabled = true
	await releases.async_load()
	for release in releases.all():
		if not release.is_ready_to_update:
			continue
		for asset in release.assets:
			if asset.is_godots_bin_for_current_platform():
				downloads.download(
					asset.browser_download_url,
					func(abs_zip_path: String) -> void:
						installer.install(abs_zip_path)
						_quick_update_running = false
						_update_button.disabled = false
				)
				return
	var dialog := AcceptDialog.new()
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.dialog_text = tr("No new compatible update found.")
	add_child(dialog)
	dialog.popup_centered()
	_quick_update_running = false
	_update_button.disabled = false


class _BadgeDot extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		draw_circle(Vector2(r, r), r, Color(0.95, 0.2, 0.2))


class SidebarNavButton extends Button:
	var _icon_name: String
	var _badge: Control
	
	func _init(icon: String, text: String, tab_container: TabContainer, tab_controls: Array) -> void:
		_icon_name = icon
		self.text = text
		self.toggle_mode = true
		self.focus_mode = Control.FOCUS_NONE
		self.alignment = HORIZONTAL_ALIGNMENT_LEFT
		self.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		self.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		self.theme_type_variation = "SidebarNavButton"
		
		self.pressed.connect(func() -> void:
			var idx := tab_controls.find(tab_container.get_current_tab_control())
			idx = wrapi(idx + 1, 0, len(tab_controls))
			tab_container.current_tab = tab_container.get_tab_idx_from_control(tab_controls[idx] as Control)
			set_pressed_no_signal(true)
		)
		tab_container.tab_changed.connect(func(idx: int) -> void:
			set_pressed_no_signal(
				tab_controls.any(func(tab_control: Control) -> bool: 
					return tab_container.get_tab_idx_from_control(tab_control) == idx\
				)
			)
		)
		
		self.ready.connect(func() -> void:
			set_pressed_no_signal(
				tab_controls.any(func(tab_control: Control) -> bool: 
					return tab_container.get_tab_idx_from_control(tab_control) == tab_container.current_tab\
				)
			)
			add_theme_font_override("font", get_theme_font("main_button_font", "EditorFonts"))
			add_theme_font_size_override("font_size", get_theme_font_size("main_button_font_size", "EditorFonts"))
			
			var dot_size := 8.0
			_badge = _BadgeDot.new()
			_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			_badge.offset_left = -(dot_size + 2.0)
			_badge.offset_top = 4.0
			_badge.offset_right = -2.0
			_badge.offset_bottom = dot_size + 4.0
			_badge.visible = false
			add_child(_badge)
		)
	
	func set_has_badge(value: bool) -> void:
		if _badge != null:
			_badge.visible = value
	
	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			if _icon_name:
				self.icon = get_theme_icon(_icon_name, "EditorIcons")
