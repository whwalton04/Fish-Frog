extends SceneTree
## Headless crab-on-crab test: puts one crab on top of another on the test
## terrain and measures how well it stands and rides there. Run with
##   godot --headless --path . -s tests/stand_test.gd -- <mode> <seconds>
## Modes:
##   drop        lowered straight on top
##   offset      lowered off to one side
##   mount       walks into the other at full speed from behind, stopping once
##               over its middle
##   mount_side  the same from the side
##   cross       walks on from behind and keeps walking, to get off the far side
##   ride        mounts from behind, then the one underneath turns round,
##               walks, turns left, walks and stops, with the rider given no
##               input
##   ground      walks on open ground with no other crab near, for comparison
## FOOTHOLDS=0 removes the crabs' footholds, to compare. The LEGS line rates
## how the rider's legs are drawn: jitter is the knees' frame-to-frame jerk in
## the body's frame, wrong_side the share of knees on the body's side of their
## hip, knee_rise how high the knees are above their hips on average.

const SPOT := Vector3(0.0, 0.107, 3.0)
## Shell bottom to centre and centre to top; the gap is between the shells.
const SHELL_HALF_HEIGHT := 0.042

var top: RigidBody3D
var bottom: RigidBody3D
var mode := "drop"
var seconds := 6.0
var frame := 0
var approach := Vector3.ZERO  # direction the rider walks on in
var mounted_at := -1.0  # when the rider stopped walking
var on_top_time := 0.0
var feet_sum := 0.0
var foothold_sum := 0.0
var gap_sum := 0.0
var off_center_sum := 0.0
var samples := 0
var tipped := 0.0
var knees := []  # per leg, the last two knee positions in the body's frame
var jerk_sum := 0.0
var wrong_side := 0
var rise_sum := 0.0
var knee_samples := 0
var measuring := false


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
		"mount", "ride", "cross": approach = Vector3.FORWARD
		"ground":
			approach = Vector3.FORWARD
			bottom.position = Vector3(6.0, 0.107, 7.0)
		"mount_side":
			approach = Vector3.LEFT
			# Both facing the way the rider walks, so it comes in side-on.
			top.rotation.y = PI / 2
			bottom.rotation.y = PI / 2
	if approach != Vector3.ZERO:
		top.position = SPOT - approach * 0.7
	# Steered by hand here, not by the player.
	player.process_mode = Node.PROCESS_MODE_DISABLED
	top.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)


func _physics_process(delta: float) -> bool:
	frame += 1
	var t := frame * delta
	var d := top.global_position - bottom.global_position
	var measure_from := 1.0
	if approach != Vector3.ZERO:
		var walking := mounted_at < 0.0 and t > 0.5 and t < 3.5 \
				and (d.dot(approach) < 0.0 or mode == "cross" or mode == "ground")
		if t > 0.5 and not walking and mounted_at < 0.0:
			mounted_at = t
		top.move_direction = approach * float(OS.get_environment("SPEED") if OS.has_environment("SPEED") else "1") if walking else Vector3.ZERO
		measure_from = mounted_at + 0.5 if mounted_at >= 0.0 else INF
	if mode == "ride" and mounted_at >= 0.0:
		# Turns round, walks, turns left and walks, all on open ground.
		var ride_t := t - mounted_at - 1.0
		if ride_t < 0.0 or ride_t > 2.4:
			bottom.move_direction = Vector3.ZERO
		elif ride_t < 1.2:
			bottom.move_direction = Vector3.BACK
		else:
			bottom.move_direction = Vector3.LEFT
		bottom.facing_direction = bottom.move_direction
	var flat := Vector2(d.x, d.z).length()
	var on_top := d.y > 0.08 and flat < 0.2
	measuring = t > measure_from or (mode == "ground" and t > 1.0 and t < 3.5)
	if t > measure_from:
		samples += 1
		if on_top:
			on_top_time += delta
			gap_sum += d.y - 2.0 * SHELL_HALF_HEIGHT
			off_center_sum += flat
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
	if frame % int(OS.get_environment("LOG_EVERY") if OS.has_environment("LOG_EVERY") else "30") == 0 and OS.has_environment("LOG"):
		var feet_on: int = top._legs.filter(func(l): return l.planted and l.collider == bottom).size()
		print("t=%.2f d=(%.2f %.3f %.2f) up=%.2f feet_on_bottom=%d bottom=(%.2f %.2f) bottom_up=%.2f yaw_diff=%.0f" % [t, d.x, d.y, d.z,
				top.global_basis.y.y, feet_on, bottom.global_position.x, bottom.global_position.z, bottom.global_basis.y.y, rad_to_deg((-top.global_basis.z).signed_angle_to(-bottom.global_basis.z, Vector3.UP))])
	if t >= seconds:
		var on_samples := on_top_time / delta
		if mode == "cross":
			print("CROSSED %s: %.2fm past the other's middle" % [d.dot(approach) > 0.4, d.dot(approach)])
		print("LEGS jitter=%.5f wrong_side=%.1f%% knee_rise=%.3fm" % [jerk_sum / maxf(knee_samples, 1),
				100.0 * wrong_side / maxf(knee_samples, 1), rise_sum / maxf(knee_samples, 1)])
		print("RESULT %s on_top=%.0f%% feet_on_bottom=%.1f on_footholds=%.1f gap=%.3fm off_center=%.3fm tipped=%.2fs" % [
				mode, 100.0 * on_top_time / maxf(samples * delta, delta), feet_sum / maxf(samples, 1),
				foothold_sum / maxf(samples, 1), gap_sum / maxf(on_samples, 1), off_center_sum / maxf(on_samples, 1),
				tipped])
		return true
	return false


## Rates the rider's leg poses each drawn frame, after the crab has posed them.
func _process(_delta: float) -> bool:
	if not measuring:
		knees.clear()
		return false
	if knees.is_empty():
		knees.resize(top._legs.size())
		for i in knees.size():
			knees[i] = []
	for i in top._legs.size():
		var leg = top._legs[i]
		var knee: Vector3 = top.to_local(leg.joints[1].global_position)
		var history: Array = knees[i]
		if history.size() == 2:
			jerk_sum += (knee - 2.0 * history[1] + history[0]).length()
			knee_samples += 1
			var from_hip: Vector3 = knee - leg.hip_local
			if Vector2(from_hip.x, from_hip.z).dot(Vector2(leg.out_local.x, leg.out_local.z)) < 0.0:
				wrong_side += 1
			rise_sum += from_hip.y
			history.pop_front()
		history.append(knee)
	return false
