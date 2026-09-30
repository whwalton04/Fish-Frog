class_name ContactCrab
extends RigidBody3D
## Contact-force crab. See docs/contact-crab-design.md.
##
## The body only moves through its legs: each planted foot pulls its hip toward
## the target pose, limited by the friction cone at the foot. Unplanted feet
## are points on tethers. The leg meshes are purely visual IK.

@export_group("Movement")
@export var move_speed := 3.2
## rad/s
@export var turn_rate := 8.0
## rad/s
@export var tilt_rate := 4.0
## How fast pushing into a wall rolls the crab up it (rad/s).
@export var wall_roll_rate := 0.5

@export_group("Legs")
@export var ride_height := 0.107
## Hip spring along the body's up axis and sideways (N/m).
@export var leg_stiffness := 330.0
@export var leg_lateral_stiffness := 90.0
## Pulls hip velocity toward the wished velocity (N·s/m); drives the body.
@export var leg_damping := 30.0
@export var leg_max_force := 60.0
@export var foot_friction := 0.8
## Leaves out other crabs, which are bumped into but not walked on.
@export_flags_3d_physics var foot_mask := 1
## 0..1
@export var terrain_follow := 1.0

@export_group("Gait")
@export var step_threshold := 0.14
## Used when standing still so the stance tidies itself up.
@export var settle_threshold := 0.027
## 1/s²
@export var swing_stiffness := 80000.0
@export var step_height := 0.05
## Seconds of velocity to place feet ahead of the body.
@export var velocity_lead := 0.1
@export var foot_placement_jitter := 0.027

@export_group("Limp")
## Spring (1/s²) and damping (1/s) holding a foot with no foothold on the body.
@export var limp_stiffness := 400.0
@export var limp_damping := 8.0

@export_group("Recovery")
## 0 disables.
@export var self_right_torque := 12.0
## Torque per radian holding the lean while rolling up a wall. 0 disables.
@export var wall_roll_torque := 6.0

@export_group("Shape")
## Half width (x) and half length (z) of the carapace.
@export var body_half_extents := Vector2(0.167, 0.133)
@export var hip_height := -0.01
## Merus, carpus+propodus, dactyl lengths (before per-leg scale).
@export var segment_lengths := Vector3(0.14, 0.133, 0.08)
@export var dactyl_tilt_deg := 20.0
@export var leg_color := Color(0.88, 0.42, 0.24)

# Per-leg layout, front to back. Degrees from the side axis; negative is forward.
const HIP_ANGLES := [-40.0, -14.0, 12.0, 36.0]
const FOOT_ANGLES := [-60.0, -22.0, 16.0, 48.0]
const FOOT_REACH := [0.22, 0.247, 0.24, 0.207]
const LEG_SCALE := [0.9, 1.0, 1.0, 0.86]
const SEGMENT_RADII := [Vector2(0.015, 0.012), Vector2(0.012, 0.0087), Vector2(0.0087, 0.002)]
# Reach limits as fractions of full leg length.
const MIN_REACH := 0.3
const MIN_SPREAD := 0.1
const MAX_RAISE := 0.5  # sin(30°)
const MAX_REACH := 0.98
# Below MAX_REACH so a fresh foot isn't released straight away.
const HOLD_REACH := 0.95
const SELF_RIGHT_DELAY := 0.5
const AIRBORNE_DELAY := 0.05
const MAX_PITCH := 0.466  # tan(25°)
# Surfaces with normal.y below this (cos 60°) are walls.
const WALL_NORMAL_Y := 0.5
const WALL_ROLL_LAG := 0.35
const FOOT_RADIUS := 0.002

class Point:
	var pos: Vector3
	var vel := Vector3.ZERO

class Leg:
	var hip_local: Vector3
	var rest_local: Vector3
	var out_local: Vector3
	var length_scale: float
	var group: int  # legs in the same group step together
	var foot := Point.new()
	var planted := false
	var normal := Vector3.UP
	var collider: Object
	var has_hold := false
	var hold: Vector3
	var hold_normal := Vector3.UP
	var hold_collider: Object
	var segments: Array[MeshInstance3D] = []
	var joints: Array[MeshInstance3D] = []

## World space, horizontal, length 0..1 of full speed. Set by Player.
var move_direction := Vector3.ZERO
## World space. Zero keeps the current facing.
var facing_direction := Vector3.ZERO

