class_name Crab
extends RigidBody3D
## Physics-driven crab.
##
## The body is a single rigid body held up by eight procedural feet: points
## that snap to the ground, step to keep up with the body, and push/pull on the
## body like springs attached at the hips. Because each foot only supports the
## body while planted, the body bobs, tilts and drifts as the gait cycles.
## The leg meshes are purely visual 3-segment IK drawn between hip and foot.

@export_group("Movement")
## Top walking speed (m/s).
@export var move_speed := 3.2
## How quickly the body tries to reach the wished velocity (1/s).
@export var move_response := 8.0
@export var max_drive_force := 100.0
@export var turn_stiffness := 13.0
@export var turn_damping := 1.6

@export_group("Suspension")
## Desired height of the body centre above the feet.
@export var ride_height := 0.107
@export var leg_stiffness := 330.0
@export var leg_damping := 12.0
@export var leg_max_force := 60.0
## Horizontal spring pulling each hip back over its planted foot. This is what
## makes the body drift and jiggle as feet plant ahead and fall behind.
@export var foot_anchor_stiffness := 90.0
@export var upright_stiffness := 2.0
@export var upright_damping := 0.2

@export_group("Gait")
## How far a foot may lag its target before stepping while walking.
@export var step_threshold := 0.14
## Smaller threshold used when standing still so the stance tidies itself up.
@export var settle_threshold := 0.027
@export var step_duration := 0.04
@export var step_height := 0.05
## Seconds of velocity to place feet ahead of the body.
@export var velocity_lead := 0.1
## Random scatter of where each foot lands (m). Uneven footing is what makes
## the anchor springs nudge the body around instead of cancelling out.
@export var foot_placement_jitter := 0.027
## Random variation of each step's duration (fraction).
@export var step_time_jitter := 0.2

@export_group("Shape")
## Half width (x) and half length (z) of the carapace, used to place hips.
@export var body_half_extents := Vector2(0.167, 0.133)
@export var hip_height := -0.01
## Merus, carpus+propodus, dactyl lengths (before per-leg scale).
@export var segment_lengths := Vector3(0.14, 0.133, 0.08)
## How far the dactyl (last segment) leans inward from vertical.
@export var dactyl_tilt_deg := 20.0
@export var leg_color := Color(0.88, 0.42, 0.24)
@export var show_foot_markers := true

@export_group("Falling")
## Feet with no reachable ground go limp. How strongly they spring back toward
## a relaxed pose (1/s²), how much their motion follows the body, and air drag.
@export var limp_pose_stiffness := 30.0
@export var limp_joint_damping := 3.0
@export var limp_air_drag := 0.6

@export_group("Walls")
## Feet that meet a wall before their rest spot brace against it, pushing the
## body away like struts. Stiffness of that push (N/m).
@export var wall_brace_stiffness := 250.0
## How far the hip is held from the wall, as a fraction of the leg's natural
## sideways reach. Below 1 so braced feet stay on the wall once pushed off.
@export var wall_standoff := 0.85
## Fraction of a normal leg's support a braced foot gives, as if standing at
## the wall's base. Below 1 lets the braced side sag so the body leans in.
@export var wall_support := 0.6
## Pushing side-on into a wall makes braced feet lift their hips up it
## instead, rolling the body away from the wall (and over, if kept up). Scales
## how hard they can lift, relative to a normal leg.
@export var wall_climb_strength := 1.0
## Top speed the hips rise while climbing (m/s): how long a push it takes to
## roll over.
@export var wall_climb_speed := 0.15

@export_group("Recovery")
## Torque that rolls the crab back over once it has lain on its back or side
## for `self_right_delay` seconds. 0 disables.
@export var self_right_torque := 12.0
@export var self_right_delay := 0.5

@export_group("Eyes")
## Eye stalks are simulated springs: they lag behind the body's motion, wobble
## after bumps and bend off walls. Stiffness (1/s²) and damping (1/s).
@export var eye_stiffness := 700.0
@export var eye_damping := 5.0
## How far a stalk may bend from upright.
@export var eye_max_bend_deg := 75.0
@export var eye_radius := 0.01

