class_name PauseMenu
extends Control
## What the crown does when it puts the quill down: the game stops, the campaign can be written to the shelf
## or taken from it, and the door back to the menu is here. Opened with ESC when no sheet is in the way.

signal closed

var _list: VBoxContainer
var _saves: PanelContainer
var _message: Label
var _when: Label
var _speed_before := 1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.03, 0.02, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var centre := VBoxContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.grow_vertical = Control.GROW_DIRECTION_BOTH
	centre.add_theme_constant_override("separation", 12)
	add_child(centre)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", KDTheme.card_panel())
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre.add_child(frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	frame.add_child(col)
	var title := SettlementHud._label(col, 22, KDTheme.GOLD, true)
	title.text = "IL REGNO ATTENDE"
	col.add_child(KDTheme.ornate_rule())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_when = SettlementHud._label(col, 14, Color(KDTheme.TEXT_LIGHT, 0.85), false)
	_when.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


	_button(col, "Riprendi", close)
	_button(col, "Salva partita", _save_now)
	_button(col, "Carica partita", func() -> void:
		_saves.visible = not _saves.visible
		if _saves.visible:
			_refresh_list())
	_button(col, "Torna al menù", _to_menu)
	_button(col, "Esci dal gioco", func() -> void: get_tree().quit())
	_message = SettlementHud._label(col, 13, Color("#BFE39A"), false)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.visible = false

	_saves = PanelContainer.new()
	_saves.add_theme_stylebox_override("panel", KDTheme.card_panel())
	_saves.visible = false
	_saves.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre.add_child(_saves)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 210)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_saves.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)


func _button(parent: Control, text: String, action: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(300, 40)
	KDTheme.button_styles(btn)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(action)
	parent.add_child(btn)


func open() -> void:
	if not Session.has_game():
		return
	_speed_before = Session.current.clock.speed_index
	_when.text = Session.current.date_text()
	Session.current.clock.set_speed(0)
	_message.visible = false
	_saves.visible = false
	visible = true


func close() -> void:
	visible = false
	if Session.has_game():
		Session.current.clock.set_speed(_speed_before)
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _save_now() -> void:
	if not Session.has_game():
		return
	var session := Session.current
	var k := session.world.player()
	var slot := "%s_%d" % [(k.name if k else "regno").to_lower().replace(" ", "_"), session.world.day]
	var path := SaveCatalogue.write(session, slot, session.date_text())
	_message.text = "Partita salvata: %s" % session.date_text() if path != "" else "Il salvataggio non è riuscito."
	_message.add_theme_color_override("font_color", Color("#BFE39A") if path != "" else Color("#FFB09A"))
	_message.visible = true


func _refresh_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for entry in SaveCatalogue.list():
		var btn := Button.new()
		btn.text = "%s — %s" % [String(entry["realm"]) if String(entry["realm"]) != "" else String(entry["slot"]),
			String(entry["date_text"])]
		btn.tooltip_text = "salvata il %s" % String(entry["saved_at"])
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(460, 34)
		KDTheme.button_styles(btn)
		var path := String(entry["path"])
		btn.pressed.connect(func() -> void: _load(path))
		_list.add_child(btn)
	if _list.get_child_count() == 0:
		var none := SettlementHud._label(_list, 14, Color(KDTheme.TEXT_LIGHT, 0.8), false)
		none.text = "Nessuna partita salvata."


func _load(path: String) -> void:
	var loaded := SaveSystem.load_from_file(path)
	if loaded == null:
		_message.text = "Quel salvataggio non si apre."
		_message.add_theme_color_override("font_color", Color("#FFB09A"))
		_message.visible = true
		return
	Session.adopt_loaded(loaded)
	get_tree().reload_current_scene()


func _to_menu() -> void:
	Session.end()
	get_tree().change_scene_to_file(MainMenu.MENU_SCENE)

