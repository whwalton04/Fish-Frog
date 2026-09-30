extends SceneTree
## Headless behaviour scenarios for the crab. Run from the project folder:
##   godot --headless --path . -s res://tests/scenarios.gd
## Env vars: CRAB_SCENE (default res://crab/crab2.tscn) to test another crab,
## SCENARIOS (comma list) to run a subset.
##
## Leg states in the output: P planted, S swinging to a foothold, L limp.

# Platform box in test_terrain: x -2..2, y 0..2.07, z -15.8..-11.8
const PLATFORM_MIN := Vector3(-1.995, -1.0, -15.795)
const PLATFORM_MAX := Vector3(1.995, 2.065, -11.805)

var crab: RigidBody3D
var rig: Node3D


func _initialize() -> void:
	var world: Node = load("res://world/test_terrain.tscn").instantiate()
	var scene_path := OS.get_environment("CRAB_SCENE")
	if scene_path != "":
		var old := world.get_node("Crab")
		world.remove_child(old)
		old.free()
		var replacement: Node = load(scene_path).instantiate()
		replacement.name = "Crab"
		world.add_child(replacement)
	root.add_child(world)
	crab = world.get_node("Crab")
	rig = world.get_node("CameraRig")
	await physics_frame

	var only := OS.get_environment("SCENARIOS")
	for scenario in ["stand", "walk", "facing", "drop", "ramp", "hump", "ledge", "walls", "climb", "eyes"]:
		if only == "" or scenario in only.split(","):
			await call(scenario)
	quit()


# --- Scenarios ------------------------------------------------------------------

func stand() -> void:
	_place(Vector3(0, 0.107, 0))
	var r = await _hold("", 240)
	_report("stand", "y=%.3f tilt=%.0f %s" % [crab.global_position.y, _tilt(), _legs()], r)


func walk() -> void:
	_place(Vector3(0, 0.107, 5))
	await _hold("", 60)
	var start := crab.global_position
	var r = await _hold("move_right", 240)
	var speed := (crab.global_position - start).length() / 2.0
	_report("walk 2s", "avg_speed=%.2f vx=%.2f %s" % [speed, crab.linear_velocity.x, _legs()], r)
	r = await _hold("", 120)
	_report("stop", "speed=%.2f %s" % [crab.linear_velocity.length(), _legs()], r)


## The crab should keep facing the camera's way whichever way it walks.
func facing() -> void:
	for action in ["move_right", "move_left", "move_forward", "move_back"]:
		_place(Vector3(0, 0.107, 12))
		await _hold("", 60)
		var r = await _hold(action, 480)
		_report("face %s 4s" % action, "yaw_err=%.0f %s" % [_yaw_error(), _legs()], r)


func drop() -> void:
	_place(Vector3(0, 2.0, 0))
	var r = await _hold("", 240)
	_report("drop 2m", "y=%.3f tilt=%.0f %s" % [crab.global_position.y, _tilt(), _legs()], r)


func ramp() -> void:
	_place(Vector3(0, 0.107, -3))
	await _hold("", 60)
	var r = await _hold("move_forward", 600)
	_report("ramp", "z=%.2f y=%.3f %s (platform top y=2.07 at z<-11.8)" % [
		crab.global_position.z, crab.global_position.y, _legs()], r)


## Humps: the cylinder ridge along x at z=-6 (x 3..13) and the dome at
## (-8, -5). Crossing should neither stall on the body nor fold the leading
## legs under it.
func hump() -> void:
	var runs := [
		["hump head-on", Vector3(8, 0.107, -1), 0.0, "move_forward", -11.0],
		["hump sideways", Vector3(8, 0.107, -1), PI / 2.0, "move_right", -11.0],
		["dome sideways", Vector3(-8, 0.107, -1), PI / 2.0, "move_right", -9.0],
	]
	for run in runs:
		rig._yaw = run[2]
		rig.rotation.y = run[2]
		_place(run[1])
		crab.global_basis = Basis(Vector3.UP, run[2])
		await _hold("", 60)
		var r = await _hold(run[3], 480)
		_report(run[0], "z=%.2f (goal %.0f) min_speed=%.2f fold=%.2f %s" % [
			crab.global_position.z, run[4], r.min_speed, r.min_spread, _legs()], r)
	rig._yaw = 0.0
	rig.rotation.y = 0.0


func ledge() -> void:
	_place(Vector3(1.3, 2.177, -13.8))
	await _hold("", 60)
	var r = await _hold("move_right", 240)
	var r2 = await _hold("", 120)
	_report("ledge", "x=%.2f y=%.3f tilt=%.0f %s" % [
		crab.global_position.x, crab.global_position.y, _tilt(), _legs()], _merge(r, r2))


func walls() -> void:
	_place(Vector3(2.5, 0.107, -13.8))
	await _hold("", 120)
	var r = await _hold("move_left", 180)
	_report("push side-on 1.5s", "tilt=%.0f lean_away=%.2f %s" % [_tilt(), crab.global_basis.y.x, _legs()], r)
	r = await _hold("", 120)
	_report("rest against wall", "tilt=%.0f %s" % [_tilt(), _legs()], r)
	_place(Vector3(2.35, 0.107, -13.0))
	await _hold("", 60)
	r = await _hold("move_forward", 200)
	_report("walk along wall", "x=%.2f tilt=%.0f %s" % [crab.global_position.x, _tilt(), _legs()], r)
	_place(Vector3(0, 0.107, -10.5))
	await _hold("", 120)
	r = await _hold("move_forward", 240)
	_report("push head-on 2s", "tilt=%.0f %s" % [_tilt(), _legs()], r)


