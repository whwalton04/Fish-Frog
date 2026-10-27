extends Node3D

const SpeedStreaks = preload("res://assets/effects/speed_streaks.tscn")
const BarrelDistortion = preload("res://assets/effects/barrel_distortion.tscn")

@export_group("Speed Feedback")
@export var speed_effects_enabled: bool = true
@export_range(0.0, 200.0, 0.5) var effect_start_speed: float = 3.0
@export_range(0.0, 200.0, 0.5) var effect_full_speed: float = 25.0
@export_range(0.0, 40.0, 0.5) var maximum_fov_increase: float = 20.0
@export_range(0.0, 40.0, 0.5) var acceleration_fov_kick: float = 14.0
@export_range(0.1, 1.0, 0.05) var fov_speed_exponent: float = 0.5
@export_range(0.01, 2.0, 0.01) var fov_response_time: float = 0.12
@export_range(0.01, 2.0, 0.01) var speed_effect_response_time: float = 0.25
@export_range(0.0, 1.0, 0.01) var speed_streak_opacity: float = 0.65

@export_group("Barrel Distortion")
@export var barrel_distortion_enabled: bool = true
@export_range(0.0, 0.3, 0.005) var maximum_barrel_distortion: float = 0.15

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var base_fov: float = 75.0
var speed_intensity: float = 0.0
var speed_streaks: GPUParticles3D = SpeedStreaks.instantiate()
var barrel_distortion: ColorRect = BarrelDistortion.instantiate()


func _ready() -> void:
	spring_arm.add_excluded_object((get_parent() as PhysicsBody3D).get_rid())
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	base_fov = camera.fov
	# Native 3D streaks stream past the camera, leaving space around the bird.
	camera.add_child(speed_streaks)
	var overlay := CanvasLayer.new()
	overlay.name = "SpeedFeedback"
	overlay.layer = 0
	add_child(overlay)
	# Distort the world and its 3D streaks before drawing the debug HUD.
	overlay.add_child(barrel_distortion)
	barrel_distortion.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	var accelerating := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("boost")
	_update_speed_effects(delta, accelerating)


func _update_speed_effects(delta: float, accelerating: bool = false) -> void:
	# Actual speed includes dives and coasting, rather than only the boost key.
	var speed := (get_parent() as RigidBody3D).linear_velocity.length()
	var speed_range := maxf(effect_full_speed - effect_start_speed, 0.001)
	var target := clampf((speed - effect_start_speed) / speed_range, 0.0, 1.0)
	if not speed_effects_enabled:
		target = 0.0
	var weight := 1.0 - exp(-delta / maxf(speed_effect_response_time, 0.001))
	speed_intensity = lerpf(speed_intensity, target, weight)
	# Reserve most widening for the throttle, with only a small speed-based tail.
	# Exponent 0.5 is a square root: strong early response, diminishing increases.
	var fov_budget := maxf(maximum_fov_increase, 0.0)
	var kick := clampf(acceleration_fov_kick, 0.0, fov_budget)
	var speed_widening := (fov_budget - kick) * pow(target, clampf(fov_speed_exponent, 0.1, 1.0))
	var throttle_widening := kick if accelerating and speed_effects_enabled else 0.0
	var target_fov := clampf(base_fov + throttle_widening + speed_widening, 1.0, 150.0)
	var fov_weight := 1.0 - exp(-delta / maxf(fov_response_time, 0.001))
	camera.fov = lerpf(camera.fov, target_fov, fov_weight)
	speed_streaks.process_material.color = Color(1.0, 1.0, 1.0,
		speed_intensity * speed_streak_opacity)
	speed_streaks.amount_ratio = speed_intensity
	# Scale simulation speed instead of stretching the geometry into long rays.
	speed_streaks.speed_scale = clampf(speed / 25.0, 0.15, 8.0)
	speed_streaks.emitting = target > 0.001
	speed_streaks.visible = speed_intensity > 0.001
	var distortion := clampf(maximum_barrel_distortion, 0.0, 0.3) * speed_intensity
	if not barrel_distortion_enabled:
		distortion = 0.0
	barrel_distortion.material.set_shader_parameter("strength", distortion)
	barrel_distortion.visible = distortion > 0.0001
