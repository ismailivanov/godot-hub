class_name DownloadsContainer
extends ScrollContainer
## Container for displaying active download items.
##
## Automatically shows or hides based on whether download items are present.
## Applies theme styling to match the application theme.


@onready var hbox: HBoxContainer = $HBoxContainer


func _ready() -> void:
	var update_scroll_container_visibility := func() -> void:
		self.visible = hbox.get_child_count() > 0

	hbox.child_entered_tree.connect(func(_node: Node) -> void:
		update_scroll_container_visibility.call_deferred()
	)
	hbox.child_exiting_tree.connect(func(_node: Node) -> void:
		update_scroll_container_visibility.call_deferred()
	)
	update_scroll_container_visibility.call()

	theme_changed.connect(_update_theme)


func _update_theme() -> void:
	self.add_theme_stylebox_override("panel", get_theme_stylebox("panel", "Tree"))


func add_download_item(item: Control) -> void:
	hbox.add_child(item)
