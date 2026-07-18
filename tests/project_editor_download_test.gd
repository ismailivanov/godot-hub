extends Node

var _failures := 0


func _ready() -> void:
	_test_version_hint_parsing()
	_test_download_target()
	_test_platform_asset_selection()
	_test_project_editor_compatibility()
	if _failures > 0:
		get_tree().quit(1)
		return
	print("Project editor download tests passed.")
	get_tree().quit()


func _test_version_hint_parsing() -> void:
	var parsed := VersionHint.parse("Godot v4.7 stable")
	_check(parsed.is_valid, "Expected a valid version hint")
	_check(parsed.version == "4.7", "Expected version 4.7")
	_check(parsed.stage == "stable", "Expected stable release")
	_check(not VersionHint.parse("custom editor").is_valid, "Expected invalid custom hint")


func _test_download_target() -> void:
	var target := RemoteEditorsTreeDataSourceGithub.download_target_from_version_hint(
		"Godot v4.7 rc2 mono"
	)
	_check(str(target.get("version")) == "4.7", "Expected download version 4.7")
	_check(str(target.get("release")) == "rc2", "Expected rc2 download")
	_check(target.get("mono") is bool, "Expected a boolean Mono flag")
	if target.get("mono") is bool:
		var wants_mono: bool = target["mono"]
		_check(wants_mono, "Expected Mono download")
	_check(
		RemoteEditorsTreeDataSourceGithub.download_target_from_version_hint(
			"custom editor"
		).is_empty(),
		"Expected no target for an invalid hint",
	)


func _test_platform_asset_selection() -> void:
	var assets: Array[RemoteEditorsTreeDataSourceGithub.GodotAsset] = [
		_asset("Godot_v4.7-stable_linux.x86_64.zip"),
		_asset("Godot_v4.7-stable_mono_linux_x86_64.zip"),
	]
	var suffixes: Array[String] = ["_linux.x86_64.zip", "_linux_x86_64.zip"]
	var standard := RemoteEditorsTreeDataSourceGithub.pick_platform_asset(
		assets, suffixes, false
	)
	var mono := RemoteEditorsTreeDataSourceGithub.pick_platform_asset(
		assets, suffixes, true
	)
	_check(standard != null, "Expected a standard platform asset")
	_check(mono != null, "Expected a Mono platform asset")
	if standard != null:
		_check(
			standard.name == "Godot_v4.7-stable_linux.x86_64.zip",
			"Selected the wrong standard asset",
		)
	if mono != null:
		_check(
			mono.name == "Godot_v4.7-stable_mono_linux_x86_64.zip",
			"Selected the wrong Mono asset",
		)


func _test_project_editor_compatibility() -> void:
	var installed_options := [{
		"label": "Godot v4.7 stable",
		"path": "/tmp/Godot",
		"version_hint": "Godot v4.7 stable",
	}]
	_check(
		not ProjectListItemControl.installed_options_match_project(
			installed_options, "4.6-stable", false
		),
		"Expected the required-version download option when installed editors mismatch",
	)
	_check(
		ProjectListItemControl.editor_matches_project(
			"4.7-stable", "Godot v4.7 stable", false
		),
		"Expected the matching installed editor to be accepted",
	)
	_check(
		not ProjectListItemControl.editor_matches_project(
			"4.6-stable", "Godot v4.7 stable", false
		),
		"Expected a different editor version to be rejected",
	)
	_check(
		not ProjectListItemControl.editor_matches_project(
			"4.7-stable", "Godot v4.7 stable", true
		),
		"Expected a standard editor to be rejected for a C# project",
	)
	_check(
		ProjectListItemControl.editor_matches_project(
			"4.7-stable", "Godot v4.7 stable mono", true
		),
		"Expected a Mono editor to be accepted for a C# project",
	)


func _asset(name: String) -> RemoteEditorsTreeDataSourceGithub.GodotAsset:
	return RemoteEditorsTreeDataSourceGithub.GodotAsset.new({
		"name": name,
		"browser_download_url": "https://example.com/%s" % name,
	})


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
