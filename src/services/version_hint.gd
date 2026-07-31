class_name VersionHint
extends RefCounted
## Parses and compares editor version hint strings.


## Severity of a project to editor version change.
enum ChangeKind {
	## Same major.minor. Only patch differs.
	PATCH,
	## Minor version differs.
	MINOR,
	## Major version differs.
	MAJOR,
}


## Returns true when two hints describe the same editor build.
static func are_equal(a: String, b: String, ignore_mono: bool = false) -> bool:
	if a == b: return true
	return parse(a).eq(parse(b), ignore_mono)


## Returns the parsed version, or the raw hint when parsing fails.
static func version_or_nothing(hint: String) -> String:
	var parsed := parse(hint)
	if parsed.is_valid: return parsed.version
	return hint


## Returns a normalized hint string when parsing succeeds.
static func normalize(hint: String) -> String:
	var parsed := parse(hint)
	if parsed.is_valid: return str(parsed)
	return hint.strip_edges()


## Scores how closely two hints match. Higher is closer.
static func similarity(a: String, b: String) -> int:
	if a == b: return 100
	var parsed_a := parse(a)
	var parsed_b := parse(b)
	var score := 0
	if not parsed_a.is_valid or not parsed_b.is_valid: return 0
	if parsed_a.major_version == parsed_b.major_version:
		score += 6
	if parsed_a.minor_version == parsed_b.minor_version:
		score += 6
	if parsed_a.version == parsed_b.version:
		score += 6
	if parsed_a.is_mono == parsed_b.is_mono:
		score += 2
	if parsed_a.stage == parsed_b.stage:
		score += 2
	elif parsed_a.stage.begins_with(parsed_b.stage):
		score += 1
	elif parsed_b.stage.begins_with(parsed_a.stage):
		score += 1
	return score


## Returns true when both hints share the same dotted version number.
static func same_version(a: String, b: String) -> bool:
	return parse(a).version == parse(b).version


## Compares editor vs project. Returns 1 newer, 0 equal or unknown, or negative when older.
static func compare_editor_to_project(project_hint: String, editor_hint: String) -> int:
	var project_version := parse(project_hint)
	var editor_version := parse(editor_hint)
	if not project_version.is_valid or not editor_version.is_valid: return 0
	return VersionComparison.compare(editor_version.version, project_version.version)


## Classifies how far the editor version moves from the project version.
static func change_kind(project_hint: String, editor_hint: String) -> ChangeKind:
	var project_version := parse(project_hint)
	var editor_version := parse(editor_hint)
	if not project_version.is_valid or not editor_version.is_valid:
		return ChangeKind.PATCH
	var project_parts := VersionComparison.parts(project_version.version)
	var editor_parts := VersionComparison.parts(editor_version.version)
	var project_major: int = project_parts[0] if project_parts.size() > 0 else 0
	var editor_major: int = editor_parts[0] if editor_parts.size() > 0 else 0
	if project_major != editor_major: return ChangeKind.MAJOR
	var project_minor: int = project_parts[1] if project_parts.size() > 1 else 0
	var editor_minor: int = editor_parts[1] if editor_parts.size() > 1 else 0
	if project_minor != editor_minor: return ChangeKind.MINOR
	return ChangeKind.PATCH


## Returns true when major.minor match. Patch may differ.
static func same_branch(a: String, b: String) -> bool:
	var parsed_a := parse(a)
	var parsed_b := parse(b)
	if not parsed_a.is_valid or not parsed_b.is_valid: return false
	return change_kind(a, b) == ChangeKind.PATCH


## Parses a free form version hint into a structured item.
static func parse(version_hint: String) -> Item:
	var tags: Array
	version_hint = version_hint.to_lower().strip_edges()
	if " " in version_hint:
		tags = version_hint.split(" ")
	else:
		tags = version_hint.split("-")
	var item := Item.new()
	var parsers := [
		_ParsedVersion.new(),
		_ParsedIsMono.new(),
		_ParsedStage.new(PackedStringArray([
			"stable",
			"dev",
			"rc",
			"alpha",
			"beta",
			"pre-alpha"
		]))
	]
	for parser: Object in parsers:
		parser.call("fill", item, tags)
	return item


static func _as_version(tag: String) -> String:
	if tag.begins_with("v") and tag.substr(1, 3).is_valid_float():
		return tag.substr(1)
	elif tag.substr(0, 3).is_valid_float():
		return tag
	return ""


static func _is_version(tag: String) -> bool:
	return _as_version(tag) != ""


class Item:
	var version := ""
	var major_version := ""
	var minor_version := ""
	var stage := "stable"
	var is_mono := false
	var is_valid := false

	func eq(other: Item, ignore_mono: bool = false) -> bool:
		if not is_valid: return false
		if not other.is_valid: return false
		var result := version == other.version and stage == other.stage
		if not ignore_mono: return result and is_mono == other.is_mono
		return result

	func _to_string() -> String:
		if not is_valid: return "unknown version"
		var base := "%s-%s" % [version, stage]
		if is_mono:
			base += "-%s" % "mono"
		return base


class _ParsedVersion:
	func fill(item: Item, tags: PackedStringArray) -> void:
		for tag: String in tags:
			var version := VersionHint._as_version(tag)
			if not version.is_empty():
				item.version = version
				item.major_version = version.substr(0, 1)
				item.minor_version = version.substr(0, 3)
				item.is_valid = true
				return
		item.is_valid = false


class _ParsedStage:
	var _known_stages: PackedStringArray

	func _init(known_stages: PackedStringArray) -> void:
		_known_stages = known_stages

	func fill(item: Item, tags: PackedStringArray) -> void:
		for tag: String in tags:
			if VersionHint._is_version(tag): continue
			if tag == "mono": continue
			for stage: String in _known_stages:
				if tag.begins_with(stage):
					item.stage = tag


class _ParsedIsMono:
	func fill(item: Item, tags: PackedStringArray) -> void:
		for tag: String in tags:
			if tag == "mono":
				item.is_mono = true
				return
		item.is_mono = false
