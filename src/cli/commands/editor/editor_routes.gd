class_name EditorsRoutes
extends Routes.List
## Routes for editor-related CLI commands.
##
## Handles commands under the "editor" namespace such as listing editors.


func _init(ctx: CliContext) -> void:
	self._items = [
		EditorListCommand.Route.new(ctx)
	]


func match(cmd: CliParser.ParsedCommandResult, user_args: PackedStringArray) -> bool:
	return cmd.namesp == "editor" and super.match(cmd, user_args)
