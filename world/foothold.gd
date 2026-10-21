class_name Foothold
extends Marker3D
## A spot on some geometry where a foot can stand, for shapes the legs don't
## find good holds on by themselves, such as another crab's shell.
##
## A foot whose usual spot comes within capture_radius goes here instead, as
## long as it's already on, or reaching for, the body this belongs to (the
## nearest CollisionObject3D above it). The foot pushes along this node's +Y,
## whatever the surface under it faces, so a foothold on a rim can be stood on.

const GROUP := &"footholds"

## How close a foot's usual spot has to come for the foot to go here (m,
## scaled with the node).
@export_range(0.01, 1.0, 0.01) var capture_radius := 0.15
## How many feet can stand here at once.
@export_range(1, 8) var capacity := 1

var _users := {}  # foot -> animal it belongs to


func _enter_tree() -> void:
	add_to_group(GROUP)


func get_body() -> CollisionObject3D:
	var node := get_parent()
	while node and not node is CollisionObject3D:
		node = node.get_parent()
	return node


func get_normal() -> Vector3:
	return global_basis.y.normalized()


func get_capture_radius() -> float:
	return capture_radius * global_basis.get_scale().x


func is_free_for(foot: Object) -> bool:
	for user in _users.keys():
		if not is_instance_valid(_users[user]):
			_users.erase(user)
	return _users.has(foot) or _users.size() < capacity


func claim(foot: Object, animal: Node) -> void:
	_users[foot] = animal


func release(foot: Object) -> void:
	_users.erase(foot)
