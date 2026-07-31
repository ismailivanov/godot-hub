extends Node


var _failures := 0


func _ready() -> void:
	_test_version_hint_parsing()
	_test_download_target()
	_test_platform_asset_selection()
	_test_project_editor_compatibility()
	_test_version_change_kind()
	_test_engine_brand_detection()
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
	_check(
		ProjectListItemControl.editor_matches_project(
			"4.5-stable", "Godot v4.5.1 stable", false
		),
		"Expected patch-different editors on the same branch to be accepted",
	)
	_check(
		ProjectListItemControl.editor_matches_project(
			"4.5.0-stable", "4.5.1-stable", false
		),
		"Expected 4.5.0 and 4.5.1 to be treated as compatible",
	)


func _test_version_change_kind() -> void:
	_check(
		VersionHint.compare_editor_to_project("4.5-stable", "4.5.1-stable") > 0,
		"Expected 4.5.1 to be newer than 4.5",
	)
	_check(
		VersionHint.compare_editor_to_project("4.5.1-stable", "4.5.0-stable") < 0,
		"Expected 4.5.0 to be older than 4.5.1",
	)
	_check(
		VersionHint.compare_editor_to_project("4.5-stable", "4.6-stable") > 0,
		"Expected 4.6 to be newer than 4.5",
	)
	_check(
		VersionHint.compare_editor_to_project("4.5-stable", "3.5-stable") < 0,
		"Expected 3.5 to be older than 4.5",
	)
	_check(
		VersionHint.change_kind("4.5-stable", "4.5.1-stable") == VersionHint.ChangeKind.PATCH,
		"Expected 4.5 → 4.5.1 to be a patch change",
	)
	_check(
		VersionHint.same_branch("4.5-stable", "4.5.1-stable"),
		"Expected 4.5 and 4.5.1 to share a branch",
	)
	_check(
		not VersionHint.same_branch("4.5-stable", "4.6-stable"),
		"Expected 4.5 and 4.6 to be different branches",
	)
	_check(
		VersionHint.change_kind("4.5-stable", "4.6-stable") == VersionHint.ChangeKind.MINOR,
		"Expected 4.5 → 4.6 to be a minor change",
	)
	_check(
		VersionHint.change_kind("4.5-stable", "3.5-stable") == VersionHint.ChangeKind.MAJOR,
		"Expected 4.5 → 3.5 to be a major change",
	)
	_check(
		VersionHint.normalize("Godot v4.5.1 stable") == "4.5.1-stable",
		"Expected normalized editor hint",
	)
	var minor_text := ProjectListItemControl.version_change_dialog_text(
		"4.5-stable", "4.6-stable"
	)
	_check(
		minor_text.contains("Back up"),
		"Expected minor dialog to recommend a backup",
	)
	var major_text := ProjectListItemControl.version_change_dialog_text(
		"4.5-stable", "3.5-stable"
	)
	_check(
		major_text.contains("strongly recommend"),
		"Expected major dialog to strongly recommend a backup",
	)


func _test_engine_brand_detection() -> void:
	var redot_item := _editor_item_with_name(
		"Redot v4.5 stable", "C:/editors/Redot_v4.5-stable_win64.exe"
	)
	_check(
		EditorEngineBrand.detect(redot_item, false) == EditorEngineBrand.REDOT,
		"Expected Redot brand from editor metadata",
	)
	var rodot_item := _editor_item_with_name(
		"Rodot v26.1", "D:/Software/Redot 26.1/redot.exe"
	)
	_check(
		EditorEngineBrand.detect(rodot_item, false) == EditorEngineBrand.REDOT,
		"Expected Redot brand from Rodot name / Redot path",
	)
	var path_only := _editor_item_with_name(
		"Custom Build", "D:/Software/Redot 26.2/redot.exe"
	)
	_check(
		EditorEngineBrand.detect(path_only, false) == EditorEngineBrand.REDOT,
		"Expected Redot brand from path alone",
	)
	var godot_item := _editor_item_with_name(
		"Godot v4.7 stable", "C:/editors/Godot_v4.7-stable_win64.exe"
	)
	_check(
		EditorEngineBrand.detect(godot_item, false) == EditorEngineBrand.GODOT,
		"Expected Godot brand from editor metadata",
	)
	redot_item.list_icon_path = "res://assets/Godot128x128.png"
	redot_item.engine_brand = EditorEngineBrand.REDOT
	redot_item.refresh_engine_brand(false)
	_check(
		redot_item.engine_brand == EditorEngineBrand.REDOT,
		"Custom list icon should block automatic brand refresh",
	)


func _editor_item_with_name(name: String, path: String) -> LocalEditors.Item:
	var cfg := ConfigFile.new()
	cfg.set_value(path, "name", name)
	return LocalEditors.Item.new(
		ConfigFileSection.new(path, IConfigFileLike.of_config(cfg))
	)


func _asset(name: String) -> RemoteEditorsTreeDataSourceGithub.GodotAsset:
	return RemoteEditorsTreeDataSourceGithub.GodotAsset.new({
		"name": name,
		"browser_download_url": "https://example.com/%s" % name,
	})


func _check(condition: bool, message: String) -> void:
	if condition: return
	_failures += 1
	push_error(message)
