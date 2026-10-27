class_name Footprints
extends Node3D
## Leaves small dimples in the sand where a crab's feet come down, which
## fade away over time. Each is shaded as a bowl with a raised lip, lit from
## `sun`, so it reads as a dent rather than a stain.
##
## Listens to every ContactCrab's foot_down, including crabs added later, and
## keeps the prints in one MultiMesh as a ring buffer: once full, the oldest
## print is reused.

const FOOTPRINT_SHADER := preload("res://world/footprint.gdshader")
# Raised off the ground this much (× print size), so it doesn't z-fight.
const LIFT := 0.12

## The terrain to print on. Feet on anything else leave no print.
@export var terrain: Terrain3D
## Lights the prints' walls and lips. Without one, they're lit from above.
@export var sun: DirectionalLight3D
## Prints are only left where this terrain texture shows (0 = Sand).
@export_range(0, 31) var texture_id := 0
## Seconds a print takes to fade away.
@export_range(1.0, 300.0, 1.0, "or_greater") var lifetime := 12.0
## Most prints shown at once; the oldest is reused after this.
@export_range(16, 4096, 1) var max_prints := 2048
## Diameter of a print (m), for a crab of size 1.
@export_range(0.005, 0.2, 0.001) var print_size := 0.08
## How much a fresh print darkens the sand at its centre, 0..1.
@export_range(0.0, 1.0, 0.01) var darkness := 0.15
## How strongly the sun lights and shades the walls of a print.
@export_range(0.0, 2.0, 0.01) var shading := 0.3
## How high the sand is pushed up around a print, × its depth, so how much the
## lip catches the light.
@export_range(0.0, 1.0, 0.01) var lip := 0.1
## Chance a foot coming down leaves a print, so a trail isn't too busy.
@export_range(0.0, 1.0, 0.01) var print_chance := 0.4
## A foot coming down within this of its last print (× print size) leaves
## no new one, so a foot shuffling in place doesn't pile prints up.
@export_range(0.0, 2.0, 0.01) var min_spacing := 0.5

var _multimesh := MultiMesh.new()
var _material := ShaderMaterial.new()
var _next := 0
var _time := 0.0
# Crab instance id -> its legs' last print positions.
var _last_prints := {}


func _ready() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE
	_material.shader = FOOTPRINT_SHADER
	mesh.material = _material

	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_custom_data = true
	_multimesh.mesh = mesh
	_multimesh.instance_count = max_prints
	_multimesh.visible_instance_count = 0

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = _multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

	for node in get_tree().root.find_children("*", "ContactCrab", true, false):
		_watch(node)
	get_tree().node_added.connect(_watch)


func _process(delta: float) -> void:
	_time += delta
	_material.set_shader_parameter("now", _time)
	_material.set_shader_parameter("lifetime", lifetime)
	_material.set_shader_parameter("darkness", darkness)
	_material.set_shader_parameter("shading", shading)
	_material.set_shader_parameter("lip", lip)
	# A directional light shines along its -Z.
	_material.set_shader_parameter("light_dir", sun.global_basis.z.normalized() if sun else Vector3.UP)


func _watch(node: Node) -> void:
	if node is ContactCrab and not node.foot_down.is_connected(_on_foot_down):
		node.foot_down.connect(_on_foot_down.bind(node))


func _on_foot_down(leg: int, at: Vector3, normal: Vector3, collider: Object,
		crab: ContactCrab) -> void:
	if not terrain or collider != terrain or not _is_on_texture(at):
		return
	var diameter := print_size * crab.size
	var last: PackedVector3Array = _last_prints.get(crab.get_instance_id(), PackedVector3Array())
	if last.size() <= leg:
		last.resize(leg + 1)
		last.fill(Vector3.INF)
	if last[leg].distance_to(at) < diameter * min_spacing:
		return
	last[leg] = at
	_last_prints[crab.get_instance_id()] = last
	if randf() < print_chance:
		_add_print(at, normal, diameter)


func _is_on_texture(at: Vector3) -> bool:
	var tex: Vector3 = terrain.data.get_texture_id(at)
	if is_nan(tex.z):
		return false
	# Base below half blend, overlay above.
	return int(tex.y if tex.z >= 0.5 else tex.x) == texture_id


## Lays a round print flat on the ground.
func _add_print(at: Vector3, normal: Vector3, diameter: float) -> void:
	var tangent := normal.cross(Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD).normalized()
	var basis := Basis(tangent * diameter, normal, tangent.cross(normal) * diameter)
	var xform := global_transform.affine_inverse() * Transform3D(basis, at + normal * diameter * LIFT)

	_multimesh.set_instance_transform(_next, xform)
	_multimesh.set_instance_custom_data(_next, Color(_time, randf(), 0.0, 0.0))
	_next = (_next + 1) % max_prints
	_multimesh.visible_instance_count = maxi(_multimesh.visible_instance_count, _next if _next > 0 else max_prints)
