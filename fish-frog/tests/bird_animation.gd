extends SceneTree

var failures := 0
var observed := {}
var observed_rotations := {}


func _initialize() -> void:
	call_deferred("run_checks")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func capture_pose(skeleton: Skeleton3D) -> void:
	# Modifier results are temporary; read them while modification_processed fires.
	for index in range(skeleton.get_bone_count()):
		observed[index] = skeleton.get_bone_global_pose(index)
		observed_rotations[index] = skeleton.get_bone_pose_rotation(index)


func save_pose(label: String, skeleton: Skeleton3D) -> void:
	var data := {}
	for index in range(skeleton.get_bone_count()):
		var pose: Transform3D = observed[index]
		var rest := skeleton.get_bone_global_rest(index)
		data[skeleton.get_bone_name(index)] = {"pose": [pose.basis.x, pose.basis.y, pose.basis.z, pose.origin].map(func(v): return [v.x, v.y, v.z]),
			"rest": [rest.basis.x, rest.basis.y, rest.basis.z, rest.origin].map(func(v): return [v.x, v.y, v.z])}
	DirAccess.make_dir_recursive_absolute("res://.godot/bird_animation_checks")
	var file := FileAccess.open("res://.godot/bird_animation_checks/" + label + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))


func run_checks() -> void:
	if not ResourceLoader.exists("res://actors/bird/bird_animation.tscn"):
		check(false, "Bird needs a rigged walking/flapping/leg-ragdoll visual scene")
		quit(1)
		return
	var bird = load("res://actors/bird/bird.gd").new()
	bird.freeze = true
	bird.position = Vector3(0, 1, 0)
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	bird.add_child(visuals)
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	bird.add_child(pivot)
	var animation = load("res://actors/bird/bird_animation.tscn").instantiate()
	visuals.add_child(animation)
	root.add_child(bird)
	var skeleton: Skeleton3D = animation.skeleton
	skeleton.get_node("SoleAlignment").modification_processed.connect(capture_pose.bind(skeleton))
	skeleton.get_node("RagdollAttachment").modification_processed.connect(capture_pose.bind(skeleton))
	var floor := StaticBody3D.new()
	floor.position.y = -.5
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 1, 50)
	collision.shape = box
	floor.add_child(collision)
	root.add_child(floor)
	bird.is_grounded = true
	for frame in range(60):
		await physics_frame
	check(skeleton != null and skeleton.get_bone_count() == 21, "Animation must use the complete rigged skeleton")
	check(skeleton.global_basis.get_scale().is_equal_approx(Vector3.ONE), "Physics skeleton must have unit world scale")
	for side in ["L", "R"]:
		var foot := skeleton.find_bone("foot." + side)
		var knee := skeleton.find_bone("leg_lower." + side)
		var foot_pos := skeleton.to_global(observed[foot].origin)
		var knee_pos := skeleton.to_global(observed[knee].origin)
		check(absf(foot_pos.y - animation.sole_clearance) < .025, "Standing foot must meet the ground: " + side + " " + str(foot_pos))
		check(knee_pos.z > foot_pos.z + .02, "Visible hock must bend backward: " + side)
		for part in ["wing_upper.", "wing_fore.", "wing_tip."]:
			var index := skeleton.find_bone(part + side)
			var rest_rotation := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
			check(observed_rotations[index].angle_to(rest_rotation) < .001,
				"Grounded wing joints must remain unbent to prevent folding distortion: " + part + side)
	check(animation._wing_meshes.size() == 2, "Both wing meshes need a compact side pose")
	for mesh in animation._wing_meshes:
		var compact: int = mesh.find_blend_shape_by_name("CompactWing")
		check(compact >= 0, "Grounded wings must use uniform compact geometry instead of a joint fold")
		if compact >= 0:
			check(mesh.get_blend_shape_value(compact) > .999, "Grounded wing must shrink into its side pose")
	check(not animation.legs_simulating, "Grounded legs must be controlled by foot-placement IK")
	save_pose("standing", skeleton)
	# A moving body should make stance feet stay planted between swing phases.
	bird.linear_velocity = Vector3(0, 0, -1.4)
	var left_positions: Array[Vector3] = []
	for frame in range(90):
		bird.position.z -= 1.4 / 60.0
		await physics_frame
		left_positions.append(skeleton.to_global(observed[skeleton.find_bone("foot.L")].origin))
	var max_lift := 0.0
	var planted := 0
	for position in left_positions:
		max_lift = maxf(max_lift, position.y)
		if absf(position.y - animation.sole_clearance) < .03:
			planted += 1
	check(max_lift > animation.sole_clearance + .06, "Walking must lift the swing foot")
	check(planted > 20, "Walking must include grounded stance frames")
	# Releasing movement during a swing must finish the step without a snap.
	for frame in range(90):
		bird.position.z -= 1.4 / 60.0
		await physics_frame
		var foot: Vector3 = skeleton.to_global(observed[skeleton.find_bone("foot.L")].origin)
		if foot.y > animation.sole_clearance + .08:
			break
	var last_foot: Vector3 = skeleton.to_global(observed[skeleton.find_bone("foot.L")].origin)
	bird.linear_velocity = Vector3.ZERO
	var largest_step := 0.0
	for frame in range(60):
		await physics_frame
		var foot: Vector3 = skeleton.to_global(observed[skeleton.find_bone("foot.L")].origin)
		largest_step = maxf(largest_step, foot.distance_to(last_foot))
		last_foot = foot
	check(largest_step < .1, "Stopping mid-swing must lower the foot smoothly: " + str(largest_step))
	check(absf(last_foot.y - animation.sole_clearance) < .03, "A stopped walk must settle the foot on the ground")
	bird.linear_velocity = Vector3.ZERO
	bird.is_grounded = false
	bird.linear_velocity = Vector3(0, 6.5, 0)
	for frame in range(30):
		bird.position.y += 6.5 / 60.0
		await physics_frame
	check(animation.legs_simulating, "Airborne legs must enter actual physics simulation")
	check(animation.physical_legs.size() == 6, "Both complete leg/foot chains must have physical bones")
	for bone in animation.physical_legs:
		check(bone.is_simulating_physics(), "Air leg bone must be physically simulated: " + bone.bone_name)
	var wing := skeleton.find_bone("wing_upper.L")
	var first: Quaternion = observed_rotations[wing]
	for frame in range(10):
		bird.position.y += 6.5 / 60.0
		await physics_frame
	check(first.angle_to(observed_rotations[wing]) < .001, "Airborne wings must stay in a glide pose without a Space press")
	bird.powered_flight = true
	for cycle in 3:
		var excursion := 0.0
		for frame in range(ceili(60.0 / animation.flap_frequency)):
			await physics_frame
			excursion = maxf(excursion, first.angle_to(observed_rotations[wing]))
		check(excursion > .05, "Hover keeps wings beating each cycle without input")
	save_pose("flight", skeleton)
	bird.powered_flight = false
	for frame in range(ceili(60.0 / animation.flap_frequency) + 2):
		await physics_frame
	check(first.angle_to(observed_rotations[wing]) < .001, "Wings settle into glide after hover")
	for side in ["L", "R"]:
		var hip: Vector3 = observed[skeleton.find_bone("leg_upper." + side)].origin
		var expected_hip := skeleton.get_bone_rest(skeleton.find_bone("leg_upper." + side)).origin
		var pelvis: Transform3D = observed[skeleton.find_bone("pelvis")]
		check(hip.distance_to(pelvis * expected_hip) < .15, "Airborne hip must remain attached to the pelvis: " + side)
	# Make the body turn and travel; joints must remain attached and finite.
	bird.linear_velocity = Vector3(.6, 0, -1.8)
	for frame in range(120):
		bird.position += Vector3(.01, 0, -.03)
		bird.yaw += .006
		await physics_frame
	for side in ["L", "R"]:
		var hip: Vector3 = skeleton.to_global(observed[skeleton.find_bone("leg_upper." + side)].origin)
		var foot: Vector3 = skeleton.to_global(observed[skeleton.find_bone("foot." + side)].origin)
		check(foot.is_finite() and foot.distance_to(hip) < 1.5, "Ragdoll chain must remain attached during travel: " + side)
	var max_attachment_error := 0.0
	for frame in range(30):
		bird.linear_velocity = Vector3(0, 0, -25)
		bird.position.z -= 25.0 / 60.0
		await physics_frame
		for side in ["L", "R"]:
			var hip: Vector3 = observed[skeleton.find_bone("leg_upper." + side)].origin
			var pelvis: Transform3D = observed[skeleton.find_bone("pelvis")]
			var offset := skeleton.get_bone_rest(skeleton.find_bone("leg_upper." + side)).origin
			max_attachment_error = maxf(max_attachment_error, hip.distance_to(pelvis * offset))
	check(max_attachment_error < .05, "Flight-speed ragdoll must not stretch away from the pelvis: " + str(max_attachment_error))
	# Landing must reclaim the leg bones without leaving a solver/physics fight.
	bird.is_grounded = true
	bird.position.y = 1
	bird.linear_velocity = Vector3.ZERO
	for frame in range(60):
		await physics_frame
	check(not animation.legs_simulating, "Landing must stop leg ragdolling")
	for side in ["L", "R"]:
		var foot: Vector3 = skeleton.to_global(observed[skeleton.find_bone("foot." + side)].origin)
		check(absf(foot.y - animation.sole_clearance) < .03, "Landing must plant the feet again: " + side)
	bird.queue_free()
	floor.queue_free()
	await process_frame
	print("PASS: rig, compact unbent wings, backward hocks, planted/lifted feet, wing flapping, partial physical leg simulation, travel and landing" if failures == 0 else "FAIL: %d animation checks" % failures)
	quit(1 if failures else 0)
