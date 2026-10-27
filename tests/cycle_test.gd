extends SceneTree
## Headless test of switching control with the arrows and Q. On the test
## terrain, stacks Crab3 and Crab2 on Crab4, then walks right through the group
## and back left, checking the stack comes bottom to top going right, top to
## bottom going left, and that the ends wrap round. Run with
##   godot --headless --path . -s tests/cycle_test.gd

var player: Player
var crabs := {}
var frame := 0
var ok := true


func _initialize() -> void:
	var world: Node3D = load("res://world/test_terrain.tscn").instantiate()
	load("res://tests/group_test.gd").gather_crabs(world)
	root.add_child(world)
	player = world.get_node("Player")
	for crab in player.get_animals():
		crabs[crab.name] = crab


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame == 240:
		var bottom: ContactCrab = crabs["Crab4"]
		for name in ["Crab3", "Crab2"]:
			crabs[name].global_position = bottom.global_position + Vector3(0.3, 0.0, 0.0)
	if frame == 250:
		_check("stacked", crabs["Crab3"].mount_onto(crabs["Crab4"]) and crabs["Crab2"].mount_onto(crabs["Crab3"]))
	if frame == 300:
		var order := player.get_cycle().map(func(a): return String(a.name))
		print("cycle %s" % [order])
		_check("stack together, bottom first",
				order == ["Crab1", "Crab4", "Crab3", "Crab2", "Crab5", "Crab6"])
		var right := []
		for i in order.size() + 1:
			_press(&"control_next")
			right.append(String(player.controlled.name))
		print("right %s" % [right])
		_check("right goes up the stack and on out of it",
				right == ["Crab1", "Crab4", "Crab3", "Crab2", "Crab5", "Crab6", "Crab1"])
		_press(&"control_group")
		_check("Q back to the group", player.controlled == null)
		var left := []
		for i in order.size() + 1:
			_press(&"control_previous")
			left.append(String(player.controlled.name))
		print("left %s" % [left])
		_check("left comes down the stack and on out of it",
				left == ["Crab6", "Crab5", "Crab2", "Crab3", "Crab4", "Crab1", "Crab6"])
		print("RESULT %s" % ("PASS" if ok else "FAIL"))
		return true
	return false


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(what: String, passed: bool) -> void:
	print("%s %s" % ["ok  " if passed else "FAIL", what])
	ok = ok and passed
