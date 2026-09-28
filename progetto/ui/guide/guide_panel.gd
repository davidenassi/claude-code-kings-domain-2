class_name GuidePanel
extends PanelContainer
## The card of the first steps: one thing at a time, in the corner, with the way to close it for good.
## It never blocks anything — it is a note on the table, not a wall.
##
## HUD review (Phase 18): folded it is a small bar with the book, the name of the step and a chevron; a click
## unfolds the text. It starts folded — the minimap under it stays, the corner is not two fixed blocks.

var _title: Label
var _text: Label
var _progress: Label
var _body: VBoxContainer
var _chevron: TextureRect
var _timer := 0.0
var _expanded := false
## True while a sheet of the realm is open over the same corner: the note waits under it.
var covered := false


func _ready() -> void:
	add_theme_stylebox_override("panel", KDTheme.dark_panel())
	custom_minimum_size = Vector2(300, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	head.tooltip_text = "Clic per aprire o chiudere il passo della guida"
	head.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			set_expanded(not _expanded))
	col.add_child(head)
	var mark := KDUi.icon_node(&"book", 22.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(mark)
	_title = SettlementHud._label(head, 16, KDTheme.GOLD, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chevron = TextureRect.new()
	_chevron.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chevron.custom_minimum_size = Vector2(18, 18)
	_chevron.modulate = Color(KDTheme.GOLD, 0.9)
	_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_chevron)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	col.add_child(_body)
	_text = SettlementHud._label(_body, 15, Color(KDTheme.TEXT_LIGHT, 0.95), false)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(276, 0)
	var foot := HBoxContainer.new()
	_body.add_child(foot)
	_progress = SettlementHud._label(foot, 14, Color(KDTheme.TEXT_LIGHT, 0.65), false)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "Chiudi la guida"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 14)
	KDTheme.button_styles(close)
	close.pressed.connect(func() -> void:
		if Session.has_game():
			Guide.dismiss(Session.current.world)
		visible = false)
	foot.add_child(close)
	set_expanded(false)
	refresh()


func set_expanded(on: bool) -> void:
	_expanded = on
	_body.visible = on
	_chevron.texture = KDTheme.chevron_down_texture() if on else KDTheme.chevron_texture()


func is_expanded() -> bool:
	return _expanded


func _process(delta: float) -> void:
	_timer += delta
	if _timer < 0.5:
		return
	_timer = 0.0
	if not Session.has_game():
		return
	if Guide.advance(Session.current.world):
		var step := Guide.current(Session.current.world)
		if Guide.finished(Session.current.world):
			EventBus.notify("I primi passi sono fatti", "Il regno cammina da sé: la guida si chiude qui.", &"realm")
		else:
			EventBus.notify("Fatto", "Ora: %s" % String(step.get("title", "")), &"realm")
	refresh()


func refresh() -> void:
	if not Session.has_game():
		visible = false
		return
	var world := Session.current.world
	var index := Guide.current_index(world)
	if index >= Guide.DONE or Guide.finished(world):
		visible = false
		return
	var step := Guide.current(world)
	if step.is_empty():
		visible = false
		return
	visible = not covered
	_title.text = String(step.get("title", ""))
	_text.text = String(step.get("text", ""))
	_progress.text = "passo %d di %d" % [index + 1, Guide.steps().size()]

