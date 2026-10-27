extends SceneTree
## Headless flag test: on the test terrain, a crab comes near one flag and
## then another, checking only the last is active, then builds a stack in the
## group and presses rally. Every crab should come out of its stack, drop near
## the active flag rally_interval apart, with the camera on the flag meanwhile,
## and end up standing on its own. Run with
##   godot --headless --path . -s tests/flag_test.gd

var player: Player
var first: Flag
var second: Flag
var crabs: Array[Node3D] = []
var frame := 0
var ok := true
var rally_at := INF
var arrivals: Array[float] = []


func _initialize() -> void:
	var world: Node3D = load("res://world/test_terrain.tscn").instantiate()
	load("res://tests/group_test.gd").gather_crabs(world)
	first = load("res://world/flag.tscn").instantiate()
	first.position = Vector3(0.0, 0.0, -1.0)
	world.add_child(first)
	second = load("res://world/flag.tscn").instantiate()
	second.position = Vector3(3.0, 0.0, 1.0)
	world.add_child(second)
	root.add_child(world)
	player = world.get_node("Player")


func _physics_process(delta: float) -> bool:
	frame += 1
	var t := frame * delta
	if is_equal_approx(t, 0.5):
		_check("none active at the start", Flag.active == null)
		for flag in [first, second]:
			flag.global_position = _floor_under(flag.global_position)
		first.activate()
		_check("first active", Flag.active == first and first._pennant_mat.albedo_color == first.active_color)
	if is_equal_approx(t, 3.0):
		crabs = player.get_animals()
		_check("group of six", crabs.size() == 6)
		# A crab coming into the second flag's reach takes over.
		crabs[0].drop_at(second.global_position + Vector3(0.0, 0.2, 0.3))
	if is_equal_approx(t, 4.5):
		_check("second active", Flag.active == second)
		_check("first back to idle", first._pennant_mat.albedo_color == first.idle_color)
		_check("second orange", second._pennant_mat.albedo_color == second.active_color)
		# Bring the walker back into the group, and stack three in it.
		crabs[0].drop_at(crabs[1].global_position + Vector3(0.0, 0.3, 0.5))
	if is_equal_approx(t, 6.0):
		crabs = player.get_animals()
		var stacked := 0
		for i in range(1, crabs.size()):
			for j in crabs.size():
				if i != j and crabs[i].mount == null and crabs[i].can_mount(crabs[j]):
					crabs[i].mount_onto(crabs[j])
					stacked += 1
					break
		print("stacked %d mounts, group %d" % [stacked, crabs.size()])
		_check("something stacked", stacked > 0)
	if is_equal_approx(t, 7.0):
		var press := InputEventAction.new()
		press.action = &"rally"
		press.pressed = true
		Input.parse_input_event(press)
		rally_at = t
	if t > rally_at:
		for crab in crabs:
			var near := Vector2(crab.global_position.x - second.global_position.x,
					crab.global_position.z - second.global_position.z).length() < 1.0
			if near and crab.get_meta("arrived", -1.0) < 0.0:
				crab.set_meta("arrived", t)
				arrivals.append(t - rally_at)
	if is_equal_approx(t, rally_at + 1.2):
		_check("camera on the flag mid-rally", player.get_focus() == second.global_position)
	if is_equal_approx(t, rally_at + 0.05):
		var mounted := crabs.filter(func(c): return c.mount != null or c.rider != null)
		_check("stacks taken apart", mounted.is_empty())
	if t > rally_at + 6.0:
		arrivals.sort()
		print("arrivals %s" % [arrivals.map(func(a): return snappedf(a, 0.01))])
		_check("all arrived", arrivals.size() == crabs.size())
		var steady := true
		for i in range(1, arrivals.size()):
			steady = steady and absf(arrivals[i] - arrivals[i - 1] - player.rally_interval) < 0.05
		_check("rally_interval apart", steady)
		for crab in crabs:
			var d: Vector3 = crab.global_position - second.global_position
			print("%s at (%.2f %.2f %.2f) up %.2f mounted %s" % [crab.name, d.x, d.y, d.z,
					crab.global_basis.y.y, crab.mount != null])
		_check("all upright", crabs.all(func(c): return c.global_basis.y.y > 0.8))
		_check("all in the group", player.get_animals().size() == crabs.size())
		print("RESULT %s" % ("PASS" if ok else "FAIL"))
		return true
	return false


func _check(what: String, passed: bool) -> void:
	print("%s %s" % ["ok  " if passed else "FAIL", what])
	ok = ok and passed


func _floor_under(at: Vector3) -> Vector3:
	var hit := root.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0, 1))
	return hit.position if not hit.is_empty() else at
