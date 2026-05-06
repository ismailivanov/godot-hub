class_name RemoteEditorsControl
extends Control

signal installed(name: String, abs_path: String)
signal recommended_stable_download_busy(busy: bool)

const MIRROR_GITHUB_ID = 0
const MIRROR_DEFAULT = MIRROR_GITHUB_ID

const uuid = preload("res://addons/uuid.gd")

@export var _editor_download_scene : PackedScene
@export var _editor_install_scene : PackedScene
@export var _remote_editor_direct_link_scene : PackedScene

@onready var _open_downloads_button: Button = %OpenDownloadsButton
@onready var _direct_link_button: Button = %DirectLinkButton
@onready var _refresh_button: Button = %RefreshButton
@onready var _remote_editors_tree := %RemoteEditorsTree as RemoteEditorsTreeControl
@onready var _tree_mirror_button: = %TreeMirrorButton as OptionButton

var _editor_downloads: DownloadsContainer
var _stable_download_busy := false
var _tree_mirrors: Dictionary[int, RemoteEditorsTreeDataSource.I] = {}
var _active_mirror_cache := Cache.smart_value(
	self, "active_mirror", true
).map_return_value(func(v: Variant) -> Variant:
	if not v in _tree_mirrors:
		return MIRROR_DEFAULT
	else:
		return v
)


func init(editor_downloads: DownloadsContainer) -> void:
	_editor_downloads = editor_downloads


func set_has_installed_editors(has_any: bool) -> void:
	_remote_editors_tree.set_has_installed_editors(has_any)


func force_reset_recommended_stable_state() -> void:
	_stable_download_busy = false
	_remote_editors_tree.set_recommended_stable_button_disabled(false)
	recommended_stable_download_busy.emit(false)


## Re-enable recommended-stable buttons after reopening a tab/window if no download is in flight.
func sync_stable_download_buttons_if_idle() -> void:
	if _stable_download_busy:
		return
	_remote_editors_tree.set_recommended_stable_button_disabled(false)
	recommended_stable_download_busy.emit(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		sync_stable_download_buttons_if_idle()


func _ready() -> void:
	(%SectionTitle as Label).text = tr("Installs")
	_tree_mirrors[MIRROR_GITHUB_ID] = RemoteEditorsTreeDataSourceGithub.Self.new(
		RemoteEditorsTreeDataSource.RemoteAssetsCallable.new(download_zip)
	)
	
	_tree_mirror_button.add_item("GitHub", MIRROR_GITHUB_ID)
	_tree_mirror_button.selected = _tree_mirror_button.get_item_index(
		_active_mirror_cache.ret(MIRROR_DEFAULT) as int
	)
	_tree_mirror_button.item_selected.connect(_on_mirror_selected)
	
	_open_downloads_button.pressed.connect(func() -> void:
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(Config.DOWNLOADS_PATH.ret() as String))
	)
	_open_downloads_button.icon = get_theme_icon("Load", "EditorIcons")
	_open_downloads_button.tooltip_text = tr("Open Downloads Dir")
	
	_direct_link_button.icon = get_theme_icon("AssetLib", "EditorIcons")
	_direct_link_button.pressed.connect(func() -> void:
		var link_dialog: RemoteEditorDirectLinkControl = _remote_editor_direct_link_scene.instantiate()
		add_child(link_dialog)
		link_dialog.popup_centered()
		link_dialog.link_confirmed.connect(func(link: String) -> void:
			download_zip(link, "custom_editor.zip")
		)
	)
	
	_refresh_button.icon = get_theme_icon("Reload", "EditorIcons")
	_refresh_button.tooltip_text = tr("Refresh")
	#_refresh_button.self_modulate = Color(1, 1, 1, 0.6)
	_remote_editors_tree.post_ready(_refresh_button)
	_remote_editors_tree.recommended_stable_download_requested.connect(request_latest_stable_editor_download)
	var cached_mirror_id := _active_mirror_cache.ret(MIRROR_DEFAULT) as int
	await _remote_editors_tree.set_data_source(_tree_mirrors[cached_mirror_id])


