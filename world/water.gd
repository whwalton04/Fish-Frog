@tool
class_name Water
extends Node3D
## A sea out to the horizon whose surface rises and falls, and that floats any
## RigidBody3D in it.
##
## The surface rests at this node's height. Bodies are floated by sampling the
## corners of their collision shapes' bounding box: each corner under the
## surface pushes up at that corner, so a body bobs, tilts with the waves and
## settles upright on its broadest side.

## How far the surface rises and falls either side of rest (m).
@export_range(0.0, 5.0, 0.01, "or_greater") var amplitude := 0.3
## Seconds for one rise and fall.
@export_range(0.1, 30.0, 0.1, "or_greater") var period := 4.0
## Distance between wave crests (m). 0 makes the whole sea rise and fall
## together; otherwise the waves roll across it.
@export_range(0.0, 200.0, 0.5, "or_greater") var wavelength := 0.0
## Compass heading the waves roll toward (degrees, 0 = +X).
@export_range(-180.0, 180.0, 1.0) var direction_deg := 0.0

@export_group("Floating")
## Upward push on a body fully under, × its weight. Above 1 floats, and a
## body floats with about 1 / this of itself under.
@export_range(0.0, 10.0, 0.05) var buoyancy := 2.0
## Slows a body moving through the water, per second, scaled by how much of
## it is under.
@export_range(0.0, 20.0, 0.1) var linear_drag := 2.0
## Slows a body turning in the water, per second.
@export_range(0.0, 20.0, 0.1) var angular_drag := 2.0
## Physics layers of the bodies the water floats.
@export_flags_3d_physics var body_mask := 3

@export_group("Look")
@export var color := Color(0.3, 0.65, 0.95, 0.85)
## Width of the sea (m). It follows the camera, so this only needs to reach
## the horizon.
@export_range(100.0, 10000.0, 10.0) var extent := 4000.0
## Width of one mesh cell (m). Smaller rolls short waves more smoothly.
@export_range(0.5, 50.0, 0.5) var cell_size := 4.0

const DEPTH := 200.0  # how far below the surface bodies are still floated

var _time := 0.0
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _area: Area3D
var _shape: BoxShape3D
var _bounds := {}  # body -> its collision shapes' local AABB
var _built := []  # the settings the mesh and area were last built for


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://world/water.gdshader")
	_mesh = MeshInstance3D.new()
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.top_level = true
	add_child(_mesh)
	_shape = BoxShape3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = _shape
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.monitorable = false
	_area.add_child(collider)
	add_child(_area)
	_rebuild()


func _build_key() -> Array:
	return [extent, cell_size, amplitude, body_mask]


func _rebuild() -> void:
	_built = _build_key()
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent, extent)
	plane.subdivide_width = int(extent / cell_size) - 1
	plane.subdivide_depth = plane.subdivide_width
	_mesh.mesh = plane
	_shape.size = Vector3(extent, DEPTH + amplitude + 1.0, extent)
	_area.position.y = (amplitude + 1.0 - DEPTH) * 0.5
	_area.collision_mask = body_mask


## Height of the surface at a world position (its y is ignored).
func height_at(pos: Vector3) -> float:
	var along := 0.0
	if wavelength > 0.0:
		along = _direction().dot(Vector2(pos.x, pos.z)) / wavelength
	return global_position.y + amplitude * sin(TAU * (_time / period - along))


func _direction() -> Vector2:
	return Vector2.from_angle(deg_to_rad(direction_deg))


func _process(_delta: float) -> void:
	# Follow the camera across the sea, snapped to whole cells so the waves
	# don't swim over the vertices.
	var center := global_position
	var camera := get_viewport().get_camera_3d()
	if Engine.is_editor_hint():
		# Looked up by name, as EditorInterface doesn't exist in exported games.
		camera = Engine.get_singleton(&"EditorInterface").get_editor_viewport_3d().get_camera_3d()
	if camera:
		center.x = snappedf(camera.global_position.x, cell_size)
		center.z = snappedf(camera.global_position.z, cell_size)
	_mesh.global_position = center
	_material.set_shader_parameter("color", color)
	_material.set_shader_parameter("amplitude", amplitude)
	_material.set_shader_parameter("period", period)
	_material.set_shader_parameter("wavelength", wavelength)
	_material.set_shader_parameter("direction", _direction())
	_material.set_shader_parameter("wave_time", _time)


func _physics_process(delta: float) -> void:
	_time += delta
	if _built != _build_key():
		_rebuild()
	if Engine.is_editor_hint():
		return
	for body in _area.get_overlapping_bodies():
		if body is RigidBody3D and not body.freeze:
			_float(body)


func _float(body: RigidBody3D) -> void:
	var box: AABB = _bounds.get(body, AABB())
	if not _bounds.has(body):
		box = _local_bounds(body)
		_bounds[body] = box
		body.tree_exiting.connect(func(): _bounds.erase(body), CONNECT_ONE_SHOT)
	if not box.has_volume():
		return
	var xform := body.global_transform
	var height := (xform.basis * box.size).abs().y  # rough vertical extent
	var weight := body.mass * body.get_gravity().length()
	var under := 0.0
	for i in 8:
		var corner := xform * box.get_endpoint(i)
		var depth := height_at(corner) - corner.y
		var share := clampf(depth / height + 0.5, 0.0, 1.0)
		if share > 0.0:
			body.apply_force(Vector3.UP * buoyancy * weight * share / 8.0, corner - body.global_position)
			under += share / 8.0
	if under > 0.0:
		body.apply_central_force(-body.linear_velocity * linear_drag * body.mass * under)
		var radius_sq := box.size.length_squared() * 0.25
		body.apply_torque(-body.angular_velocity * angular_drag * body.mass * radius_sq * under)


func _local_bounds(body: RigidBody3D) -> AABB:
	var box := AABB()
	var first := true
	for owner_id in body.get_shape_owners():
		var shape_xform := body.shape_owner_get_transform(owner_id)
		for i in body.shape_owner_get_shape_count(owner_id):
			var shape_box: AABB = shape_xform * body.shape_owner_get_shape(owner_id, i).get_debug_mesh().get_aabb()
			box = shape_box if first else box.merge(shape_box)
			first = false
	return box
