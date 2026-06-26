extends Node
## Automatically closes the application based on configuration.
##
## Checks the AUTO_CLOSE config setting and quits the application
## if the setting is enabled.


func close_if_should() -> void:
	if Config.auto_close.ret(): get_tree().quit()
