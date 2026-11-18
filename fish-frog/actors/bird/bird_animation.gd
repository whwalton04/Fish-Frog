extends Node3D
## Crane-inspired skeletal animation: planted stance/swing feet on the ground,
## compact side wings, and partial leg ragdoll with animated air wings.

const PoseModifier = preload("res://actors/bird/bird_pose_modifier.gd")

@export_range(.2, 3.0, .05) var stride_length := 1.05
@export_range(.02, .4, .01) var step_height := .15
@export_range(.5, 4.0, .1) var flap_frequency := 1.7
@export_range(.1, 1.2, .05) var flap_amplitude := .72
@export_range(.05, 1.0, .05) var transition_time := .3
@export var sole_clearance := .0488125
@export_range(0.0, 2.0, .1) var airborne_leg_gravity := .6

var bird: RigidBody3D
var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
var physical_legs: Array[PhysicalBone3D] = []
var legs_simulating := false
var _legs: Array[Dictionary] = []
var _rest_global: Array[Transform3D] = []
var _ground_blend := 1.0
var _phase := 0.0
var _flap_elapsed := INF
var _was_grounded := false
var _initialized := false
var _wing_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	var ancestor := get_parent()
	while ancestor and not ancestor is RigidBody3D:
		ancestor = ancestor.get_parent()
	bird = ancestor as RigidBody3D
	skeleton = _find_skeleton(self)
	if bird == null or skeleton == null:
		push_error("BirdAnimation requires a bird RigidBody3D and a rigged Skeleton3D")
		set_physics_process(false)
		return
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	for index in range(skeleton.get_bone_count()):
		_rest_global.append(skeleton.get_bone_global_rest(index))
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if mesh.find_blend_shape_by_name("CompactWing") >= 0:
			_wing_meshes.append(mesh)
	var pose_pass := PoseModifier.new()
	pose_pass.name = "CranePose"
	pose_pass.driver = self
	skeleton.add_child(pose_pass)
	for side in ["L", "R"]:
		_create_leg_ik(side)
	var feet_pass := PoseModifier.new()
	feet_pass.name = "SoleAlignment"
	feet_pass.driver = self
	feet_pass.feet_pass = true
	skeleton.add_child(feet_pass)
	_create_leg_physics()
	var attachment_pass := PoseModifier.new()
	attachment_pass.name = "RagdollAttachment"
	attachment_pass.driver = self
	attachment_pass.attachment_pass = true
	skeleton.add_child(attachment_pass)
	_initialized = true


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _create_leg_ik(side: String) -> void:
	var foot_index := skeleton.find_bone("foot." + side)
	var target := Node3D.new()
	target.name = "FootTarget" + side
	add_child(target)
	var pole := Node3D.new()
	pole.name = "HockPole" + side
	add_child(pole)
	var ik := TwoBoneIK3D.new()
	ik.name = "GroundLegIK" + side
	skeleton.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "leg_upper." + side)
	ik.set_middle_bone_name(0, "leg_lower." + side)
	ik.set_end_bone_name(0, "foot." + side)
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.set_extend_end_bone(0, false)
	ik.set_use_virtual_end(0, false)
	var lower := skeleton.find_bone("leg_lower." + side)
	ik.set_pole_direction_vector(0, _rest_global[lower].basis.inverse() * Vector3(0, 0, -1))
	_legs.append({"side": side, "foot": foot_index, "target": target, "pole": pole,
		"ik": ik, "planted": Vector3.ZERO, "normal": Vector3.UP,
		"swinging": false, "start": Vector3.ZERO, "end": Vector3.ZERO,
		"swing_t": 0.0, "duration": .3, "phase_window": false})


func _create_physical_bone(bone_name: String, length: float, anchor := false) -> PhysicalBone3D:
	var body := PhysicalBone3D.new()
	body.name = "Physical_" + bone_name.replace(".", "_")
	body.collision_layer = 0
	body.collision_mask = 0 if anchor else 1
	body.mass = .08 if bone_name.begins_with("foot") else .18
	body.gravity_scale = airborne_leg_gravity
	body.linear_damp = .4
	body.angular_damp = 2.0
	body.can_sleep = false
	body.body_offset = Transform3D(Basis.IDENTITY, Vector3(0, length * .5, 0))
	body.joint_offset = Transform3D(Basis.IDENTITY, Vector3(0, -length * .5, 0))
	if not anchor:
		var collision := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = .025 if not bone_name.begins_with("foot") else .04
		capsule.height = maxf(length * .85, capsule.radius * 2.0)
		collision.shape = capsule
		body.add_child(collision)
	simulator.add_child(body)
	body.set("bone_name", bone_name)
	body.joint_type = PhysicalBone3D.JOINT_TYPE_NONE if anchor else PhysicalBone3D.JOINT_TYPE_CONE
	if not anchor:
		body.set("joint_constraints/swing_span", 75.0 if bone_name.begins_with("leg_upper") else 55.0)
		body.set("joint_constraints/twist_span", 15.0)
	return body


