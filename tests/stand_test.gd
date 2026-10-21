extends SceneTree
## Headless crab-on-crab test: puts one crab on top of another on the test
## terrain and measures how well it stands there. Run with
##   godot --headless --path . -s tests/stand_test.gd -- <drop|offset|walk> <seconds>
## drop: lowered straight on top. offset: lowered off to one side. walk: walks
## into the other from behind until over its middle (or 3 s), then stops. FOOTHOLDS=0 removes the
## crabs' footholds, to compare.

const SPOT := Vector3(0.0, 0.107, 3.0)

var top: RigidBody3D
var bottom: RigidBody3D
var mode := "drop"
var seconds := 6.0
var frame := 0
var on_top_time := 0.0
var feet_sum := 0.0
var foothold_sum := 0.0
var samples := 0
var tipped := 0.0
var settle_at := 1.0  # measuring starts here


func _initialize() -> void:
	seed(int(OS.get_environment("SEED")) if OS.has_environment("SEED") else 1)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: mode = args[0]
	if args.size() > 1: seconds = float(args[1])
	var world: Node3D = load("res://world/test_terrain.tscn").instantiate()
	var player: Node = world.get_node("Player")
	top = player.get_node("Crab1")
	bottom = world.get_node("Crab2")
	for crab in world.find_children("*", "RigidBody3D", true, false):
		if crab != top and crab != bottom and "move_direction" in crab:
			crab.get_parent().remove_child(crab)
			crab.free()
		elif OS.get_environment("FOOTHOLDS") == "0" and crab.has_node("Footholds"):
			crab.get_node("Footholds").free()
	bottom.position = SPOT
	match mode:
		"drop": top.position = SPOT + Vector3(0.0, 0.25, 0.0)
		"offset": top.position = SPOT + Vector3(0.1, 0.25, 0.0)
		"walk": top.position = SPOT + Vector3(0.0, 0.0, 0.7)
	# Steered by hand here, not by the player.
	player.process_mode = Node.PROCESS_MODE_DISABLED
	top.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)


func _physics_process(delta: float) -> bool:
	frame += 1
	var t := frame * delta
	var d := top.global_position - bottom.global_position
	if mode == "walk":
		var walking := t > 0.5 and t < 3.5 and d.z > 0.0 and settle_at == 1.0
		top.move_direction = Vector3.FORWARD * 0.5 if walking else Vector3.ZERO
		if t > 0.5 and not walking and settle_at == 1.0:
			settle_at = t + 0.5
	var on_top := d.y > 0.08 and Vector2(d.x, d.z).length() < 0.2
	if t > settle_at:
		samples += 1
		if on_top:
			on_top_time += delta
		var feet := 0
		var footholds := 0
		for leg in top._legs:
			if leg.planted and leg.collider == bottom:
				feet += 1
				if leg.foothold:
					footholds += 1
		feet_sum += feet
		foothold_sum += footholds
		if top.global_basis.y.y < 0.3:
			tipped += delta
	if frame % 60 == 0 and OS.has_environment("LOG"):
		var feet_on: int = top._legs.filter(func(l): return l.planted and l.collider == bottom).size()
		print("t=%.1f d=(%.2f %.2f %.2f) up=%.2f feet_on_bottom=%d bottom_moved=%.2f" % [t, d.x, d.y, d.z,
				top.global_basis.y.y, feet_on, Vector2(bottom.global_position.x - SPOT.x, bottom.global_position.z - SPOT.z).length()])
	if t >= seconds:
		var moved := Vector2(bottom.global_position.x - SPOT.x, bottom.global_position.z - SPOT.z).length()
		print("RESULT %s on_top=%.0f%% feet_on_bottom=%.1f on_footholds=%.1f bottom_moved=%.2fm tipped=%.2fs" % [
				mode, 100.0 * on_top_time / maxf(samples * delta, delta), feet_sum / maxf(samples, 1),
				foothold_sum / maxf(samples, 1), moved, tipped])
		return true
	return false
