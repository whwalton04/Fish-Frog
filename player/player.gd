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
## The right and left arrows take the next or previous animal to steer on its
## own while the rest wait; Q goes back to the group. The animals cycle in
## child order, with each stack together from the bottom up, so in a stack
## right goes up it and left down it, and going past its top or bottom moves
## on to the animals outside it. The group is whoever is near each other: an
## animal left far from the others is dropped off beside the player, and an
## animal in the `animals` group that comes near a member joins. Walking the
## controlled animal away from the others makes it the group instead: the
## others are dropped off, and it gathers a new group from whoever it meets.
##
## While steering one animal, the animal it's looking at (nearest the middle of
## the view, within its mount_range) is marked with an arrow, and the mount
## action (space) puts it on top. Animals mounted on others aren't steered, so
## a stack walks as one. One mounted with nothing to mount looked at marks the
## spot on the floor it's looking at instead, at least min_jump_radius away,
## and space jumps it down there.
##
## The ability action (shift) uses the controlled animal's ability, if
## it has one (see SpecialCrab).
##
## The rally action (U) takes the group apart from any stacks and drops its
## animals one by one, rally_interval apart, above the active Flag.

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
## How near and far a jump off a stack lands, across the ground from where
## it starts (m, × the animal's size).
@export var min_jump_radius := 0.6
@export var max_jump_radius := 2.0
## What the floor a jump lands on is made of.
@export_flags_3d_physics var floor_mask := 1
## Seconds between animals dropping onto the flag in a rally.
@export var rally_interval := 0.25
## How far above the top of the flag they drop from, and how far apart round
## its pole (m).
@export var rally_drop_height := 0.2
@export var rally_spread := 0.3

## Whether the player steers the animals. While off (another animal has
## control) they stand still and the input is left alone; turning it
## back on puts the view back on them.
var active := true:
	set(value):
		active = value
		if active and has_node("CameraRig"):
			$CameraRig.make_current()

## The animal steered on its own, or null when steering the group. It may have
## wandered out of the group and still be steered.
var controlled: Node3D = null
## What the controlled animal would mount, or null.
var looked_at: Node3D = null
## Where on the floor the controlled animal would jump down to, while mounted.
var jump_target := Vector3.ZERO
var has_jump_target := false

var _arrow: MeshInstance3D
# Animals still to drop in a rally, the flag, and seconds to the next drop.
var _rally_queue: Array[Node3D] = []
var _rally_flag: Flag
var _rally_clock := 0.0
var _rally_count := 0


func _ready() -> void:
	_arrow = _make_arrow()
	add_child(_arrow)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("ability"):
		if controlled and controlled.has_method("use_ability"):
			controlled.use_ability()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("mount"):
		if looked_at:
			controlled.mount_onto(looked_at)
		elif has_jump_target:
			controlled.jump_to(jump_target)
			has_jump_target = false
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("rally"):
		_start_rally()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("control_group"):
		_control(null)
	elif event.is_action_pressed("control_next"):
		_cycle(1)
	elif event.is_action_pressed("control_previous"):
		_cycle(-1)
	else:
		return
	get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	# Mid-rally the group is split between here and the flag, so it isn't
	# sorted into clusters, or steered, until everyone has arrived.
	if not _rally_queue.is_empty():
		_rally_step(delta)
		for animal in get_animals():
			animal.move_direction = Vector3.ZERO
		return
	if not active:
		has_jump_target = false
		for animal in get_animals():
			animal.move_direction = Vector3.ZERO
		return
	_update_membership()
	_update_jump_target()
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
		if animal.get("mount"):
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
	looked_at = _find_looked_at() if active else null
	_arrow.visible = looked_at != null or has_jump_target
	var bob := sin(Time.get_ticks_msec() * 0.006) * 0.015
	if looked_at:
		var size: float = looked_at.get("size") if "size" in looked_at else 1.0
		_arrow.global_position = looked_at.global_position + Vector3.UP * (0.12 + bob) * size
		_arrow.scale = Vector3.ONE * size
	elif has_jump_target:
		var size: float = controlled.get("size") if "size" in controlled else 1.0
		_arrow.global_position = jump_target + Vector3.UP * (0.02 + bob) * size
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


