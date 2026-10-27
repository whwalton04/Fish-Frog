
extends Node3D

const FISH_SCENE = preload("res://fish.tscn")


func _ready() -> void:
	create_environment()
	create_camera()
	create_fish()
	create_seabed()


func create_environment() -> void:
	# Blue background and soft ambient light
	var world = WorldEnvironment.new()
	var environment = Environment.new()

	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	environment.ambient_light_source = (
		Environment.AMBIENT_SOURCE_COLOR
	)
	environment.ambient_light_color = Color(0.35, 0.65, 0.8)
	environment.ambient_light_energy = 0.8

	world.environment = environment
	add_child(world)

	# Light the fish
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.2
	add_child(light)


func create_camera() -> void:
	var camera = Camera3D.new()
	camera.position = Vector3(0, 5, 10)
	camera.fov = 55
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true


func create_fish() -> void:
	var fish = FISH_SCENE.instantiate()
	add_child(fish)


func create_seabed() -> void:
	var seabed = MeshInstance3D.new()
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(30, 30)

	seabed.mesh = mesh
	seabed.position.y = -2.0

	var sand = StandardMaterial3D.new()
	sand.albedo_color = Color(0.12, 0.38, 0.38)
	sand.roughness = 1.0
	seabed.material_override = sand

	add_child(seabed)
