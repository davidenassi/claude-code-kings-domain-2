class_name EventCard
extends PanelContainer
## What the world puts in front of the king: a title, a few lines, and the answers with what they cost and
## what they bring. It appears by itself when something happens and waits — for a while.
##
## Phase 18: the kind of the event is written in the band of the frame, a painted emblem of its category
## stands beside the title, and under every answer its consequences are written out, green what helps and red
## what hurts (they used to hide in a tooltip).

## The emblem of each category of event (painted icons of the kit).
const CATEGORY_ICONS := {
	"crisi": &"alert", "cultura": &"culture", "dinastia": &"house_arms", "diplomazia": &"diplomacy",
	"economia": &"trade", "famiglie": &"growth", "fede": &"clergy", "guerra": &"war", "popolazione": &"people",
	"sovrano": &"crown", "terra": &"grain",
}
## Effects that are good when they go down.
const WORSE_WHEN_UP := ["turbulence", "unrest", "kill_people"]

var _category: Label
var _emblem: TextureRect
var _title: Label
var _text: Label
var _options: VBoxContainer
var _shown := -1


func _ready() -> void:
	var frame := KDTheme.wood_panel().duplicate() as StyleBox
	if frame is StyleBoxTexture:
		(frame as StyleBoxTexture).content_margin_top = 8   # the band of the frame carries the category
	add_theme_stylebox_override("panel", frame)
	custom_minimum_size = Vector2(560, 0)
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var band := MarginContainer.new()
	band.add_theme_constant_override("margin_left", 4)
	band.custom_minimum_size = Vector2(0, 46)   # the whole band: what follows starts under the inner frame
	col.add_child(band)
	_category = SettlementHud._label(band, 13, Color("#E9D8A6"), true)
	_category.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	var medallion := PanelContainer.new()
	medallion.add_theme_stylebox_override("panel",
		KDUi.style(&"panel_gold", Vector4(10, 10, 10, 10)) if KDUi.has(&"panel_gold") else KDTheme.dark_panel())
	medallion.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(medallion)
	_emblem = TextureRect.new()
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem.custom_minimum_size = Vector2(60, 60)
	medallion.add_child(_emblem)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 8)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(words)
	_title = SettlementHud._label(words, 22, KDTheme.GOLD, true)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(400, 0)
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", KDTheme.parchment_panel())
	words.add_child(sheet)
	_text = Label.new()
	_text.add_theme_font_override("font", KDFonts.serif())
	_text.add_theme_font_size_override("font_size", 15)
	_text.add_theme_color_override("font_color", KDTheme.INK)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(390, 0)
	sheet.add_child(_text)
	col.add_child(KDTheme.ornate_rule())
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 8)
	col.add_child(_options)
	EventBus.event_raised.connect(func(_id: String) -> void: refresh())


func _process(_delta: float) -> void:
	if not Session.has_game():
		return
	var world := Session.current.world
	var pending_id := int(world.pending_events[0]["id"]) if not world.pending_events.is_empty() else -1
	if pending_id != _shown:
		refresh()