func _create_leg_physics() -> void:
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "AirLegPhysics"
	skeleton.add_child(simulator)
	# An unsimulated pelvis provides the moving kinematic anchor for both hips.
	_create_physical_bone("pelvis", .18, true)
	for side in ["L", "R"]:
		for part in ["leg_upper.", "leg_lower.", "foot."]:
			var index := skeleton.find_bone(part + side)
			var children := skeleton.get_bone_children(index)
			var length := .176
			if not children.is_empty():
				length = _rest_global[index].origin.distance_to(_rest_global[children[0]].origin)
			physical_legs.append(_create_physical_bone(part + side, length))
	for body in simulator.get_children():
		body.add_collision_exception_with(bird)
		for other in simulator.get_children():
			if other != body:
				body.add_collision_exception_with(other)
	simulator.active = false


func _set_air_legs(airborne: bool) -> void:
	if legs_simulating == airborne:
		return
	legs_simulating = airborne
	for leg in _legs:
		leg.ik.active = not airborne
	if airborne:
		simulator.active = true
		var names: Array[StringName] = []
		for body in physical_legs:
			names.append(StringName(body.get("bone_name")))
		simulator.physical_bones_start_simulation(names)
		for body in physical_legs:
			body.linear_velocity = bird.linear_velocity
	else:
		simulator.physical_bones_stop_simulation()
		simulator.active = false


