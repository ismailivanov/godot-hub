class_name GodotsInstall
extends RefCounted
## Installs Godot Hub updates and delegates AUR-managed installs to an AUR helper.


class I:
	func cleanup_previous_update() -> void:
		pass

	func is_system_managed() -> bool:
		return false

	func install_system_update() -> bool:
		return false

	func install(_abs_zip_path: String) -> Error:
		return ERR_UNAVAILABLE


class Default extends I:
	const uuid = preload("res://addons/uuid.gd")
	const AUR_PACKAGE := "godot-hub-bin"

	var _current_exe_path: String
	var _tree: SceneTree

	func _init(current_exe_path: String, tree: SceneTree) -> void:
		_current_exe_path = current_exe_path
		_tree = tree

	func cleanup_previous_update() -> void:
		var old_exe := _current_exe_path + ".old"
		if FileAccess.file_exists(old_exe):
			DirAccess.remove_absolute(old_exe)

	func is_system_managed() -> bool:
		if not OS.has_feature("linux"):
			return false
		var output: Array = []
		return (
			OS.execute("pacman", ["-Qo", _current_exe_path], output, true) == 0
			and AUR_PACKAGE in "\n".join(output)
		)

	func install_system_update() -> bool:
		var helper := _find_program(["yay", "paru", "pikaur", "trizen"])
		var terminal := _find_program([
			"xdg-terminal-exec", "konsole", "gnome-terminal", "xfce4-terminal",
			"foot", "kitty", "alacritty", "xterm",
		])
		if helper.is_empty() or terminal.is_empty():
			return false

		var update_dir := _new_update_dir()
		var script_path := update_dir.path_join("aur-update.sh")
		if not _write_file(script_path, """#!/bin/sh
helper="$1"
pid="$2"
executable="$3"
"$helper" -S --needed godot-hub-bin
status=$?
if [ "$status" -eq 0 ]; then
	kill -TERM "$pid" 2>/dev/null || true
	while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
	nohup "$executable" >/dev/null 2>&1 &
	rm -rf "$(dirname "$0")"
else
	printf '\nGodot Hub update failed. Press Enter to close.\n'
	read -r _
fi
exit "$status"
"""):
			return false
		OS.execute("chmod", ["+x", script_path])

		var command: PackedStringArray = ["sh", script_path, helper, str(OS.get_process_id()), _current_exe_path]
		var args := command
		match terminal.get_file():
			"gnome-terminal":
				args = PackedStringArray(["--"] + Array(command))
			"xfce4-terminal":
				args = PackedStringArray(["-x"] + Array(command))
			"xdg-terminal-exec":
				pass
			_:
				args = PackedStringArray(["-e"] + Array(command))
		return OS.create_process(terminal, args) > 0

	func install(abs_zip_path: String) -> Error:
		var update_dir := _new_update_dir()
		var unzip_error := zip.unzip(abs_zip_path, update_dir)
		if unzip_error != OK:
			return unzip_error

		if OS.has_feature("windows"):
			return _install_windows(update_dir)
		if OS.has_feature("macos"):
			return _install_macos(update_dir)
		if OS.has_feature("linux"):
			return _install_linux(update_dir)
		return ERR_UNAVAILABLE

	func _install_windows(update_dir: String) -> Error:
		var downloaded_exe := update_dir.path_join("GodotHub.exe")
		if not FileAccess.file_exists(downloaded_exe):
			return ERR_FILE_NOT_FOUND
		var script_path := update_dir.path_join("apply-update.ps1")
		if not _write_file(script_path, """param(
	[int]$PidToWait,
	[string]$CurrentExe,
	[string]$NewExe,
	[string]$UpdateDir
)
Wait-Process -Id $PidToWait -ErrorAction SilentlyContinue
$OldExe = "$CurrentExe.old"
Remove-Item -LiteralPath $OldExe -Force -ErrorAction SilentlyContinue
Move-Item -LiteralPath $CurrentExe -Destination $OldExe -Force
try {
	Move-Item -LiteralPath $NewExe -Destination $CurrentExe -Force
	Start-Process -FilePath $CurrentExe
	Remove-Item -LiteralPath $OldExe -Force -ErrorAction SilentlyContinue
	Remove-Item -LiteralPath $UpdateDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
	if ((Test-Path -LiteralPath $OldExe) -and !(Test-Path -LiteralPath $CurrentExe)) {
		Move-Item -LiteralPath $OldExe -Destination $CurrentExe -Force
	}
	throw
}
"""):
			return ERR_CANT_CREATE
		var process_id := OS.create_process("powershell.exe", [
			"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path,
			str(OS.get_process_id()), _current_exe_path, downloaded_exe, update_dir,
		])
		if process_id <= 0:
			return ERR_CANT_FORK
		_tree.quit()
		return OK

	func _install_macos(update_dir: String) -> Error:
		var nested_zip := update_dir.path_join("GodotHub.zip")
		if FileAccess.file_exists(nested_zip):
			var nested_error := zip.unzip(nested_zip, update_dir)
			if nested_error != OK:
				return nested_error
		var downloaded_app := update_dir.path_join("GodotHub.app")
		var current_app := _current_exe_path.get_base_dir().get_base_dir().get_base_dir()
		if not current_app.ends_with(".app") or not DirAccess.dir_exists_absolute(downloaded_app):
			return ERR_FILE_NOT_FOUND
		var script_path := update_dir.path_join("apply-update.sh")
		if not _write_file(script_path, """#!/bin/sh
pid="$1"
current_app="$2"
new_app="$3"
update_dir="$4"
while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
old_app="${current_app}.old"
rm -rf "$old_app"
mv "$current_app" "$old_app" || exit 1
if mv "$new_app" "$current_app"; then
	open "$current_app"
	rm -rf "$old_app" "$update_dir"
else
	mv "$old_app" "$current_app"
	exit 1
fi
"""):
			return ERR_CANT_CREATE
		OS.execute("chmod", ["+x", script_path])
		var process_id := OS.create_process("sh", [
			script_path, str(OS.get_process_id()), current_app, downloaded_app, update_dir,
		])
		if process_id <= 0:
			return ERR_CANT_FORK
		_tree.quit()
		return OK

	func _install_linux(update_dir: String) -> Error:
		var downloaded_exe := update_dir.path_join("GodotHub.x86_64")
		if not FileAccess.file_exists(downloaded_exe):
			return ERR_FILE_NOT_FOUND
		OS.execute("chmod", ["+x", downloaded_exe])
		var script_path := update_dir.path_join("apply-update.sh")
		if not _write_file(script_path, """#!/bin/sh
pid="$1"
current_exe="$2"
new_exe="$3"
update_dir="$4"
while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
old_exe="${current_exe}.old"
rm -f "$old_exe"
mv "$current_exe" "$old_exe" || exit 1
if mv "$new_exe" "$current_exe"; then
	chmod +x "$current_exe"
	nohup "$current_exe" >/dev/null 2>&1 &
	rm -f "$old_exe"
	rm -rf "$update_dir"
else
	mv "$old_exe" "$current_exe"
	exit 1
fi
"""):
			return ERR_CANT_CREATE
		OS.execute("chmod", ["+x", script_path])
		var process_id := OS.create_process("sh", [
			script_path, str(OS.get_process_id()), _current_exe_path, downloaded_exe, update_dir,
		])
		if process_id <= 0:
			return ERR_CANT_FORK
		_tree.quit()
		return OK

	func _new_update_dir() -> String:
		var path := ProjectSettings.globalize_path(
			(Config.UPDATES_PATH.ret() as String).path_join("godot-hub-update-%s" % uuid.v4().substr(0, 8))
		)
		DirAccess.make_dir_recursive_absolute(path)
		return path

	func _write_file(path: String, content: String) -> bool:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(content)
		file.close()
		return true

	func _find_program(names: Array[String]) -> String:
		for name in names:
			var output: Array = []
			if OS.execute("which", [name], output, true) == 0 and not output.is_empty():
				return str(output[0]).strip_edges()
		return ""


class Forbidden extends I:
	var _node: Node

	func _init(node: Node) -> void:
		_node = node

	func install(_abs_zip_path: String) -> Error:
		var dialog := ConfirmationDialogAutoFree.new()
		dialog.title = tr("Alert!")
		dialog.dialog_text = tr("Installing is forbidden!")
		_node.add_child(dialog)
		dialog.popup_centered()
		return ERR_UNAUTHORIZED
