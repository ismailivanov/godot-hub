class_name VersionComparison
extends RefCounted
## Compares dotted Godot style version strings.


## Returns true when candidate is newer than current.
static func is_newer(candidate: String, current: String) -> bool:
	return compare(candidate, current) > 0


## Compares two versions. Returns 1, 0, or -1.
static func compare(a: String, b: String) -> int:
	var a_parts := parts(a)
	var b_parts := parts(b)
	for index: int in range(maxi(a_parts.size(), b_parts.size())):
		var a_part: int = a_parts[index] if index < a_parts.size() else 0
		var b_part: int = b_parts[index] if index < b_parts.size() else 0
		if a_part != b_part:
			return 1 if a_part > b_part else -1
	return 0


## Splits a version string into integer parts.
static func parts(version: String) -> Array[int]:
	var result: Array[int] = []
	for part: String in version.trim_prefix("v").split("-", true, 1)[0].split("."):
		result.append(int(part))
	return result
