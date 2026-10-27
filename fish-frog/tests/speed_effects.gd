extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _settle(pivot: Node3D, accelerating: bool = false) -> void:
	for frame in range(240):
		if accelerating:
			pivot._update_speed_effects(1.0 / 60.0, true)
		else:
			pivot._update_speed_effects(1.0 / 60.0)


func _run() -> void:
	var bird := RigidBody3D.new()
	bird.freeze = true
	var pivot = load("res://camera_pivot.gd").new()
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 75.0
	arm.add_child(camera)
	pivot.add_child(arm)
	bird.add_child(pivot)
	root.add_child(bird)
	if pivot.get("speed_streaks") == null:
		_check(false, "Speed feedback must provide short white streaks in 3D space")
		bird.free()
		quit(1)
		return
	if not pivot.has_method("_update_speed_effects"):
		_check(false, "Camera must provide speed-based FOV and speed-line feedback")
	else:
		_settle(pivot)
		_check(pivot.speed_streaks is GPUParticles3D, "Speed streaks must exist in 3D space")
		_check(pivot.speed_streaks.get_parent() == camera, "Streaks must pass the camera rather than cover the screen")
		_check(is_equal_approx(camera.fov, 75.0), "Stationary bird must retain the original FOV")
		_check(is_zero_approx(pivot.speed_streaks.process_material.color.a), "Speed lines must disappear at rest")
		bird.linear_velocity = Vector3(0.0, 0.0, -14.0)
		pivot._update_speed_effects(1.0 / 60.0)
		_check(camera.fov > 75.0 and camera.fov < 85.0, "Acceleration must widen FOV progressively rather than snap")
		_settle(pivot)
		var medium_fov: float = camera.fov
		var medium_lines: float = pivot.speed_streaks.process_material.color.a
		var medium_streak_speed: float = pivot.speed_streaks.speed_scale
		_check(pivot.speed_streaks.emitting, "Moving flight must emit passing streaks")
		_check(medium_lines > 0.0 and medium_lines < 1.0, "Medium speed must create partial speed-line strength")
		bird.linear_velocity = Vector3(0.0, 0.0, -1000.0)
		_settle(pivot)
		_check(camera.fov > medium_fov and camera.fov <= 95.001, "High speed must increase FOV while respecting its cap")
		_check(pivot.speed_streaks.process_material.color.a > medium_lines and pivot.speed_streaks.process_material.color.a <= 1.0, "Speed-line strength must increase and remain capped")
		_check(pivot.speed_streaks.speed_scale > medium_streak_speed, "Streaks must pass faster as flight speed increases")
		bird.linear_velocity = Vector3(0.0, -14.0, 0.0)
		_settle(pivot)
		_check(absf(camera.fov - medium_fov) < 0.01, "Equal speed in a dive must give the same feedback as forward flight")
		bird.linear_velocity = Vector3.ZERO
		_settle(pivot)
		_check(absf(camera.fov - 75.0) < 0.01 and pivot.speed_streaks.process_material.color.a < 0.001, "Slowing must restore normal FOV and fade the lines")
		_check(not pivot.speed_streaks.emitting and not pivot.speed_streaks.visible, "Passing streaks must stop and disappear at rest")
		pivot.speed_effects_enabled = false
		bird.linear_velocity = Vector3(0.0, 0.0, -100.0)
		_settle(pivot)
		_check(absf(camera.fov - 75.0) < 0.01 and pivot.speed_streaks.process_material.color.a < 0.001, "Disabling feedback must retain normal view at speed")
		pivot.speed_effects_enabled = true
		pivot.effect_full_speed = pivot.effect_start_speed
		_settle(pivot)
		_check(is_finite(camera.fov) and camera.fov <= 95.001, "Equal speed thresholds must not cause invalid FOV")
		_check(not pivot.speed_streaks.has_method("_draw"), "Streaks must use native particles rather than scripted screen drawing")
		pivot.effect_start_speed = 3.0
		pivot.effect_full_speed = 25.0
		bird.linear_velocity = Vector3.ZERO
		_settle(pivot)
		bird.linear_velocity = Vector3(0.0, 0.0, -8.5)
		_settle(pivot)
		var early_gain: float = camera.fov - 75.0
		bird.linear_velocity = Vector3(0.0, 0.0, -19.5)
		_settle(pivot)
		var three_quarter_fov: float = camera.fov
		bird.linear_velocity = Vector3(0.0, 0.0, -25.0)
		_settle(pivot)
		_check(early_gain > (camera.fov - three_quarter_fov) * 2.0,
			"Root curve must widen FOV more at low speed than for the same speed increase near the cap")
		_check(camera.fov <= 82.0, "Speed alone must provide only subtle FOV widening")
		# Dynamic call keeps this regression runnable before the new argument exists.
		if pivot.get_method_list().filter(func(method): return method.name == "_update_speed_effects")[0].args.size() < 2:
			_check(false, "Pressing accelerate must supply an FOV kick independent of actual speed")
		else:
			bird.linear_velocity = Vector3.ZERO
			_settle(pivot)
			pivot._update_speed_effects(0.12, true)
			_check(camera.fov > 82.0 and camera.fov < 89.0, "Initial accelerate press must give a large but smoothed FOV kick")
			_settle(pivot, true)
			_check(camera.fov > 88.0 and pivot.speed_streaks.process_material.color.a < 0.001, "FOV kick must work at rest without inventing speed lines")
			bird.linear_velocity = Vector3(0.0, 0.0, -100.0)
			_settle(pivot, true)
			_check(camera.fov <= 95.001, "Acceleration kick and speed curve must share the total FOV cap")
			_settle(pivot)
			_check(camera.fov <= 82.0 and camera.fov > 75.0, "Releasing accelerate must remove the kick while retaining speed-based widening")
			pivot.speed_effects_enabled = false
			_settle(pivot, true)
			_check(absf(camera.fov - 75.0) < 0.01, "Disabling speed effects must also disable the acceleration kick")
	if pivot.get("barrel_distortion") == null:
		_check(false, "Camera must provide a barrel-distortion overlay")
	else:
		pivot.speed_effects_enabled = true
		bird.linear_velocity = Vector3.ZERO
		_settle(pivot)
		var lens: ColorRect = pivot.barrel_distortion
		_check(not lens.visible, "Barrel distortion must disappear at rest")
		_check(lens.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Lens overlay must not block cursor steering")
		bird.linear_velocity = Vector3(0.0, 0.0, -14.0)
		_settle(pivot)
		var medium_distortion: float = lens.material.get_shader_parameter("strength")
		_check(lens.visible and medium_distortion > 0.0, "Flight speed must introduce barrel distortion")
		bird.linear_velocity = Vector3(0.0, 0.0, -1000.0)
		_settle(pivot)
		var full_distortion: float = lens.material.get_shader_parameter("strength")
		_check(full_distortion > medium_distortion and full_distortion <= pivot.maximum_barrel_distortion + 0.00001,
			"Barrel distortion must scale with speed and respect its cap")
		pivot.barrel_distortion_enabled = false
		_settle(pivot)
		_check(not lens.visible and is_zero_approx(lens.material.get_shader_parameter("strength")), "Lens effect must have an independent off switch")
		pivot.barrel_distortion_enabled = true
		pivot.speed_effects_enabled = false
		_settle(pivot)
		_check(not lens.visible, "Disabling speed feedback must fade out lens distortion too")
	bird.free()
	print("PASS: speed-based FOV and speed lines" if failures == 0 else "FAIL: %d speed effect checks" % failures)
	quit(1 if failures > 0 else 0)