func request_latest_stable_editor_download() -> void:
	if _stable_download_busy:
		return
	_set_stable_download_busy(true)
	var info := await RemoteEditorsTreeDataSourceGithub.async_latest_stable_editor_download_for_this_os()
	if info.is_empty():
		_set_stable_download_busy(false)
		var accept_dialog := AcceptDialog.new()
		accept_dialog.visibility_changed.connect(func() -> void:
			if not accept_dialog.visible:
				accept_dialog.queue_free()
		)
		accept_dialog.dialog_text = tr("Could not find a stable editor download for this platform.")
		add_child(accept_dialog)
		accept_dialog.popup_centered()
		return
	var finish_busy := func() -> void:
		_set_stable_download_busy(false)
	download_zip(info["url"] as String, info["file_name"] as String, finish_busy)


func _set_stable_download_busy(busy: bool) -> void:
	if _stable_download_busy == busy:
		return
	_stable_download_busy = busy
	_remote_editors_tree.set_recommended_stable_button_disabled(busy)
	recommended_stable_download_busy.emit(busy)


func _on_mirror_selected(item_idx: int) -> void:
	var item_id := _tree_mirror_button.get_item_id(item_idx)
	if item_id in _tree_mirrors:
		await _remote_editors_tree.set_data_source(_tree_mirrors[item_id])
		_active_mirror_cache.put(item_id)


func download_zip(
	url: String,
	file_name: String,
	on_http_terminal: Callable = Callable(),
) -> void:
	var editor_download: AssetDownload = _editor_download_scene.instantiate()
	_editor_downloads.add_download_item(editor_download)
	var http_terminal := func() -> void:
		if on_http_terminal.is_valid():
			on_http_terminal.call()
	editor_download.download_failed.connect(http_terminal, CONNECT_ONE_SHOT)
	editor_download.downloaded.connect(http_terminal, CONNECT_ONE_SHOT)
	editor_download.request_failed.connect(http_terminal, CONNECT_ONE_SHOT)
	editor_download.start(
		url, (Config.DOWNLOADS_PATH.ret() as String) + "/", file_name
	)
	editor_download.download_failed.connect(func(response_code: int) -> void:
		Output.push(
			"Failed to download editor: %s" % response_code
		)
	)
	editor_download.downloaded.connect(func(abs_path: String) -> void:
		install_zip(
			abs_path, 
			file_name.replace(".zip", "").replace(".", "_"), 
			utils.guess_editor_name(file_name.replace(".zip", "")),
			func() -> void: editor_download.queue_free()
		)
	)


## on_install: Optional[Callbale]
func install_zip(zip_abs_path: String, root_unzip_folder_name: String, possible_editor_name: String, on_install:Variant=null) -> void:
	var zip_content_dir := _unzip_downloaded(zip_abs_path, root_unzip_folder_name)
	if not DirAccess.dir_exists_absolute(zip_content_dir):
		var accept_dialog := AcceptDialog.new()
		accept_dialog.visibility_changed.connect(func() -> void:
			if not accept_dialog.visible:
				accept_dialog.queue_free()
		)
		accept_dialog.dialog_text = tr("Error extracting archive.")
		add_child(accept_dialog)
		accept_dialog.popup_centered()
	else:
		var editor_install: RemoteEditorInstallControl = _editor_install_scene.instantiate()
		add_child(editor_install)
		editor_install.init(possible_editor_name, zip_content_dir)
		editor_install.installed.connect(func(p_name: String, exec_path: String) -> void:
			installed.emit(p_name, ProjectSettings.globalize_path(exec_path))
			if on_install:
				(on_install as Callable).call()
		)
		editor_install.popup_centered()


func _unzip_downloaded(downloaded_abs_path: String, root_unzip_folder_name: String) -> String:
	var zip_content_dir := "%s/%s" % [Config.VERSIONS_PATH.ret(), root_unzip_folder_name]
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(zip_content_dir)):
		zip_content_dir += "-%s" % uuid.v4().substr(0, 8)
	zip_content_dir += "/"
	zip.unzip(downloaded_abs_path, zip_content_dir)
	return zip_content_dir
