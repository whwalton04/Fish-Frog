extends CharacterBody3D

@export var swim_speed := 4.0
@export var tail_speed := 8.0
@export var tail_strength := 0.55
@onready var model: Node3D = $Clownfish
@onready var camera_arm: SpringArm3D = $CameraArm
@onready var rig: Skeleton3D = $"Clownfish/Fish Rig/Skeleton3D"
@onready var tail_bone := rig.find_bone("Tail")

var tail_rest: Quaternion
var tail_axis: Vector3
var tail_phase := 0.0
var tail_weight := 0.0


func _ready() -> void:
	camera_arm.add_excluded_object(get_rid())
	tail_rest = rig.get_bone_pose_rotation(tail_bone)
	var tail_basis := rig.global_basis * rig.get_bone_global_rest(tail_bone).basis
	tail_axis = (tail_basis.inverse() * Vector3.UP).normalized()


func _physics_process(delta: float) -> void:
	var stick := Input.get_vector("walk_left", "walk_right", "walk_forward", "walk_backward")
	var horizontal := Vector3(stick.x, 0.0, stick.y).rotated(Vector3.UP, camera_arm.rotation.y)
	var lift := float(Input.is_action_pressed("Flap")) - float(Input.is_physical_key_pressed(KEY_CTRL))
	var direction := (horizontal + Vector3.UP * lift).limit_length()
	velocity = direction * swim_speed
	move_and_slide()
	var speed_ratio := clampf(get_real_velocity().length() / maxf(swim_speed, 0.001), 0.0, 1.0)
	tail_weight = move_toward(tail_weight, speed_ratio, 5.0 * delta)
	if tail_weight > 0.0:
		tail_phase = fmod(tail_phase + delta * tail_speed, TAU)
	else:
		tail_phase = 0.0
	var swing := Quaternion(tail_axis, sin(tail_phase) * tail_strength * tail_weight)
	rig.set_bone_pose_rotation(tail_bone, tail_rest * swing)
	if horizontal.length_squared() > 0.001:
		var heading := atan2(horizontal.x, horizontal.z)
		model.rotation.y = lerp_angle(model.rotation.y, heading, 1.0 - exp(-8.0 * delta))
