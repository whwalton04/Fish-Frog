class_name ContactCrab
extends RigidBody3D
## Contact-force crab. See docs/contact-crab-design.md.
##
## The body only moves through its legs: each planted foot pulls its hip toward
## the target pose, limited by the friction cone at the foot. Unplanted feet
## are points on tethers. The leg meshes are purely visual IK.

## Each setting is relative to the crab's mass, size or stride, so changing one
## doesn't upset the others.

## Scales the whole crab: body, collision, legs and gait. Mass is left to the
## body's own `mass`. Applied on ready.
@export_range(0.25, 4.0, 0.01) var size := 1.0
## m/s
@export_range(0.0, 10.0, 0.1) var move_speed := 3.2
## rad/s. The body tilts to follow the ground at half this.
@export_range(0.5, 20.0, 0.1) var turn_rate := 8.0
## Bounce frequency of the body on its legs (Hz). Also how quickly it picks
## up speed, until grip limits it.
@export_range(1.0, 8.0, 0.1) var stance_hz := 3.7
## Most a leg can push, in multiples of its share of the body's weight.
@export_range(1.5, 30.0, 0.1) var strength := 10.0
## Foot friction: sideways force per unit of push. Caps acceleration at about
## grip × g.
@export_range(0.1, 2.0, 0.01) var grip := 0.8
## How far a foot drifts from its foothold before stepping, as a fraction of
## leg length.
@export_range(0.1, 0.6, 0.01) var stride := 0.4
## How fast pushing into a wall rolls the crab up it (rad/s). 0 never climbs.
@export_range(0.0, 2.0, 0.01) var climb_rate := 0.5
@export var can_self_right := true

@export_group("Look")
@export var leg_color := Color(0.88, 0.42, 0.24)
## What the feet can stand on, other crabs included.
@export_flags_3d_physics var foot_mask := 3

# Geometry at size 1.
const BODY_HALF_EXTENTS := Vector2(0.167, 0.133)
const HIP_HEIGHT := -0.01
const RIDE_HEIGHT := 0.107
const STEP_HEIGHT := 0.05
# Belly probes: rays start this far above the centre, one this far ahead.
const BODY_HALF_HEIGHT := 0.042
const BELLY_PROBE_HEIGHT := 0.1
const BELLY_LEAD := 0.22
const BELLY_CLEARANCE := 0.02
const MAX_BELLY_LIFT := 0.14
# How far above the hip a foot looks for the top of a wall, × leg reach.
const STEP_UP_RAISE := 0.4
const FOOT_RADIUS := 0.002
# Merus, carpus+propodus, dactyl.
const SEGMENT_LENGTHS := Vector3(0.14, 0.133, 0.08)
const DACTYL_TILT_DEG := 20.0
const STRADDLE_TILT_DEG := 45.0  # leaning out, with the foot under the hip
## How far out, × reach, a foot must stand before the leg reaches toward it
## rather than along its own direction.
const OUTWARD_SPREAD := 0.3
## How much the knee leans out as well as up.
const KNEE_OUTWARD := 0.5

# Legs
const LATERAL_STIFFNESS := 0.27  # × vertical stiffness
const STANCE_DAMPING_RATIO := 1.04
# Gait, as fractions of the step threshold.
const SETTLE_FRACTION := 0.2
const JITTER_FRACTION := 0.2
# Seconds of velocity to place feet ahead of the body.
const LEAD_TIME := 0.1
# Free feet: springs in 1/s², damping in 1/s.
const SWING_STIFFNESS := 80000.0
const LIMP_STIFFNESS := 400.0
const LIMP_DAMPING := 8.0
# Recovery torques, in units of _torque_scale().
const SELF_RIGHT_TORQUE := 0.245
const SELF_RIGHT_DAMPING := 0.23
const WALL_ROLL_TORQUE := 0.122  # per radian
const WALL_ROLL_DAMPING := 0.038

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
## A foot on a foothold may stand this far inward of its hip and this close to
## it, × reach, so it can straddle something narrower than its stance from
## lying on it, rising as the feet take hold.
const FOOTHOLD_INWARD := 0.2
const FOOTHOLD_MIN_REACH := 0.15
## A held foothold is kept until the foot's usual spot is this many capture
## radii away, so the foot doesn't flick between it and the ground.
const FOOTHOLD_KEEP := 1.5
# Below MAX_REACH so a fresh foot isn't released straight away.
const HOLD_REACH := 0.95
const SELF_RIGHT_DELAY := 0.5
const AIRBORNE_DELAY := 0.05
const MAX_PITCH := 0.466  # tan(25°)
# Surfaces with normal.y below this (cos 60°) are walls.
const WALL_NORMAL_Y := 0.5
const WALL_ROLL_LAG := 0.35

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
	# Foot and normal in the collider's frame, so the foot rides it.
	var foot_local: Vector3
	var normal_local: Vector3
	var has_hold := false
	var hold: Vector3
	var hold_normal := Vector3.UP
	var hold_collider: Object
	var hold_local: Vector3
	var hold_normal_local: Vector3
	var hold_foothold: Foothold
	var foothold: Foothold  # the one the planted foot is on
	var stood_on: Foothold  # as last told to the foothold
	var segments: Array[MeshInstance3D] = []
	var joints: Array[MeshInstance3D] = []