var _legs: Array[Leg] = []
var _initialized := false
var _wish := Vector3.ZERO
var _drive := Vector3.ZERO
var _desired_facing := Vector3.FORWARD
var _target_basis := Basis()
var _fit_center := Vector3.ZERO
var _wall_roll := 0.0
var _wall_normal := Vector3.ZERO
var _walls_seen := Vector3.ZERO
var _stuck_time := 0.0
var _support := 0.0
var _pushing := false
var _air_time := 0.0
var _airborne := false
var _righting := false
var _time := 0.0


func _ready() -> void:
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = leg_color
	leg_mat.roughness = 0.6

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
	for radii in SEGMENT_RADII:
		var mesh := SphereMesh.new()
		mesh.radius = radii.x * 1.1
		mesh.height = radii.x * 2.2
		mesh.radial_segments = 10
		mesh.rings = 5
		mesh.material = leg_mat
		joint_meshes.append(mesh)

	for side in [-1.0, 1.0]:
		for i in 4:
			var leg := _make_leg(side, i)
			for s in 3:
				leg.segments.append(_add_visual(segment_meshes[s]))
				leg.joints.append(_add_visual(joint_meshes[s]))
			_legs.append(leg)

	_desired_facing = -global_basis.z
	_target_basis = global_basis.orthonormalized()


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
	leg.foot.pos = to_global(leg.rest_local)
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
	_time += delta
	_wish = _get_wish_velocity()
	_update_target_basis(delta)
	_update_gait()

	_support = 0.0
	_pushing = false
	_fit_center = _fit_body_center()
	for leg in _legs:
		if leg.planted:
			_push_with_leg(leg)
		else:
			_move_free_foot(leg, delta)
	_air_time = 0.0 if _pushing else _air_time + delta
	_airborne = _air_time > AIRBORNE_DELAY

	_apply_self_right(delta)
	_apply_wall_roll()


func _process(_delta: float) -> void:
	for leg in _legs:
		_pose_leg(leg)


# --- Target pose --------------------------------------------------------------

func _get_wish_velocity() -> Vector3:
	var level := Vector3(facing_direction.x, 0.0, facing_direction.z)
	if level.length_squared() > 1e-4:
		_desired_facing = level.normalized()
	return Vector3(move_direction.x, 0.0, move_direction.z).limit_length(1.0) * move_speed


## The pose the legs try to hold the body in, updated at limited rates.
func _update_target_basis(delta: float) -> void:
	var ground_sum := Vector3.ZERO
	var wall_sum := Vector3.ZERO
	for leg in _legs:
		if leg.planted:
			if leg.normal.y > WALL_NORMAL_Y:
				ground_sum += leg.normal
			else:
				wall_sum += leg.normal
	var forward := -_target_basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var turn := forward.signed_angle_to(_desired_facing, Vector3.UP)
	forward = forward.rotated(Vector3.UP, clampf(turn, -turn_rate * delta, turn_rate * delta))

	var up := Vector3.UP
	if ground_sum.length_squared() > 1e-6:
		up = up.lerp(ground_sum.normalized(), terrain_follow).normalized()
		# Crabs roll freely but pitch little.
		var pitch := up.dot(forward)
		var rest := up - forward * pitch
		up = (rest + forward * clampf(pitch, -rest.length() * MAX_PITCH, rest.length() * MAX_PITCH)).normalized()
	_drive = Quaternion(Vector3.UP, up) * _wish

	_update_wall_roll(wall_sum + _walls_seen, delta)
	_walls_seen = Vector3.ZERO
	if _wall_roll > 0.0:
		up = up.rotated(Vector3.UP.cross(_wall_normal).normalized(), _wall_roll)

	var tilt := _target_basis.y.angle_to(up)
	if tilt > tilt_rate * delta:
		up = _target_basis.y.slerp(up, tilt_rate * delta / tilt).normalized()
	var level_forward := forward - up * forward.dot(up)
	if level_forward.length_squared() > 1e-4:
		_target_basis = Basis.looking_at(level_forward, up)


func _update_wall_roll(wall_sum: Vector3, delta: float) -> void:
	var pushing := _pushing_into(wall_sum)
	if pushing:
		_wall_normal = Vector3(wall_sum.x, 0.0, wall_sum.z).normalized()
	if global_basis.y.y < -0.3:
		_wall_roll = 0.0
	elif pushing:
		# Only grows while the body keeps up.
		if _target_basis.y.angle_to(Vector3.UP) - global_basis.y.angle_to(Vector3.UP) < WALL_ROLL_LAG:
			_wall_roll += wall_roll_rate * delta
	else:
		_wall_roll = maxf(_wall_roll - wall_roll_rate * 2.0 * delta, 0.0)