# Per-leg layout, front to back. Angles are degrees around the body measured
# from the side axis; negative points toward the front (-Z).
const HIP_ANGLES := [-40.0, -14.0, 12.0, 36.0]
const FOOT_ANGLES := [-60.0, -22.0, 16.0, 48.0]
const FOOT_REACH := [0.22, 0.247, 0.24, 0.207]
const LEG_SCALE := [0.9, 1.0, 1.0, 0.86]
## Fractions of full leg reach a step target, and a planted foot, may sit at.
const TARGET_REACH := 0.95
const PLANTED_REACH := 0.98
## Climbing lift per m/s the hip is short of wall_climb_speed (N·s/m).
const CLIMB_SPEED_GAIN := 400.0
const SEGMENT_RADII := [Vector2(0.015, 0.012), Vector2(0.012, 0.0087), Vector2(0.0087, 0.002)]

class Leg:
	var hip_local: Vector3
	var rest_local: Vector3
	var out_local: Vector3
	var length_scale: float
	## Tetrapod gait: legs in the same group step together.
	var group: int
	var foot: Vector3
	var foot_vel := Vector3.ZERO
	var target: Vector3
	var target_normal := Vector3.UP
	## The target is on a wall rather than the ground.
	var target_wall := false
	## Surface the foot is on while planted (and where a step started).
	var foot_normal := Vector3.UP
	var foot_wall := false
	var planted := false
	var stepping := false
	var step_t := 0.0
	var step_time := 0.0
	var step_offset := Vector3.ZERO
	var step_from: Vector3
	var step_to: Vector3
	var step_from_normal := Vector3.UP
	var step_from_wall := false
	var segments: Array[MeshInstance3D] = []
	var joints: Array[MeshInstance3D] = []
	var marker: MeshInstance3D

class Eye:
	var stalk: MeshInstance3D
	var base_local: Vector3
	## Base to eye centre.
	var length: float
	var half_stalk: float
	var tip: Vector3
	var tip_vel := Vector3.ZERO

var _legs: Array[Leg] = []
var _eyes: Array[Eye] = []
var _initialized := false
var _ground_normal := Vector3.UP
var _desired_facing := Vector3.FORWARD
var _wish := Vector3.ZERO
## How much the feet on walls are climbing, averaged (0..1), from last tick.
var _climb_amount := 0.0
var _stuck_time := 0.0
var _righting := false
var _time := 0.0
var _marker_planted_mat: StandardMaterial3D
var _marker_stepping_mat: StandardMaterial3D


func _ready() -> void:
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = leg_color
	leg_mat.roughness = 0.6
	_marker_planted_mat = StandardMaterial3D.new()
	_marker_planted_mat.albedo_color = Color(0.15, 0.55, 0.95)
	_marker_stepping_mat = StandardMaterial3D.new()
	_marker_stepping_mat.albedo_color = Color(0.95, 0.85, 0.2)

	var segment_meshes: Array[CylinderMesh] = []
	for radii in SEGMENT_RADII:
		var mesh := CylinderMesh.new()
		mesh.height = 1.0
		mesh.bottom_radius = radii.x
		mesh.top_radius = radii.y
		mesh.radial_segments = 10
		mesh.rings = 1
		mesh.material = leg_mat
		segment_meshes.append(mesh)
	var joint_meshes: Array[SphereMesh] = []
	for radius in [SEGMENT_RADII[0].x, SEGMENT_RADII[1].x, SEGMENT_RADII[2].x]:
		var mesh := SphereMesh.new()
		mesh.radius = radius * 1.1
		mesh.height = radius * 2.2
		mesh.radial_segments = 10
		mesh.rings = 5
		mesh.material = leg_mat
		joint_meshes.append(mesh)
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.013
	marker_mesh.bottom_radius = 0.013
	marker_mesh.height = 0.007
	marker_mesh.radial_segments = 12

	for side in [-1.0, 1.0]:
		for i in 4:
			var leg := _make_leg(side, i)
			for s in 3:
				leg.segments.append(_add_visual(segment_meshes[s]))
				leg.joints.append(_add_visual(joint_meshes[s]))
			leg.marker = _add_visual(marker_mesh)
			leg.marker.visible = show_foot_markers
			_legs.append(leg)

	for stalk_name in ["StalkL", "StalkR"]:
		var stalk := get_node_or_null(stalk_name) as MeshInstance3D
		if stalk:
			_eyes.append(_make_eye(stalk))