## World space, horizontal, length 0..1 of full speed. Set by Player.
var move_direction := Vector3.ZERO
## World space. Zero keeps the current facing.
var facing_direction := Vector3.ZERO

var _legs: Array[Leg] = []
var _initialized := false
# Size as applied on ready, and the settings derived from the exports.
var _size := 1.0
var _segment_lengths := SEGMENT_LENGTHS
var _leg_stiffness := 0.0
var _leg_damping := 0.0
var _leg_max_force := 0.0
var _step_threshold := 0.0
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
var _under: Object  # what's right under the belly, if anything
var _carrier: Object  # what the crab is riding: under it, its feet on its footholds
var _near_footholds: Array[Foothold] = []  # those a foot could take this tick
var _time := 0.0


func _ready() -> void:
	_size = size
	_segment_lengths = SEGMENT_LENGTHS * _size
	_apply_size()

	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = leg_color
	leg_mat.roughness = 0.6

	var segment_meshes: Array[CylinderMesh] = []
	for radii in SEGMENT_RADII:
		var mesh := CylinderMesh.new()
		mesh.height = 1.0
		mesh.bottom_radius = radii.x * _size
		mesh.top_radius = radii.y * _size
		mesh.radial_segments = 10
		mesh.rings = 1
		mesh.material = leg_mat
		segment_meshes.append(mesh)
	var joint_meshes: Array[SphereMesh] = []
	for radii in SEGMENT_RADII:
		var mesh := SphereMesh.new()
		mesh.radius = radii.x * 1.1 * _size
		mesh.height = radii.x * 2.2 * _size
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
		hip_dir.x * BODY_HALF_EXTENTS.x * 0.9, HIP_HEIGHT, hip_dir.z * BODY_HALF_EXTENTS.y * 0.9) * _size
	leg.out_local = foot_dir
	leg.rest_local = leg.hip_local + foot_dir * FOOT_REACH[i] * leg.length_scale * _size
	leg.rest_local.y = -RIDE_HEIGHT * _size
	leg.group = (i + (1 if side > 0.0 else 0)) % 2
	leg.foot.pos = to_global(leg.rest_local)
	return leg


func _side_dir(side: float, degrees: float) -> Vector3:
	var r := deg_to_rad(degrees)
	return Vector3(side * cos(r), 0.0, sin(r))


## Scales the scene's own children (collision, carapace, eyes) to `size`.
## Convex shapes are rebuilt rather than scaled, since physics doesn't like
## scaled shapes.
func _apply_size() -> void:
	if is_equal_approx(_size, 1.0):
		return
	for child in get_children():
		if child is CollisionShape3D and child.shape is ConvexPolygonShape3D:
			var shape: ConvexPolygonShape3D = child.shape.duplicate()
			var points := shape.points
			for i in points.size():
				points[i] *= _size
			shape.points = points
			child.shape = shape
			child.position *= _size
		elif child is Node3D:
			child.transform = child.transform.scaled(Vector3.ONE * _size)


