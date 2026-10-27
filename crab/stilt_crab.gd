class_name StiltCrab
extends SpecialCrab
## Its ability stretches its lower legs to stilt_length times their length,
## lifting the body high on them, and folds them back again. It can't walk,
## turn, mount or jump while its legs are any longer than usual. Mounted, it
## stands up on the crab underneath, lifting any stack above.

@export_group("Stilts")
@export_range(1.0, 8.0, 0.1) var stilt_length := 3.0
## Seconds to stretch the legs all the way out, or fold them back.
@export_range(0.1, 5.0, 0.05) var stilt_time := 1.0

var _stilts_out := false


func use_ability() -> void:
	_stilts_out = not _stilts_out


func can_walk() -> bool:
	return leg_extension == 1.0


func can_mount(target: Node3D) -> bool:
	return can_walk() and super(target)


## Lands a fresh crab, legs folded.
func drop_at(at: Vector3) -> void:
	_stilts_out = false
	leg_extension = 1.0
	super(at)


func _physics_process(delta: float) -> void:
	var goal := stilt_length if _stilts_out else 1.0
	leg_extension = move_toward(leg_extension, goal, (stilt_length - 1.0) / stilt_time * delta)
	super(delta)
