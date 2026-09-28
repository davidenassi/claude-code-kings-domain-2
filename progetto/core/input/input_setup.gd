class_name InputSetup
extends RefCounted
## Registers the game's input actions at startup (kept in code so project.godot stays readable).


static func register() -> void:
	_key(&"kd_pan_left", [KEY_A, KEY_LEFT])
	_key(&"kd_pan_right", [KEY_D, KEY_RIGHT])
	_key(&"kd_pan_up", [KEY_W, KEY_UP])
	_key(&"kd_pan_down", [KEY_S, KEY_DOWN])
	_key(&"kd_zoom_in", [KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP])
	_key(&"kd_zoom_out", [KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN])
	_key(&"kd_pause", [KEY_SPACE])
	_key(&"kd_speed_1", [KEY_1])
	_key(&"kd_speed_2", [KEY_2])
	_key(&"kd_speed_3", [KEY_3])
	_key(&"kd_speed_4", [KEY_4])
	_key(&"kd_speed_5", [KEY_5])
	_key(&"kd_quick_save", [KEY_F5])
	_key(&"kd_quick_load", [KEY_F9])
	_key(&"kd_toggle_debug", [KEY_F3])
	_key(&"kd_cancel", [KEY_ESCAPE])


static func _key(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

