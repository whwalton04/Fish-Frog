extends Node3D
## Third-person orbit camera. Mouse to look, wheel to zoom, Esc frees the
## mouse, click to capture it again.

@export var target: Node3D
@export var distance := 1.2
@export var min_distance := 0.5
@export var max_distance := 3.5
@export var height_offset := 0.12
@export var mouse_sensitivity := 0.003
@export var follow_smoothing := 12.0

var _yaw := 0.0
var _pitch := -0.45

@onready var _pitch_pivot: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if target:
		global_position = target.global_position + Vector3.UP * height_offset
		if target is CollisionObject3D:
			_arm.add_excluded_object(target.get_rid())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.35, 0.35)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				distance = maxf(min_distance, distance - 0.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				distance = minf(max_distance, distance + 0.1)
			MOUSE_BUTTON_LEFT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if target:
		var goal := target.global_position + Vector3.UP * height_offset
		global_position = global_position.lerp(goal, 1.0 - exp(-follow_smoothing * delta))
	rotation = Vector3(0.0, _yaw, 0.0)
	_pitch_pivot.rotation = Vector3(_pitch, 0.0, 0.0)
	_arm.spring_length = distance
