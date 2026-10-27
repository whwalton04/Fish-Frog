extends Node3D
## Third-person orbit camera around the animals the player steers: the group,
## or the one animal being controlled, or the flag they're dropping onto in a
## rally. Mouse to look, wheel to zoom, Esc frees the mouse, click to capture
## it again.

@export var player: Player
@export var distance := 1.2
@export var min_distance := 0.5
@export var max_distance := 3.5
## How much further out the camera sits as the group grows: the distance
## scales by 1 + this * (sqrt(animals) - 1), so one animal is unchanged.
## Controlling a single animal zooms back in.
@export var group_zoom := 0.4
@export var height_offset := 0.12
@export var mouse_sensitivity := 0.003
@export var follow_smoothing := 12.0
@export var zoom_smoothing := 4.0

var _yaw := 0.0
var _pitch := -0.45
var _zoom := 1.0

@onready var _pitch_pivot: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The player may sit anywhere; the rig goes where the animals are.
	top_level = true
	if player:
		global_position = player.get_center() + Vector3.UP * height_offset
		_zoom = _group_zoom()
		var animals: Array = player.get_animals() + get_tree().get_nodes_in_group(Player.ANIMAL_GROUP)
		for animal in animals:
			if animal is CollisionObject3D:
				_arm.add_excluded_object(animal.get_rid())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and (not player or player.active):
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.35, 0.35)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP when not player or player.active:
				distance = maxf(min_distance, distance - 0.1)
			MOUSE_BUTTON_WHEEL_DOWN when not player or player.active:
				distance = minf(max_distance, distance + 0.1)
			MOUSE_BUTTON_LEFT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if player:
		var goal := player.get_focus() + Vector3.UP * height_offset
		global_position = global_position.lerp(goal, 1.0 - exp(-follow_smoothing * delta))
		_zoom = lerpf(_zoom, _group_zoom(), 1.0 - exp(-zoom_smoothing * delta))
	rotation = Vector3(0.0, _yaw, 0.0)
	_pitch_pivot.rotation = Vector3(_pitch, 0.0, 0.0)
	_arm.spring_length = distance * _zoom


func make_current() -> void:
	$Pitch/SpringArm3D/Camera3D.make_current()


func _group_zoom() -> float:
	return 1.0 + group_zoom * (sqrt(maxf(player.get_steered().size(), 1.0)) - 1.0)
