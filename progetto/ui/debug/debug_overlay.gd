class_name DebugOverlay
extends CanvasLayer
## Developer overlay (F3): date, speed, fps, simulation rate, camera zoom and position.

@export var camera_path: NodePath
@export var runner_path: NodePath

var _label: Label
var _camera: WorldCamera
var _runner: SimulationRunner


func _ready() -> void:
	layer = 50
	_camera = get_node_or_null(camera_path) as WorldCamera
	_runner = get_node_or_null(runner_path) as SimulationRunner

	var panel := PanelContainer.new()
	# bottom left: the top left belongs to the stores bar
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position = Vector2(12, -12)
	panel.offset_left = 12
	panel.offset_bottom = -12
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.04, 0.78)
	style.border_color = Color(0.79, 0.64, 0.29, 0.9)
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.93, 0.88, 0.75))
	_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(_label)

	# the notifications of the game live in the HUD (NotificationStack), not in the debug overlay


## The camera of the map on the table (Rebirth: each map has its own).
func set_camera(camera: WorldCamera) -> void:
	_camera = camera


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"kd_toggle_debug"):
		visible = not visible


func _process(_delta: float) -> void:
	if not visible:
		return
	var lines: PackedStringArray = []
	if Session.has_game():
		var s := Session.current
		var d := s.calendar.date_of(s.world.day)
		lines.append("%s  (%s)" % [s.date_text(), s.calendar.season_name(int(d["season"]))])
		var speed_name := s.clock.speed_names[s.clock.speed_index] if s.clock.speed_index < s.clock.speed_names.size() else str(s.clock.speed_index)
		lines.append("Velocità: %s  [Spazio, 1-5]" % speed_name)
		if _runner:
			lines.append("Tick/s: %.0f" % _runner.last_ticks_per_second)
	lines.append("FPS: %d" % Engine.get_frames_per_second())
	if _camera:
		lines.append("Zoom: %.3f m/px" % _camera.meters_per_pixel())
		var p := _camera.world_position()
		lines.append("Camera: %.0f, %.0f m" % [p.x, p.y])
	_label.text = "\n".join(lines)

