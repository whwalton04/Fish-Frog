extends SceneTree

var failures := 0
var feet := {}


func capture_feet(animator: Node3D) -> void:
	for leg in animator._legs:
		feet[leg.side] = animator.skeleton.to_global(animator.skeleton.get_bone_global_pose(leg.foot).origin)


func _initialize() -> void:
	call_deferred("run_checks")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func run_checks() -> void:
	var scene = load("res://maps/world.tscn").instantiate()
	var terrain: CSGBox3D = scene.get_node("CSGBox3D2")
	root.add_child(scene)
	var bird: RigidBody3D = scene.get_node("bird")
	var box: RigidBody3D = scene.get_node("RigidBody3D")
	for frame in range(120):
		await physics_frame
	check(terrain.use_collision and terrain.size.x == 400, "Keep the existing world terrain")
	check(bird.get("is_grounded"), "Bird must settle onto the terrain in walking mode")
	check(bird.get_node_or_null("Visuals/BirdAnimation") != null, "Terrain bird must retain its rigged animation")
	check(bird.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") != null, "Terrain bird must retain the existing camera")
	var animator = bird.get_node("Visuals/BirdAnimation")
	animator.skeleton.get_node("SoleAlignment").modification_processed.connect(capture_feet.bind(animator))
	var grabber = bird.get_node("Grabber")
	check(grabber.find_grab_target() == box, "The box must be immediately reachable in front of the spawn")
	check(not grabber.try_grab(), "Grounded bird must reject pickup")
	var meshes := box.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() == 1 and meshes[0].mesh is BoxMesh and meshes[0].material_override == null,
		"The pickup must be a plain default cube")
	if not grabber.has_method("get_foot_grip_position"):
		check(false, "Carrying must provide leg attachment targets")
		scene.queue_free()
		await process_frame
		quit(1)
		return
	for prop in [box]:
		check(prop.is_in_group("grabbable") and prop.mass <= grabber.maximum_mass, "Pickup must be eligible for grabbing: " + prop.name)
		check(prop.global_position.y > .05 and prop.linear_velocity.length() < .1, "Pickup must settle onto the terrain: " + prop.name)
		bird._perform_flap(Vector3.ZERO)
		bird.freeze = true
		bird.linear_velocity = Vector3.ZERO
		bird.get_node("Visuals").basis = Basis.IDENTITY
		bird.global_position = prop.global_position - grabber.grip_offset
		for frame in range(3):
			await physics_frame
		var blocker := StaticBody3D.new()
		var block_shape := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(.2, .25, .2)
		block_shape.shape = shape
		blocker.add_child(block_shape)
		scene.add_child(blocker)
		blocker.global_position = bird.global_position + Vector3(0, -.77, -.35)
		for frame in range(3):
			await physics_frame
		check(grabber.find_grab_target() == prop, "Low blocker must leave the original pickup visible")
		var before: Vector3 = prop.global_position
		check(not grabber.try_grab(), "Pickup must reject a blocked relocation into the carry pose")
		check(prop.global_position.distance_to(before) < .01 and not prop.lock_rotation, "Rejected pickup must leave cube physics intact")
		blocker.queue_free()
		await physics_frame
		await physics_frame
		check(grabber.try_grab() and grabber.held_body == prop, "Bird must grab the actual terrain prop: " + prop.name)
		for frame in range(12):
			await physics_frame
		check(is_instance_valid(grabber.held_body), "Terrain prop must stay held: " + prop.name)
		check(grabber.get_node_or_null("CarryAnchor/CarryJoint") is PinJoint3D, "Cube must have an attachment joint rather than a spring carry")
		check(not animator.legs_simulating, "Legs must grip the held cube instead of ragdolling")
		for leg in animator._legs:
			check(leg.target.global_position.distance_to(grabber.get_foot_grip_position(leg.side)) < .03,
				"Each foot must grip the actual cube surface")
		bird.set("is_grounded", false)
		bird.global_position.y += .1
		for frame in range(90):
			bird.global_position += Vector3(.05, .04, 0)
			bird.get_node("Visuals").rotation = Vector3(.2, frame * .008, .15)
			await physics_frame
		check(is_instance_valid(grabber.held_body), "The joint must retain the cube during flight")
		check(not animator.legs_simulating, "Airborne feet must grip while carrying")
		for leg in animator._legs:
			check(feet[leg.side].distance_to(grabber.get_foot_grip_position(leg.side)) < .12,
				"The actual animated foot must reach the cube in flight")
		check(prop.global_position.distance_to(grabber._anchor.global_position) < .5, "Attached cube must follow the moving leg anchor")
		grabber.release()
		for frame in range(3):
			await physics_frame
		check(animator.legs_simulating, "Releasing in flight must restore leg ragdoll")
		check(grabber.get_node_or_null("CarryAnchor/CarryJoint") == null, "Release must remove the joint")
		check(grabber.held_body == null and not prop.freeze, "Released terrain prop must remain a dynamic body: " + prop.name)
		check(not prop.lock_rotation, "Releasing must restore the cube's angular physics")
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://maps/world.tscn", "Run Project must launch the existing world")
	scene.queue_free()
	await process_frame
	print("PASS: existing terrain, plain cube, joint carry, airborne foot grip, release recovery and main scene" if failures == 0 else "FAIL: %d playground checks" % failures)
	quit(1 if failures else 0)