## Takes over a stalk from the scene (stalk mesh centred on its node, eye as
## its first child) and simulates it from then on.
func _make_eye(stalk: MeshInstance3D) -> Eye:
	var eye := Eye.new()
	eye.stalk = stalk
	eye.half_stalk = (stalk.mesh as CylinderMesh).height * 0.5
	eye.base_local = stalk.position - stalk.basis.y * eye.half_stalk
	eye.length = eye.half_stalk + (stalk.get_child(0) as Node3D).position.y
	eye.tip = to_global(eye.base_local + Vector3.UP * eye.length)
	stalk.top_level = true
	return eye


func _make_leg(side: float, i: int) -> Leg:
	var leg := Leg.new()
	var hip_dir := _side_dir(side, HIP_ANGLES[i])
	var foot_dir := _side_dir(side, FOOT_ANGLES[i])
	leg.length_scale = LEG_SCALE[i]
	leg.hip_local = Vector3(
		hip_dir.x * body_half_extents.x * 0.9, hip_height, hip_dir.z * body_half_extents.y * 0.9)
	leg.out_local = foot_dir
	leg.rest_local = leg.hip_local + foot_dir * FOOT_REACH[i] * leg.length_scale
	leg.rest_local.y = -ride_height
	leg.group = (i + (1 if side > 0.0 else 0)) % 2
	leg.foot = to_global(leg.rest_local)
	return leg


func _side_dir(side: float, degrees: float) -> Vector3:
	var r := deg_to_rad(degrees)
	return Vector3(side * cos(r), 0.0, sin(r))


func _add_visual(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.top_level = true
	add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	var flat_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	_time += delta
	_wish = _get_wish_velocity()
	_update_feet(delta, flat_vel)
	var support := _apply_leg_forces()
	_apply_drive(_wish, flat_vel, support)
	_apply_turning(_wish)
	_apply_upright()
	_apply_self_right(delta)
	_update_eyes(delta)


func _process(_delta: float) -> void:
	var up := global_basis.y
	for leg in _legs:
		_pose_leg(leg, up)
	for eye in _eyes:
		_pose_eye(eye)


# --- Input -------------------------------------------------------------------

func _get_wish_velocity() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam := get_viewport().get_camera_3d()
	var cam_basis := cam.global_basis if cam else global_basis
	var forward := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()
	var right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z).normalized()
	_desired_facing = forward
	return (right * input.x - forward * input.y) * move_speed


# --- Feet --------------------------------------------------------------------

func _update_feet(delta: float, flat_vel: Vector3) -> void:
	# Capped at half the threshold so feet spend as long ahead of the hip as
	# behind it, keeping the anchor springs from dragging or pushing on average.
	var lead := (flat_vel * velocity_lead).limit_length(step_threshold * 0.5)
	var moving := flat_vel.length() > 0.1 or absf(angular_velocity.y) > 0.4
	var group_stepping := [false, false]
	for leg in _legs:
		if leg.stepping:
			group_stepping[leg.group] = true

	for leg in _legs:
		var hit := _probe_ground(leg, lead)
		if not _initialized:
			leg.planted = hit
			if hit:
				leg.foot = leg.target
				leg.foot_normal = leg.target_normal
				leg.foot_wall = leg.target_wall
			continue
		var prev := leg.foot
		if _update_foot(leg, delta, hit, moving, group_stepping):
			leg.foot_vel = (leg.foot - prev) / delta
	_initialized = true


