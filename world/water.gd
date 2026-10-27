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

## The terrain the foam rings. Its shoreline is baked when the water is
## ready, and again whenever the terrain is sculpted.
@export var terrain: Terrain3D:
	set(value):
		terrain = value
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
const BAKE_DELAY := 0.5  # s after the terrain's last edit to rebake the shore
const FAR := 1e20  # squared distance standing for no shore at all
const TERRAIN_SIGNALS: Array[StringName] = [&"maps_edited", &"height_maps_changed", &"region_map_changed"]

var _time := 0.0
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _area: Area3D
var _shape: BoxShape3D
var _bounds := {}  # body -> its collision shapes' local AABB
var _built := []  # the settings the mesh and area were last built for
var _baked := []  # the settings the shore was last baked for
var _bake_due := -1.0  # _time to rebake the shore at, or -1
var _watched: Terrain3DData  # the terrain data whose edits rebake the shore
var _bake_task := -1  # WorkerThreadPool task of the shore bake underway, or -1
var _bake_result := []  # the bake's image and shore_rect, once it's done


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


func _exit_tree() -> void:
	if _bake_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_bake_task)
		_bake_task = -1
		_bake_result.clear()


## Bakes, for every point over terrain, how far it is across the surface to
## the waterline (m; negative on land), once with the sea at its lowest and
## once at its highest, for the shader to ring the shore with foam. The
## distances are worked out on a worker thread and handed over when done.
func bake_shore() -> void:
	if not _material:
		return
	if _bake_task >= 0:
		_bake_due = _time  # once the bake underway finishes
		return
	_bake_due = -1.0
	_baked = _bake_key()
	_watch_terrain()
	if not terrain or not terrain.data or terrain.data.get_region_locations().is_empty():
		_material.set_shader_parameter("shore_distance", null)
		_material.set_shader_parameter("shore_rect", Vector4.ZERO)
		return
	var spacing := terrain.vertex_spacing
	var size := terrain.region_size
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := -lo
	for loc: Vector2i in terrain.data.get_region_locations():
		lo = lo.min(loc)
		hi = hi.max(loc + Vector2i.ONE)
	var cells := (hi - lo) * size
	# Gaps between regions are deep sea.
	var heights := PackedFloat64Array()
	heights.resize(cells.x * cells.y)
	heights.fill(-1e4)
	for loc: Vector2i in terrain.data.get_region_locations():
		var map: Image = terrain.data.get_region(loc).get_height_map()
		if not map:
			continue
		if map.get_format() != Image.FORMAT_RF:
			map = map.duplicate()
			map.convert(Image.FORMAT_RF)
		var src := map.get_data().to_float32_array()
		var width := map.get_width()
		var corner := (loc - lo) * size
		for row in mini(size, map.get_height()):
			var base := (corner.y + row) * cells.x + corner.x
			for col in mini(size, width):
				var h := src[row * width + col]
				if not is_nan(h):
					heights[base + col] = h
	var low_level := global_position.y - amplitude
	var high_level := global_position.y + amplitude
	# Pixels sit on the terrain's vertices, so the rect starts half a cell out.
	var origin := (Vector2(lo * size) - Vector2(0.5, 0.5)) * spacing
	var extent_m := Vector2(cells) * spacing
	var rect := Vector4(origin.x, origin.y, extent_m.x, extent_m.y)
	var result := _bake_result
	result.clear()
	_bake_task = WorkerThreadPool.add_task(func():
		var low := _shore_distance(heights, cells, spacing, low_level)
		var high := _shore_distance(heights, cells, spacing, high_level)
		var texels := PackedFloat32Array()
		texels.resize(cells.x * cells.y * 2)
		for i in cells.x * cells.y:
			texels[i * 2] = low[i]
			texels[i * 2 + 1] = high[i]
		result.append(Image.create_from_data(cells.x, cells.y, false, Image.FORMAT_RGF, texels.to_byte_array()))
		result.append(rect))


## Hands a finished bake to the shader.
func _finish_bake() -> void:
	if _bake_task < 0 or not WorkerThreadPool.is_task_completed(_bake_task):
		return
	WorkerThreadPool.wait_for_task_completion(_bake_task)
	_bake_task = -1
	if _bake_result.size() == 2:
		_material.set_shader_parameter("shore_distance", ImageTexture.create_from_image(_bake_result[0]))
		_material.set_shader_parameter("shore_rect", _bake_result[1])
	_bake_result.clear()


