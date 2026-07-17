extends SceneTree

const VersionComparison = preload("res://src/services/version_comparison.gd")


func _init() -> void:
	assert(VersionComparison.is_newer("v1.2", "v1.1"))
	assert(VersionComparison.is_newer("v1.2.1", "v1.2"))
	assert(not VersionComparison.is_newer("v1.2", "v1.2.0"))
	assert(not VersionComparison.is_newer("v1.1", "v1.2"))
	quit()