## Steps, plants or lets one foot hang. Returns false while the foot is limp
## (its velocity is then simulated rather than derived from its motion).
func _update_foot(leg: Leg, delta: float, hit: bool, moving: bool, group_stepping: Array) -> bool:
	if leg.stepping:
		if _is_reachable(leg, leg.step_to, TARGET_REACH):
			_advance_step(leg, delta, hit)
			return true
		leg.stepping = false  # the ground fell away mid-step: go limp
	if leg.planted and not _is_reachable(leg, leg.foot, PLANTED_REACH):
		leg.planted = false  # left behind on a ledge or overstretched: let go
	if not hit:
		leg.planted = false
		_simulate_limp(leg, delta)
		return false

	var error := leg.foot.distance_to(leg.target)
	var threshold := step_threshold if moving else settle_threshold
	var may_step: bool = not group_stepping[1 - leg.group]
	if not leg.planted or error > step_threshold * 2.0 or (error > threshold and may_step):
		leg.stepping = true
		leg.step_t = 0.0
		leg.step_time = step_duration * (1.0 + randf_range(-step_time_jitter, step_time_jitter))
		var jitter := Vector2.from_angle(randf() * TAU) * randf() * foot_placement_jitter
		leg.step_offset = Vector3(jitter.x, 0.0, jitter.y)
		leg.step_from = leg.foot
		leg.step_from_normal = leg.foot_normal
		leg.step_from_wall = leg.foot_wall
		leg.step_to = _snap_offset_target(leg)
		group_stepping[leg.group] = true
	return true


## Finds where a foot should go. First looks sideways from the body toward the
## foot's rest spot at hip level: a wall in the way becomes a brace point on
## the wall. Otherwise probes down for ground from there, which also keeps the
## probe from starting inside geometry and finding floor beneath a wall. Only
## counts surfaces the leg can reach, so ledges above a falling body are ignored.
func _probe_ground(leg: Leg, lead: Vector3) -> bool:
	var up := global_basis.y
	var probe_rise := hip_height + ride_height * 1.3
	var from := global_position + up * (hip_height + ride_height * 0.3)
	var above_rest := to_global(leg.rest_local) + lead + up * probe_rise
	var result := _ray(from, above_rest)
	if not result.is_empty() and result.normal.dot(Vector3.UP) < 0.6:
		return _set_wall_target(leg, result)
	if result.is_empty() and leg.target_wall and _climb_factor(leg.target_normal) > 0.0:
		# Rolled far up a wall the sideways probe points into the air; keep
		# gripping by reaching straight for the wall this foot was on.
		var hip := to_global(leg.hip_local) + leg.target_normal * 0.05
		var grip := _ray(hip, hip - leg.target_normal * _leg_reach(leg) * 0.8)
		if not grip.is_empty() and grip.normal.dot(Vector3.UP) < 0.6:
			return _set_wall_target(leg, grip)
	if result.is_empty():
		result = _ray(above_rest, above_rest + Vector3.DOWN * (ride_height + 0.4))
	if result.is_empty() or not _is_reachable(leg, result.position, TARGET_REACH):
		return false
	leg.target = result.position
	leg.target_normal = result.normal
	leg.target_wall = false
	return true


## Braces the foot on a wall a little below where the probe hit it, so it
## presses in below the hip rather than level with it. When climbing, the foot
## reaches up the wall to about hip height instead.
func _set_wall_target(leg: Leg, hit: Dictionary) -> bool:
	var normal: Vector3 = hit.normal
	var drop := ride_height * lerpf(0.4, 0.1, _climb_factor(normal))
	var lower: Vector3 = hit.position + normal * 0.03 - global_basis.y * drop
	var low_hit := _ray(lower, lower - normal * 0.06)
	if not low_hit.is_empty() and low_hit.normal.dot(Vector3.UP) < 0.6:
		hit = low_hit
	if not _is_reachable(leg, hit.position, TARGET_REACH):
		return false
	leg.target = hit.position
	leg.target_normal = hit.normal
	leg.target_wall = true
	return true


