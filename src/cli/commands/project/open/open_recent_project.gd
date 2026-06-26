class_name OpenRecentProject
extends RefCounted
## Opens the most recently accessed Godot project.
##
## This command retrieves the last opened project from the projects
## list and launches it in the configured editor.


class Route extends Routes.Item:
	## Route handler for the open recent project command.

	var _ctx: CliContext


	func _init(ctx: CliContext) -> void:
		_ctx = ctx


	func route(cmd: CliParser.ParsedCommandResult, user_args: PackedStringArray) -> void:
		OpenRecentProject.new(_ctx.editors, _ctx.projects).execute()


	func match(cmd: CliParser.ParsedCommandResult, user_args: PackedStringArray) -> bool:
		return cmd.args.has_options(["recent", "r"])


var _editors: LocalEditors.List
var _projects: Projects.List


func _init(editors: LocalEditors.List, projects: Projects.List) -> void:
	_editors = editors
	_projects = projects


func execute() -> void:
	var project := _projects.get_last_opened()
	if project:
		project.load(false)
		project.edit()
	else:
		Output.push("Recent project does not exist.")
