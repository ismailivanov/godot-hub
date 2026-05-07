class_name NewProjectDialog
extends "res://src/components/projects/install_project_dialog/install_project_dialog.gd"

signal created(path: String)

@onready var _handler_option_button: OptionButton = %HandlerOptionButton
@onready var _custom_form_tabs: TabContainer = $VBoxContainer/CustomFormTabs

var _handler_godot4: NewProjectGodot4
var _handler_godot3: NewProjectGodot3
var _local_editors: LocalEditors.List


func setup_editors(editors: LocalEditors.List) -> void:
	if _local_editors != null:
		if _local_editors.editor_name_changed.is_connected(_on_editors_list_changed):
			_local_editors.editor_name_changed.disconnect(_on_editors_list_changed)
		if _local_editors.editor_removed.is_connected(_on_editors_list_changed):
			_local_editors.editor_removed.disconnect(_on_editors_list_changed)
	_local_editors = editors
	editors.editor_name_changed.connect(_on_editors_list_changed)
	editors.editor_removed.connect(_on_editors_list_changed)
	_refresh_version_dropdown()


func _on_editors_list_changed(_arg: Variant = null) -> void:
	_refresh_version_dropdown()


func _ready() -> void:
	super._ready()
	
	_handler_godot4 = NewProjectGodot4.new()
	_handler_godot3 = NewProjectGodot3.new()
	_add_handler_form(_handler_godot4)
	_add_handler_form(_handler_godot3)
	
	_handler_option_button.item_selected.connect(func(idx: int) -> void:
		var meta: Variant = _handler_option_button.get_item_metadata(idx)
		if meta is Dictionary:
			var md := meta as Dictionary
			_custom_form_tabs.current_tab = _custom_form_tabs.get_tab_idx_from_control(md["form"] as Control)
		_validate()
	)
	
	_successfully_confirmed.connect(func() -> void:
		var meta: Variant = _handler_option_button.get_item_metadata(_handler_option_button.selected)
		if meta is not Dictionary:
			return
		var md := meta as Dictionary
		if md.get("no_editor", false):
			return
		var handler := md.get("self") as NewProjectHandler
		if handler == null:
			return
		var ctx := NewProjectContext.new(self)
		ctx.dir = _project_path_line_edit.text.strip_edges()
		ctx.project_name = _project_name_edit.text.strip_edges()
		ctx.form = _custom_form_tabs.get_current_tab_control()
		handler.create_project(ctx)
	)

	_refresh_version_dropdown()


func _validate() -> void:
	super._validate()
	if get_ok_button().disabled:
		return
	if _handler_option_button.item_count <= 0:
		return
	var sel_meta: Variant = _handler_option_button.get_item_metadata(_handler_option_button.selected)
	if sel_meta is Dictionary and (sel_meta as Dictionary).get("no_editor", false):
		_error(tr("No editor installed."))


func _on_raise(args: Variant = null) -> void:
	_refresh_version_dropdown()
	_project_name_edit.grab_focus()
	_project_name_edit.select_all()


func _add_handler_form(handler: NewProjectHandler) -> void:
	var handler_form := handler.custom_form()
	handler_form.name = handler.label()
	_custom_form_tabs.add_child(handler_form)


func _form_for_handler(handler: NewProjectHandler) -> Control:
	if handler == _handler_godot4:
		return _custom_form_tabs.get_tab_control(0)
	return _custom_form_tabs.get_tab_control(1)


func _editor_major(editor: LocalEditors.Item) -> int:
	var ver := editor.get_version()
	if not ver.is_empty():
		var head := ver.split(".")[0].split("-")[0]
		if head.is_valid_int():
			var mv := int(head)
			if mv == 3 or mv == 4:
				return mv
	var parsed := VersionHint.parse(editor.version_hint)
	if parsed.is_valid and parsed.major_version.is_valid_int():
		var mj := int(parsed.major_version)
		if mj == 3 or mj == 4:
			return mj
	return -1


func _editor_option_label(editor: LocalEditors.Item) -> String:
	var ver := editor.get_version()
	if ver.is_empty():
		return editor.name
	return "%s (%s)" % [editor.name, ver]


func _editor_sort_before(a: LocalEditors.Item, b: LocalEditors.Item) -> bool:
	var ma := _editor_major(a)
	var mb := _editor_major(b)
	if ma != mb:
		return ma > mb
	var va := VersionHint.version_or_nothing(a.version_hint)
	var vb := VersionHint.version_or_nothing(b.version_hint)
	if va != vb:
		return va.naturalcasecmp_to(vb) > 0
	return a.name.naturalcasecmp_to(b.name) < 0


