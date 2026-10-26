class_name Foothold
extends Marker3D
## A spot on an animal's body where a mounted animal's foot is glued, such as
## on a crab's shell. Walking feet ignore footholds; they're only used once an
## animal mounts the body this belongs to (the nearest CollisionObject3D above
## it). The foot pushes and pulls along this node's +Y, whatever the surface
## under it faces.

signal foot_planted(animal: Node)
signal foot_lifted(animal: Node)

## Raises the mounted animal's body this much above its usual ride height (m,
## scaled with the node), averaged over its feet.
@export_range(0.0, 0.3, 0.005) var lift := 0.0


func get_body() -> CollisionObject3D:
	var node := get_parent()
	while node and not node is CollisionObject3D:
		node = node.get_parent()
	return node


func get_normal() -> Vector3:
	return global_basis.y.normalized()


func get_lift() -> float:
	return lift * global_basis.get_scale().x
