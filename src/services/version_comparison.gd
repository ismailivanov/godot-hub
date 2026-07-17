extends RefCounted


static func is_newer(candidate: String, current: String) -> bool:
	var candidate_parts := _parts(candidate)
	var current_parts := _parts(current)
	for index in range(maxi(candidate_parts.size(), current_parts.size())):
		var candidate_part: int = candidate_parts[index] if index < candidate_parts.size() else 0
		var current_part: int = current_parts[index] if index < current_parts.size() else 0
		if candidate_part != current_part:
			return candidate_part > current_part
	return false


static func _parts(version: String) -> Array[int]:
	var parts: Array[int] = []
	for part in version.trim_prefix("v").split("-", true, 1)[0].split("."):
		parts.append(int(part))
	return parts
