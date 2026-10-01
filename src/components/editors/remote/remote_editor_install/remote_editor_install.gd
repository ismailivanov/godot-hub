class_name RemoteEditorInstallControl
extends ConfirmationDialog
## Dialog for installing downloaded remote editors.
##
## Downloads install without it when [method find_editor_executable] finds their
## editor and a name tells its version; [method RemoteEditorsControl.install_zip] says
## when it asks instead.


## Emitted when installed.
signal installed(editor_name: String, editor_exec_path: String)

@onready var _editor_name_edit: LineEdit = %EditorNameEdit
@onready var _select_exec_file_tree: Tree = %SelectExecFileTree
@onready var _show_all_check_box := %ShowAllCheckBox as CheckBox

var _dir_content: Array[edir.DirListResult]


func _ready() -> void:
	_select_exec_file_tree.custom_minimum_size = Vector2(350, 150) * Config.EDSCALE
	_select_exec_file_tree.select_mode = Tree.SELECT_SINGLE
	_select_exec_file_tree.item_selected.connect(func() -> void:
		var root := _select_exec_file_tree.get_root()
		var selected := _select_exec_file_tree.get_selected()
		if root:
			for c in root.get_children():
				if c == selected:
					continue
				c.set_checked(0, false)
	)
	_show_all_check_box.toggled.connect(func(_a: bool) -> void:
		_setup_editor_select_tree()
	)


func init(editor_name: String, editor_exec_path: String) -> void:
	assert(editor_exec_path.ends_with("/"))
	Output.push("Installing editor: %s" % editor_exec_path)
	_dir_content = edir.list_recursive(editor_exec_path)
	_editor_name_edit.text = editor_name
	_select_exec_file_tree.show()
	_setup_editor_select_tree()


## Returns the path of the editor to run on [param os_name] (as [method OS.get_name]
## names it) in [param dir_content], the files of an extracted editor download: an
## [code].app[/code] folder on macOS, an [code].exe[/code] other than the console one
## on Windows, a binary named for its architecture on Linux, such as
## [code].x86_64[/code], [code].arm64[/code] or [code].64[/code]. Files
## [method is_named_like_editor] come first, then the ones closest to the archive's root;
## the .NET runtime in GodotSharp and the metadata of macOS archivers never count.
## Returns an empty string when there is no such file, or when two fit as well, e.g.
## builds for two architectures.
static func find_editor_executable(
	dir_content: Array[edir.DirListResult], os_name: String
) -> String:
	# Folders are matched inside the archive, whatever the versions folder is called.
	var root := _root_of(dir_content)
	var best_path := ""
	var best_rank := Vector2i.ZERO
	var tied := false
	for x in dir_content:
		if not _is_editor_candidate(x, os_name, root):
			continue
		var rank := _editor_rank(x)
		if best_path.is_empty() or rank < best_rank:
			best_path = x.path
			best_rank = rank
			tied = false
		elif rank == best_rank:
			tied = true
	return "" if tied else best_path


## Whether the editor build at [param path] is named like the Godot and Redot ones, e.g.
## [code]Godot_v4.7.2-stable_linux.x86_64[/code] or [code]Godot_mono.app[/code], unlike
## a game exported for the same platform.
static func is_named_like_editor(path: String) -> bool:
	var file_name := path.get_file().to_lower()
	return file_name.begins_with("godot") or file_name.begins_with("redot")


func _setup_editor_select_tree() -> void:
	_select_exec_file_tree.clear()
	var root := _select_exec_file_tree.create_item()
	var os_name := OS.get_name()
	var listed: Array[edir.DirListResult] = []
	for x in _dir_content:
		if _fits_platform(x, os_name):
			listed.append(x)
	# Elsewhere, or when the editor is named otherwise (e.g. a custom build ending in
	# .mono), any file may be it.
	if listed.is_empty():
		for x in _dir_content:
			if x.is_file:
				listed.append(x)
	# Checks what an install without this dialog would use, if anything.
	var editor_path := find_editor_executable(_dir_content, os_name)
	for x in listed:
		var item := _select_exec_file_tree.create_item(root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_text(0, x.file)
		item.set_editable(0, true)
		item.set_meta("full_path", x.path)
		if x.path == editor_path:
			item.set_checked(0, true)
			item.select(0)


## Whether [param x] has the form of an editor build for [param os_name].
static func _fits_platform(x: edir.DirListResult, os_name: String) -> bool:
	var extension := x.extension.to_lower()
	match os_name:
		"macOS":
			return x.is_dir and extension == "app"
		"Windows":
			return x.is_file and extension == "exe"
		"Linux":
			# x86_64, arm64, x86_32 and arm32, or 64 and 32 for 3.x and older: never
			# the .pck, .so or .dll files next to an editor.
			return x.is_file and (extension.contains("32") or extension.contains("64"))
	return false


## Whether [param x], listed in the folder [param root], can be the editor
## [method find_editor_executable] looks for.
static func _is_editor_candidate(
	x: edir.DirListResult, os_name: String, root: String
) -> bool:
	if not _fits_platform(x, os_name):
		return false
	# The folders from the root to x, each with slashes around it.
	var path := "/" + x.path.trim_prefix(root).trim_prefix("/") + "/"
	return not (
		x.file.begins_with(".")
		or x.file.to_lower().contains("console")
		or path.contains("/GodotSharp/")
		or path.contains("/__MACOSX/")
	)


## The folder [param dir_content] lists, as [method edir.list_recursive] lists it: the
## one holding its shallowest entry.
static func _root_of(dir_content: Array[edir.DirListResult]) -> String:
	var root := ""
	var depth := -1
	for x in dir_content:
		var x_depth := x.path.count("/")
		if depth == -1 or x_depth < depth:
			root = x.path.get_base_dir()
			depth = x_depth
	return root


## Orders the editors [method find_editor_executable] finds, the best first: those
## [method is_named_like_editor], then those closest to the root.
static func _editor_rank(x: edir.DirListResult) -> Vector2i:
	return Vector2i(0 if is_named_like_editor(x.path) else 1, x.path.count("/"))


func _process(delta: float) -> void:
	var ok_disabled := true
	var selected := _select_exec_file_tree.get_selected()
	if selected and selected.is_checked(0):
		ok_disabled = false
	get_ok_button().disabled = ok_disabled


func _on_confirmed() -> void:
	var selected_item := _select_exec_file_tree.get_selected()
	if not (selected_item and selected_item.is_checked(0)):
		return
	var path := selected_item.get_meta("full_path") as String
	# TODO validate data ???
	installed.emit(_editor_name_edit.text, path)
	queue_free()


func _on_canceled() -> void:
	queue_free()