## How much a foot on a wall with this normal should climb (0..1): the player
## must be pushing into the wall, and the crab must be side-on to it.
func _climb_factor(normal: Vector3) -> float:
	var n := Vector3(normal.x, 0.0, normal.z)
	if n.length_squared() < 1e-4 or _wish.length_squared() < 1e-4:
		return 0.0
	n = n.normalized()
	var into := clampf(-_wish.dot(n) / move_speed, 0.0, 1.0)
	# Side-on = facing along the wall. Uses the forward axis, which stays level
	# as the body rolls up the wall, so climbing doesn't fade mid-roll.
	var forward := Vector3(global_basis.z.x, 0.0, global_basis.z.z)
	if forward.length_squared() < 1e-4:
		return 0.0
	var side_on := clampf((0.85 - absf(forward.normalized().dot(n))) / 0.35, 0.0, 1.0)
	return into * side_on


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


## True if the point isn't well above the hip and is within the given fraction
## of reach. Slightly above is allowed so a crab lying on its belly can still
## plant and push itself back up.
## Targets use a tighter fraction than planted feet so a freshly placed foot
## is never immediately overstretched (which would make it step in a loop).
func _is_reachable(leg: Leg, point: Vector3, reach_fraction: float) -> bool:
	var to_point := point - to_global(leg.hip_local)
	return to_point.dot(global_basis.y) < ride_height * 0.25 \
			and to_point.length() < _leg_reach(leg) * reach_fraction


## The step target plus this step's random scatter, re-snapped to the ground.
## Wall braces aren't scattered, and scatter that would cross a wall is dropped.
func _snap_offset_target(leg: Leg) -> Vector3:
	if leg.step_offset == Vector3.ZERO or leg.target_wall:
		return leg.target
	var lifted := leg.target + Vector3.UP * 0.03
	if not _ray(lifted, lifted + leg.step_offset).is_empty():
		return leg.target
	var from := leg.target + leg.step_offset + Vector3.UP * 0.1
	var result := _ray(from, from + Vector3.DOWN * 0.2)
	if result.is_empty() or not _is_reachable(leg, result.position, TARGET_REACH):
		return leg.target
	return result.position


func _advance_step(leg: Leg, delta: float, hit: bool) -> void:
	leg.step_t = minf(leg.step_t + delta / leg.step_time, 1.0)
	if hit:
		leg.step_to = _snap_offset_target(leg)  # keep tracking the body while in the air
	var t := leg.step_t
	var s := t * t * (3.0 - 2.0 * t)
	# Lift along up, tipped away from any wall at either end of the step.
	var lift := global_basis.y
	if leg.step_from_wall:
		lift += leg.step_from_normal
	if leg.target_wall:
		lift += leg.target_normal
	leg.foot = leg.step_from.lerp(leg.step_to, s) + lift.normalized() * sin(PI * t) * step_height
	if t >= 1.0:
		leg.stepping = false
		leg.planted = true
		leg.foot = leg.step_to
		leg.foot_normal = leg.target_normal
		leg.foot_wall = leg.target_wall


## Ragdoll-ish foot: a point mass under gravity and air drag, loosely sprung
## toward a relaxed pose, tethered to the hip by the leg's length. Plants
## again if it swings into walkable ground within reach.
func _simulate_limp(leg: Leg, delta: float) -> void:
	var hip := to_global(leg.hip_local)
	var hip_vel := linear_velocity + angular_velocity.cross(hip - global_position)
	var pose_local := leg.rest_local + Vector3.UP * ride_height * 0.4
	if _righting:
		# Flail while trying to roll back over.
		pose_local += Vector3.UP * sin(_time * 22.0 + leg.hip_local.z * 60.0) * ride_height
	var pose := to_global(pose_local)
	var pose_vel := linear_velocity + angular_velocity.cross(pose - global_position)
	var accel := get_gravity() \
			+ (pose - leg.foot) * limp_pose_stiffness \
			+ (pose_vel - leg.foot_vel) * limp_joint_damping \
			- leg.foot_vel * limp_air_drag
	leg.foot_vel += accel * delta
	var next := leg.foot + leg.foot_vel * delta

	# Tether: keep the foot between a folded and a fully stretched leg.
	var reach := _leg_reach(leg)
	var offset := next - hip
	var dist := offset.length()
	if dist > 1e-5:
		var dir := offset / dist
		var limit := clampf(dist, reach * 0.3, reach * 0.98)
		if limit != dist:
			next = hip + dir * limit
			var rel := (leg.foot_vel - hip_vel).dot(dir)
			if (limit < dist and rel > 0.0) or (limit > dist and rel < 0.0):
				leg.foot_vel -= dir * rel

	# Cast from slightly above so a foot resting on a surface can't slip through.
	var query := PhysicsRayQueryParameters3D.create(
		leg.foot + Vector3.UP * 0.01, next, collision_mask, [get_rid()])
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var normal: Vector3 = result.normal
		next = result.position + normal * 0.002
		leg.foot_vel -= normal * minf(leg.foot_vel.dot(normal), 0.0)
		if normal.dot(Vector3.UP) > 0.6 and _is_reachable(leg, result.position, PLANTED_REACH):
			leg.planted = true
			leg.foot_normal = normal
			leg.foot_wall = false
			leg.foot_vel = Vector3.ZERO
			next = result.position
	leg.foot = next


