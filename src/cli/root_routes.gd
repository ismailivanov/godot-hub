class_name RootRoutes
extends Routes.List
## Root route aggregator for all CLI command routes.
##
## Combines all available route handlers into a single list
## for command processing and dispatching.


func _init(ctx: CliContext) -> void:
	self._items = [
		DefaultRoutes.new(ctx),
		EditorsRoutes.new(ctx),
		ExecCommand.Route.new(ctx)
	]
