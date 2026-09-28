class_name NotificationStack
extends VBoxContainer
## What the realm tells the ruler while he looks elsewhere: the newest on top, each with the painted icon of
## what it is about, a coloured edge, and how long ago it happened. The ones that happened somewhere on the
## map offer to take the camera there.
##
## Phase 18: at most four, each a single line — icon, short title, how long ago; the small news of the
## village (a birth, a roof finished, a traveller who stays) in a quieter colour and gone sooner. Since the HUD review they live in the "Notizie" block of the right column (NewsPanel) and
## they stay while they are recent — measured in days of the game, so a paused game keeps them — instead of
## fading after a few seconds of the player's time.

const MAX_CARDS := 4
## Days of the game a piece of news stays in the block.
const LIFE_DAYS := 60
const MINOR_LIFE_DAYS := 12
const WIDTH := 330.0
const KIND_COLORS := {
	&"war": "#E2896F", &"army": "#E2A06F", &"court": "#E9D8A6", &"law": "#DCCFAE",
	&"diplomacy": "#BFD9E3", &"event": "#E9D8A6", &"realm": "#BFE39A", &"warning": "#FFB09A",
	&"emigration": "#D8C0A0", &"travellers": "#CFE0B8", &"spirit": "#BFD9E3", &"treasury": "#EFC96F",
	&"death": "#C9B8A0", &"birth": "#CFE0B8", &"building": "#DCCFAE",
}
const KIND_ICONS := {
	&"war": &"war", &"army": &"shield", &"court": &"crown", &"law": &"law", &"diplomacy": &"diplomacy",
	&"event": &"chronicle", &"realm": &"village", &"warning": &"alert", &"emigration": &"people",
	&"travellers": &"people", &"spirit": &"lily", &"treasury": &"treasury", &"death": &"people",
	&"birth": &"growth", &"building": &"build", &"good": &"growth", &"bad": &"alert",
}
## News of the village that does not need a card of its own.
const MINOR_KINDS := [&"birth", &"building", &"travellers"]

var _camera: WorldCamera
## [{card, age (real seconds, for the fade in), day, life, when (Label)}]
var _cards: Array[Dictionary] = []
var _tick := 0.0


func setup(camera: WorldCamera) -> void:
	_camera = camera


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.notification.connect(_on_notification)


func _process(delta: float) -> void:
	var today := Session.current.world.day if Session.has_game() else 0
	_tick += delta
	var kept: Array[Dictionary] = []
	for entry in _cards:
		if not is_instance_valid(entry["card"]):
			continue
		var card := entry["card"] as Control
		entry["age"] = float(entry["age"]) + delta
		card.modulate.a = clampf(float(entry["age"]) / 0.25, 0.0, 1.0)   # it arrives, it does not pop
		if today - int(entry["day"]) > int(entry["life"]):
			card.queue_free()
			continue
		kept.append(entry)
	_cards = kept
	if _tick > 0.5:
		_tick = 0.0
		for entry in _cards:
			(entry["when"] as Label).text = when_text(today - int(entry["day"]))


## "oggi", "ieri", "5 giorni fa", "2 mesi fa".
static func when_text(days: int) -> String:
	if days <= 0:
		return "oggi"
	if days == 1:
		return "ieri"
	if days < 30:
		return "%d giorni fa" % days
	var months := days / 30
	return "un mese fa" if months == 1 else "%d mesi fa" % months


func _on_notification(title: String, text: String, kind: StringName, world_pos: Vector2) -> void:
	var minor := kind in MINOR_KINDS
	var colour := Color.html(String(KIND_COLORS.get(kind, "#E9D8A6")))
	var card := PanelContainer.new()
	# one dark row with the colour of its kind on the left edge: icon, a short title, how long ago. The whole
	# text is in the tooltip, opens under the title with a click, and stays in the chronicle (HUD review)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.07, 0.04, 0.55)
	style.border_color = colour
	style.border_width_left = 3
	style.set_corner_radius_all(3)
	style.content_margin_left = 9
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var icon: StringName = KIND_ICONS.get(kind, &"chronicle")
	if KDUi.has(StringName("icon_%s" % icon)):
		var mark := KDUi.icon_node(icon, 22.0)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(mark)
	var head := SettlementHud._label(row, 15, colour.lerp(KDTheme.TEXT_LIGHT, 0.35) if minor else colour, not minor)
	head.text = title
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.clip_text = true
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var when := SettlementHud._label(row, 14, Color(KDTheme.TEXT_LIGHT, 0.6), false)
	when.text = "oggi"
	when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	when.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# folded away until the card is clicked
	var detail := VBoxContainer.new()
	detail.name = "Detail"
	detail.add_theme_constant_override("separation", 4)
	detail.visible = false
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(detail)
	var body := SettlementHud._label(detail, 14, Color(KDTheme.TEXT_LIGHT, 0.95), false)
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(WIDTH - 30.0, 0)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var here := world_pos != Vector2.INF and _camera != null
	if here:
		var go := Button.new()
		go.text = "Vai sul posto"
		go.focus_mode = Control.FOCUS_NONE
		go.add_theme_font_size_override("font_size", 14)
		go.size_flags_horizontal = Control.SIZE_SHRINK_END
		KDTheme.button_styles(go)
		go.pressed.connect(func() -> void: _camera.focus_on(world_pos, _camera.meters_per_pixel(), false))
		detail.add_child(go)
	card.tooltip_text = "%s\n%s\nClic: %s" % [title, text, "leggi tutto e vai sul posto" if here else "leggi tutto"]
	card.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			detail.visible = not detail.visible)
	add_child(card)
	move_child(card, 0)
	while get_child_count() > MAX_CARDS:
		var oldest := get_child(get_child_count() - 1)
		remove_child(oldest)
		oldest.queue_free()
	card.modulate.a = 0.0
	_cards.append({"card": card, "age": 0.0, "day": Session.current.world.day if Session.has_game() else 0,
		"life": MINOR_LIFE_DAYS if minor else LIFE_DAYS, "when": when})