func _pushing_into(wall_normal: Vector3) -> bool:
	var level := Vector3(wall_normal.x, 0.0, wall_normal.z)
	if level.length_squared() < 1e-4 or _wish.length_squared() < 0.01:
		return false
	return _wish.normalized().dot(-level.normalized()) > 0.5


# --- Legs ---------------------------------------------------------------------

## Springs the hip toward the target pose over the planted feet, carries an
## eighth of the weight and drives toward the wished velocity, limited by the
## friction cone.
func _push_with_leg(leg: Leg) -> void:
	if not _in_reach(leg, leg.foot.pos, MAX_REACH):
		leg.planted = false
		return
	var hip := to_global(leg.hip_local)
	var offset := hip - global_position
	var hip_vel := linear_velocity + angular_velocity.cross(offset)
	var up := _target_basis.y

	# A foot can't pull the body toward its surface.
	var drive := _drive
	var into := drive.dot(leg.normal)
	if into < 0.0:
		drive -= leg.normal * into

	var error := _fit_center + _target_basis * leg.hip_local - hip
	var lift := up * error.dot(up)
	var force := lift * leg_stiffness + (error - lift) * leg_lateral_stiffness \
			+ (drive - hip_vel) * leg_damping \
			- get_gravity() * mass / _legs.size()
	force = _friction_cone(force, leg.normal).limit_length(leg_max_force)
	if force == Vector3.ZERO:
		if _airborne and hip.distance_to(leg.foot.pos) > (leg.rest_local - leg.hip_local).length():
			leg.planted = false
		return
	_pushing = true

	# Level with the centre of mass, so driving doesn't pitch the body.
	apply_force(force, offset - global_basis.y * offset.dot(global_basis.y))
	_support += force.dot(global_basis.y)
	var body := leg.collider as RigidBody3D
	if body:
		body.apply_force(-force, leg.foot.pos - body.global_position)


## Average body centre implied by each planted foot's rest spot. Wall feet
## count only when no foot is on the ground.
func _fit_body_center() -> Vector3:
	var ground := Vector3.ZERO
	var ground_count := 0
	var wall := Vector3.ZERO
	var wall_count := 0
	for leg in _legs:
		if not leg.planted:
			continue
		var center := leg.foot.pos - _target_basis * leg.rest_local
		if leg.normal.y > WALL_NORMAL_Y:
			ground += center
			ground_count += 1
		else:
			wall += center
			wall_count += 1
	if ground_count > 0:
		return ground / ground_count
	return wall / wall_count if wall_count > 0 else global_position


## Push only, never pull; sideways force at most friction times push.
func _friction_cone(force: Vector3, normal: Vector3) -> Vector3:
	var push := force.dot(normal)
	if push <= 0.0:
		return Vector3.ZERO
	var slide := force - normal * push
	return normal * push + slide.limit_length(foot_friction * push)


func _update_gait() -> void:
	var flat_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	# Capped so feet spend as long ahead of the hip as behind it.
	var lead := (flat_vel * velocity_lead).limit_length(step_threshold * 0.5)
	var moving := flat_vel.length() > 0.1 or absf(angular_velocity.y) > 0.4
	var threshold := step_threshold if moving else settle_threshold
	var swinging := [false, false]
	for leg in _legs:
		if not leg.planted and leg.has_hold:
			swinging[leg.group] = true

	for leg in _legs:
		# A swinging foot keeps its foothold, or it would chase it forever.
		if leg.planted or not leg.has_hold or not _in_reach(leg, leg.hold, HOLD_REACH):
			leg.has_hold = _find_hold(leg, lead)
		if not _initialized:
			leg.planted = leg.has_hold
			if leg.planted:
				_plant(leg, leg.hold, leg.hold_normal, leg.hold_collider)
			continue
		if not leg.planted or not leg.has_hold:
			continue
		if leg.foot.pos.distance_to(leg.hold) > threshold and not swinging[1 - leg.group]:
			leg.planted = false
			leg.foot.vel = Vector3.ZERO
			_scatter_hold(leg)
			swinging[leg.group] = true
	_initialized = true


