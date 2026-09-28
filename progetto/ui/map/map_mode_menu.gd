class_name MapModeMenu
extends VBoxContainer
## The map modes at the foot of the left column: one button that says which map is on the table, and the list
## of the others folded underneath. It replaces the bar that used to sit open across the top of the screen.
## Keyboard unchanged: M cycles, the F-keys of data/defs/map_modes.json choose. The four maps a ruler reads every
## day (politics, terrain, resources, population) are in the list; the others under «Altre mappe» (consolidation).

var _controller: MapModeController
var _head: Button
var _list: VBoxContainer
var _more: Button
var _more_list: VBoxContainer
var _buttons: Dictionary = {}   # StringName -> Button
var _group := ButtonGroup.new()


func setup(controller: MapModeController) -> void:
	_controller = controller
	add_theme_constant_override("separation", 3)
	_head = Button.new()
	_head.focus_mode = Control.FOCUS_NONE
	_head.icon = KDUi.icon(&"village")
	_head.expand_icon = true
	_head.add_theme_constant_override("icon_max_width", 20)
	_head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_head.custom_minimum_size = Vector2(232, 36)
	_head.add_theme_font_size_override("font_size", 16)
	_head.tooltip_text = "Le mappe del regno (M per scorrere)"
	KDTheme.button_styles(_head)
	_head.pressed.connect(func() -> void: _list.visible = not _list.visible)
	add_child(_head)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.visible = false
	add_child(_list)
	_more_list = VBoxContainer.new()
	_more_list.add_theme_constant_override("separation", 2)
	_more_list.visible = false
	for mode in MapModes.ids():
		var info := MapModes.mode_info(mode)
		var secondary := String(info.get("tier", "primary")) == "secondary"
		if secondary and _more == null:
			_more = Button.new()
			_more.text = "Altre mappe ▸"
			_more.focus_mode = Control.FOCUS_NONE
			_more.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_more.custom_minimum_size = Vector2(232, 28)
			KDTheme.button_styles(_more)
			_more.add_theme_font_size_override("font_size", 15)
			_more.pressed.connect(func() -> void:
				_more_list.visible = not _more_list.visible
				_more.text = "Altre mappe ▾" if _more_list.visible else "Altre mappe ▸")
			_list.add_child(_more)
			_list.add_child(_more_list)
		var b := Button.new()
		b.text = String(info.get("name", mode))
		b.tooltip_text = "%s (%s)" % [info.get("name", mode), info.get("key", "")]
		b.toggle_mode = true
		b.button_group = _group
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(232, 28)
		KDTheme.button_styles(b)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func() -> void:
			if _controller:
				_controller.set_mode(mode))
		(_more_list if secondary else _list).add_child(b)
		_buttons[mode] = b
	if _controller:
		_controller.mode_changed.connect(_sync)
		_sync(_controller.mode)


func _sync(mode: StringName) -> void:
	if _buttons.has(mode):
		(_buttons[mode] as Button).set_pressed_no_signal(true)
	_head.text = "Mappa: %s" % String(MapModes.mode_info(mode).get("name", mode))


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or _controller == null:
		return
	if k.physical_keycode == KEY_M:
		_controller.cycle(-1 if k.shift_pressed else 1)
		get_viewport().set_input_as_handled()
		return
	for mode in MapModes.ids():
		var key_name := String(MapModes.mode_info(mode).get("key", ""))
		if key_name != "" and OS.find_keycode_from_string(key_name) == k.physical_keycode:
			_controller.set_mode(mode)
			get_viewport().set_input_as_handled()
			return

