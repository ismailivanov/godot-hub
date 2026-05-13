class_name ScanFileDialog
extends FileDialog
## File dialog for scanning directories.


## Emitted when dir to scan is selected.
signal dir_to_scan_selected(dir: String)


func _init() -> void:
	title = tr("Select a Folder to Scan")
	dir_selected.connect(func(dir: String) -> void:
		dir_to_scan_selected.emit(dir)
	)


func _ready() -> void:
	file_mode = FileDialog.FILE_MODE_OPEN_DIR
	access = FileDialog.ACCESS_FILESYSTEM
