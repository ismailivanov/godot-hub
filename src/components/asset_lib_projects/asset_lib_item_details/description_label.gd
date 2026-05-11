class_name AssetLibDetailsDescriptionLabel
extends RichTextLabel



func _ready() -> void:
	meta_clicked.connect(func(meta: Variant) -> void:
		OS.shell_open(str(meta))
	)


func configure(item: AssetLib.Item) -> void:
	clear()
	append_text(item.description)
	set_selection_enabled(true)
	set_context_menu_enabled(true)