func _add_visual(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.top_level = true
	add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	_time += delta
	_update_tuning()
	_wish = _get_wish_velocity().limit_length(move_speed * _foothold_speed_scale())
	_follow_surfaces()
	_update_target_basis(delta)
	_update_gait()

	_support = 0.0
	_pushing = false
	_fit_center = _fit_body_center()
	_fit_center += _target_basis.y * _belly_lift()
	for leg in _legs:
		if leg.planted:
			_push_with_leg(leg)
		else:
			_move_free_foot(leg, delta)
	_air_time = 0.0 if _pushing else _air_time + delta
	_airborne = _air_time > AIRBORNE_DELAY

	_apply_self_right(delta)
	_apply_wall_roll()
	_tell_footholds()


func _process(_delta: float) -> void:
	for leg in _legs:
		_pose_leg(leg)


## Derives the leg and gait settings from the exports every tick, so they can
## be tuned while running (all but size).
func _update_tuning() -> void:
	var omega := TAU * stance_hz
	_leg_stiffness = mass * omega * omega / _legs.size()
	_leg_damping = STANCE_DAMPING_RATIO * 2.0 * mass * omega / _legs.size()
	_leg_max_force = strength * mass * get_gravity().length() / _legs.size()
	_step_threshold = stride * _leg_reach_full()

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
	# A rider turns with what it rides, until told to face elsewhere.
	if _carrier is RigidBody3D:
		var spin: float = (_carrier as RigidBody3D).angular_velocity.y * delta
		forward = forward.rotated(Vector3.UP, spin)
		_desired_facing = _desired_facing.rotated(Vector3.UP, spin)
		facing_direction = facing_direction.rotated(Vector3.UP, spin)
	var turn := forward.signed_angle_to(_desired_facing, Vector3.UP)
	forward = forward.rotated(Vector3.UP, clampf(turn, -turn_rate * delta, turn_rate * delta))

	var up := Vector3.UP
	if ground_sum.length_squared() > 1e-6:
		up = (ground_sum.normalized() + _foot_plane_up()).normalized()
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
	var max_tilt := turn_rate * 0.5 * delta
	if tilt > max_tilt:
		up = _target_basis.y.slerp(up, max_tilt / tilt).normalized()
	var level_forward := forward - up * forward.dot(up)
	if level_forward.length_squared() > 1e-4:
		_target_basis = Basis.looking_at(level_forward, up)


## Up of the plane best fitting the planted ground feet, so feet standing
## higher on one side (on a step, or another crab) tilt the body. Falls back to
## the current up with fewer than three feet.
func _foot_plane_up() -> Vector3:
	var points: Array[Vector3] = []
	var mean := Vector3.ZERO
	var to_local := _target_basis.inverse()
	for leg in _legs:
		if leg.planted and leg.normal.y > WALL_NORMAL_Y:
			var p := to_local * leg.foot.pos
			points.append(p)
			mean += p
	if points.size() < 3:
		return _target_basis.y
	mean /= points.size()
	# Least squares y = a x + b z through the mean.
	var sxx := 0.0
	var sxz := 0.0
	var szz := 0.0
	var sxy := 0.0
	var szy := 0.0
	for p in points:
		var d := p - mean
		sxx += d.x * d.x
		sxz += d.x * d.z
		szz += d.z * d.z
		sxy += d.x * d.y
		szy += d.z * d.y
	var det := sxx * szz - sxz * sxz
	if det < 1e-8 * _size * _size * _size * _size:
		return _target_basis.y
	var a := (sxy * szz - szy * sxz) / det
	var b := (szy * sxx - sxy * sxz) / det
	return (_target_basis * Vector3(-a, 1.0, -b)).normalized()


func _update_wall_roll(wall_sum: Vector3, delta: float) -> void:
	var pushing := _pushing_into(wall_sum)
	if pushing:
		_wall_normal = Vector3(wall_sum.x, 0.0, wall_sum.z).normalized()
	if global_basis.y.y < -0.3 or climb_rate <= 0.0:
		_wall_roll = 0.0
	elif pushing:
		# Only grows while the body keeps up.
		if _target_basis.y.angle_to(Vector3.UP) - global_basis.y.angle_to(Vector3.UP) < WALL_ROLL_LAG:
			_wall_roll += climb_rate * delta
	else:
		_wall_roll = maxf(_wall_roll - climb_rate * 2.0 * delta, 0.0)


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
	if not _in_reach(leg, leg.foot.pos, MAX_REACH, leg.foothold != null):
		leg.planted = false
		return
	var hip := to_global(leg.hip_local)
	var offset := hip - global_position
	var hip_vel := linear_velocity + angular_velocity.cross(offset) \
			- _surface_velocity(leg.collider, leg.foot.pos)
	var up := _target_basis.y

	# A foot can't pull the body toward its surface.
	var drive := _drive
	var into := drive.dot(leg.normal)
	if into < 0.0:
		drive -= leg.normal * into

	var error := _fit_center + _target_basis * leg.hip_local - hip
	var lift := up * error.dot(up)
	var force := lift * _leg_stiffness + (error - lift) * _leg_stiffness * LATERAL_STIFFNESS \
			+ (drive - hip_vel) * _leg_damping \
			- get_gravity() * mass / _legs.size()
	var leg_grip := leg.foothold.grip if leg.foothold and leg.foothold.grip > 0.0 else grip
	force = _friction_cone(force, leg.normal, leg_grip).limit_length(_leg_max_force)
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


## How far to raise the body above the feet's fit so its belly clears what's
## under it, or just ahead of it, such as another crab. Ahead looks higher, so
## the crab walking into another is the one that goes on top.
func _belly_lift() -> float:
	if _airborne or _righting:
		return 0.0
	var up := _target_basis.y
	var start := global_position + up * BELLY_PROBE_HEIGHT * _size
	var samples: Array[Vector3] = [Vector3.ZERO]
	for corner in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		samples.append(_target_basis * (corner * Vector3(BODY_HALF_EXTENTS.x, 0, BODY_HALF_EXTENTS.y)) * _size)
	if _wish.length_squared() > 0.01:
		samples.append(_drive.normalized() * BELLY_LEAD * _size)
	var lift := 0.0
	for i in samples.size():
		var from: Vector3 = start + samples[i]
		var hit := _ray(from, from - up * (BELLY_PROBE_HEIGHT + RIDE_HEIGHT) * _size)
		if hit.is_empty():
			continue
		# Under the body, only what's below the centre counts, or a crab being
		# climbed onto would rise to clear the climber.
		if i < 5 and (hit.position - global_position).dot(up) > 0.0:
			continue
		var needed: float = (hit.position - _fit_center).dot(up) + (BODY_HALF_HEIGHT + BELLY_CLEARANCE) * _size
		lift = maxf(lift, needed)
	return minf(lift, MAX_BELLY_LIFT * _size)


## Average body centre implied by each planted foot's rest spot. Wall feet
## count only when no foot is on the ground. Riding, only feet on the
## carrier's footholds count, so feet left on the ground don't hold the body
## down on it; they're stretched until they step up too.
func _fit_body_center() -> Vector3:
	var ground := Vector3.ZERO
	var ground_count := 0
	var wall := Vector3.ZERO
	var wall_count := 0
	for leg in _legs:
		if not leg.planted:
			continue
		if _carrier and not (leg.foothold and leg.foothold.get_body() == _carrier):
			continue
		var center := leg.foot.pos - _target_basis * _fit_rest(leg)
		if leg.normal.y > WALL_NORMAL_Y:
			ground += center
			ground_count += 1
		else:
			wall += center
			wall_count += 1
	if ground_count > 0:
		return ground / ground_count
	return wall / wall_count if wall_count > 0 else global_position


## The foot's rest spot, or for a foot on a foothold, the spot along the leg's
## outward line level with it, raised by the foothold's lift: a foothold may
## sit anywhere from under the hip to full stretch, and only its height and
## sideways offset place the body. Riding and not walking, it's under the
## hip, so the rider settles to straddle the carrier, centred between its feet.
func _fit_rest(leg: Leg) -> Vector3:
	if not leg.foothold:
		return leg.rest_local
	var along := 0.0
	if not (_carrier and leg.foothold.get_body() == _carrier and _wish.length_squared() < 0.01):
		var local := _target_basis.inverse() * (leg.foot.pos - global_position)
		var full := Vector2(leg.rest_local.x - leg.hip_local.x, leg.rest_local.z - leg.hip_local.z).length()
		along = clampf((local - leg.hip_local).dot(leg.out_local), 0.0, full)
	var rest := leg.hip_local + leg.out_local * along
	rest.y = leg.rest_local.y - leg.foothold.get_lift()
	return rest


## Push only, never pull; sideways force at most friction times push.
func _friction_cone(force: Vector3, normal: Vector3, friction: float) -> Vector3:
	var push := force.dot(normal)
	if push <= 0.0:
		return Vector3.ZERO
	var slide := force - normal * push
	return normal * push + slide.limit_length(friction * push)


func _update_gait() -> void:
	var rel_vel := linear_velocity - _ground_velocity()
	var flat_vel := Vector3(rel_vel.x, 0.0, rel_vel.z)
	# Capped so feet spend as long ahead of the hip as behind it.
	var lead := (flat_vel * LEAD_TIME).limit_length(_step_threshold * 0.5)
	var moving := flat_vel.length() > 0.1 * _size or absf(angular_velocity.y) > 0.4
	var threshold := _step_threshold if moving else _step_threshold * SETTLE_FRACTION
	_gather_footholds(lead)
	var belly := _ray(global_position, global_position - global_basis.y * RIDE_HEIGHT * 2.5 * _size)
	_under = belly.get("collider")
	_carrier = null
	for leg in _legs:
		if leg.planted and leg.foothold and _under and leg.foothold.get_body() == _under:
			_carrier = _under
	var swinging := [false, false]
	for leg in _legs:
		if not leg.planted and leg.has_hold:
			swinging[leg.group] = true

	for leg in _legs:
		# A swinging foot keeps its foothold, or it would chase it forever.
		if leg.planted or not leg.has_hold \
				or not _in_reach(leg, leg.hold, HOLD_REACH, leg.hold_foothold != null):
			leg.has_hold = _find_hold(leg, lead)
		if not _initialized:
			leg.planted = leg.has_hold
			if leg.planted:
				_plant(leg, leg.hold, leg.hold_normal, leg.hold_collider, leg.hold_foothold)
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
## then down. Rising ground, or a wall being walked into, is reached along. A
## foothold near the home spot wins over what the rays find.
func _find_hold(leg: Leg, lead: Vector3) -> bool:
	var pose := global_basis.orthonormalized()
	var up := pose.y
	var from := global_position + up * leg.hip_local.y
	var above := global_position + pose * leg.rest_local + lead \
			+ up * (leg.hip_local.y - leg.rest_local.y)
	var obstacle := _ray(from, above)
	var hit := {}
	if obstacle.is_empty() or obstacle.normal.y <= WALL_NORMAL_Y:
		hit = _step_up(leg, from, above)
		if not hit.is_empty() and not _in_reach(leg, hit.position, HOLD_REACH):
			hit = {}
	if not hit.is_empty():
		pass
	elif obstacle.is_empty():
		hit = _ray(above, above - up * _leg_reach(leg))
	elif obstacle.normal.y > WALL_NORMAL_Y or (climb_rate > 0.0 and _pushing_into(obstacle.normal)):
		hit = _reach_along(obstacle, above)
	else:
		var base: Vector3 = obstacle.position + obstacle.normal * 0.02 * _size
		hit = _ray(base, base - up * _leg_reach(leg))
	if not obstacle.is_empty() and obstacle.normal.y <= WALL_NORMAL_Y:
		_walls_seen += obstacle.normal
	if (hit.is_empty() or not _in_reach(leg, hit.position, HOLD_REACH)) and not obstacle.is_empty():
		hit = obstacle
	if not hit.is_empty() and not _in_reach(leg, hit.position, HOLD_REACH):
		hit = {}
	var home := global_position + pose * leg.rest_local + lead
	var foothold := _pick_foothold(leg, home, hit.get("collider"))
	if foothold:
		_set_hold(leg, foothold.global_position, foothold.get_normal(), foothold.get_body(), foothold)
		return true
	if hit.is_empty():
		_hold_foothold(leg, null)
		return false
	_set_hold(leg, hit.position, hit.normal, hit.collider)
	return true


## The free foothold nearest the home spot, within its capture radius and the
## leg's reach, or the one already held while it still qualifies. It must be
## on what the rays found, on what the belly or a foot is on, or the rays found
## nothing: footholds guide feet onto geometry the crab is on, they don't pull
## it off the ground onto a neighbour.
func _pick_foothold(leg: Leg, home: Vector3, found: Object) -> Foothold:
	var best: Foothold = null
	var best_dist := INF
	for foothold in _near_footholds:
		var radius := foothold.get_capture_radius()
		if foothold == leg.hold_foothold:
			radius *= FOOTHOLD_KEEP
		var dist := foothold.global_position.distance_to(home)
		if dist >= minf(radius, best_dist):
			continue
		var body := foothold.get_body()
		if not body or body == self or not foothold.is_free_for(leg):
			continue
		if found and body != found and body != _under and not _standing_on(body):
			continue
		if not _in_reach(leg, foothold.global_position, HOLD_REACH, true):
			continue
		# Stays on the one it has while it can, rather than stepping across to
		# a neighbour that has come slightly nearer.
		if foothold == leg.hold_foothold:
			return foothold
		best = foothold
		best_dist = dist
	return best


## Narrows the footholds to those near enough for any foot's home spot to
## capture, once a tick, so each leg doesn't search every one in the world.
func _gather_footholds(lead: Vector3) -> void:
	var reach := 0.0
	for leg in _legs:
		reach = maxf(reach, leg.rest_local.length())
	reach += lead.length()
	_near_footholds.clear()
	for node in get_tree().get_nodes_in_group(Foothold.GROUP):
		var foothold := node as Foothold
		if not foothold or not is_instance_valid(foothold):
			continue
		var bound := reach + foothold.get_capture_radius() * FOOTHOLD_KEEP
		if foothold.global_position.distance_squared_to(global_position) < bound * bound:
			_near_footholds.append(foothold)


## The lowest speed scale of the footholds the feet stand on or are reaching
## for, so a crab slows as it steps onto them rather than once it's there.
func _foothold_speed_scale() -> float:
	var lowest := 1.0
	for leg in _legs:
		if leg.planted and leg.foothold:
			lowest = minf(lowest, leg.foothold.speed_scale)
		if leg.has_hold and is_instance_valid(leg.hold_foothold):
			lowest = minf(lowest, leg.hold_foothold.speed_scale)
	return lowest


## Tells footholds when a foot starts or stops standing on them.
func _tell_footholds() -> void:
	for leg in _legs:
		var on := leg.foothold if leg.planted and is_instance_valid(leg.foothold) else null
		if on == leg.stood_on:
			continue
		if is_instance_valid(leg.stood_on):
			leg.stood_on.foot_lifted.emit(self)
		if on:
			on.foot_planted.emit(self)
		leg.stood_on = on


func _standing_on(body: Object) -> bool:
	for leg in _legs:
		if leg.planted and leg.collider == body:
			return true
	return false


## Looks down from above hip height, so a foot can stand on top of something
## a little higher than the hips, such as another crab or a low wall.
func _step_up(leg: Leg, from: Vector3, above: Vector3) -> Dictionary:
	var up := global_basis.orthonormalized().y
	var lift := up * _leg_reach(leg) * STEP_UP_RAISE
	if not _ray(from, from + lift).is_empty() or not _ray(from + lift, above + lift).is_empty():
		return {}
	var hit := _ray(above + lift, above - up * _leg_reach(leg))
	if hit.is_empty() or hit.normal.dot(up) <= WALL_NORMAL_Y:
		return {}
	return hit


func _reach_along(surface: Dictionary, goal: Vector3) -> Dictionary:
	var n: Vector3 = surface.normal
	var lift := STEP_HEIGHT * _size
	var start: Vector3 = surface.position + n * 0.01 * _size
	var along: Vector3 = goal - surface.position
	along -= n * along.dot(n)
	var over: Vector3 = start + along + n * lift
	if not _ray(start, start + n * lift).is_empty() \
			or not _ray(start + n * lift, over).is_empty():
		return {}
	return _ray(over, over - n * lift * 3.0)


func _scatter_hold(leg: Leg) -> void:
	if leg.hold_foothold:
		return
	var n := leg.hold_normal
	var tangent := n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD).normalized()
	var offset := tangent.rotated(n, randf() * TAU) * randf() * _step_threshold * JITTER_FRACTION
	var lifted := leg.hold + n * 0.02 * _size
	if not _ray(lifted, lifted + offset).is_empty():
		return
	var hit := _ray(lifted + offset, lifted + offset - n * 0.05 * _size)
	if not hit.is_empty():
		_set_hold(leg, hit.position, hit.normal, hit.collider)


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
		var step_height := STEP_HEIGHT * _size
		var to_foot := leg.foot.pos - leg.hold
		var across := (to_foot - leg.hold_normal * to_foot.dot(leg.hold_normal)).length()
		var lift_dir := (global_basis.y + leg.hold_normal).normalized()
		target = leg.hold + lift_dir * minf(across, step_height) - leg.hold_normal * step_height * 0.5
		_spring_point(leg.foot, target, _surface_velocity(leg.hold_collider, leg.hold),
				SWING_STIFFNESS, 2.0 * sqrt(SWING_STIFFNESS), Vector3.ZERO, delta)
	else:
		var ride_height := RIDE_HEIGHT * _size
		var pose := leg.rest_local + Vector3.UP * ride_height * 0.4
		if _righting:
			pose += Vector3.UP * sin(_time * 22.0 + leg.hip_local.z / _size * 60.0) * ride_height
		target = to_global(pose)
		var target_vel := linear_velocity + angular_velocity.cross(target - global_position)
		_spring_point(leg.foot, target, target_vel, LIMP_STIFFNESS, LIMP_DAMPING,
				get_gravity(), delta)

	var reach := _leg_reach(leg)
	var min_reach := FOOTHOLD_MIN_REACH if stepping and leg.hold_foothold else MIN_REACH
	_tether(leg.foot, hip, hip_vel, reach * min_reach, reach * MAX_REACH)
	var hit := _collide(leg.foot, from, FOOT_RADIUS * _size)
	var arrived := leg.foot.pos.distance_to(leg.hold) < 0.01 * _size
	# Striking the surface by a foothold counts as standing on the foothold.
	if stepping and leg.hold_foothold and not hit.is_empty():
		arrived = arrived or hit.position.distance_to(leg.hold) < 0.03 * _size
	if stepping and arrived:
		_plant(leg, leg.hold, leg.hold_normal, leg.hold_collider, leg.hold_foothold)
	elif not hit.is_empty() and _in_reach(leg, hit.position, HOLD_REACH):
		_plant(leg, hit.position, hit.normal, hit.collider)


