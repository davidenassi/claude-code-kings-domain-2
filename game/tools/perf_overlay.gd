extends CanvasLayer
## F3: toggles a small performance read-out (FPS, frame time, draw calls, nodes, video memory).

var _label: Label


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.position = Vector2(12, 12)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(1, 1, 0.85))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = not visible


func _process(_d: float) -> void:
	if not visible:
		return
	_label.text = "FPS %d  |  %.1f ms\ndraw calls %d  |  oggetti %d\nnodi %d  |  VRAM %.0f MB" % [
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]
