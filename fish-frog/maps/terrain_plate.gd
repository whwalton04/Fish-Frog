@tool
extends Node3D
## Small, editable blockout plates for the opening ocean and beach regions.

@export_enum("Ocean", "Beach") var map_style: String = "Ocean":
	set(value):
		map_style = value
		if is_inside_tree():
			_build_map()

var _materials: Dictionary = {}
var _generated: Node3D


func _ready() -> void:
	_build_map()


func _build_map() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		remove_child(child)
		child.free()
	_materials.clear()
	_generated = Node3D.new()
	_generated.name = "Terrain and landmarks"
	add_child(_generated)
	_generated.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
	if map_style == "Beach":
		_build_beach()
	else:
		_build_ocean()


func _mat(key: String, hex_color: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.resource_name = key
	material.albedo_color = Color(hex_color)
	material.roughness = 0.92
	_materials[key] = material
	return material


func _box(label: String, position: Vector3, size: Vector3, material: Material,
		collidable: bool = true, rotation: float = 0.0) -> Node3D:
	var holder: Node3D
	if collidable:
		var body := StaticBody3D.new()
		body.name = label
		_generated.add_child(body)
		body.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position = position
		collision.rotation.y = rotation
		body.add_child(collision)
		collision.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
		holder = body
	else:
		holder = Node3D.new()
		holder.name = label
		_generated.add_child(holder)
		holder.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
	var visual := MeshInstance3D.new()
	visual.name = "Low poly block"
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	visual.position = position
	visual.rotation.y = rotation
	holder.add_child(visual)
	visual.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
	return holder


func _rock(label: String, position: Vector3, scale: Vector3, material: Material,
		collidable: bool = true) -> Node3D:
	var holder: Node3D
	if collidable:
		var body := StaticBody3D.new()
		body.name = label
		body.position = position
		_generated.add_child(body)
		body.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		collision.shape = shape
		collision.scale = scale
		body.add_child(collision)
		collision.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
		holder = body
	else:
		holder = Node3D.new()
		holder.name = label
		holder.position = position
		_generated.add_child(holder)
		holder.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
	var visual := MeshInstance3D.new()
	visual.name = "Faceted rock"
	var mesh := SphereMesh.new()
	mesh.radial_segments = 7
	mesh.rings = 3
	visual.mesh = mesh
	visual.scale = scale
	visual.material_override = material
	holder.add_child(visual)
	visual.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
	return holder


func _column(label: String, position: Vector3, height: float, radius: float,
		material: Material) -> void:
	var column := _box(label, position, Vector3(radius * 1.2, height, radius * 1.2), material, false)
	var cap := _rock(label + " cap", position + Vector3(0.0, height * 0.48, 0.0),
		Vector3(radius * 0.8, radius * 0.5, radius * 0.8), material, false)
	column.add_child(cap)
	cap.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null


func _build_ocean() -> void:
	name = "Ocean | debris nursery blockout"
	set_meta("region", "Ocean")
	set_meta("design_anchor", "A sheltered nursery and a debris stream with room to contain debris while keeping a clear passage.")
	var deep := _mat("Deep water edge", "416f80")
	var seabed := _mat("Sandstone seabed", "b2b09a")
	var reef := _mat("Reef stone", "718c82")
	var coral := _mat("Muted coral placeholder", "d19a80")
	var current := _mat("Current marker", "82bdc0")
	var debris := _mat("Debris placeholder", "575e5a")
	_box("Ocean plate | lower water rim", Vector3(0, -0.48, 0), Vector3(98, 0.9, 78), deep)
	_box("Seabed | broad walkable floor", Vector3(0, -0.02, 0), Vector3(91, 0.12, 71), seabed)

	# Stepped shelves provide a shallow horizon and frame a large navigable basin.
	_box("North reef shelf", Vector3(0, 0.42, 31.0), Vector3(76, 0.8, 6.0), reef)
	_box("West reef shelf", Vector3(-41.0, 0.32, 1.0), Vector3(7.0, 0.6, 48.0), reef)
	_box("East reef shelf", Vector3(41.0, 0.32, 2.0), Vector3(7.0, 0.6, 45.0), reef)

	# The nursery is a readable low ring, open on its eastern side.
	var nursery_center := Vector3(-25.0, 0.0, 13.0)
	for i in range(9):
		var angle := TAU * float(i + 2) / 12.0
		var point := nursery_center + Vector3(cos(angle) * 9.0, 0.55, sin(angle) * 7.0)
		_rock("Nursery reef | %02d" % i, point, Vector3(2.6, 1.0, 2.4), reef)
	for i in range(6):
		var x := -29.0 + float(i % 3) * 4.2
		var z := 9.0 + floor(float(i) / 3.0) * 4.0
		_column("Nursery coral placeholder | %02d" % i,
			Vector3(x, 1.4 + float(i % 2) * 0.25, z), 2.7 + float(i % 3) * 0.5,
			0.85, coral)
	_box("Nursery | clear approach gap", Vector3(-14.8, 0.18, 13.0), Vector3(7.0, 0.16, 1.0), current, false)

	# Pale segmented strips suggest flow from the southern inlet toward the nursery.
	var flow_points: Array[Vector3] = [
		Vector3(27.0, 0.10, -29.0), Vector3(23.0, 0.10, -22.0),
		Vector3(18.0, 0.10, -14.0), Vector3(12.0, 0.10, -7.0),
		Vector3(6.0, 0.10, 0.0), Vector3(-1.0, 0.10, 5.0),
		Vector3(-8.0, 0.10, 10.0),
	]
	for i in range(flow_points.size() - 1):
		var delta := flow_points[i + 1] - flow_points[i]
		_box("Current path marker | %02d" % i,
			(flow_points[i] + flow_points[i + 1]) * 0.5,
			Vector3(1.25, 0.035, delta.length()), current, false, atan2(delta.x, delta.z))

	# A pair of partial boulder rows leaves visible gaps for water and wildlife.
	for row in range(2):
		for i in range(5):
			if i == 2:
				continue
			var x := 14.0 + float(i) * 5.0
			var z := 10.0 + float(row) * 4.8
			_rock("Outlet boulder row %d | %02d" % [row + 1, i],
				Vector3(x, 0.7, z), Vector3(2.5, 1.2, 2.1), reef)
	for i in range(5):
		var x := 22.0 + float(i) * 3.0
		var z := -12.0 - float(i % 2) * 3.0
		_box("Loose debris placeholder | %02d" % i,
			Vector3(x, 0.42, z), Vector3(1.4, 0.7, 0.9), debris, true,
			float(i) * 0.31)
	# A wide uncluttered center leaves space for swimming and later level props.
	_box("Ocean map | center swim lane", Vector3(0.0, 0.07, -7.0),
		Vector3(13.0, 0.04, 12.0), current, false)


func _build_beach() -> void:
	name = "Beach | driftwood crossing blockout"
	set_meta("region", "Beach")
	set_meta("design_anchor", "A coastal inlet, tide pools, and a useful driftwood crossing that also narrows the land route.")
	var ocean := _mat("Coastal water", "548ca0")
	var shallows := _mat("Shallow tidal water", "79aeb0")
	var sand := _mat("Dry sand", "d7c39b")
	var wet_sand := _mat("Wet sand", "bba887")
	var dune := _mat("Raised dune", "c9b18a")
	var stone := _mat("Coastal stone", "807e70")
	var driftwood := _mat("Driftwood placeholder", "867762")
	var grass := _mat("Sparse dune grass", "8d9b78")
	_box("Beach plate | lower water rim", Vector3(0.0, -0.48, 0.0),
		Vector3(98.0, 0.9, 78.0), ocean)
	_box("Open sand | central walkable floor", Vector3(0.0, -0.015, 10.0),
		Vector3(91.0, 0.13, 53.0), sand)
	_box("Northern dune step", Vector3(0.0, 0.35, 35.0), Vector3(86.0, 0.8, 4.0), dune)
	_box("West beach headland", Vector3(-43.0, 0.42, 12.0), Vector3(5.0, 0.9, 42.0), dune)
	_box("East beach headland", Vector3(43.0, 0.34, 11.0), Vector3(5.0, 0.75, 38.0), dune)

	# Shoreline and the shallow inlet make the land / water boundary easy to read.
	_box("Shoreline | wet sand band", Vector3(0.0, 0.075, -17.2),
		Vector3(90.0, 0.05, 2.5), wet_sand, false)
	_box("Coastline | water shelf", Vector3(0.0, 0.04, -27.0),
		Vector3(94.0, 0.08, 19.0), shallows, false)
	_box("Inlet | lower reach", Vector3(-3.0, 0.09, -15.0),
		Vector3(10.0, 0.07, 14.0), shallows, false, -0.16)
	_box("Inlet | upper reach", Vector3(1.5, 0.09, -4.0),
		Vector3(8.0, 0.07, 12.0), shallows, false, 0.23)
	_box("Inlet | quiet pool", Vector3(-2.0, 0.09, 5.0),
		Vector3(13.0, 0.07, 8.0), shallows, false, -0.08)

	# A stout trunk bridges the inlet. Its squared low-poly form is a placeholder
	# landmark, with beach on both sides to keep the plate useful for prototyping.
	_box("Driftwood | main crossing", Vector3(-1.0, 0.54, -7.2),
		Vector3(16.0, 0.72, 2.4), driftwood, true, 0.14)
	_box("Driftwood | fork", Vector3(6.2, 0.50, -6.6),
		Vector3(5.8, 0.55, 1.7), driftwood, true, -0.42)
	_box("Driftwood | spare section", Vector3(18.0, 0.45, -2.8),
		Vector3(9.5, 0.55, 1.7), driftwood, true, -0.22)

	# Tide pools and scattered low-poly rocks give the shoreline landmarks.
	for i in range(3):
		var x := -28.0 + float(i) * 13.0
		var z := -13.0 - float(i % 2) * 1.8
		_box("Tide pool | %02d" % i, Vector3(x, 0.105, z),
			Vector3(7.0 + float(i % 2) * 2.0, 0.04, 3.0), shallows, false,
			float(i - 1) * 0.16)
	for i in range(12):
		var x := -37.0 + float((i * 17) % 72)
		var z := -10.0 + float((i * 11) % 30)
		var scale := Vector3(1.0 + float(i % 3) * 0.4, 0.55, 0.8 + float(i % 2) * 0.35)
		_rock("Beach stone | %02d" % i, Vector3(x, 0.53, z), scale, stone)
	for i in range(8):
		var x := -33.0 + float((i * 19) % 66)
		var z := 25.0 + float(i % 3) * 2.5
		_column("Dune grass placeholder | %02d" % i,
			Vector3(x, 0.85, z), 1.1 + float(i % 2) * 0.4, 0.35, grass)
