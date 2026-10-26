extends SceneTree
func _init() -> void:
	var p: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var inst: Node = p.instantiate()
	var sprite := inst.get_node_or_null("PetController/CharacterSprite")
	print("CharacterSprite 是 AnimatedSprite2D: ", "OK" if sprite is AnimatedSprite2D else "FAIL")
	inst.free()
	quit(0 if sprite is AnimatedSprite2D else 1)
