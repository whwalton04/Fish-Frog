extends Node3D
## Physics-based carry for the bird. Mark eligible RigidBody3D nodes
## with the "grabbable" group; they remain collidable with the world.

@export_range(0.1, 5.0, 0.1) var grab_radius: float = 1.5
@export var grip_offset := Vector3(0.0, -0.7, -1.0)
@export_range(0.1, 100.0, 0.1) var maximum_mass: float = 5.0
@export_range(0.5, 10.0, 0.1) var release_distance: float = 3.0
@export var show_grab_hint: bool = true

@onready var bird: RigidBody3D = get_parent() as RigidBody3D
@onready var visuals: Node3D = bird.get_node_or_null("Visuals")

var held_body: RigidBody3D
var _anchor: AnimatableBody3D
var _joint: PinJoint3D
var _previous_rotation_lock := false
var _half_size := Vector3.ONE * .3
var _grab_requested := false
var _added_bird_exception := false
var _added_object_exception := false
var _hint := Label.new()
var _query_shape := SphereShape3D.new()


func _ready() -> void:
	_anchor = AnimatableBody3D.new()
	_anchor.name = "CarryAnchor"
	_anchor.collision_layer = 0
	_anchor.collision_mask = 0
	_anchor.sync_to_physics = false
	add_child(_anchor)
	_anchor.top_level = true
	var hud := CanvasLayer.new()
	hud.name = "GrabHint"
	add_child(hud)
	hud.add_child(_hint)
	_hint.position = Vector2(16, 44)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event.is_action_pressed("grab") and not event.is_echo():
		# Space queries run in the physics tick rather than the input callback.
		_grab_requested = true
		get_viewport().set_input_as_handled()


func get_grip_position() -> Vector3:
	var grip_basis := visuals.global_basis.orthonormalized() if visuals else bird.global_basis.orthonormalized()
	return bird.global_position + grip_basis * grip_offset


func find_grab_target() -> RigidBody3D:
	_query_shape.radius = grab_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _query_shape
	query.transform = Transform3D(Basis.IDENTITY, get_grip_position())
	query.collision_mask = bird.collision_mask
	query.exclude = [bird.get_rid()]
	var nearest: RigidBody3D
	var nearest_distance := INF
	var space := get_world_3d().direct_space_state
	for hit in space.intersect_shape(query, 64):
		var body := hit.collider as RigidBody3D
		if body == null or body.is_queued_for_deletion() or body.freeze or not body.is_in_group("grabbable") or body.mass > maximum_mass:
			continue
		var distance := get_grip_position().distance_squared_to(body.global_position)
		if distance > grab_radius * grab_radius or distance >= nearest_distance:
			continue
		var ray := PhysicsRayQueryParameters3D.create(bird.global_position, body.global_position, bird.collision_mask, [bird.get_rid(), body.get_rid()])
		ray.hit_from_inside = true
		if not space.intersect_ray(ray).is_empty():
			continue
		nearest = body
		nearest_distance = distance
	return nearest


func try_grab() -> bool:
	if not bird.get("is_hovering") or is_instance_valid(held_body):
		return false
	held_body = find_grab_target()
	if held_body == null:
		return false
	_added_bird_exception = not bird.get_collision_exceptions().has(held_body)
	_added_object_exception = not held_body.get_collision_exceptions().has(bird)
	if _added_bird_exception:
		bird.add_collision_exception_with(held_body)
	if _added_object_exception:
		held_body.add_collision_exception_with(bird)
	# Remove exceptions while its physics RID is still alive, including deletion.
	held_body.tree_exiting.connect(release, CONNECT_ONE_SHOT)
	_previous_rotation_lock = held_body.lock_rotation
	held_body.lock_rotation = true
	_half_size = Vector3.ONE * .3
	for child in held_body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			_half_size = child.shape.size * child.global_basis.get_scale().abs() * .5
			break
	_anchor.global_position = _carry_position()
	var destination := _anchor.global_position - held_body.global_basis.y.normalized() * _half_size.y
	var motion := PhysicsTestMotionParameters3D.new()
	motion.from = held_body.global_transform
	motion.motion = destination - held_body.global_position
	motion.exclude_bodies = [bird.get_rid()]
	if PhysicsServer3D.body_test_motion(held_body.get_rid(), motion):
		release()
		return false
	held_body.global_position = destination
	held_body.linear_velocity = bird.linear_velocity
	held_body.angular_velocity = Vector3.ZERO
	held_body.sleeping = false
	_joint = PinJoint3D.new()
	_joint.name = "CarryJoint"
	_anchor.add_child(_joint)
	_joint.node_a = _joint.get_path_to(_anchor)
	_joint.node_b = _joint.get_path_to(held_body)
	return true


func _carry_position() -> Vector3:
	var grip_basis := visuals.global_basis.orthonormalized() if visuals else bird.global_basis.orthonormalized()
	var grounded := bool(bird.get("is_grounded"))
	var offset := Vector3(0, -.3, -.35) if grounded else Vector3(0, -.7, .1)
	var point := bird.global_position + grip_basis * offset
	if grounded:
		var ray := PhysicsRayQueryParameters3D.create(bird.global_position,
			bird.global_position + Vector3.DOWN * 2.0, bird.collision_mask, [bird.get_rid(), held_body.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			point.y = maxf(point.y, hit.position.y + _half_size.y * 2.0 + .06)
	return point


func get_foot_grip_position(side: String) -> Vector3:
	if not is_instance_valid(held_body):
		return get_grip_position()
	var up := held_body.global_basis.y.normalized()
	var across := held_body.global_basis.x.normalized()
	return held_body.global_position + up * (_half_size.y + .0488125) + across * minf(.15, _half_size.x * .5) * (-1.0 if side == "L" else 1.0)


func release() -> void:
	if is_instance_valid(_joint):
		_joint.node_a = NodePath()
		_joint.node_b = NodePath()
		_joint.free()
	_joint = null
	if is_instance_valid(held_body):
		held_body.lock_rotation = _previous_rotation_lock
		if held_body.tree_exiting.is_connected(release):
			held_body.tree_exiting.disconnect(release)
		if _added_bird_exception:
			bird.remove_collision_exception_with(held_body)
		if _added_object_exception:
			held_body.remove_collision_exception_with(bird)
	held_body = null
	_added_bird_exception = false
	_added_object_exception = false


func _physics_process(_delta: float) -> void:
	if _grab_requested:
		_grab_requested = false
		if is_instance_valid(held_body):
			release()
		else:
			try_grab()
	if is_instance_valid(held_body):
		_anchor.global_position = _carry_position()
		if held_body.is_queued_for_deletion() or _anchor.global_position.distance_to(held_body.global_position) > release_distance:
			release()
	else:
		held_body = null
	_hint.visible = show_grab_hint and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _hint.visible:
		_hint.text = "E: Release" if held_body else "E: Grab" if bird.get("is_hovering") and find_grab_target() else ""


func _exit_tree() -> void:
	release()
