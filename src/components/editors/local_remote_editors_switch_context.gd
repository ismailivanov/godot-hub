class_name LocalRemoteEditorsSwitchContext
extends RefCounted
## Routes editor requests between the Installs page and the Install Editor modal.
##
## The modal is used through open(), close(), is_open() and its closed signal
## (the RemoteEditorsControl API), so tests can pass a stand-in.


## Emitted when the selected page changes or the modal opens or closes.
signal changed
## Emitted when a project requests an editor download.
signal editor_download_requested(version_hint: String, require_mono: bool, on_installed: Callable)

var _local: Control
var _remote: Control
var _tabs: TabContainer


func _init(local: Control, remote: Control, tabs: TabContainer) -> void:
	_local = local
	_remote = remote
	_tabs = tabs

	_tabs.tab_changed.connect(func(_idx: int) -> void:
		changed.emit()
	)
	_remote.connect(&"closed", func() -> void:
		changed.emit()
	)


## Closes the Install Editor modal and shows the Installs page.
func go_to_local() -> void:
	if remote_is_selected():
		_remote.call(&"close")
	_select_installs()


## Shows the Installs page with the Install Editor modal open over it.
func go_to_remote() -> void:
	_select_installs()
	if not remote_is_selected():
		_remote.call(&"open")
		changed.emit()


## Shows the Installs page, where the download row appears, then forwards the request.
func request_editor_download(
	version_hint: String, require_mono: bool, on_installed: Callable
) -> void:
	go_to_local()
	editor_download_requested.emit(version_hint, require_mono, on_installed)


## Whether the Installs page is shown without the modal over it.
func local_is_selected() -> bool:
	return _tabs.get_current_tab_control() == _local and not remote_is_selected()


## Whether the Install Editor modal is open.
func remote_is_selected() -> bool:
	return _remote.call(&"is_open") as bool


func _select_installs() -> void:
	_tabs.current_tab = _tabs.get_tab_idx_from_control(_local)
