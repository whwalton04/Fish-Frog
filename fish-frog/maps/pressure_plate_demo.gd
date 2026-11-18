extends Node3D

@onready var block: RigidBody3D = $Block
@onready var plate: StaticBody3D = $Plate
@onready var door: AnimatableBody3D = $Door
@onready var closed_height := door.position.y


func _physics_process(delta: float) -> void:
	var pressed: bool = (
		$Bird/Grabber.held_body != block
		and block.global_position.y > plate.global_position.y + 0.1
		and block.get_colliding_bodies().has(plate)
	)
	var target := closed_height + 3.4 if pressed else closed_height
	door.position.y = move_toward(door.position.y, target, 4.0 * delta)
	$Plate/Surface.position.y = -0.04 if pressed else 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		get_tree().reload_current_scene()
