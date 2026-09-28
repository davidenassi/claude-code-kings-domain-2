class_name ArmyPanel
extends PanelContainer
## The host sheet: who can be raised in the village and at what price, and what the armies already on the road
## are made of — men, heart, bread left, who commands them and where they are going.

var _levy: VBoxContainer
var _armies: VBoxContainer
var _signature := ""
var _refresh_timer := 0.0
var _interaction: MapInteraction
var _scroll: ScrollContainer
var _col: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", KDTheme.wood_panel())
	custom_minimum_size = Vector2(500, 0)
	visible = false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 200)   # fitted to what is written (_fit), up to 560
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_scroll = scroll
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	_col = col

	# the name and the cross are the PanelHost's business, in the band of the frame; the first row starts
	# under the inner line of the frame
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	col.add_child(gap)

	KDSheet.section_in(col, "LEVA")
	_levy = VBoxContainer.new()
	_levy.add_theme_constant_override("separation", 4)
	col.add_child(_levy)
	KDSheet.section_in(col, "SCHIERE")
	_armies = VBoxContainer.new()
	_armies.add_theme_constant_override("separation", 6)
	col.add_child(_armies)


func set_interaction(interaction: MapInteraction) -> void:
	_interaction = interaction


func toggle() -> void:
	visible = not visible
	if visible:
		_signature = ""
		refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_signature = ""


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer += delta
	if _refresh_timer > 0.7:
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
	var signature := ""
	for a in world.armies:
		if a.kingdom == me.id:
			signature += "%d:%d:%d;" % [a.id, a.men(), a.regiments.size()]
	for s in world.settlements:
		if s.kingdom == me.id:
			signature += "t%d:%d;" % [s.id, s.training.size()]
	if signature != _signature:
		_signature = signature
		_rebuild(session, me)
		call_deferred("_fit")
	else:
		_update(session, me)


## A short sheet is short, like the others (Phase 18: it stood 560 pixels tall around four lines).
func _fit() -> void:
	if _scroll and _col:
		_scroll.custom_minimum_size.y = clampf(_col.get_combined_minimum_size().y, 140.0, 560.0)


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _rebuild(session: GameSession, me: KingdomState) -> void:
	var world := session.world
	_clear(_levy)
	_clear(_armies)
	var home: SettlementState = null
	for s in world.settlements:
		if s.kingdom == me.id:
			home = s
			break
	if home:
		for u in Military.units():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			_levy.add_child(row)
			var pennant := KDUi.icon_node(ArmyLayer._gonfalon_of(u), 24.0)   # the pennant the regiment will march under
			row.add_child(pennant)
			var label := SettlementHud._label(row, 14, KDTheme.TEXT_LIGHT, false)
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			label.text = "%s — %d uomini, %d armi, %d oro" % [u.display_name, u.men, u.weapons, int(u.gold)]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var btn := Button.new()
			btn.text = "Arruola"
			btn.focus_mode = Control.FOCUS_NONE
			KDTheme.button_styles(btn)
			var command := RecruitUnitCommand.create(home.id, u.id)
			var reason := command.validate(session)
			btn.disabled = reason != ""
			btn.tooltip_text = "%s\nAddestramento: %d giorni · paga %.2f oro al giorno\n%s" % [
				u.description, u.train_days, u.upkeep_gold_day, reason]
			btn.pressed.connect(func() -> void:
				Session.current.submit(RecruitUnitCommand.create(home.id, u.id))
				_signature = ""
				refresh())
			row.add_child(btn)
			label.tooltip_text = btn.tooltip_text
			label.mouse_filter = Control.MOUSE_FILTER_PASS
		for t in home.training:
			var u := Military.unit(t["unit"])
			var line := SettlementHud._label(_levy, 13, Color("#E9D8A6"), false)
			line.text = "In addestramento: %d %s — %d giorni" % [(t["people"] as PackedInt32Array).size(),
				u.display_name.to_lower() if u else "?", ceili(float(t["days_left"]))]
	for a in world.armies:
		if a.kingdom == me.id:
			_army_row(session, a)
	if _armies.get_child_count() == 0:
		var none := SettlementHud._label(_armies, 14, Color(KDTheme.TEXT_LIGHT, 0.8), false)
		none.text = "Nessuna schiera in campo."