## Raycasts in the body's frame from hip height out above the foot's home spot,
## then down. Rising ground, or a wall being walked into, is reached along.
func _find_hold(leg: Leg, lead: Vector3) -> bool:
	var pose := global_basis.orthonormalized()
	var up := pose.y
	var from := global_position + up * leg.hip_local.y
	var above := global_position + pose * leg.rest_local + lead \
			+ up * (leg.hip_local.y - leg.rest_local.y)
	var obstacle := _ray(from, above)
	var hit := {}
	if obstacle.is_empty():
		hit = _ray(above, above - up * _leg_reach(leg))
	elif obstacle.normal.y > WALL_NORMAL_Y or _pushing_into(obstacle.normal):
		hit = _reach_along(obstacle, above)
	else:
		var base: Vector3 = obstacle.position + obstacle.normal * 0.02
		hit = _ray(base, base - up * _leg_reach(leg))
	if not obstacle.is_empty() and obstacle.normal.y <= WALL_NORMAL_Y:
		_walls_seen += obstacle.normal
	if (hit.is_empty() or not _in_reach(leg, hit.position, HOLD_REACH)) and not obstacle.is_empty():
		hit = obstacle
	if hit.is_empty() or not _in_reach(leg, hit.position, HOLD_REACH):
		return false
	leg.hold = hit.position
	leg.hold_normal = hit.normal
	leg.hold_collider = hit.collider
	return true


func _reach_along(surface: Dictionary, goal: Vector3) -> Dictionary:
	var n: Vector3 = surface.normal
	var start: Vector3 = surface.position + n * 0.01
	var along: Vector3 = goal - surface.position
	along -= n * along.dot(n)
	var over: Vector3 = start + along + n * step_height
	if not _ray(start, start + n * step_height).is_empty() \
			or not _ray(start + n * step_height, over).is_empty():
		return {}
	return _ray(over, over - n * step_height * 3.0)


func _scatter_hold(leg: Leg) -> void:
	var n := leg.hold_normal
	var tangent := n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD).normalized()
	var offset := tangent.rotated(n, randf() * TAU) * randf() * foot_placement_jitter
	var lifted := leg.hold + n * 0.02
	if not _ray(lifted, lifted + offset).is_empty():
		return
	var hit := _ray(lifted + offset, lifted + offset - n * 0.05)
	if not hit.is_empty():
		leg.hold = hit.position
		leg.hold_normal = hit.normal
		leg.hold_collider = hit.collider


func _move_free_foot(leg: Leg, delta: float) -> void:
	var hip := to_global(leg.hip_local)
	var hip_vel := linear_velocity + angular_velocity.cross(hip - global_position)
	if hip.distance_to(leg.foot.pos) > _leg_reach(leg) * 2.0:
		leg.foot.pos = hip
		leg.foot.vel = hip_vel
	var from := leg.foot.pos
	var target: Vector3
	var stepping := leg.has_hold and not _airborne
	if stepping:
		# Arc over, then strike slightly into the surface.
		var to_foot := leg.foot.pos - leg.hold
		var across := (to_foot - leg.hold_normal * to_foot.dot(leg.hold_normal)).length()
		var lift_dir := (global_basis.y + leg.hold_normal).normalized()
		target = leg.hold + lift_dir * minf(across, step_height) - leg.hold_normal * step_height * 0.5
		_spring_point(leg.foot, target, Vector3.ZERO, swing_stiffness, 2.0 * sqrt(swing_stiffness),
				Vector3.ZERO, delta)
	else:
		var pose := leg.rest_local + Vector3.UP * ride_height * 0.4
		if _righting:
			pose += Vector3.UP * sin(_time * 22.0 + leg.hip_local.z * 60.0) * ride_height
		target = to_global(pose)
		var target_vel := linear_velocity + angular_velocity.cross(target - global_position)
		_spring_point(leg.foot, target, target_vel, limp_stiffness, limp_damping,
				get_gravity(), delta)

	var reach := _leg_reach(leg)
	_tether(leg.foot, hip, hip_vel, reach * MIN_REACH, reach * MAX_REACH)
	var hit := _collide(leg.foot, from, FOOT_RADIUS)
	if stepping and leg.foot.pos.distance_to(leg.hold) < 0.01:
		_plant(leg, leg.hold, leg.hold_normal, leg.hold_collider)
	elif not hit.is_empty() and _in_reach(leg, hit.position, HOLD_REACH):
		_plant(leg, hit.position, hit.normal, hit.collider)


func _plant(leg: Leg, at: Vector3, normal: Vector3, collider: Object) -> void:
	leg.planted = true
	# Off the surface, so later rays from here still see it.
	leg.foot.pos = at + normal * FOOT_RADIUS
	leg.foot.vel = Vector3.ZERO
	leg.normal = normal
	leg.collider = collider


