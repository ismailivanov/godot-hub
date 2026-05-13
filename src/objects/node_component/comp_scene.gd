class_name CompScene
extends _Component
## Provides comp scene.


func _init(scene: PackedScene, children=[]):
	super._init(func(): return scene.instantiate())
	self.children(children)
