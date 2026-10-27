class_name Flag
extends Node3D
## A pole with a triangular pennant. A crab coming near makes it the active
## flag, and the pennant turns the crabs' orange; only one flag is active at a
## time. The player's rally action drops the group onto the active flag.

## Of the whole flag, about twice a crab's (m).
@export_range(0.05, 3.0, 0.01) var height := 0.3
## How near a crab's centre must come to make this the active flag (m).
@export_range(0.05, 3.0, 0.01) var reach := 0.5
@export var idle_color := Color(0.92, 0.9, 0.84)
@export var active_color := Color(0.82, 0.32, 0.18)

## The active flag, or null.
static var active: Flag

var _pennant_mat: StandardMaterial3D


func _ready() -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.45, 0.36, 0.26)
	pole_mat.roughness = 0.8
	var pole := CylinderMesh.new()
	pole.top_radius = height * 0.02
	pole.bottom_radius = height * 0.02
	pole.height = height
	pole.radial_segments = 8
	pole.rings = 1
	pole.material = pole_mat
	_add_mesh(pole, Transform3D(Basis(), Vector3.UP * height * 0.5))

	# A prism's apex points up; turned on its side, it points out from the pole.
	_pennant_mat = StandardMaterial3D.new()
	_pennant_mat.roughness = 0.7
	var pennant := PrismMesh.new()
	pennant.size = Vector3(height * 0.3, height * 0.45, height * 0.03)
	pennant.material = _pennant_mat
	_add_mesh(pennant, Transform3D(Basis(Vector3.BACK, -PI * 0.5),
			Vector3(height * 0.225, height * 0.85, 0.0)))

	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = reach
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	_show_active()


func _exit_tree() -> void:
	if active == self:
		active = null


## The top of the pole.
func get_top() -> Vector3:
	return global_position + global_basis.y * height


func activate() -> void:
	var was := active
	active = self
	if is_instance_valid(was) and was != self:
		was._show_active()
	_show_active()


func _on_body_entered(body: Node3D) -> void:
	if body is ContactCrab and active != self:
		activate()


func _show_active() -> void:
	_pennant_mat.albedo_color = active_color if active == self else idle_color


func _add_mesh(mesh: Mesh, at: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = at
	add_child(mi)