## Between folded and stretched, on the leg's own side, not far above the hip.
func _in_reach(leg: Leg, point: Vector3, max_fraction: float) -> bool:
	var to_point := point - to_global(leg.hip_local)
	var dist := to_point.length()
	var reach := _leg_reach(leg)
	return dist > reach * MIN_REACH and dist < reach * max_fraction \
			and to_point.dot(global_basis.y) < dist * MAX_RAISE \
			and to_point.dot(global_basis * leg.out_local) > reach * MIN_SPREAD


func _leg_reach(leg: Leg) -> float:
	return (segment_lengths.x + segment_lengths.y + segment_lengths.z) * leg.length_scale


# --- Points on tethers ----------------------------------------------------------

## Implicit-Euler spring-damper step: stable at any stiffness.
func _spring_point(p: Point, target: Vector3, target_vel: Vector3, stiffness: float,
		damping: float, accel: Vector3, dt: float) -> void:
	p.vel = (p.vel + dt * (stiffness * (target - p.pos) + damping * target_vel + accel)) \
			/ (1.0 + dt * damping + dt * dt * stiffness)
	p.pos += p.vel * dt


func _tether(p: Point, anchor: Vector3, anchor_vel: Vector3, min_len: float, max_len: float) -> void:
	var offset := p.pos - anchor
	var dist := offset.length()
	if dist < 1e-6:
		return
	var clamped := clampf(dist, min_len, max_len)
	if clamped == dist:
		return
	var dir := offset / dist
	p.pos = anchor + dir * clamped
	var rel := (p.vel - anchor_vel).dot(dir)
	if (dist > clamped and rel > 0.0) or (dist < clamped and rel < 0.0):
		p.vel -= dir * rel


func _collide(p: Point, from: Vector3, radius: float) -> Dictionary:
	var hit := _ray(from, p.pos)
	if not hit.is_empty():
		var normal: Vector3 = hit.normal
		p.pos = hit.position + normal * radius
		p.vel -= normal * minf(p.vel.dot(normal), 0.0)
	return hit


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, foot_mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


# --- Recovery ------------------------------------------------------------

## Rolls the crab back over once it has lain tipped over, unsupported by its
## legs, for SELF_RIGHT_DELAY.
func _apply_self_right(delta: float) -> void:
	var up := global_basis.y
	var held_up := _support > get_gravity().length() * mass * 0.3 and up.y > -0.2
	_stuck_time = _stuck_time + delta if up.y < 0.3 and not held_up else 0.0
	_righting = self_right_torque > 0.0 and _stuck_time > SELF_RIGHT_DELAY
	if not _righting:
		return
	var axis := up.cross(Vector3.UP)
	if axis.length_squared() < 0.01:
		axis = global_basis.z
	apply_torque(axis.normalized() * self_right_torque - angular_velocity * self_right_torque * 0.3)


func _apply_wall_roll() -> void:
	if _wall_roll <= 0.0 or wall_roll_torque <= 0.0 or _righting:
		return
	var axis := global_basis.y.cross(_target_basis.y)
	var angle := global_basis.y.angle_to(_target_basis.y)
	if axis.length_squared() > 1e-8:
		axis = axis.normalized() * angle
	apply_torque(axis * wall_roll_torque - angular_velocity * wall_roll_torque * 0.1)


# --- Visuals ----------------------------------------------------------------------

func _pose_leg(leg: Leg) -> void:
	var up := global_basis.y
	var lengths := segment_lengths * leg.length_scale
	var hip := to_global(leg.hip_local)
	var foot := leg.foot.pos

	var outward := foot - hip
	outward -= up * outward.dot(up)
	outward = outward.normalized() if outward.length_squared() > 1e-6 else global_basis * leg.out_local

	# Dactyl stands out from the surface, leaning in toward the body.
	var normal := leg.normal if leg.planted else up
	var inward := -(outward - normal * outward.dot(normal))
	var tilt := deg_to_rad(dactyl_tilt_deg)
	var dactyl := normal * cos(tilt)
	if inward.length_squared() > 1e-6:
		dactyl += inward.normalized() * sin(tilt)
	var ankle := foot + dactyl * lengths.z

	# Two-bone IK hip -> ankle, knee bent upward.
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
		ankle = hip + dir * reach

	_place_segment(leg.segments[0], hip, knee)
	_place_segment(leg.segments[1], knee, ankle)
	_place_segment(leg.segments[2], ankle, foot)
	leg.joints[0].global_position = hip
	leg.joints[1].global_position = knee
	leg.joints[2].global_position = ankle


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
