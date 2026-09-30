class_name Player
extends Node3D
## Steers the animals placed under it. Turns the move input and the camera's
## angle into a direction for each one, every physics tick.
##
## An animal is any child with a `move_direction` property (world space,
## horizontal, length 0..1 of its full speed) and, optionally, a
## `facing_direction`. Add them as children in the scene or at runtime.
##
## The animals don't walk in parallel: each heads for a point some way ahead of
## the group's centre, so they crowd together as they go. A lone animal is its
## own centre, so it walks straight, exactly as the input says.

## How far ahead of the group's centre the animals aim for (m). Closer
## converges harder.
@export var converge_distance := 4.0
## The most an animal's direction turns away from the input's (degrees).
@export var max_converge_deg := 35.0


func _physics_process(_delta: float) -> void:
	var animals := get_animals()
	if animals.is_empty():
		return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam := get_viewport().get_camera_3d()
	var cam_basis := cam.global_basis if cam else global_basis
	var forward := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()
	var right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z).normalized()
	var move := right * input.x - forward * input.y
	if move.length_squared() <= 0.01:
		for animal in animals:
			animal.move_direction = Vector3.ZERO
		return

	var focus := get_center() + move.normalized() * converge_distance
	var limit := deg_to_rad(max_converge_deg)
	for animal in animals:
		var to_focus := focus - animal.global_position
		to_focus.y = 0.0
		var turn := 0.0
		if to_focus.length_squared() > 1e-4:
			turn = clampf(move.signed_angle_to(to_focus, Vector3.UP), -limit, limit)
		animal.move_direction = move.rotated(Vector3.UP, turn)
		if "facing_direction" in animal:
			animal.facing_direction = forward.rotated(Vector3.UP, turn)


func get_animals() -> Array[Node3D]:
	var animals: Array[Node3D] = []
	for child in get_children():
		if child is Node3D and "move_direction" in child and not child.is_queued_for_deletion():
			animals.append(child)
	return animals


## Average position of the animals.
func get_center() -> Vector3:
	var animals := get_animals()
	if animals.is_empty():
		return global_position
	var sum := Vector3.ZERO
	for animal in animals:
		sum += animal.global_position
	return sum / animals.size()