func _plant(leg: Leg, at: Vector3, normal: Vector3, collider: Object,
		foothold: Foothold = null) -> void:
	leg.planted = true
	leg.foothold = foothold
	# Off the surface, so later rays from here still see it.
	leg.foot.pos = at + normal * FOOT_RADIUS * _size
	leg.foot.vel = Vector3.ZERO
	leg.normal = normal
	leg.collider = collider
	var body := _surface(collider)
	if body:
		leg.foot_local = body.global_transform.affine_inverse() * leg.foot.pos
		leg.normal_local = body.global_basis.orthonormalized().inverse() * normal


func _set_hold(leg: Leg, at: Vector3, normal: Vector3, collider: Object,
		foothold: Foothold = null) -> void:
	_hold_foothold(leg, foothold)
	leg.hold = at
	leg.hold_normal = normal
	leg.hold_collider = collider
	var body := _surface(collider)
	if body:
		leg.hold_local = body.global_transform.affine_inverse() * at
		leg.hold_normal_local = body.global_basis.orthonormalized().inverse() * normal


func _hold_foothold(leg: Leg, foothold: Foothold) -> void:
	if leg.hold_foothold == foothold:
		return
	if is_instance_valid(leg.hold_foothold):
		leg.hold_foothold.release(leg)
	if foothold:
		foothold.claim(leg, self)
	leg.hold_foothold = foothold


