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
##
## Keys 2-9 take one animal (in child order) to steer on its own while the rest
## wait; 1 goes back to the group. The group is whoever is near each other: an
## animal left far from the others is dropped off beside the player, and an
## animal in the `animals` group that comes near a member joins.
##
## While steering one animal, the animal it's looking at (nearest the middle of
## the view, within its mount_range) is marked with an arrow, and the mount
## action (space) puts it on top. Animals mounted on others aren't steered with
## the group, so a stack walks as one; steering one on its own gets it off.

const ANIMAL_GROUP := &"animals"

## How far ahead of the group's centre the animals aim for (m). Closer
## converges harder.
@export var converge_distance := 4.0
## The most an animal's direction turns away from the input's (degrees).
@export var max_converge_deg := 35.0
## A stray joins when it comes this close to any member, across the ground (m).
@export var join_radius := 1.5
## A member leaves when it's this far from the rest, across the ground (m).
## Wider than join_radius, so one at the edge doesn't flicker in and out.
@export var leave_radius := 3.0
## The most an animal can be off the middle of the view and still be the one
## looked at (degrees).
@export var look_angle_deg := 30.0

## The animal steered on its own, or null when steering the group. It may have
## wandered out of the group and still be steered.
var controlled: Node3D = null
## What the controlled animal would mount, or null.
var looked_at: Node3D = null

var _arrow: MeshInstance3D


func _ready() -> void:
	_arrow = _make_arrow()
	add_child(_arrow)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mount") and looked_at:
		controlled.mount_onto(looked_at)
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var number: int = event.physical_keycode - KEY_0
	if number == 1:
		_control(null)
	elif number >= 2 and number <= 9:
		var animals := get_animals()
		if number - 2 >= animals.size():
			return
		_control(animals[number - 2])
	else:
		return
	get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	_update_membership()
	var steered := get_steered()
	if steered.is_empty():
		return
	if controlled:
		for animal in get_animals():
			if animal != controlled:
				animal.move_direction = Vector3.ZERO

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam := get_viewport().get_camera_3d()
	var cam_basis := cam.global_basis if cam else global_basis
	var forward := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()
	var right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z).normalized()
	var move := right * input.x - forward * input.y
	if move.length_squared() <= 0.01:
		for animal in steered:
			animal.move_direction = Vector3.ZERO
		return

	var focus := get_center() + move.normalized() * converge_distance
	var limit := deg_to_rad(max_converge_deg)
	for animal in steered:
		if not controlled and animal.get("mount"):
			animal.move_direction = Vector3.ZERO
			continue
		var to_focus := focus - animal.global_position
		to_focus.y = 0.0
		var turn := 0.0
		if to_focus.length_squared() > 1e-4:
			turn = clampf(move.signed_angle_to(to_focus, Vector3.UP), -limit, limit)
		animal.move_direction = move.rotated(Vector3.UP, turn)
		if "facing_direction" in animal:
			animal.facing_direction = forward.rotated(Vector3.UP, turn)


func _process(_delta: float) -> void:
	looked_at = _find_looked_at()
	_arrow.visible = looked_at != null
	if looked_at:
		var size: float = looked_at.get("size") if "size" in looked_at else 1.0
		var bob := sin(Time.get_ticks_msec() * 0.006) * 0.015
		_arrow.global_position = looked_at.global_position + Vector3.UP * (0.12 + bob) * size
		_arrow.scale = Vector3.ONE * size


## The animal the controlled one can mount nearest the middle of the view.
func _find_looked_at() -> Node3D:
	if not controlled or not is_instance_valid(controlled) or not controlled.has_method("mount_onto"):
		return null
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return null
	var best: Node3D = null
	var best_angle := deg_to_rad(look_angle_deg)
	var candidates := get_animals()
	for animal in get_tree().get_nodes_in_group(ANIMAL_GROUP):
		if animal is Node3D and animal not in candidates:
			candidates.append(animal)
	for animal in candidates:
		if not controlled.can_mount(animal):
			continue
		var angle := (-cam.global_basis.z).angle_to(animal.global_position - cam.global_position)
		if angle < best_angle:
			best = animal
			best_angle = angle
	return best


## A downward-pointing triangle that always faces the camera, drawn over
## everything.
func _make_arrow() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.035, 0.06, 0.0), Vector3(0.035, 0.06, 0.0), Vector3(0.0, 0.0, 0.0)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var arrow := MeshInstance3D.new()
	arrow.mesh = mesh
	arrow.top_level = true
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.visible = false
	return arrow


func get_animals() -> Array[Node3D]:
	var animals: Array[Node3D] = []
	for child in get_children():
		if child is Node3D and "move_direction" in child and not child.is_queued_for_deletion():
			animals.append(child)
	return animals


## The animals the input moves: the controlled one, or else the group.
func get_steered() -> Array[Node3D]:
	if controlled and is_instance_valid(controlled) and not controlled.is_queued_for_deletion():
		return [controlled]
	return get_animals()


## Average position of the steered animals.
func get_center() -> Vector3:
	var animals := get_steered()
	if animals.is_empty():
		return global_position
	var sum := Vector3.ZERO
	for animal in animals:
		sum += animal.global_position
	return sum / animals.size()


func _control(animal: Node3D) -> void:
	if controlled and is_instance_valid(controlled) and controlled != animal:
		controlled.move_direction = Vector3.ZERO
	controlled = animal


## Keeps the biggest cluster of members, dropping off the rest, then takes in
## strays near it. On a tie the controlled animal's cluster is the one to go,
## so walking it away from the others takes it out of the group.
func _update_membership() -> void:
	var keep: Array[Node3D] = []
	for cluster in _clusters(get_animals()):
		if cluster.size() > keep.size() or (cluster.size() == keep.size() and controlled in keep):
			keep = cluster
	for animal in get_animals():
		if animal not in keep:
			_release(animal)
	if keep.is_empty():
		return
	for animal in get_tree().get_nodes_in_group(ANIMAL_GROUP):
		if animal is Node3D and not animal.get_parent() is Player and "move_direction" in animal \
				and not animal.is_queued_for_deletion() and _near_any(animal, keep, join_radius):
			animal.reparent(self)
			keep.append(animal)


func _release(animal: Node3D) -> void:
	animal.add_to_group(ANIMAL_GROUP)
	animal.reparent(get_parent())
	if animal != controlled:
		animal.move_direction = Vector3.ZERO


## Splits the animals into groups that are each within leave_radius of one
## another, link by link.
func _clusters(animals: Array[Node3D]) -> Array[Array]:
	var clusters: Array[Array] = []
	var left := animals.duplicate()
	while not left.is_empty():
		var cluster: Array[Node3D] = [left.pop_front()]
		var i := 0
		while i < cluster.size():
			for other in left.duplicate():
				if _ground_distance(cluster[i], other) < leave_radius:
					cluster.append(other)
					left.erase(other)
			i += 1
		clusters.append(cluster)
	return clusters


func _near_any(animal: Node3D, others: Array[Node3D], radius: float) -> bool:
	for other in others:
		if _ground_distance(animal, other) < radius:
			return true
	return false


func _ground_distance(a: Node3D, b: Node3D) -> float:
	var d := a.global_position - b.global_position
	return Vector2(d.x, d.z).length()