func climb() -> void:
	for seconds in [0.5, 1.0, 2.0, 4.0]:
		_place(Vector3(2.5, 0.107, -13.8))
		await _hold("", 120)
		var r = await _hold("move_left", int(seconds * 120))
		var r2 = await _hold("", 480)
		_report("strafe into wall %.1fs" % seconds, "then released: final tilt=%.0f %s" % [
			_tilt(), _legs()], r, "released", r2)


func eyes() -> void:
	_place(Vector3(0, 0.107, 5))
	await _hold("", 120)
	await _hold("move_right", 120)
	var r = await _hold("", 90)
	_report("eyes after stop", "", r)
	_place(Vector3(0, 1.0, 5))
	await _hold("", 30)
	r = await _hold("", 150)
	_report("eyes after 1m drop", "", r)


# --- Helpers ------------------------------------------------------------------

func _place(p: Vector3) -> void:
	crab.global_transform = Transform3D(Basis(), p)
	crab.linear_velocity = Vector3.ZERO
	crab.angular_velocity = Vector3.ZERO


## Holds an input for some frames and gathers stats over them.
func _hold(action: String, frames: int) -> Dictionary:
	if action != "":
		Input.action_press(action)
	var stats := {max_tilt = 0.0, flipped_at = -1.0, inside = 0, max_eye = 0.0, frames = frames,
			min_speed = INF, min_spread = INF}
	for f in frames:
		await physics_frame
		var tilt := _tilt()
		stats.max_tilt = maxf(stats.max_tilt, tilt)
		if tilt > 120.0 and stats.flipped_at < 0.0:
			stats.flipped_at = f / 120.0
		for leg in crab._legs:
			if _inside_platform(_foot(leg)):
				stats.inside += 1
		stats.max_eye = maxf(stats.max_eye, _eye_bend())
		if f > 60:
			stats.min_speed = minf(stats.min_speed, crab.linear_velocity.length())
		stats.min_spread = minf(stats.min_spread, _spread())
	if action != "":
		Input.action_release(action)
	return stats


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var m := a.duplicate()
	m.max_tilt = maxf(a.max_tilt, b.max_tilt)
	m.inside = a.inside + b.inside
	m.max_eye = maxf(a.max_eye, b.max_eye)
	if m.flipped_at < 0.0 and b.flipped_at >= 0.0:
		m.flipped_at = a.frames / 120.0 + b.flipped_at
	return m


func _report(label: String, detail: String, r: Dictionary, label2 := "", r2 := {}) -> void:
	var line := "%-24s %s | max_tilt=%.0f%s feet_in_wall=%d eye_max=%.0f" % [
		label, detail, r.max_tilt,
		(" FLIPPED@%.2fs" % r.flipped_at) if r.flipped_at >= 0.0 else "", r.inside, r.max_eye]
	if label2 != "":
		line += " | %s: max_tilt=%.0f%s" % [label2, r2.max_tilt,
			(" FLIPPED@%.2fs" % r2.flipped_at) if r2.flipped_at >= 0.0 else ""]
	print(line)


## Degrees between the crab's facing and the camera's.
func _yaw_error() -> float:
	var f := -crab.global_basis.z
	var cam := -rig.global_basis.z
	return rad_to_deg(Vector2(f.x, f.z).angle_to(Vector2(cam.x, cam.z)))


## The least any planted foot sits out from its hip, across the body, as a
## fraction of its rest spread. Near 0: the foot is folded under the body.
func _spread() -> float:
	var worst := INF
	for leg in crab._legs:
		if not leg.planted:
			continue
		var out: Vector3 = crab.global_basis.inverse() * (_foot(leg) - crab.to_global(leg.hip_local))
		var rest: Vector3 = leg.rest_local - leg.hip_local
		worst = minf(worst, Vector2(out.x, out.z).dot(Vector2(rest.x, rest.z).normalized())
				/ Vector2(rest.x, rest.z).length())
	return worst


func _tilt() -> float:
	return rad_to_deg(acos(clampf(crab.global_basis.y.y, -1.0, 1.0)))


func _foot(leg) -> Vector3:
	var p = leg.get("foot")
	return p.pos if p is Object else p


func _legs() -> String:
	var s := ""
	for leg in crab._legs:
		if leg.planted:
			s += "P"
		elif leg.get("stepping") == true or leg.get("has_hold") == true:
			s += "S"
		else:
			s += "L"
	return s


func _eye_bend() -> float:
	var worst := 0.0
	for eye in crab._eyes:
		var tip = eye.get("tip")
		var tip_pos: Vector3 = tip.pos if tip is Object else tip
		var base: Vector3 = crab.to_global(eye.base_local)
		worst = maxf(worst, rad_to_deg(crab.global_basis.y.angle_to(tip_pos - base)))
	return worst


func _inside_platform(p: Vector3) -> bool:
	return p.x > PLATFORM_MIN.x and p.x < PLATFORM_MAX.x and p.y > PLATFORM_MIN.y \
			and p.y < PLATFORM_MAX.y and p.z > PLATFORM_MIN.z and p.z < PLATFORM_MAX.z
