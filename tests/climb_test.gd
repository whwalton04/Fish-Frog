extends SceneTree
## Headless climb test: a crab walks into a still one. Run with
##   godot --headless --path . -s tests/climb_test.gd

const CRAB := preload("res://crab/crab2.tscn")
const SECONDS := 6.0
var LOG_EVERY := 15
var LOG_UNTIL := 99.0

var rider: RigidBody3D
var carrier: RigidBody3D
var frame := 0
var dir := Vector3(1, 0, 0)
var speed := 1.0
var best := 0.0
var on_frames := 0
var stopped_at := -1.0
var top_frames := 0


func _initialize() -> void:
	seed(int(OS.get_environment("SEED")) if OS.has_environment("SEED") else 1)
	var root3d := Node3D.new()
	root.add_child(root3d)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.5
	root3d.add_child(ground)

	var args := OS.get_cmdline_user_args()
	var gap := float(args[0]) if args.size() > 0 else 0.7
	if args.size() > 2: LOG_EVERY = int(args[2])
	if args.size() > 3: LOG_UNTIL = float(args[3])
	var yaw := deg_to_rad(float(args[1])) if args.size() > 1 else 0.0
	dir = Vector3(cos(yaw), 0, -sin(yaw))
	if OS.has_environment("SPEED"): speed = float(OS.get_environment("SPEED"))

	carrier = CRAB.instantiate()
	carrier.position = Vector3(0, 0.11, 0)
	root3d.add_child(carrier)
	rider = CRAB.instantiate()
	rider.position = Vector3(0, 0.11, 0) - dir * gap
	root3d.add_child(rider)


func _physics_process(delta: float) -> bool:
	frame += 1
	var t := frame * delta
	var over := (rider.global_position - carrier.global_position).dot(dir) > -0.03
	if OS.has_environment("STOP") and over and stopped_at < 0.0:
		stopped_at = t
	if stopped_at >= 0.0:
		rider.move_direction = Vector3.ZERO
		if rider.global_position.y - carrier.global_position.y > 0.06:
			top_frames += 1
	elif t > 0.5:
		rider.move_direction = dir * speed
		rider.facing_direction = Vector3(0, 0, -1)
	var on := 0
	for leg in rider._legs:
		if leg.planted and leg.collider == carrier:
			on += 1
	var holds := 0
	for leg in rider._legs:
		if leg.has_hold and leg.hold_collider == carrier:
			holds += 1
	if on > 0:
		on_frames += 1
	best = maxf(best, rider.global_position.y)
	if frame % LOG_EVERY == 0 and t < LOG_UNTIL:
		print("t=%.2f rider=(%.2f %.2f %.2f) up.y=%.2f roll=%.2f onCarrier=%d holds=%d planted=%d carrier=(%.2f %.3f %.2f) up.y=%.2f" % [
			t, rider.global_position.x, rider.global_position.y, rider.global_position.z,
			rider.global_basis.y.y, rider._wall_roll, on, holds,
			rider._legs.filter(func(l): return l.planted).size(),
			carrier.global_position.x, carrier.global_position.y, carrier.global_position.z, carrier.global_basis.y.y])
	if OS.has_environment("LEGS") and frame % LOG_EVERY == 0 and t < LOG_UNTIL and t > 0.6:
		var line := "   "
		for leg in rider._legs:
			var c := "G"
			if leg.collider == carrier: c = "C"
			var h := "-"
			if leg.has_hold: h = "c" if leg.hold_collider == carrier else "g"
			line += " %s%s%s%.2f" % ["P" if leg.planted else "s", c if leg.planted else "", h, leg.foot.pos.y]
		print(line)
	if OS.has_environment("PROBE") and frame % LOG_EVERY == 0 and t < LOG_UNTIL and t > 0.6:
		for i in [4, 5, 6, 7]:
			var leg = rider._legs[i]
			var pose: Basis = rider.global_basis.orthonormalized()
			var from: Vector3 = rider.global_position + pose.y * leg.hip_local.y
			var above: Vector3 = rider.global_position + pose * leg.rest_local + pose.y * (leg.hip_local.y - leg.rest_local.y)
			var ob: Dictionary = rider._ray(from, above)
			var su: Dictionary = rider._step_up(leg, from, above)
			print("    leg%d above=(%.2f %.2f) ob=%s su=%s reach=%s" % [i, above.x, above.y,
				"-" if ob.is_empty() else "%s n=%s" % [ob.collider.name, ob.normal],
				"-" if su.is_empty() else "%s %s" % [su.collider.name, su.position],
				"-" if su.is_empty() else str(rider._in_reach(leg, su.position, 0.95))])
	if t >= SECONDS:
		print("RESULT best_y=%.3f on_frames=%d final_y=%.3f stopped_at=%.2f top_frac=%.2f final_dy=%.3f up=%.2f/%.2f" % [best, on_frames, rider.global_position.y,
			stopped_at, top_frames / maxf((t - stopped_at) / delta, 1.0) if stopped_at >= 0.0 else 0.0,
			rider.global_position.y - carrier.global_position.y, rider.global_basis.y.y, carrier.global_basis.y.y])
		return true
	return false