func _ground_point(ideal: Vector3) -> Dictionary:
	var exclude: Array[RID] = [bird.get_rid()]
	for body in physical_legs:
		exclude.append(body.get_rid())
	var ray := PhysicsRayQueryParameters3D.create(ideal + Vector3.UP * .65,
		ideal - Vector3.UP * 1.0, bird.collision_mask, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and hit.normal.y > .5:
		return {"point": hit.position + hit.normal * sole_clearance, "normal": hit.normal}
	# Keep an unreachable ledge target local rather than extending the leg forever.
	return {"point": ideal, "normal": Vector3.UP}


func _physics_process(delta: float) -> void:
	if not _initialized:
		return
	var grounded := bool(bird.get("is_grounded"))
	if grounded:
		_flap_elapsed = INF
	elif bird.get("is_hovering"):
		var elapsed := 0.0 if is_inf(_flap_elapsed) else _flap_elapsed
		_flap_elapsed = fmod(elapsed + delta, 1.0 / flap_frequency)
	elif _flap_elapsed < 1.0 / flap_frequency:
		_flap_elapsed += delta
	_ground_blend = move_toward(_ground_blend, 1.0 if grounded else 0.0, delta / transition_time)
	for mesh in _wing_meshes:
		mesh.set_blend_shape_value(mesh.find_blend_shape_by_name("CompactWing"), _ground_blend)
	var grabber = bird.get_node_or_null("Grabber")
	var carrying: bool = grabber != null and is_instance_valid(grabber.held_body)
	_set_air_legs(not grounded and not carrying)
	if carrying:
		for leg in _legs:
			leg.target.global_position = grabber.get_foot_grip_position(leg.side)
			leg.normal = grabber.held_body.global_basis.y.normalized()
			var hip := skeleton.find_bone("leg_upper." + leg.side)
			leg.pole.global_position = skeleton.to_global(_rest_global[hip].origin + Vector3(0, .1, -.85))
	elif grounded:
		var velocity: Vector3 = bird.linear_velocity - bird.get("ground_velocity")
		velocity.y = 0
		var speed := velocity.length()
		var direction := velocity.normalized()
		_phase = fmod(_phase + speed * delta / stride_length, 1.0)
		for index in range(_legs.size()):
			var leg: Dictionary = _legs[index]
			var neutral: Vector3 = skeleton.to_global(_rest_global[leg.foot].origin)
			var ideal := _ground_point(neutral)
			if not _was_grounded:
				leg.planted = ideal.point
				leg.normal = ideal.normal
				leg.swinging = false
				leg.phase_window = false
				leg.target.global_position = leg.planted
			else:
				# Stance and swing targets travel with a moving support surface.
				var support_motion: Vector3 = bird.get("ground_velocity") * delta
				leg.planted += support_motion
				leg.start += support_motion
				leg.end += support_motion
			var phase := fmod(_phase + index * .5, 1.0)
			var swing_window := speed > .05 and phase >= .6
			if not leg.swinging and swing_window and not leg.phase_window:
				var landing := _ground_point(neutral + direction * stride_length * .65)
				_begin_step(leg, landing, clampf(stride_length * .4 / maxf(speed, .1), .12, .45))
			elif not leg.swinging and speed <= .05 and leg.planted.distance_to(neutral) > .18 and not _any_foot_swinging():
				# Turn/stop corrections are small steps, never a sliding reset.
				_begin_step(leg, ideal, .25)
			if leg.swinging:
				leg.swing_t = minf(1.0, leg.swing_t + delta / leg.duration)
				var t: float = leg.swing_t
				leg.target.global_position = leg.start.lerp(leg.end, smoothstep(0.0, 1.0, t)) + Vector3.UP * sin(t * PI) * step_height
				if t >= 1.0:
					leg.planted = leg.end
					leg.swinging = false
			else:
				leg.target.global_position = leg.planted
			leg.phase_window = swing_window
			var hip := skeleton.find_bone("leg_upper." + leg.side)
			leg.pole.global_position = skeleton.to_global(_rest_global[hip].origin + Vector3(0, .1, -.85))
	_was_grounded = grounded and not carrying


func _begin_step(leg: Dictionary, landing: Dictionary, duration: float) -> void:
	leg.start = leg.target.global_position
	leg.end = landing.point
	leg.normal = landing.normal
	leg.swing_t = 0.0
	leg.duration = duration
	leg.swinging = true


func _any_foot_swinging() -> bool:
	for leg in _legs:
		if leg.swinging:
			return true
	return false


func _delta_rotation(index: int, axis: Vector3, angle: float) -> Quaternion:
	var local_axis := _rest_global[index].basis.inverse() * axis
	return skeleton.get_bone_rest(index).basis.get_rotation_quaternion() * Quaternion(local_axis.normalized(), angle)


func _flap_angle(part: int) -> float:
	var duration := 1.0 / flap_frequency
	if _flap_elapsed >= duration:
		return 0.0
	var phase := clampf(_flap_elapsed / duration, 0.0, 1.0)
	var amplitude := flap_amplitude * (1.0 if part == 0 else .4)
	return sin(phase * TAU - part * .35) * sin(phase * PI) * amplitude


func apply_poses() -> void:
	if not _initialized:
		return
	skeleton.reset_bone_poses()
	var air := 1.0 - _ground_blend
	var pelvis := skeleton.find_bone("pelvis")
	skeleton.set_bone_pose_rotation(pelvis, _delta_rotation(pelvis, Vector3.RIGHT, deg_to_rad(55.0) * air))
	var head := skeleton.find_bone("head")
	skeleton.set_bone_pose_rotation(head, _delta_rotation(head, Vector3.RIGHT, deg_to_rad(-55.0) * air))
	for side in ["L", "R"]:
		var sign_x := 1.0 if side == "L" else -1.0
		for part in range(3):
			var bone_name: String = ["wing_upper.", "wing_fore.", "wing_tip."][part] + side
			var index := skeleton.find_bone(bone_name)
			var angle := _flap_angle(part) * sign_x
			var flight := _delta_rotation(index, Vector3.FORWARD, -angle)
			var unbent := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(index, flight.slerp(unbent, _ground_blend))


func align_feet() -> void:
	if not _initialized or legs_simulating:
		return
	for leg in _legs:
		var pose := skeleton.get_bone_global_pose(leg.foot)
		var aligned := Basis(Quaternion(skeleton.global_basis.y.normalized(), Vector3(leg.normal))) * skeleton.global_basis * _rest_global[leg.foot].basis
		pose.basis = skeleton.global_basis.inverse() * aligned
		skeleton.set_bone_global_pose(leg.foot, pose)


func lock_leg_translations() -> void:
	if not _initialized or not legs_simulating:
		return
	# Physics controls joint rotation. Preserve exact anatomical lengths so
	# solver lag at flight speed cannot pull the skinned hips/feet apart.
	for body in physical_legs:
		var index := body.get_bone_id()
		skeleton.set_bone_pose_position(index, skeleton.get_bone_rest(index).origin)


func _exit_tree() -> void:
	if is_instance_valid(simulator):
		simulator.physical_bones_stop_simulation()
