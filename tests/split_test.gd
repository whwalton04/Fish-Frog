extends SceneTree
## Headless split test: on the test terrain, takes one crab off on its own,
## walks it away until it becomes the group and the others are dropped off,
## goes back to group steering and walks the new group of one back until the
## others join it again. Run with
##   godot --headless --path . -s tests/split_test.gd

var player: Player
var scout: Node3D
var frame := 0
var phase := "settle"
var left_at := -1.0
var joined_at := -1.0
var old_members: Array[Node3D] = []


func _initialize() -> void:
	var world: Node3D = load("res://world/test_terrain.tscn").instantiate()
	load("res://tests/group_test.gd").gather_crabs(world)
	root.add_child(world)
	player = world.get_node("Player")


func _physics_process(delta: float) -> bool:
	frame += 1
	var t := frame * delta
	match phase:
		"settle":
			if t >= 2.0:
				scout = player.get_animals()[0]
				old_members = player.get_animals()
				old_members.erase(scout)
				_press_key(KEY_2)
				Input.action_press("move_forward")
				phase = "scout"
		"scout":
			if player.controlled != scout:
				print("FAIL key 2 didn't take control of %s" % scout.name)
				return true
			if scout.get_parent() != player:
				print("FAIL %s was dropped off instead of becoming the group" % scout.name)
				return true
			if player.get_animals() == [scout]:
				left_at = t
				Input.action_release("move_forward")
				_press_key(KEY_1)
				phase = "regroup"
			elif t > 10.0:
				print("FAIL %s never split from the group" % scout.name)
				return true
		"regroup":
			if player.controlled != null:
				print("FAIL key 1 didn't go back to the group")
				return true
			for old in old_members:
				if old.get_parent() == player or old.move_direction != Vector3.ZERO:
					print("FAIL %s is still in the old group" % old.name)
					return true
			Input.action_press("move_back")
			phase = "chase"
		"chase":
			if player.get_animals().size() == old_members.size() + 1:
				joined_at = t
				Input.action_release("move_back")
				var names := player.get_animals().map(func(a): return a.name)
				print("RESULT left=%.2fs joined=%.2fs order=%s" % [left_at, joined_at, names])
				return true
			if t > left_at + 15.0:
				print("FAIL %s never gathered the others again" % scout.name)
				return true
	if frame % 60 == 0 and OS.has_environment("LOG"):
		print("t=%.1f %s members=%d scout=(%.2f %.2f)" % [t, phase, player.get_animals().size(),
				scout.global_position.x if scout else 0.0, scout.global_position.z if scout else 0.0])
	return false


func _press_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
