extends SceneTree
## Headless crab-stacking test. Run with
##   godot --headless --path . -s tests/stack_test.gd
## Builds a stack of five on the test terrain, mounting onto the top and into
## the middle, then walks the bottom crab about, lets it stand, gets the top
## one off by moving it, and finally pushes down on the stack from outside.
## Prints the gaps between shells (they should hold, not shrink, as the stack
## grows), how far the top sways from over the bottom, and whether the stack
## stays together.

const SPOT := Vector3(0.0, 0.107, 3.0)
const RING := 0.35

var crabs: Array = []
var frame := 0
var alone_height := 0.0
var max_sway := 0.0
var broke_at := -1.0
var squeeze_before := 0.0


func _initialize() -> void:
	var world: Node3D = load("res://world/test_terrain.tscn").instantiate()
	var player: Node = world.get_node("Player")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	for crab in world.find_children("*", "RigidBody3D", true, false):
		if "move_direction" in crab:
			crab.process_mode = Node.PROCESS_MODE_PAUSABLE
			crabs.append(crab)
	crabs[0].position = SPOT
	for i in range(1, crabs.size()):
		var angle := TAU * i / (crabs.size() - 1)
		crabs[i].position = SPOT + Vector3(cos(angle), 0.0, sin(angle)) * RING
	# Only five are stacked; the rest wait out of the way.
	for i in range(5, crabs.size()):
		crabs[i].position = SPOT + Vector3(3.0 + i, 0.0, 0.0)
	root.add_child(world)


func _physics_process(delta: float) -> bool:
	frame += 1
	var t := frame * delta
	var bottom: ContactCrab = crabs[0]
	if OS.has_environment("LOG") and frame % 12 == 0:
		var line := "t=%.2f" % t
		for c in _stack():
			line += "  c%d(%.2f %.3f %.2f up%.2f)" % [crabs.find(c), c.global_position.x, c.global_position.y, c.global_position.z, c.global_basis.y.y]
		print(line)
	if is_equal_approx(t, 0.4):
		alone_height = bottom.global_position.y
	# 1 on 0, 2 on top, 3 into the middle (between 0 and 1), 4 on top.
	var plan := {0.5: [1, 0], 0.8: [2, 1], 1.1: [3, 0], 1.4: [4, 2]}
	for at in plan:
		if is_equal_approx(t, at):
			var who: ContactCrab = crabs[plan[at][0]]
			# Brought alongside first: the stack may have drifted off.
			var target: Node3D = crabs[plan[at][1]]
			who.global_position = Vector3(target.global_position.x + 0.3, who.global_position.y, target.global_position.z)
			var ok := who.mount_onto(target)
			print("t=%.1f crab%d mounts crab%d: %s  stack=%s" % [t, plan[at][0], plan[at][1], ok, _stack_names()])
	if is_equal_approx(t, 2.5):
		_report("standing", alone_height)
	if t > 3.0 and t < 4.0:
		bottom.move_direction = Vector3.FORWARD
		bottom.facing_direction = Vector3.FORWARD
	elif t >= 4.0 and t < 5.0:
		bottom.move_direction = Vector3.LEFT * 0.7
		bottom.facing_direction = Vector3.LEFT
	else:
		bottom.move_direction = Vector3.ZERO
	if t > 3.0 and t < 6.0:
		var top := _stack()[-1] as Node3D
		var d := top.global_position - bottom.global_position
		max_sway = maxf(max_sway, Vector2(d.x, d.z).length())
		if broke_at < 0.0 and _stack().size() < 5:
			broke_at = t
	if is_equal_approx(t, 6.5):
		print("walking: max sway %.3fm, intact=%s%s" % [max_sway, broke_at < 0.0,
				"" if broke_at < 0.0 else " (broke at %.2fs)" % broke_at])
		_report("after walking", alone_height)
	# The top one moves off.
	var leaving: ContactCrab = crabs[4]
	if t > 6.6 and t < 7.0:
		leaving.move_direction = Vector3.RIGHT
	elif t >= 7.0:
		leaving.move_direction = Vector3.ZERO
	if is_equal_approx(t, 8.0):
		print("top moved: mounted=%s  stack=%s" % [leaving.mount != null, _stack_names()])
		squeeze_before = _stack()[-1].global_position.y - bottom.global_position.y
	# An outside push down on the top, three times a crab's weight.
	if t > 8.0 and t < 9.0:
		var top: RigidBody3D = _stack()[-1]
		top.apply_central_force(Vector3.DOWN * top.mass * 9.8 * 3.0)
	if is_equal_approx(t, 9.0):
		var squeezed: float = _stack()[-1].global_position.y - bottom.global_position.y
		print("squeezed from outside: stack height %.3f -> %.3fm" % [squeeze_before, squeezed])
	if t > 10.5:
		var relaxed: float = _stack()[-1].global_position.y - bottom.global_position.y
		print("released: stack height %.3fm" % relaxed)
		_report("end", alone_height)
		return true
	return false


func _stack() -> Array:
	var stack: Array = [crabs[0]]
	while stack[-1].rider:
		stack.append(stack[-1].rider)
	return stack


func _stack_names() -> String:
	return " > ".join(_stack().map(func(c): return "crab%d" % crabs.find(c)))


func _report(label: String, alone: float) -> void:
	var stack := _stack()
	var gaps := []
	for i in range(1, stack.size()):
		gaps.append("%.3f" % (stack[i].global_position.y - stack[i - 1].global_position.y))
	var up_min := 1.0
	for c in stack:
		up_min = minf(up_min, c.global_basis.y.y)
	print("%s: %s  bottom height %.3f (alone %.3f)  gaps %s  min up %.2f" % [label, _stack_names(),
			stack[0].global_position.y, alone, ", ".join(gaps), up_min])
