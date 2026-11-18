extends SceneTree

const DEMO := "res://maps/pressure_plate_demo.tscn"


func _initialize() -> void:
	call_deferred("run")


func ticks(count: int) -> void:
	for tick in range(count):
		await physics_frame


func run() -> void:
	if not ResourceLoader.exists(DEMO):
		push_error("Missing playable pressure plate scene")
		quit(1)
		return
	var scene = load(DEMO).instantiate()
	root.add_child(scene)
	var bird = scene.get_node("Bird")
	var grabber = bird.get_node("Grabber")
	var box: RigidBody3D = scene.get_node("Block")
	var plate: StaticBody3D = scene.get_node("Plate")
	var door: AnimatableBody3D = scene.get_node("Door")
	var closed := door.position
	await ticks(90)
	bird._perform_flap(Vector3.ZERO)
	bird.freeze = true
	bird.global_position = box.global_position - grabber.grip_offset + Vector3.UP * 0.4
	await ticks(3)
	if not grabber.try_grab():
		push_error("Bird could not pick up the starting block")
		quit(1)
		return
	var target := Vector3(plate.position.x, 2, plate.position.z)
	for i in range(100):
		bird.global_position = bird.global_position.move_toward(target, 0.1)
		await physics_frame
	if grabber.held_body != box or not door.position.is_equal_approx(closed):
		push_error("Held block must travel to the plate with the door closed")
		quit(1)
		return
	grabber.release()
	await ticks(150)
	if door.position.y < closed.y + 2.5:
		push_error("Released block must open the doorway")
		quit(1)
		return
	box.global_position.x += 4
	box.sleeping = false
	await ticks(150)
	if not door.position.is_equal_approx(closed):
		push_error("Unweighted plate must close the door")
		quit(1)
		return
	print("PASS: grab, carry, drop, door opening and closing")
	quit()
