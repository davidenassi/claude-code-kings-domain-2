class_name WorldView
extends Node2D
## Parent of every world-space renderer. Children use world coordinates (metres).
## Floating origin: this node is offset by -origin so that the visible area always has small
## canvas coordinates, avoiding float32 jitter far from (0, 0) at close zoom.

signal origin_changed(origin: Vector2)

const REBASE_DISTANCE := 12000.0
const SNAP := 4096.0

var origin: Vector2 = Vector2.ZERO


func set_origin(new_origin: Vector2) -> void:
	if new_origin == origin:
		return
	origin = new_origin
	position = -origin
	origin_changed.emit(origin)


## Called by the camera: rebases when the view drifted too far from the current origin.
func track(world_center: Vector2) -> bool:
	if world_center.distance_to(origin) < REBASE_DISTANCE:
		return false
	set_origin(world_center.snapped(Vector2(SNAP, SNAP)))
	return true