func refresh() -> void:
	if not Session.has_game():
		return
	var session := Session.current
	var world := session.world
	if world.pending_events.is_empty():
		visible = false
		_shown = -1
		return
	var pending: Dictionary = world.pending_events[0]
	var e := Events.event(StringName(pending["event"]))
	if e.is_empty():
		visible = false
		return
	_shown = int(pending["id"])
	visible = true
	var realm := session.world.player()
	var category := String(e.get("category", ""))
	_category.text = category.to_upper() if category != "" else "UN FATTO DEL REGNO"
	_emblem.texture = KDUi.icon(CATEGORY_ICONS.get(category, &"chronicle"))
	_title.text = Events.words(realm, String(e.get("title", "Un fatto")))
	_title.add_theme_color_override("font_color", _color_of(String(e.get("kind", "good"))))
	_text.text = Events.words(realm, String(e.get("text", "")))
	for c in _options.get_children():
		_options.remove_child(c)
		c.queue_free()
	var options: Array = e.get("options", [])
	for i in options.size():
		var option: Dictionary = options[i]
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 2)
		_options.add_child(block)
		var btn := Button.new()
		btn.text = Events.words(realm, String(option.get("text", "…")))
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(520, 36)
		KDTheme.button_styles(btn)
		var command := ChooseEventOptionCommand.create(_shown, i)
		var reason := command.validate(session)
		btn.disabled = reason != ""
		btn.tooltip_text = reason
		var index := i
		var pending_id := _shown
		btn.pressed.connect(func() -> void:
			Session.current.submit(ChooseEventOptionCommand.create(pending_id, index))
			refresh())
		block.add_child(btn)
		var effects: Dictionary = option.get("effects", {})
		var consequences := RichTextLabel.new()
		consequences.bbcode_enabled = true
		consequences.fit_content = true
		consequences.scroll_active = false
		consequences.mouse_filter = Control.MOUSE_FILTER_IGNORE
		consequences.custom_minimum_size = Vector2(520, 0)
		consequences.add_theme_font_override("normal_font", KDFonts.serif())
		consequences.add_theme_font_size_override("normal_font_size", 14)
		consequences.add_theme_color_override("default_color", Color(KDTheme.TEXT_LIGHT, 0.85))
		var told := effects_bbcode(effects)
		consequences.text = "[center]%s[/center]" % (told if told != "" else "[color=%s]nessuna conseguenza immediata[/color]" % KDTip.DIM)
		if reason != "":
			consequences.text += "\n[center][color=%s]%s[/color][/center]" % [KDTip.BAD, reason]
		block.add_child(consequences)


static func _color_of(kind: String) -> Color:
	match kind:
		"bad":
			return Color("#E2A06F")
		"crisis":
			return Color("#E2896F")
		_:
			return KDTheme.GOLD


## What an answer really does, coloured: green what helps the crown, red what hurts it.
static func effects_bbcode(effects: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in effects.keys():
		var value: Variant = effects[key]
		var good_up := not (key in WORSE_WHEN_UP)
		match key:
			"treasury": parts.append("tesoro %s" % KDTip.signed(float(value), 0, good_up))
			"legitimacy": parts.append("legittimità %s" % KDTip.signed(float(value), 0, good_up))
			"stability": parts.append("stabilità %s" % KDTip.signed(float(value), 0, good_up))
			"prestige": parts.append("prestigio %s" % KDTip.signed(float(value), 0, good_up))
			"turbulence": parts.append("turbolenza %s" % KDTip.signed(float(value), 0, good_up))
			"trust": parts.append("fiducia %s" % KDTip.signed(float(value), 0, good_up))
			"research": parts.append("sapere %s" % KDTip.signed(float(value), 0, good_up))
			"unrest": parts.append("malcontento %s%%" % KDTip.signed(float(value) * 100.0, 0, good_up))
			"kill_people": parts.append(KDTip.colored("%d morti" % int(value), KDTip.BAD))
			"favour":
				for fid: String in (value as Dictionary).keys():
					var fd: FactionDef = Defs.get_def("factions", StringName(fid))
					parts.append("%s %s" % [(fd.display_name if fd else fid).to_lower(), KDTip.signed(float((value as Dictionary)[fid]))])
			"stock":
				for res: String in (value as Dictionary).keys():
					var rd: ResourceDef = Defs.resource(StringName(res))
					parts.append("%s %s" % [(rd.display_name if rd else res).to_lower(), KDTip.signed(float((value as Dictionary)[res]))])
			"crisis":
				parts.append(KDTip.colored("%s per %d giorni" % [(value as Dictionary).get("name", "crisi"),
					int((value as Dictionary).get("days", 0))], KDTip.BAD))
			"opinion_neighbour": parts.append("opinione di un vicino %s" % KDTip.signed(float(value)))
	return "  ·  ".join(parts)


## The same in plain words (for logs and tests).
static func _effects_text(effects: Dictionary) -> String:
	var rt := RegEx.create_from_string("\\[[^\\]]*\\]")
	return rt.sub(effects_bbcode(effects), "", true)

