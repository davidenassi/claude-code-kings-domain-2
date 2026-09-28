class_name ArmsView
extends Control
## Displays a coat of arms inside a UI layout.

var arms: CoatOfArms:
	set(value):
		arms = value
		queue_redraw()


func _draw() -> void:
	if arms:
		arms.draw_on(self, Rect2(Vector2.ZERO, size), Color(0.08, 0.05, 0.03), 2.0)

