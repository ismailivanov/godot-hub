class_name LocalRemoteEditorsSwitchContext
extends RefCounted
## Context for switching between local and remote editor views.


## Emitted when the item is changed.
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


func go_to_local() -> void:
	_tabs.current_tab = _tabs.get_tab_idx_from_control(_local)


func go_to_remote() -> void:
	_tabs.current_tab = _tabs.get_tab_idx_from_control(_remote)


func request_editor_download(
	version_hint: String, require_mono: bool, on_installed: Callable
) -> void:
	go_to_remote()
	editor_download_requested.emit(version_hint, require_mono, on_installed)


func local_is_selected() -> bool:
	return _tabs.current_tab == _tabs.get_tab_idx_from_control(_local)


func remote_is_selected() -> bool:
	return _tabs.current_tab == _tabs.get_tab_idx_from_control(_remote)