## Takes every animal in the group out of its stack, then queues them to drop
## onto the active flag, the first straight away.
func _start_rally() -> void:
	if not is_instance_valid(Flag.active) or not _rally_queue.is_empty():
		return
	_rally_flag = Flag.active
	_rally_queue = get_animals()
	_rally_clock = 0.0
	_rally_count = 0
	for animal in _rally_queue:
		if animal.has_method("leave_stack"):
			animal.leave_stack()


func _rally_step(delta: float) -> void:
	_rally_clock -= delta
	while _rally_clock <= 0.0 and not _rally_queue.is_empty():
		var animal: Node3D = _rally_queue.pop_front()
		if not is_instance_valid(animal) or not is_instance_valid(_rally_flag):
			continue
		# Spiralling out round the pole, so they don't land on one another.
		var out := Vector3.FORWARD.rotated(Vector3.UP, _rally_count * 2.4) \
				* rally_spread * sqrt(_rally_count)
		var at := _rally_flag.get_top() + out + Vector3.UP * rally_drop_height
		if animal.has_method("drop_at"):
			animal.drop_at(at)
		else:
			animal.global_position = at
		_rally_count += 1
		_rally_clock += rally_interval


## Where the view meets the floor, brought within min_jump_radius..
## max_jump_radius of the controlled animal across the ground, while it's
## mounted and has no animal to mount in view.
func _update_jump_target() -> void:
	has_jump_target = false
	if not controlled or not is_instance_valid(controlled) or not controlled.get("mount") \
			or not controlled.has_method("jump_to") or looked_at \
			or (controlled.has_method("can_walk") and not controlled.can_walk()):
		return
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var size: float = controlled.get("size") if "size" in controlled else 1.0
	var from := controlled.global_position
	var view := -cam.global_basis.z
	var flat_view := Vector3(view.x, 0.0, view.z)
	if flat_view.length_squared() < 1e-4:
		flat_view = Vector3(-cam.global_basis.y.x, 0.0, -cam.global_basis.y.z)
	var dir := flat_view.normalized()
	var space := get_world_3d().direct_space_state
	var distance := max_jump_radius * size
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			cam.global_position, cam.global_position + view * 100.0, floor_mask))
	if not hit.is_empty():
		var across: Vector3 = hit.position - from
		across.y = 0.0
		if across.dot(dir) > 0.0:
			distance = across.length()
	distance = clampf(distance, min_jump_radius * size, max_jump_radius * size)
	var spot := from + dir * distance
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			spot + Vector3.UP * 10.0, spot + Vector3.DOWN * 10.0, floor_mask))
	if down.is_empty():
		return
	jump_target = down.position
	has_jump_target = true


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


## Where the camera looks: the flag while the group drops onto it in a rally,
## otherwise the steered animals' centre.
func get_focus() -> Vector3:
	if not _rally_queue.is_empty() and is_instance_valid(_rally_flag):
		return _rally_flag.global_position
	return get_center()


## Average position of the steered animals.
func get_center() -> Vector3:
	var animals := get_steered()
	if animals.is_empty():
		return global_position
	var sum := Vector3.ZERO
	for animal in animals:
		sum += animal.global_position
	return sum / animals.size()


## Takes the animal `step` along from the controlled one in get_cycle(),
## wrapping round; from the group, the first or the last.
func _cycle(step: int) -> void:
	var order := get_cycle()
	if order.is_empty():
		return
	var at := order.find(controlled)
	if at < 0:
		at = -1 if step > 0 else order.size()
	_control(order[posmod(at + step, order.size())])


## The group's animals in the order the arrows go through them: child order,
## except each stack comes together, bottom to top, where its lowest member
## would.
func get_cycle() -> Array[Node3D]:
	var animals := get_animals()
	var order: Array[Node3D] = []
	for animal in animals:
		if animal in order:
			continue
		var stack: Array = animal.get_stacked() if animal.has_method("get_stacked") else [animal]
		for member in stack:
			if member in animals and member not in order:
				order.append(member)
	return order


func _control(animal: Node3D) -> void:
	if controlled and is_instance_valid(controlled) and controlled != animal:
		controlled.move_direction = Vector3.ZERO
	controlled = animal


## Keeps the controlled animal's cluster of members, or with none controlled
## the biggest, dropping off the rest, then takes in strays near it.
func _update_membership() -> void:
	var keep: Array[Node3D] = []
	for cluster in _clusters(get_animals()):
		if controlled in cluster:
			keep = cluster
			break
		if cluster.size() > keep.size():
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
