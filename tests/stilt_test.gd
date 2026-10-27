extends SceneTree
## Headless test of the stilt crab's ability. Run with
##   godot --headless --path . -s tests/stilt_test.gd
## Steers a lone StiltCrab on its own, presses the ability to stretch its legs,
## checks it rises, its knees stay low and it doesn't walk while up, switches
## to another crab and back with the arrows, presses the ability again to fold
## them, then checks it's back at its height and walks. Finally mounts it on
## the other crab and stretches its legs there.

var player: Player
var me: StiltCrab
var other: ContactCrab
var frame := 0
var ok := true
var low := 0.0
var spot := Vector3.ZERO


func _initialize() -> void:
	var world: Node3D = load("res://world/test_terrain.tscn").instantiate()
	player = world.get_node("Player")
	for crab in world.find_children("*", "RigidBody3D", true, false):
		if "move_direction" in crab and crab.name != "Crab1":
			crab.get_parent().remove_child(crab)
			crab.free()
	other = player.get_node("Crab1")
	other.position = Vector3(0.6, 0.107, 3.0)
	me = load("res://crab/stilt_crab.tscn").instantiate()
	me.position = Vector3(0.0, 0.107, 3.0)
	player.add_child(me)
	root.add_child(world)
	player.controlled = me


func _physics_process(delta: float) -> bool:
	frame += 1
	var t := frame * delta
	if is_equal_approx(t, 1.0):
		low = me.global_position.y
		_press(&"ability")
	if is_equal_approx(t, 1.5):
		_check("stretching", me.leg_extension > 1.0 and me.leg_extension < me.stilt_length)
		_check("can't walk while stretching", not me.can_walk())
	if is_equal_approx(t, 2.5):
		var rise := me.global_position.y - low
		_check("legs all the way out (×%.2f)" % me.leg_extension, me.leg_extension == me.stilt_length)
		_check("body up on them (%.2fm higher)" % rise, rise > 0.3)
		_check("upright", me.global_basis.y.y > 0.95)
		# Feet that drift less than a step stay put, a little in from their spot.
		_check_legs(0.06)
		spot = me.global_position
		Input.action_press(&"move_forward")
	if is_equal_approx(t, 3.5):
		var moved := Vector2(me.global_position.x - spot.x, me.global_position.z - spot.z).length()
		_check("stayed put while up (%.3fm)" % moved, moved < 0.05)
		_check("still up", me.global_position.y - low > 0.3)
		Input.action_release(&"move_forward")
		_press(&"control_previous")
	if is_equal_approx(t, 3.6):
		_check("left arrow switched away", player.controlled == other)
		_press(&"control_next")
	if is_equal_approx(t, 3.7):
		_check("right arrow switched back", player.controlled == me)
		_check("stayed up through switching", me.leg_extension == me.stilt_length)
		_press(&"ability")
	if is_equal_approx(t, 5.5):
		var off := absf(me.global_position.y - low)
		_check("folded back (%.3fm off its height)" % off, me.leg_extension == 1.0 and off < 0.02)
		_check("can walk again", me.can_walk())
		spot = me.global_position
		Input.action_press(&"move_forward")
	if is_equal_approx(t, 6.5):
		Input.action_release(&"move_forward")
		var moved := Vector2(me.global_position.x - spot.x, me.global_position.z - spot.z).length()
		_check("walks after (%.2fm)" % moved, moved > 0.5)
		other.drop_at(me.global_position + Vector3(0.6, 0.1, 0.0))
	if is_equal_approx(t, 8.0):
		_check("mounted", me.mount_onto(other))
	if is_equal_approx(t, 9.0):
		low = me.global_position.y - other.global_position.y
		_press(&"ability")
	if is_equal_approx(t, 10.5):
		var rise := me.global_position.y - other.global_position.y - low
		_check("stood up while mounted (%.2fm higher)" % rise, rise > 0.3)
		_check("still mounted", me.mount == other and other.rider == me)
		_check("upright on top", me.global_basis.y.y > 0.9)
		# Glued to the footholds the feet can't spread, so the knees rise more.
		_check_legs(0.09)
		_press(&"ability")
	if is_equal_approx(t, 12.0):
		var off := absf(me.global_position.y - other.global_position.y - low)
		_check("folded back on top (%.3fm off)" % off, off < 0.03 and me.mount == other)
	if t > 12.1:
		print("RESULT %s" % ("PASS" if ok else "FAIL"))
		return true
	return false


## Stretched, each knee sits no more than `max_rise` above its hip rather
## than folded up over it, and the lower leg runs straight from knee to foot.
func _check_legs(max_rise: float) -> void:
	var worst_rise := -INF
	var worst_kink := 0.0
	for leg in me._legs:
		var hip: Vector3 = leg.joints[0].global_position
		var knee: Vector3 = leg.joints[1].global_position
		var ankle: Vector3 = leg.joints[2].global_position
		worst_rise = maxf(worst_rise, (knee - hip).dot(me.global_basis.y))
		worst_kink = maxf(worst_kink, rad_to_deg((ankle - knee).angle_to(leg.foot.pos - ankle)))
	_check("knees low (at most %.3fm above the hips)" % worst_rise, worst_rise < max_rise)
	_check("lower legs straight (kinked %.1f°)" % worst_kink, worst_kink < 5.0)


func _check(what: String, passed: bool) -> void:
	print("%s %s" % ["ok  " if passed else "FAIL", what])
	ok = ok and passed


func _press(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	Input.parse_input_event(release)