func _append_version_option(handler: NewProjectHandler, label_text: String, editor_path: String) -> void:
	_handler_option_button.add_item(label_text)
	_handler_option_button.set_item_metadata(
		_handler_option_button.item_count - 1,
		{
			"self": handler,
			"form": _form_for_handler(handler),
			"editor_path": editor_path,
			"no_editor": false,
		}
	)


func _append_no_editor_option() -> void:
	_handler_option_button.add_item(tr("No editor installed."))
	_handler_option_button.set_item_metadata(
		_handler_option_button.item_count - 1,
		{
			"self": null,
			"form": _form_for_handler(_handler_godot4),
			"editor_path": "",
			"no_editor": true,
		}
	)


func _refresh_version_dropdown() -> void:
	if _handler_godot4 == null:
		return
	var prev_path := ""
	if _handler_option_button.item_count > 0 and _handler_option_button.selected >= 0:
		var pd: Variant = _handler_option_button.get_item_metadata(_handler_option_button.selected)
		if pd is Dictionary:
			prev_path = str((pd as Dictionary).get("editor_path", ""))
	
	_handler_option_button.clear()
	
	if _local_editors == null:
		_append_no_editor_option()
		_select_version_by_editor_path(prev_path)
		_validate()
		return
	
	var ed_items: Array[LocalEditors.Item] = []
	for ed: LocalEditors.Item in _local_editors.all():
		if _local_editors.editor_is_valid(ed.path):
			ed_items.append(ed)
	ed_items.sort_custom(func(a: LocalEditors.Item, b: LocalEditors.Item) -> bool:
		return _editor_sort_before(a, b)
	)
	for ed: LocalEditors.Item in ed_items:
		var maj := _editor_major(ed)
		if maj == 4:
			_append_version_option(_handler_godot4, _editor_option_label(ed), ed.path)
		elif maj == 3:
			_append_version_option(_handler_godot3, _editor_option_label(ed), ed.path)
	if _handler_option_button.item_count == 0:
		_append_no_editor_option()
	_select_version_by_editor_path(prev_path)
	_validate()


func _select_version_by_editor_path(path: String) -> void:
	var idx := 0
	if not path.is_empty():
		for i: int in range(_handler_option_button.item_count):
			var pd: Variant = _handler_option_button.get_item_metadata(i)
			if pd is Dictionary and str((pd as Dictionary).get("editor_path", "")) == path:
				idx = i
				break
	_handler_option_button.select(idx)
	var meta: Variant = _handler_option_button.get_item_metadata(idx)
	if meta is Dictionary:
		var md := meta as Dictionary
		_custom_form_tabs.current_tab = _custom_form_tabs.get_tab_idx_from_control(md["form"] as Control)


class NewProjectContext:
	var _ctx_delegate: Object
	
	var dir: String
	var project_name: String
	var form: Control
	
	func _init(ctx_delegate: Object) -> void:
		_ctx_delegate = ctx_delegate
	
	func show_error(msg: String) -> void:
		_ctx_delegate.call("_error", msg)
	
	func emit_created(path: String) -> void:
		_ctx_delegate.call("hide")
		_ctx_delegate.emit_signal("created", path)


class NewProjectHandler:
	func custom_form() -> Control:
		return Control.new()
	
	func create_project(args: NewProjectContext) -> void: 
		pass
	
	func label() -> String:
		return ""


class NewProjectGodot3 extends NewProjectHandler:
	func custom_form() -> Control:
		return NewProjectGodot3Form.new()
	
	func create_project(ctx: NewProjectContext) -> void:
		var dir := ctx.dir
		var project_file_path := dir.path_join("project.godot")
		var form := ctx.form as NewProjectGodot3Form
		var initial_settings := ConfigFile.new()
		initial_settings.set_value("", "config_version", 4)
		initial_settings.set_value("application", "config/name", ctx.project_name)
		initial_settings.set_value("application", "config/icon", "res://icon.png")
		initial_settings.set_value("rendering", "quality/driver/driver_name", form.renderer_method())
		var err := initial_settings.save(project_file_path)
		if err:
			ctx.show_error("%s %s: %s." % [
				tr("Couldn't create project.godot in project path."), tr("Code"), err
			])
			return
		else:
			var img: Texture2D = preload("res://assets/default_project_icon.svg")
			img.get_image().save_png(dir.path_join("icon.png"))
			ctx.emit_created(project_file_path)
	
	func label() -> String:
		return "Godot 3.x"


