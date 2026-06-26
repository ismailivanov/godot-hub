class_name ConfirmationDialogAutoFree
extends ConfirmationDialog
## Confirmation dialog that auto-frees on close.


func _ready() -> void:
	visibility_changed.connect(func() -> void: 
		if not visible:
			queue_free()
	)
	confirmed.connect(func() -> void:
		queue_free()
	)
