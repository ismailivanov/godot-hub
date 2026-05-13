class_name DefaultRoutes
extends Routes.List
## Routes for default CLI commands without namespace or verb.
##
## Handles global commands like help and opening recent projects.


func _init(ctx: CliContext) -> void:
	self._items = [
		Help.Route.new(),
		OpenRecentProject.Route.new(ctx)
	]


func match(cmd: CliParser.ParsedCommandResult, user_args: PackedStringArray) -> bool:
	return (
		cmd.namesp == "" 
		and cmd.verb == "" 
		and super.match(cmd, user_args)
	)
