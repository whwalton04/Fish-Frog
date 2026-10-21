extends SceneTree
## Headless terrain regression: one crab walks a fixed route over the test
## terrain. Run with
##   godot --headless --path . -s tests/terrain_test.gd -- <route>
## Routes: ramp, hump, dome, edge.

const ROUTES := {
	"ramp": [Vector3(0, -0.2, 2), Vector3(0, 0, -1), Vector3(0, 0, -1), 6.0],
	"ramp_side": [Vector3(0, -0.2, 2), Vector3(0, 0, -1), Vector3(-1, 0, 0), 8.0],
	"hump": [Vector3(3, -0.2, -6), Vector3(1, 0, 0), Vector3(0, 0, -1), 6.0],
	"dome": [Vector3(1.5, -0.2, -5.9), Vector3(-1, 0, 0), Vector3(0, 0, -1), 5.0],
	"edge": [Vector3(0, 2.2, -9.6), Vector3(1, 0, 0), Vector3(0, 0, -1), 3.0],
}

var crab: RigidBody3D
var route: Array
var frame := 0
var min_up := 1.0
var max_y := -10.0


func _initialize() -> void:
	seed(1)
	var args := OS.get_cmdline_user_args()
	route = ROUTES[args[0] if args.size() > 0 else "ramp"]
	var world: Node3D = load("res://world/test_terrain.tscn").instantiate()
	for child in world.get_node("Player").get_children():
		if child is RigidBody3D:
			child.free()
	world.get_node("Player").set_physics_process(false)
	root.add_child(world)
	crab = load("res://crab/crab2.tscn").instantiate()
	crab.position = route[0]
	world.add_child(crab)


func _physics_process(delta: float) -> bool:
	frame += 1
	var t := frame * delta
	if t > 0.5:
		crab.move_direction = route[1]
		crab.facing_direction = route[2]
	min_up = minf(min_up, crab.global_basis.y.y)
	max_y = maxf(max_y, crab.global_position.y)
	if t >= route[3]:
		var p := crab.global_position
		print("RESULT pos=(%.2f %.2f %.2f) min_up=%.2f max_y=%.2f up=%.2f" % [p.x, p.y, p.z, min_up, max_y, crab.global_basis.y.y])
		return true
	return false
