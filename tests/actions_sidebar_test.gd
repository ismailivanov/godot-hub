extends Node


const SIDEBAR_SCENE := preload("res://src/components/actions_sidebar/actions_sidebar.tscn")
const EDITOR_ITEM_SCENE := preload(
	"res://src/components/editors/local/editor_item/editor_item.tscn"
)
const PROJECT_ITEM_SCENE := preload(
	"res://src/components/projects/project_item/project_item.tscn"
)
const RELEASE_ITEM_SCENE := preload(
	"res://src/components/godots_releases/list/godots_release_item.tscn"
)

var _failures := 0


func _ready() -> void:
	var sidebar: ActionsSidebarControl = SIDEBAR_SCENE.instantiate()
	add_child(sidebar)

	var editor_item: EditorListItemControl = EDITOR_ITEM_SCENE.instantiate()
	_check_refresh(sidebar, editor_item.get_actions(), "editor item")
	editor_item.free()

	var project_item: ProjectListItemControl = PROJECT_ITEM_SCENE.instantiate()
	_check_refresh(sidebar, project_item.get_actions(), "project item")
	project_item.free()

	var release_item: GodotsReleasesListItemControl = RELEASE_ITEM_SCENE.instantiate()
	_check_refresh(sidebar, release_item.get_actions(), "release item before init")
	add_child(release_item)
	release_item.init(GodotsReleases.Release.new({
		"name": "v1.0",
		"html_url": "https://example.com",
		"prerelease": false,
		"draft": false,
	}))
	var release_actions := release_item.get_actions()
	_check(release_actions.size() == 1, "Expected one release item action")
	_check_refresh(sidebar, release_actions, "release item")
	release_item.queue_free()

	if _failures > 0:
		get_tree().quit(1)
		return
	print("Actions sidebar tests passed.")
	get_tree().quit()


func _check_refresh(sidebar: ActionsSidebarControl, actions: Array, label: String) -> void:
	_check(_refresh(sidebar, actions), "The sidebar rejected the %s actions" % label)


## Refreshes the sidebar the way the lists do when an item is selected. A
## rejected call stops this function, which then returns false.
func _refresh(sidebar: ActionsSidebarControl, actions: Array) -> bool:
	sidebar.refresh_actions(actions)
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