func _army_row(session: GameSession, a: ArmyState) -> void:
	var world := session.world
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_armies.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var name_label := SettlementHud._label(head, 15, KDTheme.TEXT_LIGHT, true)
	name_label.name = "Name%d" % a.id
	name_label.text = a.name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var state := SettlementHud._label(head, 13, Color(KDTheme.TEXT_LIGHT, 0.85), false)
	state.name = "State%d" % a.id
	state.text = _state_text(world, a)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	box.add_child(buttons)
	var detail := SettlementHud._label(buttons, 13, Color(KDTheme.TEXT_LIGHT, 0.9), false)
	detail.name = "Detail%d" % a.id
	detail.text = _detail_text(world, a)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var move := Button.new()
	move.text = "Muovi"
	move.focus_mode = Control.FOCUS_NONE
	move.tooltip_text = "Poi fai clic sulla provincia dove mandarlo"
	KDTheme.button_styles(move)
	move.pressed.connect(func() -> void:
		if _interaction:
			_interaction.order_army(a.id)
		EventBus.notify("Ordini", "Indica sulla mappa dove deve andare %s." % a.name, &"army"))
	buttons.add_child(move)
	var disband := Button.new()
	disband.text = "Sciogli"
	disband.focus_mode = Control.FOCUS_NONE
	KDTheme.button_styles(disband)
	var reason := DisbandArmyCommand.create(a.id).validate(session)
	disband.disabled = reason != ""
	disband.tooltip_text = "Gli uomini tornano alle case se sono vicino a un insediamento del regno.\n%s" % reason
	disband.add_theme_color_override("font_color", Color("#E2896F"))
	disband.pressed.connect(func() -> void:
		Session.current.submit(DisbandArmyCommand.create(a.id))
		_signature = ""
		refresh())
	buttons.add_child(disband)


func _update(session: GameSession, me: KingdomState) -> void:
	var world := session.world
	for a in world.armies:
		if a.kingdom != me.id:
			continue
		var state := _armies.find_child("State%d" % a.id, true, false) as Label
		if state:
			state.text = _state_text(world, a)
		var detail := _armies.find_child("Detail%d" % a.id, true, false) as Label
		if detail:
			detail.text = _detail_text(world, a)


static func _state_text(world: WorldState, a: ArmyState) -> String:
	var g := WorldData.get_instance().province_geo(a.province)
	for b in world.battles:
		if b.attacker == a.id or b.defender == a.id:
			return "in battaglia in %s" % (g.name if g else "campo aperto")
	for s in world.sieges:
		if s.army == a.id:
			return "assedia %s (%d%%)" % [g.name if g else "?", roundi(s.progress * 100.0)]
	if not a.path.is_empty():
		var target := WorldData.get_instance().province_geo(a.path[a.path.size() - 1])
		return "in marcia verso %s" % (target.name if target else "?")
	return "ferma in %s" % (g.name if g else "?")


static func _detail_text(world: WorldState, a: ArmyState) -> String:
	var parts := PackedStringArray()
	for r in a.regiments:
		var u := Military.unit(r["unit"])
		parts.append("%d %s" % [int(r["men"]), u.display_name.to_lower() if u else "?"])
	var commander := world.character(a.commander)
	var line := "%s · morale %d · viveri %d giorni" % [", ".join(parts), roundi(a.morale()), floori(a.supplies)]
	if commander:
		line += " · comanda %s (guerra %d)" % [commander.name, commander.skill(&"guerra")]
	if a.unpaid_days > 0:
		line += " · non pagati da %d giorni" % a.unpaid_days
	return line

