extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func make_bird(at: Vector3) -> RigidBody3D:
	var bird = load("res://actors/bird/bird.gd").new()
	bird.position = at
	bird.lock_rotation = true
	bird.can_sleep = false
	var collision := CollisionShape3D.new()
	collision.shape = CapsuleShape3D.new()
	bird.add_child(collision)
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	bird.add_child(visuals)
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	bird.add_child(pivot)
	root.add_child(bird)
	return bird


func make_box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	root.add_child(body)
	return body


func _run() -> void:
	var bird = make_bird(Vector3(0, 3, 0))
	if not bird.has_method("_update_walk_velocity"):
		check(false, "The bird needs separate grounded walking controls")
		bird.free()
		quit(1)
		return
	bird.freeze = true
	bird._set_grounded(true)
	bird.ground_camera_yaw = 0.0
	var forward: Vector3 = bird._update_walk_velocity(Vector3.ZERO, Vector2(0, -1), 1.0, true)
	check(forward.z < -1 and absf(forward.x) < 0.001, "W must walk forward relative to the ground camera")
	var strafe: Vector3 = bird._update_walk_velocity(Vector3.ZERO, Vector2.RIGHT, 1.0, true)
	check(strafe.x > 1 and absf(strafe.z) < 0.001, "D must walk sideways relative to the ground camera")
	var backward: Vector3 = bird._update_walk_velocity(Vector3.ZERO, Vector2(0, 1), 1.0, true)
	check(backward.z > 1, "S must walk backward relative to the camera")
	var diagonal: Vector3 = bird._update_walk_velocity(Vector3.ZERO, Vector2(1, -1), 1.0, true)
	check(is_equal_approx(diagonal.length(), bird.walk_speed), "Diagonal walking must not exceed walk speed")
	bird.ground_camera_yaw = -PI / 2
	bird.camera_pivot.rotation.y = bird.ground_camera_yaw
	var turned: Vector3 = bird._update_walk_velocity(Vector3.ZERO, Vector2(0, -1), 1.0, true)
	check(turned.x > 1 and absf(turned.z) < 0.001, "Walking must follow the camera's horizontal heading")
	var stopped: Vector3 = bird._update_walk_velocity(Vector3(4, -2, 3), Vector2.ZERO, 1.0, true)
	check(absf(stopped.x) < 0.001 and absf(stopped.z) < 0.001 and stopped.y == -2, "Releasing movement must brake without cancelling gravity")
	var paused: Vector3 = bird._update_walk_velocity(Vector3.ZERO, Vector2.ONE, 1.0, false)
	check(paused == Vector3.ZERO, "Releasing mouse capture must disable walking input")
	bird.ground_normal = Vector3(0, 1, 1).normalized()
	bird.ground_camera_yaw = 0.0
	bird.camera_pivot.rotation = Vector3.ZERO
	var slope: Vector3 = bird._update_walk_velocity(Vector3.ZERO, Vector2(0, -1), 1.0, true)
	check(absf(slope.dot(bird.ground_normal)) < 0.001 and slope.y > 0, "Walking must follow the supporting slope")
	bird.ground_normal = Vector3.UP
	bird.ground_velocity = Vector3(2, 0, 0)
	var platform: Vector3 = bird._update_walk_velocity(Vector3.ZERO, Vector2.ZERO, 1.0, true)
	check(platform.is_equal_approx(Vector3(2, 0, 0)), "Idle walking must inherit support-platform velocity")
	bird.ground_velocity = Vector3.ZERO
	bird.ground_camera_yaw = 0.0
	bird.camera_pivot.rotation = Vector3.ZERO
	bird._apply_cursor_motion(Vector2(80, -40))
	check(bird.ground_camera_yaw < 0 and bird.ground_camera_pitch > 0, "Ground mouse motion must look around instead of accumulating flight bias")
	check(bird.cursor_offset == Vector2.ZERO, "Ground camera input must not prime flight steering")
	bird._update_camera(1.0 / 60.0)
	check(bird.camera_pivot.rotation.y < 0 and bird.camera_pivot.rotation.y - bird.ground_camera_yaw > .02,
		"Ground mouse look must ease toward its target instead of snapping")
	var visible_forward := -Basis(Vector3.UP, bird.camera_pivot.rotation.y).z
	var viewed_walk: Vector3 = bird._update_walk_velocity(Vector3.ZERO, Vector2(0, -1), 1.0, true)
	check(viewed_walk.normalized().dot(visible_forward) > .999,
		"Walking must follow the visible camera while mouse look is smoothing")
	# Camera translation should lag behind the bird, then settle at rest.
	var old_camera: Vector3 = bird.camera_pivot.global_position
	bird.position.x += .4
	bird._update_camera(1.0 / 60.0)
	var camera_advance: float = bird.camera_pivot.global_position.x - old_camera.x
	check(camera_advance > 0 and camera_advance < .4,
		"Walking camera must follow movement smoothly rather than being position-locked")
	for tick in range(240):
		bird._update_camera(1.0 / 60.0)
	check(bird.camera_pivot.global_position.distance_to(bird.global_position) < .01,
		"Ground camera must settle back onto the bird when movement stops")
	bird.position.x += 100
	bird._update_camera(1.0 / 60.0)
	check(bird.camera_pivot.global_position.distance_to(bird.global_position) < 1.0,
		"Dynamic camera lag must stay bounded after a large position change")
	bird.position.x = 0
	bird.ground_camera_yaw = wrapf(bird.camera_pivot.rotation.y + deg_to_rad(80), -PI, PI)
	bird.ground_camera_pitch = deg_to_rad(30)
	bird._update_camera(1.0 / 60.0)
	var takeoff_view: Vector3 = bird.camera_pivot.rotation
	bird._perform_flap(Vector3.ZERO)
	bird._update_camera(1.0 / 60.0)
	check(absf(wrapf(bird.camera_pivot.rotation.y - takeoff_view.y, -PI, PI)) < deg_to_rad(1),
		"Taking off during ground mouse look must preserve the visible heading without a camera snap")
	check(absf(bird.camera_pivot.rotation.x - takeoff_view.x) < deg_to_rad(1),
		"Taking off during ground mouse look must preserve the visible camera pitch")
	bird.takeoff_cooldown = 0.0
	bird._set_grounded(true)
	bird._apply_cursor_motion(Vector2(0, -100000))
	check(bird.ground_camera_pitch <= bird.maximum_ground_look_pitch, "Ground camera pitch must be limited")
	bird.pitch = 0.5
	bird.roll = 0.4
	bird.aim_yaw = 0.2
	bird.cursor_offset = Vector2(100, 0)
	bird._set_grounded(false)
	bird._set_grounded(true)
	check(bird.pitch == 0 and bird.roll == 0 and bird.aim_yaw == 0 and bird.cursor_offset == Vector2.ZERO, "Landing must clear flight banking, pitch, and cursor bias")
	var launch: Vector3 = bird._perform_flap(Vector3(2, -4, 3))
	check(not bird.is_grounded and launch.y >= bird.takeoff_speed and launch.x == 2 and launch.z == 3, "Space must launch from the ground while preserving horizontal momentum")
	check(bird.takeoff_cooldown > 0, "Takeoff must temporarily ignore lingering floor contacts")
	bird._set_grounded(true)
	# Actual Jolt contact classification and flight/walk transitions.
	var floor := make_box(Vector3(0, -0.5, 0), Vector3(12, 1, 12))
	bird.freeze = false
	bird.position = Vector3(0, 3, 0)
	bird.linear_velocity = Vector3.ZERO
	for frame in range(100):
		await physics_frame
	check(bird.is_grounded, "Landing on a real floor must automatically enable walking")
	check(bird.ground_normal.dot(Vector3.UP) > 0.99, "The support normal must point upward")
	var launch_height: float = bird.position.y
	bird.linear_velocity = bird._perform_flap(bird.linear_velocity)
	for frame in range(8):
		await physics_frame
	check(not bird.is_grounded and bird.position.y > launch_height + 0.1, "Takeoff must actually leave the floor without immediately relanding")
	for frame in range(160):
		await physics_frame
	var hover_height: float = bird.position.y
	for frame in range(60):
		await physics_frame
	check(bird.is_hovering and absf(bird.position.y - hover_height) < .02, "A Space tap must hold altitude")
	bird.linear_velocity = Vector3.DOWN * 10
	for frame in range(60):
		await physics_frame
	check(bird.is_grounded and not bird.is_hovering, "Landing must restore walking")
	bird.rotation.z = deg_to_rad(60)
	bird.position = Vector3(0, 3, 0)
	bird.linear_velocity = Vector3.ZERO
	for frame in range(100):
		await physics_frame
	check(bird.is_grounded and bird.ground_normal.dot(Vector3.UP) > 0.99,
		"A rotated physics body must still classify the floor using world-space normals")
	bird.rotation = Vector3.ZERO
	bird.position.x = 20
	for frame in range(8):
		await physics_frame
	check(not bird.is_grounded, "Walking off an edge must restore flight automatically")
	# Walls and ceilings must never be treated as walkable floor.
	bird.gravity_scale = 0
	var wall := make_box(Vector3(20.8, 2, 0), Vector3(0.3, 8, 8))
	bird.position = Vector3(20, 2, 0)
	for frame in range(30):
		bird.linear_velocity = Vector3(3, 0, 0)
		await physics_frame
	check(not bird.is_grounded, "Touching a vertical wall must not enable walking")
	wall.queue_free()
	var ceiling := make_box(Vector3(20, 3.2, 0), Vector3(8, 0.3, 8))
	bird.position = Vector3(20, 1.5, 0)
	for frame in range(30):
		bird.linear_velocity = Vector3(0, 3, 0)
		await physics_frame
	check(not bird.is_grounded, "Touching a ceiling must not enable walking")
	for action in ["walk_forward", "walk_backward", "walk_left", "walk_right"]:
		check(InputMap.has_action(action), "Walking action must exist: " + action)
	bird.queue_free()
	floor.queue_free()
	ceiling.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: camera-relative walking, speed limits, braking, slopes, platform velocity, grounded mouse look, landing, takeoff, ledges, walls, ceilings, and input wiring")
	quit(1 if failures else 0)
