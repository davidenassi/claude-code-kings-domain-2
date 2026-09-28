class_name DiplomacyPanel
extends PanelContainer
## The table of the crowns: who is on it, what they think of us and why, what we have signed with them,
## and what we can offer or demand today. The ambassadors waiting for an answer sit at the top.

var _offers: VBoxContainer
var _rows: VBoxContainer
var _signature := ""
var _refresh_timer := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", KDTheme.wood_panel())
	custom_minimum_size = Vector2(560, 0)
	visible = false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	# the name of the sheet lives in the painted band now: keep the first row clear of the inner frame line
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	col.add_child(gap)

	# the name and the cross are the PanelHost's business, in the band of the frame

	_offers = VBoxContainer.new()
	_offers.add_theme_constant_override("separation", 4)
	col.add_child(_offers)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	col.add_child(_rows)


func toggle() -> void:
	visible = not visible
	if visible:
		_signature = ""
		refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer += delta
	if _refresh_timer > 1.0:
		_refresh_timer = 0.0
		refresh()


func refresh() -> void:
	if not Session.has_game():
		return
	var session := Session.current
	var world := session.world
	var me := world.player()
	if me == null:
		return
	var signature := "%d|%d|" % [world.offers.size(), world.kingdoms.size()]
	for k in world.kingdoms:
		if k.id == me.id or not k.alive or k.provinces.is_empty():
			continue
		var r := Diplomacy.relation(world, me.id, k.id)
		signature += "%d:%s:%s:%d;" % [k.id, ",".join(PackedStringArray(r.pacts.keys().map(func(p: StringName) -> String: return String(p)))),
			"w" if r.at_war else ("t" if r.truce_until > world.day else "-"), 1 if r.married else 0]
	if signature != _signature:
		_signature = signature
		_rebuild(session, me)
	else:
		_update_opinions(session, me)


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _rebuild(session: GameSession, me: KingdomState) -> void:
	var world := session.world
	_clear(_offers)
	_clear(_rows)
	for offer: Dictionary in world.offers:
		var sheet := PanelContainer.new()
		sheet.add_theme_stylebox_override("panel", KDTheme.parchment_panel())
		_offers.add_child(sheet)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		sheet.add_child(line)
		var text := Label.new()
		text.add_theme_font_override("font", KDFonts.serif())
		text.add_theme_font_size_override("font_size", 14)
		text.add_theme_color_override("font_color", KDTheme.INK)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(330, 0)
		text.text = String(offer["text"])
		line.add_child(text)
		for entry: Array in [["Accetta", true], ["Rifiuta", false]]:
			var btn := Button.new()
			btn.text = String(entry[0])
			btn.focus_mode = Control.FOCUS_NONE
			KDTheme.button_styles(btn)
			var offer_id := int(offer["id"])
			var accept := bool(entry[1])
			var reason := AnswerOfferCommand.create(offer_id, accept).validate(session)
			btn.disabled = reason != ""
			btn.tooltip_text = reason
			btn.pressed.connect(func() -> void:
				Session.current.submit(AnswerOfferCommand.create(offer_id, accept))
				_signature = ""
				refresh())
			line.add_child(btn)

	var others: Array[KingdomState] = []
	for k in world.kingdoms:
		if k.id != me.id and k.alive and not k.provinces.is_empty():
			others.append(k)
	others.sort_custom(func(x: KingdomState, y: KingdomState) -> bool:
		return Diplomacy.opinion(world, me.id, x.id) > Diplomacy.opinion(world, me.id, y.id))
	for k in others:
		_realm_row(session, me, k)