func _leg_reach(leg: Leg) -> float:
	return (segment_lengths.x + segment_lengths.y + segment_lengths.z) * leg.length_scale


# --- Forces ------------------------------------------------------------------

## Applies per-leg suspension and anchoring forces. Returns the fraction of
## legs currently supporting the body (0..1).
func _apply_leg_forces() -> float:
	var up := global_basis.y
	var total := 0.0
	var normal_sum := Vector3.ZERO
	var climb_sum := 0.0
	var climb_weight := 0.0
	for leg in _legs:
		var weight := _support_weight(leg)
		if weight <= 0.0:
			continue
		var contact := leg.foot
		var normal := leg.foot_normal
		var on_wall := leg.foot_wall
		if leg.stepping and leg.step_t < 0.5:
			contact = leg.step_from
			normal = leg.step_from_normal
			on_wall = leg.step_from_wall
		elif leg.stepping:
			contact = leg.step_to
			normal = leg.target_normal
			on_wall = leg.target_wall
		var hip := to_global(leg.hip_local)
		var offset := hip - global_position
		var hip_vel := linear_velocity + angular_velocity.cross(offset)

		var support_point := contact
		var support := weight
		var climb := 0.0

		if on_wall:
			climb = _climb_factor(normal)
			climb_sum += climb * weight
			climb_weight += weight
			# Strut pushing the hip out from the wall. Applied at the hip, so
			# it also leans the body.
			var rest_gap := Vector2(leg.rest_local.x - leg.hip_local.x,
					leg.rest_local.z - leg.hip_local.z).length() * wall_standoff
			var gap := (hip - contact).dot(normal)
			var brace := wall_brace_stiffness * (rest_gap - gap) - leg_damping * hip_vel.dot(normal)
			apply_force(normal * clampf(brace, 0.0, leg_max_force) * weight, offset)
			# Hold the body up as if standing at the wall's base; measuring
			# from the contact itself would push the body up the wall.
			var down_wall := contact + normal * 0.02
			var floor_hit := _ray(down_wall, down_wall + Vector3.DOWN * (ride_height + 0.2))
			if floor_hit.is_empty() or floor_hit.normal.dot(Vector3.UP) < 0.6:
				support = 0.0
			else:
				support_point = floor_hit.position
				support *= wall_support
		else:
			# Horizontal spring toward where this foot says the hip should be.
			var anchor := contact - global_basis * (leg.rest_local - leg.hip_local)
			var pull := anchor - hip
			pull.y = 0.0
			apply_force(pull.limit_length(0.13) * foot_anchor_stiffness * weight, offset)
			normal_sum += normal * weight
			# Ease off the ground legs while climbing, else they hold the body
			# level and it can never roll over.
			support *= 1.0 - _climb_amount * 0.7
		# Vertical spring: measured along the body's up so the body leans to
		# match the terrain, but pushed along world up so slopes don't shove
		# the crab sideways.
		var rest_extension := ride_height + leg.hip_local.y
		var lift := _leg_push(support_point, hip, hip_vel, up, rest_extension, leg_max_force) * support
		if climb > 0.0:
			# Climbing: push the hip up off the wall contact itself. Only the
			# wall side rises, so the body rolls away from the wall.
			var climb_lift := _leg_push(contact, hip, hip_vel, up, rest_extension,
					leg_max_force * wall_climb_strength) * weight
			# Rise no faster than the climb speed, so the roll builds gradually.
			climb_lift = minf(climb_lift, maxf(0.0, (wall_climb_speed - hip_vel.y) * CLIMB_SPEED_GAIN))
			lift = lerpf(lift, climb_lift, climb)
		apply_force(Vector3.UP * lift, offset)

		total += weight
	_ground_normal = normal_sum.normalized() if normal_sum.length_squared() > 1e-6 else Vector3.UP
	_climb_amount = climb_sum / climb_weight if climb_weight > 0.0 else 0.0
	return total / _legs.size()