## Moves planted feet and footholds along with whatever they're on, which may
## be another crab. Lets go of anything that has been freed.
func _follow_surfaces() -> void:
	for leg in _legs:
		if leg.planted:
			var body := _surface(leg.collider)
			if body:
				leg.foot.pos = body.global_transform * leg.foot_local
				leg.normal = (body.global_basis.orthonormalized() * leg.normal_local).normalized()
			else:
				leg.planted = false
		if leg.has_hold:
			var body := _surface(leg.hold_collider)
			if body:
				leg.hold = body.global_transform * leg.hold_local
				leg.hold_normal = (body.global_basis.orthonormalized() * leg.hold_normal_local).normalized()
			else:
				leg.has_hold = false
				_hold_foothold(leg, null)


func _surface(collider: Object) -> Node3D:
	if is_instance_valid(collider) and collider is Node3D:
		return collider
	return null


## Velocity of a surface at a point; zero unless it's a rigid body.
func _surface_velocity(collider: Object, point: Vector3) -> Vector3:
	if is_instance_valid(collider) and collider is RigidBody3D:
		var body: RigidBody3D = collider
		return body.linear_velocity + body.angular_velocity.cross(point - body.global_position)
	return Vector3.ZERO


## Average velocity of the surfaces under the planted feet.
func _ground_velocity() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for leg in _legs:
		if leg.planted:
			sum += _surface_velocity(leg.collider, leg.foot.pos)
			count += 1
	return sum / count if count > 0 else Vector3.ZERO