func _realm_row(session: GameSession, me: KingdomState, k: KingdomState) -> void:
	var world := session.world
	var r := Diplomacy.relation(world, me.id, k.id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_rows.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var arms := ArmsView.new()
	arms.arms = k.coat_of_arms
	arms.custom_minimum_size = Vector2(22, 26)
	head.add_child(arms)
	var name_label := SettlementHud._label(head, 15, KDTheme.TEXT_LIGHT, true)
	name_label.text = k.name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var state := SettlementHud._label(head, 13, Color(KDTheme.TEXT_LIGHT, 0.85), false)
	state.text = _state_text(world, r)
	var opinion_label := SettlementHud._label(head, 15, KDTheme.GOLD, true)
	opinion_label.name = "Opinion%d" % k.id
	opinion_label.custom_minimum_size = Vector2(44, 0)
	opinion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_set_opinion(opinion_label, r.opinion)
	var tip := PackedStringArray(["%s — %s" % [DiplomacyAi.trait_line(world, k.id), k.house]])
	for part: Dictionary in Diplomacy.opinion_breakdown(world, r):
		tip.append("%s %+.0f" % [part["label"], part["value"]])
	head.tooltip_text = "\n".join(tip)
	name_label.tooltip_text = head.tooltip_text
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	opinion_label.tooltip_text = head.tooltip_text
	opinion_label.mouse_filter = Control.MOUSE_FILTER_PASS

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	box.add_child(actions)
	for pact_id: StringName in [&"non_aggression", &"trade", &"alliance", &"tribute", &"vassalage"]:
		if r.has_pact(pact_id):
			_action(session, actions, String(Diplomacy.pact(pact_id).get("name", pact_id)),
				BreakPactCommand.create(me.id, k.id, pact_id), "Rompi il patto (la parola della corona vale meno)", true)
		else:
			_action(session, actions, String(Diplomacy.pact(pact_id).get("name", pact_id)),
				ProposePactCommand.create(me.id, k.id, pact_id), String(Diplomacy.pact(pact_id).get("description", "")), false)
	if not r.married:
		_action(session, actions, "Nozze", ArrangeMarriageCommand.create(me.id, k.id),
			String((Diplomacy.data().get("marriage", {}) as Dictionary).get("description", "")), false)
	if r.at_war:
		_action(session, actions, "Pace", MakePeaceCommand.create(me.id, k.id), "Chiedi la pace bianca", false)
		var held := War.occupied_provinces(world, me.id, k.id)
		if not held.is_empty():
			_action(session, actions, "Pace con %d province" % held.size(),
				MakePeaceCommand.create(me.id, k.id, held),
				"Chiudi la guerra tenendo le province che occupi", false)
	else:
		_action(session, actions, "Guerra", DeclareWarCommand.create(me.id, k.id), "Dichiara guerra", true)


func _action(session: GameSession, parent: Control, text: String, command: Command, tip: String, danger: bool) -> void:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	KDTheme.button_styles(btn)
	var reason := command.validate(session)
	btn.disabled = reason != ""
	btn.tooltip_text = tip if reason == "" else "%s\n%s" % [tip, reason]
	if danger:
		btn.add_theme_color_override("font_color", Color("#E2896F"))
	btn.pressed.connect(func() -> void:
		var result := Session.current.submit(command)
		if result.success and result.data.has("accepted") and not bool(result.data["accepted"]):
			EventBus.notify("Rifiuto", String(result.data.get("reason", "")), &"diplomacy")
		_signature = ""
		refresh())
	parent.add_child(btn)


func _update_opinions(session: GameSession, me: KingdomState) -> void:
	var world := session.world
	for k in world.kingdoms:
		if k.id == me.id:
			continue
		var label := _rows.find_child("Opinion%d" % k.id, true, false) as Label
		if label:
			_set_opinion(label, Diplomacy.opinion(world, me.id, k.id))


static func _set_opinion(label: Label, value: float) -> void:
	label.text = "%+d" % roundi(value)
	label.add_theme_color_override("font_color", Color("#E2896F").lerp(Color("#BFE39A"), clampf((value + 60.0) / 120.0, 0.0, 1.0)))


static func _state_text(world: WorldState, r: RelationState) -> String:
	if r.at_war:
		return "in guerra"
	var parts := PackedStringArray()
	for pact_id: StringName in r.pacts.keys():
		parts.append(String(Diplomacy.pact(pact_id).get("name", pact_id)).to_lower())
	if r.married:
		parts.append("parenti")
	if r.truce_until > world.day:
		parts.append("tregua")
	return " · ".join(parts) if parts.size() > 0 else "nessun accordo"