class NewProjectGodot3Form extends VBoxContainer:
	var _renderer: RendererSelect
	
	func _init() -> void:
		_renderer = RendererSelect.new({
			"GLES3": {
				"label": tr("OpenGL ES 3.0"),
				"default": true,
				"desc": "\n".join([
					"•  " + tr("Higher visual quality") + ".",
					"•  " + tr("All features available") + ".",
					"•  " + tr("Incompatible with older hardware") + ".",
					"•  " + tr("Not recommended for web games") + ".",
				]),
			},
			"GLES2": {
				"label": tr("OpenGL ES 2.0"),
				"desc": "\n".join([
					"•  " + tr("Lower visual quality") + ".",
					"•  " + tr("Some features not available") + ".",
					"•  " + tr("Works on most hardware") + ".",
					"•  " + tr("Recommended for web games") + ".",
				]),
			},
		})
		
		add_child(_renderer)
		
		Comp.new(Label).on_init([
			CompInit.TEXT(tr("The renderer can be changed later, but scenes may need to be adjusted.")),
			CompInit.CUSTOM(func(label: Label) -> void:
				label.custom_minimum_size = Vector2(0, 40) * Config.EDSCALE
				label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				label.modulate = Color(1, 1, 1, 0.7)
				pass\
			)
		]).add_to(self)
	
	func renderer_method() -> String:
		return _renderer.current()


class NewProjectGodot4 extends NewProjectHandler:
	const ICON_SVG := """<svg height="128" width="128" xmlns="http://www.w3.org/2000/svg"><rect x="2" y="2" width="124" height="124" rx="14" fill="#363d52" stroke="#212532" stroke-width="4"/><g transform="scale(.101) translate(122 122)"><g fill="#fff"><path d="M105 673v33q407 354 814 0v-33z"/><path fill="#478cbf" d="m105 673 152 14q12 1 15 14l4 67 132 10 8-61q2-11 15-15h162q13 4 15 15l8 61 132-10 4-67q3-13 15-14l152-14V427q30-39 56-81-35-59-83-108-43 20-82 47-40-37-88-64 7-51 8-102-59-28-123-42-26 43-46 89-49-7-98 0-20-46-46-89-64 14-123 42 1 51 8 102-48 27-88 64-39-27-82-47-48 49-83 108 26 42 56 81zm0 33v39c0 276 813 276 813 0v-39l-134 12-5 69q-2 10-14 13l-162 11q-12 0-16-11l-10-65H447l-10 65q-4 11-16 11l-162-11q-12-3-14-13l-5-69z"/><path d="M483 600c3 34 55 34 58 0v-86c-3-34-55-34-58 0z"/><circle cx="725" cy="526" r="90"/><circle cx="299" cy="526" r="90"/></g><g fill="#414042"><circle cx="307" cy="532" r="60"/><circle cx="717" cy="532" r="60"/></g></g></svg>"""

	func custom_form() -> Control:
		return NewProjectGodot4Form.new()

	func create_project(ctx: NewProjectContext) -> void:
		var dir := ctx.dir
		var form := ctx.form as NewProjectGodot4Form
		var project_file_path := dir.path_join("project.godot")
		var initial_settings := ConfigFile.new()
		initial_settings.set_value("application", "config/name", ctx.project_name)
		initial_settings.set_value("application", "config/icon", "res://icon.svg")
		
		# rendering
		initial_settings.set_value("rendering", "renderer/rendering_method", form.renderer_method())
		if form.renderer_method() == "gl_compatibility":
			initial_settings.set_value("rendering", "renderer/rendering_method.mobile", "gl_compatibility")

		var err := initial_settings.save(project_file_path)
		if err:
			ctx.show_error("%s %s: %s." % [
				tr("Couldn't create project.godot in project path."), tr("Code"), err
			])
			return
		else:
			#vcs meta
			if form.vsc_meta() == "git":
				var gitignore := FileAccess.open(dir.path_join(".gitignore"), FileAccess.WRITE)
				if gitignore != null:
					gitignore.store_line("# Godot 4+ specific ignores")
					gitignore.store_line(".godot/")
					gitignore.close()
				else:
					ctx.show_error(tr("Couldn't create .gitignore in project path."))
					return
			
				var gitattributes := FileAccess.open(dir.path_join(".gitattributes"), FileAccess.WRITE)
				if gitattributes != null:
					gitattributes.store_line("# Normalize EOL for all files that Git considers text files.")
					gitattributes.store_line("* text=auto eol=lf")
					gitattributes.close()
				else:
					ctx.show_error(tr("Couldn't create .gitattributes in project path."))
					return

			# icon
			var file_to := FileAccess.open(dir.path_join("icon.svg"), FileAccess.WRITE)
			file_to.store_string(ICON_SVG)
			file_to.close()

			ctx.emit_created(project_file_path)
	
	func label() -> String:
		return "Godot 4.x"