## Signed distance from each cell to where heights cross level (m), positive
## out to sea. Cells either side of the crossing are seeds, each knowing the
## nearest point of the line to it; an exact Euclidean distance transform
## finds every cell's nearest seed, and the distance is to that seed's point.
static func _shore_distance(heights: PackedFloat64Array, cells: Vector2i, spacing: float, level: float) -> PackedFloat64Array:
	var w := cells.x
	var h := cells.y
	var field := PackedFloat64Array()
	field.resize(w * h)
	field.fill(FAR)
	var nearest := PackedInt32Array()
	nearest.resize(w * h)
	nearest.fill(-1)
	var point := PackedVector2Array()  # each seed's nearest point of the line
	point.resize(w * h)
	var above := PackedByteArray()
	above.resize(w * h)
	for i in w * h:
		above[i] = 1 if heights[i] > level else 0
	for row in h:
		for col in w:
			var i := row * w + col
			var side := above[i]
			# Where the waterline crosses the edges to each neighbour on the
			# other side, as the terrain's mesh runs straight between them;
			# the nearest crossing along x and along z put the line itself.
			var tx := INF
			var tz := INF
			var sx := 0.0
			var sz := 0.0
			if col > 0 and above[i - 1] != side:
				tx = _crossing(heights[i], heights[i - 1], level)
				sx = -1.0
			if col < w - 1 and above[i + 1] != side:
				var t := _crossing(heights[i], heights[i + 1], level)
				if t < tx:
					tx = t
					sx = 1.0
			if row > 0 and above[i - w] != side:
				tz = _crossing(heights[i], heights[i - w], level)
				sz = -1.0
			if row < h - 1 and above[i + w] != side:
				var t := _crossing(heights[i], heights[i + w], level)
				if t < tz:
					tz = t
					sz = 1.0
			if sx == 0.0 and sz == 0.0:
				continue
			# Foot of the perpendicular onto the line through both crossings.
			var ix := sx / tx
			var iz := sz / tz
			var foot := Vector2(ix, iz) / (ix * ix + iz * iz)
			field[i] = 0.0
			nearest[i] = i
			point[i] = Vector2(col, row) + foot
	_distance_transform(field, nearest, w, h)
	var out := PackedFloat64Array()
	out.resize(w * h)
	for i in w * h:
		var d := 1e4
		if nearest[i] >= 0:
			d = Vector2(i % w, i / w).distance_to(point[nearest[i]]) * spacing
		out[i] = -d if heights[i] > level else d
	return out


## How far from a, toward its neighbour b, heights cross level (cells).
static func _crossing(a: float, b: float, level: float) -> float:
	return clampf((a - level) / (a - b), 1e-4, 1.0)


## In place, each cell's squared distance (in cells) to the nearest seed
## (cells holding 0; the rest hold FAR), and in nearest that seed's index.
## Felzenszwalb & Huttenlocher, rows then columns.
static func _distance_transform(field: PackedFloat64Array, nearest: PackedInt32Array, w: int, h: int) -> void:
	var n := maxi(w, h)
	var line := PackedFloat64Array()
	line.resize(n)
	var line_nearest := PackedInt32Array()
	line_nearest.resize(n)
	var v := PackedInt32Array()
	v.resize(n)
	var z := PackedFloat64Array()
	z.resize(n + 1)
	for row in h:
		_transform_line(field, nearest, row * w, 1, w, line, line_nearest, v, z)
	for col in w:
		_transform_line(field, nearest, col, w, h, line, line_nearest, v, z)


static func _transform_line(field: PackedFloat64Array, nearest: PackedInt32Array, start: int, stride: int, n: int,
		line: PackedFloat64Array, line_nearest: PackedInt32Array, v: PackedInt32Array, z: PackedFloat64Array) -> void:
	for q in n:
		line[q] = field[start + q * stride]
		line_nearest[q] = nearest[start + q * stride]
	var k := 0
	v[0] = 0
	z[0] = -INF
	z[1] = INF
	for q in range(1, n):
		var fq := line[q] + q * q
		var s := (fq - line[v[k]] - v[k] * v[k]) / (2.0 * (q - v[k]))
		while s <= z[k]:
			k -= 1
			s = (fq - line[v[k]] - v[k] * v[k]) / (2.0 * (q - v[k]))
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = INF
	k = 0
	for q in n:
		while z[k + 1] < q:
			k += 1
		field[start + q * stride] = minf((q - v[k]) * (q - v[k]) + line[v[k]], FAR)
		nearest[start + q * stride] = line_nearest[v[k]]


func _bake_key() -> Array:
	return [global_position.y, amplitude, terrain]


## Rebakes the shore a moment after terrain's heights stop changing.
func _watch_terrain() -> void:
	var data: Terrain3DData = terrain.data if terrain else null
	if data == _watched:
		return
	if is_instance_valid(_watched):
		for sig: StringName in TERRAIN_SIGNALS:
			if _watched.is_connected(sig, _queue_bake):
				_watched.disconnect(sig, _queue_bake)
	_watched = data
	if data:
		for sig: StringName in TERRAIN_SIGNALS:
			if not data.is_connected(sig, _queue_bake):
				data.connect(sig, _queue_bake)


func _queue_bake(_arg: Variant = null) -> void:
	_bake_due = _time + BAKE_DELAY


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
	_finish_bake()
	if _bake_due >= 0.0 and _time >= _bake_due or _baked != _bake_key():
		bake_shore()
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
	_material.set_shader_parameter("rest_height", global_position.y)


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
