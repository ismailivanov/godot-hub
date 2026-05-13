class_name Routes
## Base classes for CLI command routing.
##
## Provides a hierarchical routing system where commands are matched
## and dispatched to appropriate handlers.


class List extends Item:
	## A collection of route items that can be matched and routed.

	var _items: Array[Item] = []


	func route(cmd: CliParser.ParsedCommandResult, user_args: PackedStringArray) -> void:
		for item: Item in _items:
			if item.match(cmd, user_args):
				item.route(cmd, user_args)
				break


	func match(cmd: CliParser.ParsedCommandResult, user_args: PackedStringArray) -> bool:
		for item: Item in _items:
			if item.match(cmd, user_args): return true
		return false


class Item:
	## Base class for a routable command handler.


	func route(cmd: CliParser.ParsedCommandResult, user_args: PackedStringArray) -> void:
		return


	func match(cmd: CliParser.ParsedCommandResult, user_args: PackedStringArray) -> bool:
		return false
