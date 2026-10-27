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
@export_range(0.1, 30.0, 0.1, "or_greater") var period := 6.0
## Distance between wave crests (m). 0 makes the whole sea rise and fall
## together; otherwise the waves roll across it.
@export_range(0.0, 200.0, 0.5, "or_greater") var wavelength := 0.0
## Compass heading the waves roll toward (degrees, 0 = +X).
@export_range(-180.0, 180.0, 1.0) var direction_deg := 0.0

## The terrain the foam rings. Its heights are baked when the water is
## ready; rebake after sculpting it.
@export var terrain: Terrain3D:
	set(value):
		terrain = value
		if is_node_ready():
			bake_shore.call_deferred()
@export_tool_button("Rebake shore") var _rebake_shore := bake_shore

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
## Colour where the water is shallow; its alpha sets how see-through it is.
@export var shallow_color := Color(0.4, 0.95, 0.78, 0.55)
## Colour where the water is deep, including the open sea.
@export var deep_color := Color(0.12, 0.48, 0.39, 1.0)
## Depth at which the water turns fully deep_color (m).
@export_range(0.1, 50.0, 0.1, "or_greater") var deep_depth := 10.0
## Pale colour the sea fades to where it's seen at a low angle, toward the
## horizon.
@export var horizon_color := Color(0.66, 0.7, 0.6, 1.0)
## How tightly the horizon colour hugs the horizon; higher keeps more of the
## sea deep-coloured.
@export_range(0.5, 10.0, 0.1) var horizon_falloff := 6.0
## Colour of the foam where the water meets the shore; its alpha sets how
## thick the foam looks.
@export var foam_color := Color(0.95, 0.97, 1.0, 0.9)
## How far out from the waterline the foam reaches (m).
@export_range(0.0, 10.0, 0.01, "or_greater") var foam_width := 0.8
## How ragged the foam's edge is, 0 for a clean band.
@export_range(0.0, 2.0, 0.01) var foam_breakup := 0.6
## Size of the foam's blotches (m).
@export_range(0.1, 20.0, 0.1) var foam_scale := 1.5
## Width of the sea (m). It follows the camera, so this only needs to reach
## the horizon.
@export_range(100.0, 10000.0, 10.0) var extent := 4000.0
## Width of one mesh cell near the camera (m). Smaller rolls short waves
## more smoothly.
@export_range(0.5, 50.0, 0.5) var cell_size := 2.0
## How far from the camera the cells stay cell_size (m); beyond it they grow,
## as the waves there are too far off to need the detail.
@export_range(0.0, 1000.0, 1.0) var detail_radius := 64.0

const DEPTH := 200.0  # how far below the surface bodies are still floated
const CELL_GROWTH := 1.2  # each cell past detail_radius is this much wider

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
	bake_shore.call_deferred()


## Bakes terrain's heights into a texture the water shader samples straight
## down from each point, to find the shore for the foam.
func bake_shore() -> void:
	if not _material:
		return
	if not terrain or not terrain.data or terrain.data.get_region_locations().is_empty():
		_material.set_shader_parameter("shore_heights", null)
		_material.set_shader_parameter("shore_rect", Vector4.ZERO)
		return
	var spacing := terrain.vertex_spacing
	var region := terrain.region_size * spacing
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := -lo
	for loc: Vector2i in terrain.data.get_region_locations():
		lo = lo.min(loc)
		hi = hi.max(loc + Vector2i.ONE)
	var origin := Vector2(lo) * region
	var size := Vector2(hi - lo) * region
	var cells := Vector2i((size / spacing).round())
	var image := Image.create_empty(cells.x, cells.y, false, Image.FORMAT_RF)
	for row in cells.y:
		for col in cells.x:
			var at := origin + (Vector2(col, row) + Vector2(0.5, 0.5)) * spacing
			var h := terrain.data.get_height(Vector3(at.x, 0.0, at.y))
			image.set_pixel(col, row, Color(-1e4 if is_nan(h) else h, 0.0, 0.0))
	_material.set_shader_parameter("shore_heights", ImageTexture.create_from_image(image))
	_material.set_shader_parameter("shore_rect", Vector4(origin.x, origin.y, size.x, size.y))


func _build_key() -> Array:
	return [extent, cell_size, detail_radius, amplitude, body_mask]


func _rebuild() -> void:
	_built = _build_key()
	_mesh.mesh = _grid_mesh()
	_mesh.extra_cull_margin = amplitude
	_shape.size = Vector3(extent, DEPTH + amplitude + 1.0, extent)
	_area.position.y = (amplitude + 1.0 - DEPTH) * 0.5
	_area.collision_mask = body_mask


## A square grid the width of extent, with cell_size cells out to
## detail_radius and wider ones beyond.
func _grid_mesh() -> ArrayMesh:
	var half := extent * 0.5
	var side := PackedFloat32Array([0.0])
	var x := 0.0
	var step := cell_size
	while x < half:
		if x >= detail_radius:
			step *= CELL_GROWTH
		x = minf(x + step, half)
		side.append(x)
	var axis := PackedFloat32Array()
	for k in range(side.size() - 1, 0, -1):
		axis.append(-side[k])
	axis.append_array(side)

	var n := axis.size()
	var verts := PackedVector3Array()
	verts.resize(n * n)
	for row in n:
		for col in n:
			verts[row * n + col] = Vector3(axis[col], 0.0, axis[row])
	var normals := PackedVector3Array()
	normals.resize(n * n)
	normals.fill(Vector3.UP)
	var indices := PackedInt32Array()
	for row in n - 1:
		for col in n - 1:
			var a := row * n + col
			indices.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
	_material.set_shader_parameter("shallow_color", shallow_color)
	_material.set_shader_parameter("deep_color", deep_color)
	_material.set_shader_parameter("deep_depth", deep_depth)
	_material.set_shader_parameter("horizon_color", horizon_color)
	_material.set_shader_parameter("horizon_falloff", horizon_falloff)
	_material.set_shader_parameter("foam_color", foam_color)
	_material.set_shader_parameter("foam_width", maxf(foam_width, 0.001))
	_material.set_shader_parameter("foam_breakup", foam_breakup)
	_material.set_shader_parameter("foam_scale", foam_scale)
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