## Between folded and stretched, on the leg's own side, not far above the hip.
## A foothold may be nearer and further in.
func _in_reach(leg: Leg, point: Vector3, max_fraction: float, foothold := false) -> bool:
	var to_point := point - to_global(leg.hip_local)
	var dist := to_point.length()
	var reach := _leg_reach(leg)
	var min_reach := FOOTHOLD_MIN_REACH if foothold else MIN_REACH
	var min_spread := -FOOTHOLD_INWARD if foothold else MIN_SPREAD
	return dist > reach * min_reach and dist < reach * max_fraction \
			and to_point.dot(global_basis.y) < dist * MAX_RAISE \
			and to_point.dot(global_basis * leg.out_local) > reach * min_spread


func _leg_reach(leg: Leg) -> float:
	return _leg_reach_full() * leg.length_scale


## Reach of a full-length leg (length scale 1).
func _leg_reach_full() -> float:
	return _segment_lengths.x + _segment_lengths.y + _segment_lengths.z

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
	_righting = can_self_right and _stuck_time > SELF_RIGHT_DELAY
	if not _righting:
		return
	var axis := up.cross(Vector3.UP)
	if axis.length_squared() < 0.01:
		axis = global_basis.z
	var k := _torque_scale()
	apply_torque(axis.normalized() * SELF_RIGHT_TORQUE * k.x
			- angular_velocity * SELF_RIGHT_DAMPING * k.y)


