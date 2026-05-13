class_name EditorListCommand
## Lists all registered Godot editors.
##
## This command outputs all locally configured editors to the console.


class Route extends Routes.Item:
	## Route handler for the editor list command.

	var _ctx: CliContext


	func _init(ctx: CliContext) -> void:
		_ctx = ctx


	func route(cmd: CliParser.ParsedCommandResult, user_args: PackedStringArray) -> void:
		EditorListCommand.new(_ctx.editors).execute(Request.new())


	func match(cmd: CliParser.ParsedCommandResult, user_args: PackedStringArray) -> bool:
		return cmd.verb == "list"


class Request:
	## Request object for the editor list command (no parameters needed).
	pass


var _editors: LocalEditors.List


func _init(editors: LocalEditors.List) -> void:
	_editors = editors


func execute(req: Request) -> void:
	Output.push("\n".join(_editors.all()))
