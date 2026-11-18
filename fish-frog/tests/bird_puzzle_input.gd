extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func ticks(count: int) -> void:
	for frame in range(count):
		await physics_frame


func send_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: mouse capture requires a windowed display")
		quit()
		return
	var scene = load("res://maps/pressure_plate_demo.tscn").instantiate()
	root.add_child(scene)
	var bird = scene.get_node("Bird")
	await ticks(60)
	# Simulate returning to play after the editor or Escape releases the mouse.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	Input.flush_buffered_events()
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	Input.flush_buffered_events()
	var start: Vector3 = bird.position
	var angle: float = bird.ground_camera_yaw
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, 0)
	motion.screen_relative = motion.relative
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	send_key(KEY_D, true)
	await ticks(45)
	send_key(KEY_D, false)
	send_key(KEY_SPACE, true)
	await ticks(8)
	send_key(KEY_SPACE, false)
	var moved := start.distance_to(Vector3(bird.position.x, start.y, bird.position.z)) > 0.3
	var looked: bool = absf(bird.ground_camera_yaw - angle) > 0.02
	var flew: bool = bird.is_hovering and bird.position.y > start.y + 0.2
	var heading: float = bird.yaw
	motion = motion.duplicate()
	motion.relative = Vector2(180, 0)
	motion.screen_relative = motion.relative
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await ticks(30)
	var steered: bool = absf(angle_difference(heading, bird.yaw)) > 0.04
	print("Mouse look: %s, walking: %s, takeoff: %s, steering: %s" % [looked, moved, flew, steered])
	quit(0 if moved and looked and flew and steered else 1)