func _apply_wall_roll() -> void:
	if _wall_roll <= 0.0 or _righting:
		return
	var axis := global_basis.y.cross(_target_basis.y)
	var angle := global_basis.y.angle_to(_target_basis.y)
	if axis.length_squared() > 1e-8:
		axis = axis.normalized() * angle
	var k := _torque_scale()
	apply_torque(axis * WALL_ROLL_TORQUE * k.x - angular_velocity * WALL_ROLL_DAMPING * k.y)


## The body's weight on a lever its own size (x), and the damping (y) that
## goes with it, so recovery behaves alike at any mass and size.
func _torque_scale() -> Vector2:
	var g := get_gravity().length()
	var torque := mass * g * _size
	return Vector2(torque, torque * sqrt(_size / maxf(g, 0.01)))


# --- Visuals ----------------------------------------------------------------------

func _pose_leg(leg: Leg) -> void:
	var up := global_basis.y
	var lengths := _segment_lengths * leg.length_scale
	var hip := to_global(leg.hip_local)
	var foot := leg.foot.pos

	# Which way the leg reaches: toward the foot when it stands well out on its
	# own side, easing to the leg's own direction as the foot comes in under the
	# hip, where the direction to the foot is short and unsteady.
	var side := (global_basis * leg.out_local).normalized()
	var to_foot := foot - hip
	to_foot -= up * to_foot.dot(up)
	var spread := smoothstep(0.0, OUTWARD_SPREAD * _leg_reach(leg), to_foot.dot(side))
	var outward := side
	if to_foot.length_squared() > 1e-6:
		outward = side.slerp(to_foot.normalized(), spread) if to_foot.normalized().dot(side) > -0.99 else side

	# Dactyl stands out from the surface, leaning in toward the body. Under
	# the hip it leans out instead, so the knee has room to arch over.
	var normal := leg.normal if leg.planted else up
	var lean := -outward * (spread * 2.0 - 1.0)
	lean -= normal * lean.dot(normal)
	var tilt := deg_to_rad(lerpf(STRADDLE_TILT_DEG, DACTYL_TILT_DEG, spread))
	var dactyl := normal * cos(tilt)
	if lean.length_squared() > 1e-6:
		dactyl += lean.normalized() * sin(tilt)
	var ankle := foot + dactyl * lengths.z

	# Two-bone IK hip -> ankle, knee bent up and out. With the foot out from
	# the hip that's straight up; with it underneath, up alone is along the
	# leg and the outward part keeps the knee arched over its own side.
	var to_ankle := ankle - hip
	var dist := to_ankle.length()
	var dir := to_ankle / dist if dist > 1e-5 else outward
	var reach := clampf(dist, absf(lengths.x - lengths.y) + 1e-3, lengths.x + lengths.y - 1e-3)
	var bend := up + outward * KNEE_OUTWARD
	var pole := bend - dir * bend.dot(dir)
	pole = pole.normalized() if pole.length_squared() > 1e-6 else up
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