class NewProjectGodot4Form extends VBoxContainer:
	var _renderer: RendererSelect
	var _vcs_meta: VersionControlMetadata

	func _init() -> void:
		_renderer = RendererSelect.new({
			"forward_plus": {
				"label": tr("Forward+"),
				"default": true,
				"desc": "\n".join([
					"•  " + tr("Supports desktop platforms only."),
					"•  " + tr("Advanced 3D graphics available."),
					"•  " + tr("Can scale to large complex scenes."),
					"•  " + tr("Uses RenderingDevice backend."),
					"•  " + tr("Slower rendering of simple scenes."),
				]),
			},
			"mobile": {
				"label": tr("Mobile"),
				"desc": "\n".join([
					"•  " + tr("Supports desktop + mobile platforms."),
					"•  " + tr("Less advanced 3D graphics."),
					"•  " + tr("Less scalable for complex scenes."),
					"•  " + tr("Uses RenderingDevice backend."),
					"•  " + tr("Fast rendering of simple scenes."),
				]),
			},
			"gl_compatibility": {
				"label": tr("Compatibility"),
				"desc": "\n".join([
					"•  " + tr("Supports desktop, mobile + web platforms."),
					"•  " + tr("Least advanced 3D graphics (currently work-in-progress)."),
					"•  " + tr("Intended for low-end/older devices."),
					"•  " + tr("Uses OpenGL 3 backend (OpenGL 3.3/ES 3.0/WebGL2)."),
					"•  " + tr("Fastest rendering of simple scenes."),
				]),
			}
		})
		
		add_child(_renderer)
		
		Comp.new(Label).on_init([
			CompInit.TEXT(tr("The renderer can be changed later, but scenes may need to be adjusted.")),
			CompInit.CUSTOM(func(label: Label) -> void:
				label.custom_minimum_size = Vector2(0, 40) * Config.EDSCALE
				label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				label.modulate = Color(1, 1, 1, 0.7)
				pass\
			)
		]).add_to(self)
		
		_vcs_meta = VersionControlMetadata.new()
		add_child(_vcs_meta)
	
	func renderer_method() -> String:
		return _renderer.current()
	
	func vsc_meta() -> String:
		return _vcs_meta.current()


class VersionControlMetadata extends HBoxContainer:
	var _options: OptionButton
	
	func _init() -> void:
		var label := Label.new()
		label.text = tr("Version Control Metadata:")
		
		_options = OptionButton.new()
		_options.add_item("Git")
		_options.set_item_metadata(_options.item_count - 1, "git")
		
		_options.add_item("None")
		_options.set_item_metadata(_options.item_count - 1, "none")
		
		add_child(label)
		add_child(_options)
	
	func current() -> String:
		return _options.get_item_metadata(_options.selected) as String



class RendererSelect extends VBoxContainer:
	var _button_group := ButtonGroup.new()
	
	func _init(options: Dictionary) -> void:
		var renderer_desc_label := CompRefs.Simple.new()

		_button_group.pressed.connect(func(btn: BaseButton) -> void:
			var label := renderer_desc_label.value as Label
			var renderer_type := btn.get_meta("rendering_method") as String
			label.text = options.get(renderer_type, {"desc": "•  Unknown renderer"})["desc"]
			,
			CONNECT_DEFERRED
		)

		var checkboxes := []
		for key: String in options.keys():
			checkboxes.append(
				Comp.new(CheckBox).on_init([
					CompInit.TEXT((options[key] as Dictionary)["label"] as String),
					CompInit.SET_BUTTON_GROUP(_button_group),
					CompInit.SET_META("rendering_method", key),
					CompInit.CUSTOM(func(c: CheckBox) -> void:
						var is_default := (options[key] as Dictionary).get("default", false) as bool
						c.button_pressed = is_default
						pass\
					)
				])
			)

		Comp.new(VBoxContainer, [
			Comp.new(Label).on_init([
				CompInit.TEXT(tr("Renderer:"))
			]),
			
			Comp.new(HBoxContainer, [
				# checkboxes
				Comp.new(VBoxContainer, checkboxes),
				
				Comp.new(VSeparator),
				
				# checkbox desc
				Comp.new(VBoxContainer, [
					Comp.new(Label).on_init([
						CompInit.CUSTOM(func(l: Label) -> void:
							l.modulate = Color(1, 1, 1, 0.7)
							pass\
						)
					]).ref(renderer_desc_label)
				]).on_init([
					CompInit.SIZE_FLAGS_HORIZONTAL_EXPAND_FILL()
				]),
			]),
		]).add_to(self)
	
	func current() -> String:
		return _button_group.get_pressed_button().get_meta("rendering_method")