func _leg_push(foot: Vector3, hip: Vector3, hip_vel: Vector3, up: Vector3,
		rest_extension: float, max_force: float) -> float:
	var extension := (hip - foot).dot(up)
	var push := leg_stiffness * (rest_extension - extension) - leg_damping * hip_vel.dot(up)
	return clampf(push, 0.0, max_force)


func _support_weight(leg: Leg) -> float:
	if leg.stepping:
		return maxf(0.0, 1.0 - sin(PI * leg.step_t) * 1.5)
	return 1.0 if leg.planted else 0.0


func _apply_drive(wish: Vector3, flat_vel: Vector3, support: float) -> void:
	var force := ((wish - flat_vel) * move_response * mass).limit_length(max_drive_force)
	# Fades out once tipped well over (e.g. up a wall): pushing the body then
	# would just shove it back upright instead of letting it go over.
	var upright := clampf(global_basis.y.y * 2.0, 0.0, 1.0)
	apply_central_force(force * support * upright)


func _apply_turning(wish: Vector3) -> void:
	var torque := -angular_velocity.y * turn_damping
	var facing := Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
	if wish.length_squared() > 0.01 and facing.length_squared() > 1e-4:
		torque += facing.normalized().signed_angle_to(_desired_facing, Vector3.UP) * turn_stiffness
	apply_torque(Vector3.UP * torque)


func _apply_upright() -> void:
	var up := global_basis.y
	var target_up := _ground_normal.lerp(Vector3.UP, 0.5).normalized()
	var tilt_rate := angular_velocity - up * angular_velocity.dot(up)
	# Fades out once tipped well over so it doesn't hold the crab balanced on
	# its side; getting back up from there is _apply_self_right's job.
	var strength := clampf(up.y * 2.0, 0.0, 1.0)
	apply_torque((up.cross(target_up) * upright_stiffness - tilt_rate * upright_damping) * strength)


## Once the crab has lain tipped over (on its back or side) for a moment, rolls
## it back onto its feet while the legs flail. Held off while it's actively
## climbing a wall, which tips it this far on purpose.
func _apply_self_right(delta: float) -> void:
	var up := global_basis.y
	if up.y < 0.3 and _climb_amount < 0.1:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_righting = self_right_torque > 0.0 and _stuck_time > self_right_delay
	if not _righting:
		return
	var axis := up.cross(Vector3.UP)
	if axis.length_squared() < 0.01:
		axis = global_basis.z  # flat on its back: roll over sideways
	apply_torque(axis.normalized() * self_right_torque)


# --- Eyes --------------------------------------------------------------------

## Each eye is a point on the end of a stiff-but-springy stalk: sprung toward
## upright relative to the body, so it lags and wobbles as the body moves,
## limited in how far it bends, and pushed out of anything it swings into.
func _update_eyes(delta: float) -> void:
	var up := global_basis.y
	var max_bend := deg_to_rad(eye_max_bend_deg)
	for eye in _eyes:
		var base := to_global(eye.base_local)
		var base_vel := linear_velocity + angular_velocity.cross(base - global_position)
		var accel := (base + up * eye.length - eye.tip) * eye_stiffness \
				+ (base_vel - eye.tip_vel) * eye_damping
		var next := eye.tip + (eye.tip_vel + accel * delta) * delta

		var dir := next - base
		dir = dir.normalized() if dir.length_squared() > 1e-8 else up
		var bend := up.angle_to(dir)
		if bend > max_bend:
			var axis := up.cross(dir)
			if axis.length_squared() > 1e-8:
				dir = up.rotated(axis.normalized(), max_bend)
		next = base + dir * eye.length

		var hit := _ray(base, next + dir * eye_radius)
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			var depth: float = (hit.position - next).dot(normal) + eye_radius
			if depth > 0.0:
				next += normal * depth
				next = base + (next - base).normalized() * eye.length

		eye.tip_vel = (next - eye.tip) / delta
		eye.tip = next


