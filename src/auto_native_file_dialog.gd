extends Node
## Automatically configures FileDialog nodes to use native dialogs.
##
## This node listens for FileDialog nodes being added to the scene tree
## and applies the native dialog setting from user configuration.


func _enter_tree() -> void:
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is FileDialog:
		(node as FileDialog).use_native_dialog = Config.use_native_file_dialog.ret() as bool
