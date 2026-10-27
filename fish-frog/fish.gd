
extends Node3D

# Fish appearance
@export var body_color: Color = Color(0.1, 0.65, 0.8)
@export var fin_color: Color = Color(1.0, 0.55, 0.15)

# Swimming settings
@export var swim_speed: float = 1.0
@export var swim_radius: float = 3.0
@export var tail_speed: float = 8.0
@export var tail_strength: float = 0.55

var swim_time: float = 0.0
var tail_pivot: Node3D


func _ready() -> void:
	create_fish()


func _process(delta: float) -> void:
	# Advance the animation clock
	swim_time += delta * swim_speed

	# Move in a circular path
	var angle = swim_time * 0.5
	position = Vector3(
		cos(angle) * swim_radius,
		0.3 + sin(swim_time * 1.5) * 0.25,
		sin(angle) * swim_radius
	)

	# Face the direction of travel
	var direction = Vector3(
		-sin(angle),
		0.0,
		cos(angle)
	)
	look_at(position + direction, Vector3.UP)

	# Swing the tail from side to side
	if tail_pivot != null:
		tail_pivot.rotation.y = (
			sin(swim_time * tail_speed) * tail_strength
		)


func create_fish() -> void:
	# Materials
	var body_material = make_material(body_color)
	var fin_material = make_material(fin_color)
	var eye_material = make_material(Color.WHITE)
	var pupil_material = make_material(Color.BLACK)

	# Main body
	add_part(
		self, SphereMesh.new(), body_material,
		Vector3.ZERO, Vector3(0.65, 0.48, 1.0)
	)

	# Tail pivot: rotating this moves the tail
	tail_pivot = Node3D.new()
	tail_pivot.position = Vector3(0, 0, 0.8)
	add_child(tail_pivot)

	add_part(
		tail_pivot, SphereMesh.new(), fin_material,
		Vector3(0, 0, 0.4), Vector3(0.12, 0.48, 0.48)
	)

	# Top fin
	add_part(
		self, SphereMesh.new(), fin_material,
		Vector3(0, 0.42, 0.05),
		Vector3(0.20, 0.28, 0.40)
	)

	# Side fins
	add_part(
		self, SphereMesh.new(), fin_material,
		Vector3(-0.48, -0.12, 0.0),
		Vector3(0.12, 0.08, 0.35)
	)

	add_part(
		self, SphereMesh.new(), fin_material,
		Vector3(0.48, -0.12, 0.0),
		Vector3(0.12, 0.08, 0.35)
	)

	# Eyes on both sides
	for side in [-1.0, 1.0]:
		add_part(
			self, SphereMesh.new(), eye_material,
			Vector3(side * 0.48, 0.12, -0.53),
			Vector3(0.13, 0.13, 0.10)
		)

		add_part(
			self, SphereMesh.new(), pupil_material,
			Vector3(side * 0.55, 0.12, -0.59),
			Vector3(0.06, 0.07, 0.045)
		)


func make_material(color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	return material


func add_part(
	parent: Node3D,
	mesh: Mesh,
	material: Material,
	part_position: Vector3,
	part_scale: Vector3
) -> MeshInstance3D:
	var part = MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = part_position
	part.scale = part_scale
	parent.add_child(part)
	return part
