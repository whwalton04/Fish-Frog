extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var bird = load("res://bird.gd").new()
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	bird.add_child(visuals)
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	bird.add_child(pivot)
	root.add_child(bird)
	# Headless Godot cannot capture a mouse. Exercise the same input helper directly.
	if not bird.has_method("_apply_cursor_motion"):
		_check(false, "Mouse movement must update cursor bias separately from flight heading")
	else:
		bird._apply_cursor_motion(Vector2(100.0, 0.0))
		_check(is_zero_approx(bird.yaw), "Mouse motion must set steering bias without snapping the flight heading")
		_check(bird.cursor_bias.x > 0.0, "Rightward mouse movement must produce rightward bias")
		bird._apply_cursor_motion(Vector2(1000.0, 1000.0))
		_check(bird.cursor_bias.length() <= 1.00001, "Diagonal steering must not exceed full strength")

	if not bird.has_method("_update_steering"):
		_check(false, "Flight must advance from held cursor bias every physics tick")
	else:
		bird.cursor_offset = Vector2(200.0, 0.0)
		for tick in range(60):
			bird._update_steering(1.0 / 60.0)
		_check(bird.yaw < -0.1, "Held right bias must turn the flight heading right")
		_check(bird.roll < 0.0, "Right turns must lower the right wing")
		_check(absf(bird.aim_yaw) <= bird.maximum_aim_yaw + 0.00001, "Aim offset must remain limited")
		var first_yaw: float = bird.yaw
		for tick in range(240):
			bird._update_steering(1.0 / 60.0)
		_check(absf(wrapf(bird.yaw - first_yaw, -PI, PI)) > 0.1, "Holding bias must keep turning after aim reaches its limit")
		bird.cursor_offset = Vector2.ZERO
		for tick in range(120):
			bird._update_steering(1.0 / 60.0)
		_check(absf(bird.roll) < 0.01, "Centering the cursor must level the wings")
		var settled_yaw: float = bird.yaw
		for tick in range(60):
			bird._update_steering(1.0 / 60.0)
		_check(absf(wrapf(bird.yaw - settled_yaw, -PI, PI)) < 0.01, "Centered cursor must retain the new heading")
		bird.cursor_offset = Vector2(0.0, -200.0)
		bird.pitch = 0.0
		for tick in range(60):
			bird._update_steering(1.0 / 60.0)
		_check(bird.pitch > 0.1, "Upward cursor bias must pitch the flight upward")
		for tick in range(600):
			bird._update_steering(1.0 / 60.0)
		_check(bird.pitch <= bird.maximum_pitch + 0.00001, "Sustained upward input must respect flight pitch limit")
		bird.cursor_offset = Vector2(1.0, 1.0)
		bird._update_steering(1.0 / 60.0)
		_check(bird.cursor_bias == Vector2.ZERO, "Small cursor offsets must fall inside the dead zone")
		bird.cursor_offset = Vector2(-200.0, 0.0)
		bird.yaw = 0.0
		bird.roll = 0.0
		for tick in range(60):
			bird._update_steering(1.0 / 60.0)
		_check(bird.yaw > 0.1 and bird.roll > 0.0, "Left bias must reverse both turn and bank direction")
		bird.cursor_offset = Vector2(0.0, 200.0)
		bird.pitch = 0.0
		for tick in range(60):
			bird._update_steering(1.0 / 60.0)
		_check(bird.pitch < -0.1, "Downward cursor bias must pitch the flight downward")

	if not bird.has_method("_steer_velocity"):
		_check(false, "Flight must redirect existing momentum into turns")
	else:
		var redirected: Vector3 = bird._steer_velocity(Vector3(0.0, 0.0, -10.0), Vector3.RIGHT, 0.1)
		_check(redirected.x > 0.0 and redirected.z < 0.0, "Velocity must progressively bend into a right turn")
		_check(is_equal_approx(redirected.length(), 10.0), "Steering alone must preserve speed")
		var reversed: Vector3 = bird._steer_velocity(Vector3(0.0, 0.0, -10.0), Vector3.BACK, 0.1)
		_check(reversed.is_finite() and is_equal_approx(reversed.length(), 10.0), "Opposite velocity must turn without losing speed or producing invalid values")

	# Heading response must use X/Z speed, independent of falling or climbing.
	bird.cursor_offset = Vector2(200.0, 0.0)
	bird.linear_velocity = Vector3(0.0, 0.0, -25.0)
	bird.yaw = 0.0
	bird.roll = -bird.maximum_roll
	bird._update_steering(0.1)
	var forward_turn: float = absf(bird.yaw)
	bird.linear_velocity = Vector3(25.0, 0.0, 0.0)
	bird.yaw = 0.0
	bird.roll = -bird.maximum_roll
	bird._update_steering(0.1)
	_check(is_equal_approx(absf(bird.yaw), forward_turn), "Equal horizontal speed must turn equally regardless of world direction")
	bird.linear_velocity = Vector3(0.0, -25.0, 0.0)
	bird.yaw = 0.0
	bird.roll = -bird.maximum_roll
	bird._update_steering(0.1)
	_check(absf(bird.yaw) < forward_turn * 0.5, "Vertical speed alone must not give full horizontal turning strength")

	if not bird.has_method("_update_flight_velocity"):
		_check(false, "Glide movement must steer even without acceleration")
	else:
		bird.yaw = -PI / 2.0
		bird.pitch = 0.0
		var gliding: Vector3 = bird._update_flight_velocity(Vector3(0.0, 0.0, -20.0), 0.1, true, false)
		_check(gliding.x > 0.1 and gliding.z < 0.0, "Releasing accelerate must still bend momentum toward the flight heading")
		bird.yaw = 0.0
		var coasting := Vector3(0.0, 0.0, -20.0)
		for tick in range(60):
			coasting = bird._update_flight_velocity(coasting, 1.0 / 60.0, true, false)
		_check(coasting.length() > 17.0 and coasting.length() <= 20.0, "A one-second glide must retain momentum without adding thrust")
		var boosted: Vector3 = bird._update_flight_velocity(Vector3(0.0, 0.0, -20.0), 0.1, true, true)
		_check(boosted.length() > 20.0, "Accelerate must still add forward thrust")
		var capped: Vector3 = bird._update_flight_velocity(Vector3(0.0, 0.0, -1000.0), 0.1, true, true)
		_check(capped.length() <= bird.max_velocity + 0.001, "Flight velocity must respect its configured speed cap")

	if not bird.has_method("_update_camera"):
		_check(false, "Camera follow must have a limited angular lag")
	else:
		bird.aim_yaw = 0.0
		bird.aim_pitch = 0.0
		bird.yaw = deg_to_rad(179.0)
		bird.pitch = 0.0
		bird.linear_velocity = Vector3.ZERO
		pivot.rotation.y = deg_to_rad(-179.0)
		bird._update_camera(1.0 / 60.0)
		_check(absf(wrapf(bird.yaw - pivot.rotation.y, -PI, PI)) < deg_to_rad(3.0), "Camera must take the short path across angle wraparound")
		bird.yaw = deg_to_rad(90.0)
		pivot.rotation = Vector3.ZERO
		bird._update_camera(1.0 / 60.0)
		_check(absf(wrapf(bird.yaw - pivot.rotation.y, -PI, PI)) <= bird.maximum_camera_yaw_lag + 0.00001, "Camera yaw lag must remain capped")
		bird.linear_velocity = Vector3(10.0, 0.0, 0.0)
		bird._update_camera(1.0 / 60.0)
		_check(absf(wrapf(bird.yaw - pivot.rotation.y, -PI, PI)) <= bird.maximum_camera_yaw_lag + 0.00001, "Moving camera must retain the commanded heading even when velocity points elsewhere")
		bird.linear_velocity = Vector3.ZERO
		bird.pitch = deg_to_rad(45.0)
		bird.roll = bird.maximum_roll
		pivot.rotation = Vector3.ZERO
		bird._update_camera(1.0 / 60.0)
		_check(absf(bird.pitch - pivot.rotation.x) <= bird.maximum_camera_pitch_lag + 0.00001, "Camera pitch lag must remain capped")
		for tick in range(120):
			bird._update_camera(1.0 / 60.0)
		_check(absf(pivot.rotation.z) <= bird.maximum_camera_roll + 0.00001, "Camera roll must remain restrained during a full bank")
		bird.yaw = 0.0
		bird.pitch = 0.0
		bird.roll = 0.0
		bird.aim_yaw = deg_to_rad(-25.0)
		bird.aim_pitch = deg_to_rad(20.0)
		pivot.rotation = Vector3.ZERO
		for tick in range(240):
			bird._update_camera(1.0 / 60.0)
		_check(pivot.rotation.y < -0.01 and absf(pivot.rotation.y) < absf(bird.aim_yaw), "Camera must follow horizontal mouse aim less than the bird")
		_check(pivot.rotation.x > 0.01 and pivot.rotation.x < bird.aim_pitch, "Camera must follow vertical mouse aim less than the bird")
		bird.aim_yaw = 0.0
		bird.aim_pitch = 0.0
		for tick in range(240):
			bird._update_camera(1.0 / 60.0)
		_check(absf(pivot.rotation.y) < 0.001 and absf(pivot.rotation.x) < 0.001, "Camera mouse offset must return to center when aim centers")
		# Same aim at rest and in motion must produce the same camera target.
		bird.aim_yaw = deg_to_rad(-25.0)
		bird.aim_pitch = deg_to_rad(20.0)
		for tick in range(240):
			bird._update_camera(1.0 / 60.0)
		var stationary_camera := pivot.rotation
		bird.linear_velocity = Vector3(10.0, 0.0, 0.0)
		for tick in range(240):
			bird._update_camera(1.0 / 60.0)
		_check(absf(wrapf(pivot.rotation.y - stationary_camera.y, -PI, PI)) < 0.001,
			"Movement must not override camera mouse aim when velocity lags behind heading")

	bird.free()
	if failures == 0:
		print("PASS: cursor steering, banking, continuous turning, momentum, and camera limits")
	else:
		print("FAIL: %d flight checks" % failures)
	quit(1 if failures > 0 else 0)
