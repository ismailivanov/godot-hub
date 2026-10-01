class_name EditorDownloadsArea
extends VBoxContainer
## Editor downloads shown as full-width rows at the top of the Installs list.
##
## Hides itself while it holds no rows. Download cards are restyled as list rows:
## framed like the list with the Hub's rounded corners, a bold title and a thin
## progress bar, like the export templates line of the editor rows below.


func _ready() -> void:
	# Deferred so a row that is leaving has already been removed when counting.
	child_entered_tree.connect(func(_node: Node) -> void:
		_update_visibility.call_deferred()
	)
	child_exiting_tree.connect(func(_node: Node) -> void:
		_update_visibility.call_deferred()
	)
	# Deferred: theme_changed comes before the cached theme items are dropped.
	theme_changed.connect(_restyle_rows, CONNECT_DEFERRED)
	_update_visibility()


## Adds a download card (an AssetDownload) as a full-width row.
func add_download_item(item: Control) -> void:
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# After _ready, which sets the card's asset library look and size.
	add_child(item)
	if item is AssetDownload:
		_style_as_row(item)


func _restyle_rows() -> void:
	for child in get_children():
		if child is AssetDownload:
			_style_as_row(child as Control)


func _style_as_row(item: Control) -> void:
	# As tall as its content, like the editor rows below it.
	item.custom_minimum_size = Vector2.ZERO
	var panel := ThemeCorners.rounded(get_theme_stylebox("search_panel", "ProjectManager"), self)
	item.add_theme_stylebox_override("panel", panel)
	(item.get_node("%TitleLabel") as Label).theme_type_variation = &"HeaderSmall"
	# The status line says the percentage instead.
	ThemeCorners.style_thin_progress_bar(item.get_node("%ProgressBar") as ProgressBar, self)


func _update_visibility() -> void:
	visible = get_child_count() > 0
