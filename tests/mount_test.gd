extends SceneTree
## Headless test of mounting through the player. Run with
##   godot --headless --path . -s tests/mount_test.gd
## Steers Crab1 on its own with a crab ahead of it in view, checks that crab is
## the one looked at (arrow shown), presses mount, then moves to get off.

var player: Player
var me: ContactCrab
var other: ContactCrab
var frame := 0
var ok := true


func _initialize() -> void:
	var world: Node3D = load("res://world/test_terrain.tscn").instantiate()
	player = world.get_node("Player")
	me = player.get_node("Crab1")
	other = world.get_node("Crab2")
	for crab in world.find_children("*", "RigidBody3D", true, false):
		if crab != me and crab != other and "move_direction" in crab:
			crab.get_parent().remove_child(crab)
			crab.free()
	me.position = Vector3(0.0, 0.107, 3.0)
	# Ahead of it, where the camera behind it looks.
	other.position = Vector3(0.0, 0.107, 2.55)
	root.add_child(world)
	player.controlled = me


func _physics_process(delta: float) -> bool:
	frame += 1
	var t := frame * delta
	if is_equal_approx(t, 1.0):
		_check("looks at the crab ahead", player.looked_at == other)
		_check("arrow shown", player._arrow.visible)
		var press := InputEventAction.new()
		press.action = &"mount"
		press.pressed = true
		Input.parse_input_event(press)
	if is_equal_approx(t, 1.5):
		var release := InputEventAction.new()
		release.action = &"mount"
		Input.parse_input_event(release)
		_check("mounted", me.mount == other and other.rider == me)
		_check("on top", me.global_position.y - other.global_position.y > 0.12)
		_check("nothing left to look at", player.looked_at == null)
	if is_equal_approx(t, 2.5):
		_check("still on after standing", me.mount == other)
		Input.action_press(&"move_right")
	if is_equal_approx(t, 3.0):
		Input.action_release(&"move_right")
		_check("moving got off", me.mount == null and other.rider == null)
	if t > 4.0:
		print("RESULT %s" % ("PASS" if ok else "FAIL"))
		return true
	return false


func _check(what: String, passed: bool) -> void:
	print("%s %s" % ["ok  " if passed else "FAIL", what])
	ok = ok and passed