func _pose_eye(eye: Eye) -> void:
	var base := to_global(eye.base_local)
	var y := eye.tip - base
	y = y.normalized() if y.length_squared() > 1e-8 else global_basis.y
	var x := global_basis.x - y * global_basis.x.dot(y)
	x = x.normalized() if x.length_squared() > 1e-6 else y.cross(Vector3.FORWARD).normalized()
	eye.stalk.global_transform = Transform3D(Basis(x, y, x.cross(y)), base + y * eye.half_stalk)


# --- Visual IK ---------------------------------------------------------------

func _pose_leg(leg: Leg, up: Vector3) -> void:
	var lengths := segment_lengths * leg.length_scale
	var hip := to_global(leg.hip_local)
	var foot := leg.foot

	var outward := foot - hip
	outward -= up * outward.dot(up)
	outward = outward.normalized() if outward.length_squared() > 1e-6 else global_basis * leg.out_local

	# The dactyl stands nearly upright on the foot, leaning in toward the body,
	# or sticks out from a wall it's braced on. Blends across a step.
	var dactyl := _dactyl_dir(leg.foot_wall, leg.foot_normal, up, outward)
	if leg.stepping:
		var from_dir := _dactyl_dir(leg.step_from_wall, leg.step_from_normal, up, outward)
		var to_dir := _dactyl_dir(leg.target_wall, leg.target_normal, up, outward)
		var t := leg.step_t
		dactyl = from_dir.slerp(to_dir, t * t * (3.0 - 2.0 * t))
	var ankle := foot + dactyl * lengths.z

	# Two-bone IK hip -> ankle with the knee bent upward, so the leg arcs up
	# over the body and then down to the ground.
	var to_ankle := ankle - hip
	var dist := to_ankle.length()
	var dir := to_ankle / dist if dist > 1e-5 else outward
	var reach := clampf(dist, absf(lengths.x - lengths.y) + 1e-3, lengths.x + lengths.y - 1e-3)
	var pole := up - dir * up.dot(dir)
	pole = pole.normalized() if pole.length_squared() > 1e-6 else outward
	var along := (lengths.x * lengths.x - lengths.y * lengths.y + reach * reach) / (2.0 * reach)
	var rise := sqrt(maxf(lengths.x * lengths.x - along * along, 0.0))
	var knee := hip + dir * along + pole * rise
	if dist > reach:
		ankle = hip + dir * reach  # out of reach: let the dactyl stretch to the foot

	_place_segment(leg.segments[0], hip, knee)
	_place_segment(leg.segments[1], knee, ankle)
	_place_segment(leg.segments[2], ankle, foot)
	leg.joints[0].global_position = hip
	leg.joints[1].global_position = knee
	leg.joints[2].global_position = ankle

	leg.marker.visible = show_foot_markers
	if show_foot_markers:
		leg.marker.global_transform = Transform3D(Basis(), foot + Vector3.UP * 0.003)
		leg.marker.material_override = _marker_stepping_mat if leg.stepping else _marker_planted_mat


func _dactyl_dir(on_wall: bool, normal: Vector3, up: Vector3, outward: Vector3) -> Vector3:
	if on_wall:
		return (normal + up * 0.6).normalized()
	var tilt := deg_to_rad(dactyl_tilt_deg)
	return up * cos(tilt) - outward * sin(tilt)


func _place_segment(mi: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 1e-4:
		mi.visible = false
		return
	mi.visible = true
	var y := delta / length
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	mi.global_transform = Transform3D(Basis(x, y * length, x.cross(y)), (from + to) * 0.5)
