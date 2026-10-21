extends SceneTree
## Headless group test: the test terrain's player walks its crabs about with
## simulated input, counting how often one crab is on top of another. Run with
##   godot --headless --path . -s tests/group_test.gd -- <action,action,...> <seconds>
## Actions take turns, 1.5 s each.

var crabs: Array = []
var frame := 0
var action := "move_left"
var seconds := 6.0
var stacked_frames := 0
var tipped_frames := 0
var full_frames := 0
var max_dy := 0.0


func _initialize() -> void:
	seed(int(OS.get_environment("SEED")) if OS.has_environment("SEED") else 1)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: action = args[0]
	if args.size() > 1: seconds = float(args[1])
	var world: Node3D = load("res://world/test_terrain.tscn").instantiate()
	gather_crabs(world)
	root.add_child(world)
	for child in world.get_node("Player").get_children():
		if child is RigidBody3D:
			crabs.append(child)


func _physics_process(delta: float) -> bool:
	frame += 1
	var t := frame * delta
	var actions := action.split(",")
	var current: String = actions[int(maxf(t - 0.5, 0.0) / 1.5) % actions.size()]
	var moving := t > 0.5 and t < seconds - 2.0
	for a in actions:
		var want := moving and a == current
		if want != Input.is_action_pressed(a):
			if want:
				Input.action_press(a)
			else:
				Input.action_release(a)
	var stacked := false
	for a in crabs:
		for b in crabs:
			if a == b:
				continue
			var d: Vector3 = a.global_position - b.global_position
			if Vector2(d.x, d.z).length() < 0.25:
				if d.y > 0.06:
					stacked = true
				max_dy = maxf(max_dy, d.y)
				if d.y > 0.09:
					full_frames += 1
	if stacked:
		stacked_frames += 1
	for c in crabs:
		if c.global_basis.y.y < 0.3:
			tipped_frames += 1
	if frame % 30 == 0 and OS.has_environment("LOG"):
		var line := "t=%.1f" % t
		for c in crabs:
			line += "  (%.2f %.2f %.2f up%.2f)" % [c.global_position.x, c.global_position.y, c.global_position.z, c.global_basis.y.y]
		print(line + ("  STACKED" if stacked else ""))
	if t >= seconds:
		print("RESULT stacked=%.2fs on_top=%.2fs max_dy=%.3f tipped=%.2f crab-s" % [stacked_frames * delta, full_frames * delta, max_dy, tipped_frames * delta])
		return true
	return false


## The test terrain starts the player with one crab; brings the others in to
## where the group used to start, some dropped on top of each other.
static func gather_crabs(world: Node3D) -> void:
	var player := world.get_node("Player")
	var starts := {
		"Crab2": Vector3(-0.6, 4.933, 0.8), "Crab3": Vector3(0.6, 0.107, 0.8),
		"Crab4": Vector3(0.0, 0.107, 1.518), "Crab5": Vector3(0.0, 0.214, 3.035),
		"Crab6": Vector3(0.0, 3.63, 1.355),
	}
	for crab_name in starts:
		var crab: Node3D = world.get_node(crab_name)
		world.remove_child(crab)
		crab.position = starts[crab_name]
		player.add_child(crab)
