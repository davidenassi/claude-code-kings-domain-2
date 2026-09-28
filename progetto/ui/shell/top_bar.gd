class_name TopBar
extends Control
## The band across the top of the screen (A) and the clock under its right end (C). Everything here is read at
## a glance and never needs a click; the tooltips tell where each number comes from.
##
## Phase 18 HUD review: one continuous band of dark wood — the arms of the realm on the left, then the goods
## with big icons, the number and how much it moved in the month that closed, then on the right the great
## measures of the crown with their names. Under its right end a compact block with the date, the speed of
## time, the map button and the menu of the game.

signal map_requested
signal menu_requested

const BAND_HEIGHT := 76.0
const RESOURCES: Array = [
	# [key, icon, tooltip title]
	[&"gold", &"gold", "Oro della corona"],
	[&"food", &"bread", "Cibo"],
	[&"wood", &"wood", "Legname"],
	[&"stone", &"stone", "Pietra"],
	[&"iron", &"iron", "Ferro"],
	[&"people", &"people", "Abitanti"],
	[&"soldiers", &"war", "Uomini in armi"],
]
const MEASURES: Array = [
	# [key, icon, name under the icon]
	[&"lily", &"lily", "Prestigio"],
	[&"crown", &"crown", "Legittimità"],
	[&"shield", &"shield", "Stabilità"],
	[&"consent", &"consent", "Fiducia"],
	# before the crown (Phase 15): the community's own measures take the place of the crown's
	[&"justice", &"justice", "Autorità"],
	[&"house_arms", &"house_arms", "Famiglie"],
]
## Why goods enter or leave the stores (SettlementState.flow), in the words of the tooltips.
const FLOW_REASONS := {
	&"work": "Lavoro", &"food": "Pasti", &"build": "Cantieri", &"trade": "Mercanti", &"army": "Armi all'esercito",
	&"event": "Eventi", &"other": "Altro",
}
const TIP_EVERY := 1.0

var _values: Dictionary = {}     # key -> Label (the number)
var _deltas: Dictionary = {}     # key -> Label (how much it moved in the last month)
var _measures: Dictionary = {}   # key -> Label
var _boxes: Dictionary = {}      # key -> KDTip (the slot, that owns the tooltip)
var _rules: Dictionary = {}      # key -> the rule before the slot (hidden with it)
var _arms: ArmsView
var _date: Label
var _speed_buttons: Array[Button] = []
var _refresh_timer := 0.0
var _tip_timer := TIP_EVERY
## The measures at the start of the last two months, to tell which way they go: [older, newer].
var _snapshots: Array[Dictionary] = []


func _ready() -> void:
	# the band covers the whole viewport so its corners are really the corners of the screen; it lets every
	# click through, the map is underneath
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_band()
	_build_clock()
	EventBus.month_passed.connect(func(_day: int) -> void: _snapshot())
	refresh()


# --- A: the band ------------------------------------------------------------------------------------------

func _build_band() -> void:
	var band := PanelContainer.new()
	band.name = "Band"
	band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	band.offset_bottom = BAND_HEIGHT
	var style := KDTheme.dark_panel().duplicate() as StyleBox
	if style is StyleBoxTexture:
		# inside the painted rim: the names of the measures touched it
		(style as StyleBoxTexture).content_margin_top = 9
		(style as StyleBoxTexture).content_margin_bottom = 9
	band.add_theme_stylebox_override("panel", style)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(row)
	# the arms of the realm open the band: who we are, before what we have
	_arms = ArmsView.new()
	_arms.custom_minimum_size = Vector2(44, 52)
	_arms.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_arms.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(_arms)
	row.add_child(KDTheme.slot_rule(40))
	for entry: Array in RESOURCES:
		_values[entry[0]] = _slot(row, entry[0], entry[1], String(entry[2]))
		row.add_child(KDTheme.slot_rule(36))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spring)
	for i in MEASURES.size():
		var entry: Array = MEASURES[i]
		if i > 0:
			var rule := KDTheme.slot_rule(36)
			row.add_child(rule)
			_rules[entry[0]] = rule
		_measures[entry[0]] = _measure(row, entry[0], entry[1], String(entry[2]))


## One good: the icon, the number, and under it how much it moved in the month that closed.
func _slot(parent: Control, key: StringName, icon: StringName, tip: String) -> Label:
	var box := KDTip.new()
	box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	box.tooltip_text = KDTip.head(tip)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.custom_minimum_size = Vector2(142, 0)
	parent.add_child(box)
	_boxes[key] = box
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	# the icon weighs more than the number: it is what the eye looks for
	var mark := KDUi.icon_node(icon, 44.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(mark)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(col)
	var value := SettlementHud._label(col, 23, Color("#FFF4DC"), true)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow(value)
	var delta := SettlementHud._label(col, 15, Color("#B8F07E"), true)
	_shadow(delta)
	delta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deltas[key] = delta
	return value


## One measure of the crown: the icon, its name small, the number big.
func _measure(parent: Control, key: StringName, icon: StringName, name_text: String) -> Label:
	var box := KDTip.new()
	box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	box.tooltip_text = KDTip.head(name_text)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(box)
	_boxes[key] = box
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	var mark := KDUi.icon_node(icon, 42.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(mark)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(col)
	var title := SettlementHud._label(col, 14, Color(KDTheme.TEXT_LIGHT, 0.88), false)
	title.text = name_text
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow(title)
	var value := SettlementHud._label(col, 23, Color("#FFF4DC"), true)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow(value)
	return value


## A dark shadow under the letters: more contrast on the wood without making them bolder.
static func _shadow(label: Label) -> void:
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)


# --- C: the clock -----------------------------------------------------------------------------------------

func _build_clock() -> void:
	var anchor := MarginContainer.new()
	anchor.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	anchor.add_theme_constant_override("margin_right", 10)
	anchor.add_theme_constant_override("margin_top", int(BAND_HEIGHT) + 6)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	var clock_box := PanelContainer.new()
	clock_box.name = "Clock"
	clock_box.add_theme_stylebox_override("panel", KDTheme.dark_panel())
	clock_box.custom_minimum_size = Vector2(390, 0)
	anchor.add_child(clock_box)
	var clock_row := HBoxContainer.new()
	clock_row.add_theme_constant_override("separation", 6)
	clock_box.add_child(clock_row)
	_date = SettlementHud._label(clock_row, 17, KDTheme.GOLD, true)
	_date.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_date.custom_minimum_size = Vector2(150, 0)
	for i in 6:
		var btn := Button.new()
		if i == 0:
			btn.icon = pause_icon()   # two drawn bars, not a glyph the font may not have
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			btn.text = str(i)
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(32, 32)
		KDTheme.button_styles(btn)
		btn.tooltip_text = "Pausa (Spazio)" if i == 0 else "Velocità %d" % i
		var index := i
		btn.pressed.connect(func() -> void:
			if Session.has_game():
				Session.current.clock.set_speed(index))
		clock_row.add_child(btn)
		_speed_buttons.append(btn)
	clock_row.add_child(KDTheme.slot_rule(26))
	var map_btn := Button.new()
	map_btn.icon = KDUi.icon(&"pin_capital")
	map_btn.expand_icon = true
	map_btn.add_theme_constant_override("icon_max_width", 20)
	map_btn.focus_mode = Control.FOCUS_NONE
	map_btn.custom_minimum_size = Vector2(36, 32)
	map_btn.tooltip_text = "Cambia mappa (M)"
	KDTheme.button_styles(map_btn)
	map_btn.pressed.connect(func() -> void: map_requested.emit())
	clock_row.add_child(map_btn)
	var menu_btn := Button.new()
	menu_btn.icon = KDTheme.menu_texture()
	menu_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.custom_minimum_size = Vector2(36, 32)
	menu_btn.tooltip_text = "Menu del gioco (Esc)"
	KDTheme.button_styles(menu_btn)
	menu_btn.pressed.connect(func() -> void: menu_requested.emit())
	clock_row.add_child(menu_btn)


static var _pause_tex: Texture2D = null


static func pause_icon() -> Texture2D:
	if _pause_tex:
		return _pause_tex
	var img := Image.create(12, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(1, 1, 3, 12), Color.WHITE)
	img.fill_rect(Rect2i(8, 1, 3, 12), Color.WHITE)
	_pause_tex = ImageTexture.create_from_image(img)
	return _pause_tex


## How far down the screen the band and the clock reach (the columns start under it).
static func bottom_edge() -> float:
	return BAND_HEIGHT + 6.0 + 48.0


# --- keeping it true --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_refresh_timer += delta
	_tip_timer += delta
	if _refresh_timer > 0.25:
		_refresh_timer = 0.0
		refresh()


func refresh() -> void:
	if not Session.has_game():
		return
	var session := Session.current
	var world := session.world
	var k := world.player()
	if k == null:
		return
	if _arms.arms != k.coat_of_arms:
		_arms.arms = k.coat_of_arms
	_arms.tooltip_text = k.name
	var settlement := SettlementHud.player_settlement()
	var people := world.people_of(settlement.id).size() if settlement else 0
	_write(_values, &"gold", _thousands(roundi(k.treasury)), Color("#EFC96F") if k.treasury >= 0.0 else Color("#FF9A8A"))
	if not k.last_balance.is_empty():
		_delta(&"gold", float(k.last_balance.get("total", 0.0)))
	_write(_values, &"people", _thousands(people))
	for res: StringName in [&"wood", &"stone", &"iron"]:
		_write(_values, res, _thousands(settlement.amount(res) if settlement else 0))
		_delta(res, float(_month_balance(settlement, [res])) if settlement else 0.0, settlement == null or settlement.last_flow.is_empty())
	var food := (settlement.amount(&"grain") + settlement.amount(&"bread")) if settlement else 0
	_write(_values, &"food", _thousands(food))
	_delta(&"food", float(_month_balance(settlement, [&"grain", &"bread"])) if settlement else 0.0,
		settlement == null or settlement.last_flow.is_empty())
	var soldiers := soldiers_of(world, k)
	_write(_values, &"soldiers", _thousands(soldiers))
	_delta(&"soldiers", 0.0, true)
	if _snapshots.size() >= 2:
		# the month that closed: from the start of the one before to the start of this one
		_delta(&"people", float(int(_snapshots[-1].get("people", 0)) - int(_snapshots[-2].get("people", 0))))
	else:
		_delta(&"people", 0.0, true)
	# the crown's measures exist only once there is a crown; before, the community's own
	var crowned := k.monarchy_founded
	for key: StringName in [&"crown", &"shield", &"lily"]:
		_show(key, crowned)
	for key: StringName in [&"justice", &"house_arms"]:
		_show(key, not crowned)
	if not crowned:
		_write(_measures, &"justice", "%d" % roundi(k.authority), _tone(k.authority))
		var families := FamilySystem.living_families(world, settlement).size() if settlement else 0
		_write(_measures, &"house_arms", "%d" % families)
	_write(_measures, &"crown", "%d" % roundi(k.legitimacy), _tone(k.legitimacy))
	_write(_measures, &"shield", "%d" % roundi(k.stability), _tone(k.stability))
	_write(_measures, &"lily", "%d" % roundi(k.prestige), KDTheme.TEXT_LIGHT)
	_write(_measures, &"consent", "%d%%" % roundi(settlement.trust if settlement else 0.0),
		_tone(settlement.trust if settlement else 0.0))
	if settlement:
		_food_colour(session, settlement)
	var d := session.calendar.date_of(world.day)
	_date.text = "%s · %s" % [session.date_text(), session.calendar.season_name(int(d["season"]))]
	for i in _speed_buttons.size():
		var on := (session.clock.is_paused() and i == 0) or (not session.clock.is_paused() and session.clock.speed_index == i)
		_speed_buttons[i].add_theme_color_override("font_color", KDTheme.GOLD if on else KDTheme.TEXT_LIGHT)
		_speed_buttons[i].add_theme_color_override("icon_normal_color", KDTheme.GOLD if on else KDTheme.TEXT_LIGHT)
	if _snapshots.is_empty():
		_snapshot()
	# the tooltips are longer to write and change slowly: once a second is enough
	if _tip_timer >= TIP_EVERY:
		_tip_timer = 0.0
		write_tooltips(session, settlement)
		_pin_tip_for_screenshot()


## Men under arms: the regiments of the crown in the field and those still training in the villages.
static func soldiers_of(world: WorldState, k: KingdomState) -> int:
	var n := 0
	for a in world.armies:
		if a.kingdom == k.id:
			n += a.men()
	for s in world.settlements:
		if s.kingdom == k.id:
			for t in s.training:
				n += (t["people"] as PackedInt32Array).size()
	return n


## What the stores of these goods gained or lost in the month that closed (the register of the stores).
static func _month_balance(s: SettlementState, goods: Array) -> int:
	var total := 0
	for res: StringName in goods:
		var d: Dictionary = s.last_flow.get(res, {})
		for why: StringName in d.keys():
			total += int(d[why])
	return total


## 12500 -> "12.500": the thousands the Italian way, easier to read at a glance.
static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _delta(key: StringName, v: float, hidden: bool = false) -> void:
	var label: Label = _deltas.get(key)
	if label == null:
		return
	label.visible = not hidden
	if hidden:
		return
	var n := roundi(v)
	label.visible = n != 0   # an unchanged good says nothing: fewer small words on the band
	label.text = ("+%s" % _thousands(n)) if n > 0 else _thousands(n).replace("-", "−")
	label.add_theme_color_override("font_color", Color("#B8F07E") if n > 0 else (Color("#FF8C6A") if n < 0 else Color(KDTheme.TEXT_LIGHT, 0.6)))


## Writes every tooltip of the bar (public so the tests and the audit screenshots can read them).
func write_tooltips(session: GameSession, settlement: SettlementState) -> void:
	var world := session.world
	var k := world.player()
	if k == null:
		return
	_tip(&"gold", gold_tip(session, k))
	if settlement:
		_tip(&"people", people_tip(session, settlement))
		for res: StringName in [&"wood", &"stone", &"iron"]:
			_tip(res, goods_tip(session, settlement, res))
		_tip(&"food", food_tip(session, settlement))
		_tip(&"consent", consent_tip(settlement))
	_tip(&"soldiers", soldiers_tip(world, k))
	if k.monarchy_founded:
		_tip(&"crown", measure_tip(k, "legitimacy", "Legittimità", k.legitimacy,
			"Quanto il regno crede che la corona spetti a chi la porta."))
		_tip(&"shield", measure_tip(k, "stability", "Stabilità", k.stability,
			"La tenuta interna del regno: ordine pubblico, istituzioni che funzionano, rischio di crisi. Sotto 30 le tasse si perdono e i poteri alzano la testa; sotto 18 le campagne si ribellano."))
		_tip(&"lily", prestige_tip(k))
	elif settlement:
		_tip(&"justice", authority_tip(world, k))
		var families := FamilySystem.living_families(world, settlement).size()
		var rooted := FamilySystem.consolidated_families(world, settlement).size()
		_tip(&"house_arms", KDTip.head("Famiglie della comunità") + KDTip.rows([
			["Famiglie", "%d" % families], ["Radicate (almeno tre membri)", "%d" % rooted]])
			+ KDTip.note("Le famiglie radicate reggono la comunità: da loro verrà la casa che porterà la corona. Le famiglie, i loro gruppi e la scelta della casa reale sono nella scheda Ceti (T)."))


# --- the tooltips ----------------------------------------------------------------------------------------

## A good in the stores: how much there is, room left, and what came in and went out last month and why.
static func goods_tip(session: GameSession, s: SettlementState, res: StringName) -> String:
	var rd := Defs.resource(res)
	var name := rd.display_name if rd else String(res)
	var out := KDTip.head(name)
	var line := "%d in deposito a %s" % [s.amount(res), s.name]
	if rd and rd.uses_storage:
		line += " · posto per altri %d" % s.space_for(session.world, res)
	out += KDTip.sub(line)
	out += _flow_rows(session, s, res)
	return out


static func _flow_rows(session: GameSession, s: SettlementState, res: StringName) -> String:
	var out := ""
	var last: Dictionary = s.last_flow.get(res, {})
	var now: Dictionary = s.flow.get(res, {})
	var day := int(session.calendar.date_of(session.world.day)["day"])
	if not last.is_empty():
		out += "\n" + KDTip.sub("Il mese scorso")
		out += KDTip.rows(_reason_rows(last))
	if not now.is_empty():
		var total := 0
		for why: StringName in now.keys():
			total += int(now[why])
		if last.is_empty():
			out += "\n" + KDTip.sub("Questo mese (%d giorni)" % day)
			out += KDTip.rows(_reason_rows(now))
		else:
			out += KDTip.rows([["Questo mese (%d giorni)" % day, KDTip.signed(total)]])
	if last.is_empty() and now.is_empty():
		out += KDTip.note("Nessun movimento da quando il mese è cominciato.")
	return out


static func _reason_rows(d: Dictionary) -> Array:
	var rows: Array = []
	var total := 0
	var keys := d.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return int(d[a]) > int(d[b]))
	for why: StringName in keys:
		var n := int(d[why])
		if n == 0:
			continue
		total += n
		rows.append([String(FLOW_REASONS.get(why, why)), KDTip.signed(n)])
	rows.append(["=Saldo", KDTip.signed(total)])
	return rows


## Food: grain and bread in the stores, what moved last month, and above all whether it reaches the harvest.
static func food_tip(session: GameSession, s: SettlementState) -> String:
	var out := KDTip.head("Cibo")
	out += KDTip.sub("Grano %d · pane %d in deposito a %s · posto per altri %d" % [s.amount(&"grain"), s.amount(&"bread"),
		s.name, s.space_for(session.world, &"grain")])
	out += _flow_rows(session, s, &"grain").replace("Il mese scorso", "Grano, il mese scorso")
	if not (s.last_flow.get(&"bread", {}) as Dictionary).is_empty():
		out += "\n" + KDTip.sub("Pane, il mese scorso") + KDTip.rows(_reason_rows(s.last_flow[&"bread"]))
	var o := PopulationSystem.harvest_outlook(session, s)
	var lines := PackedStringArray()
	if s.amount(&"bread") > 0:
		lines.append("Pane in deposito: %d" % s.amount(&"bread"))
	lines.append("Il cibo in deposito basta per %d giorni." % roundi(float(o["food_days"])))
	if int(o["to_harvest"]) <= 0:
		lines.append("È il mese del raccolto.")
	else:
		lines.append("Il raccolto è fra %d giorni." % int(o["to_harvest"]))
	out += "\n" + "\n".join(lines) + "\n"
	if bool(o["short"]):
		out += KDTip.colored("Non basta: il cibo porta al raccolto %d persone su %d, le altre se ne andranno. %s" % [
			int(o["carried"]), int(o["people"]),
			"I depositi non tengono un anno di cibo: il raccolto va perso, servono granai." if bool(o["needs_granary"])
			else "Servono campi."], KDTip.BAD) + "\n"
	elif bool(o["needs_granary"]):
		out += KDTip.colored("I depositi tengono solo %d giorni di cibo, meno di un anno: un granaio salva il raccolto."
			% roundi(float(o["store_days"])), KDTip.WARN) + "\n"
	return out


func _food_colour(session: GameSession, settlement: SettlementState) -> void:
	var label: Label = _values.get(&"food")
	if label == null:
		return
	var o := PopulationSystem.harvest_outlook(session, settlement)
	if bool(o["short"]):
		label.add_theme_color_override("font_color", Color("#FF9A8A") if int(o["carried"]) * 2 < int(o["people"]) else Color("#FFD79A"))


static func gold_tip(session: GameSession, k: KingdomState) -> String:
	var out := KDTip.head("Oro della corona")
	out += KDTip.sub("%d nelle casse%s" % [roundi(k.treasury), " — in debito" if k.treasury < 0.0 else ""])
	var bl: Dictionary = k.last_balance
	if bl.is_empty():
		out += KDTip.note("Il primo mese non è ancora chiuso.")
	else:
		out += "\n" + KDTip.sub("Il mese scorso")
		var rows: Array = []
		for entry: Array in [["taxes", "Tasse degli abitanti", 1.0], ["provinces", "Rendite delle province", 1.0],
				["trade", "Mercanti", 1.0], ["imports", "Acquisti", -1.0], ["wages", "Salari", -1.0],
				["upkeep", "Manutenzione degli edifici", -1.0]]:
			var v := float(bl.get(entry[0], 0.0)) * float(entry[2])
			if absf(v) >= 0.05:
				rows.append([entry[1], KDTip.signed(v, 1)])
		rows.append(["=Saldo", KDTip.signed(float(bl.get("total", 0.0)), 1)])
		out += KDTip.rows(rows)
	var pay := 0.0
	for a in session.world.armies:
		if a.kingdom == k.id:
			pay += Military.upkeep_per_day(a)
	if pay > 0.0:
		out += KDTip.rows([["Soldo degli eserciti (al mese)", KDTip.signed(-pay * session.calendar.days_per_month, 1)]])
	return out


static func people_tip(session: GameSession, s: SettlementState) -> String:
	var world := session.world
	var people := world.people_of(s.id)
	var idle := 0
	for p in people:
		if p.job == &"idle":
			idle += 1
	var out := KDTip.head("Abitanti di %s" % s.name)
	out += KDTip.sub(s.tier_name(people.size()))
	var rows: Array = [["Persone", "%d" % people.size()],
		["Famiglie", "%d" % FamilySystem.living_families(world, s).size()],
		["Letti liberi", "%d" % PopulationSystem.free_beds(world, s)],
		["Senza lavoro", "%d" % idle]]
	if s.left_this_year > 0:
		rows.append(["Partiti quest'anno", KDTip.colored("%d" % s.left_this_year, KDTip.BAD)])
	out += KDTip.rows(rows)
	var k := world.kingdom(s.kingdom)
	if k and k.monarchy_founded and k.provinces.size() > 1:
		var realm := 0
		for pid in k.provinces:
			var p := world.province(pid)
			if p:
				realm += p.population
		out += KDTip.note("Nel regno: %d abitanti in %d province." % [realm, k.provinces.size()])
	return out


static func soldiers_tip(world: WorldState, k: KingdomState) -> String:
	var out := KDTip.head("Uomini in armi")
	var rows: Array = []
	for a in world.armies:
		if a.kingdom == k.id:
			rows.append([a.name, "%d" % a.men()])
	for s in world.settlements:
		if s.kingdom == k.id:
			for t in s.training:
				var u := Military.unit(t["unit"])
				rows.append(["In addestramento: %s" % (u.display_name.to_lower() if u else "?"), "%d" % (t["people"] as PackedInt32Array).size()])
	if rows.is_empty():
		return out + KDTip.note("Nessuno: le schiere si arruolano nella scheda Esercito, con armi nei depositi e oro nelle casse.")
	return out + KDTip.rows(rows)


static func knowledge_tip(session: GameSession, k: KingdomState) -> String:
	return KDTip.head("Punti di sapere") + KDTip.rows([["In serbo", "%d" % roundi(k.research)],
		["Ogni mese", KDTip.signed(ResearchSystem.points_per_month(session, k), 1)]]) \
		+ KDTip.note("Crescono con lo sviluppo delle province, gli edifici e il governo del sovrano; si spendono nella scheda Ricerca.")


static func consent_tip(s: SettlementState) -> String:
	var out := KDTip.head("Fiducia degli abitanti di %s" % s.name)
	var base := float(PopulationSystem.bal()["trust"].get("base", 50.0))
	var rows: Array = [["Base", "%d" % roundi(base)]]
	var target := base
	var keys := s.trust_parts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float(s.trust_parts[a]) > float(s.trust_parts[b]))
	for key: String in keys:
		var v := float(s.trust_parts[key])
		target += v
		if absf(v) >= 0.5:
			rows.append([key, KDTip.signed(v)])
	rows.append(["=Verso", "%d" % roundi(clampf(target, 0.0, 100.0))])
	out += KDTip.rows(rows)
	return out + KDTip.note("Sotto 30 la gente parte e i poteri si agitano; sopra 60 le famiglie crescono.")


## Legitimacy or order: the reasons that push it and the value it moves towards, and how it moved in a month.
func measure_tip(k: KingdomState, key: String, title: String, value: float, what: String) -> String:
	var out := KDTip.head("%s %d" % [title, roundi(value)])
	out += KDTip.note(what)
	var parts: Dictionary = k.measure_parts.get(key, {})
	if not parts.is_empty():
		var rows: Array = []
		for label: String in parts.keys():
			if label.begins_with("_"):
				continue
			var v := float(parts[label])
			if label == "Base":
				rows.append([label, "%d" % roundi(v)])
			elif absf(v) >= 0.5:
				rows.append([label, KDTip.signed(v)])
		rows.append(["=Verso", "%d" % roundi(float(parts.get("_target", value)))])
		out += KDTip.rows(rows)
	out += _trend(key, value)
	return out


func prestige_tip(k: KingdomState) -> String:
	var out := KDTip.head("Prestigio %d" % roundi(k.prestige))
	out += KDTip.note("Quello che il regno è e quello che ha fatto. Si avvicina a 100 senza toccarlo: un regno grande lotta per ogni punto.")
	var parts: Dictionary = k.measure_parts.get("prestige", {})
	var rows: Array = []
	for label: String in parts.keys():
		if absf(float(parts[label])) >= 0.5:
			rows.append([label, KDTip.signed(float(parts[label]))])
	out += KDTip.rows(rows)
	return out + _trend("prestige", k.prestige)


static func authority_tip(world: WorldState, k: KingdomState) -> String:
	var parts := FamilySystem.authority_parts(world, k)
	var out := KDTip.head("Autorità della comunità %d" % roundi(k.authority))
	out += KDTip.note("La capacità di decidere insieme: con abbastanza autorità e una famiglia forte, la comunità può darsi una corona.")
	var rows: Array = []
	for key: String in parts.keys():
		if not key.begins_with("_") and absf(float(parts[key])) >= 0.5:
			rows.append([key, KDTip.signed(float(parts[key]))])
	rows.append(["=Verso", "%d" % roundi(float(parts.get("_target", 0.0)))])
	return out + KDTip.rows(rows)


func _snapshot() -> void:
	if not Session.has_game() or Session.current.world.player() == null:
		return
	var k := Session.current.world.player()
	var home := SettlementHud.player_settlement()
	_snapshots.append({"legitimacy": k.legitimacy, "stability": k.stability, "prestige": k.prestige,
		"people": Session.current.world.people_of(home.id).size() if home else 0})
	while _snapshots.size() > 2:
		_snapshots.pop_front()


func _trend(key: String, value: float) -> String:
	if _snapshots.is_empty():
		return ""
	var from := float(_snapshots[0].get(key, value))
	var change := value - from
	var span := "negli ultimi due mesi" if _snapshots.size() >= 2 else "da inizio mese"
	return KDTip.rows([["Andamento %s" % span, KDTip.signed(change)]])


# --- small helpers ---------------------------------------------------------------------------------------

var _pinned: Node = null


## --kd-tip=<pill>: the tooltip of a pill drawn open on the screen, for the screenshots of the audit.
func _pin_tip_for_screenshot() -> void:
	var key := StringName(String(BootArgs.parse().get("tip", "")))
	if key == &"" or not _boxes.has(key):
		return
	if _pinned:
		_pinned.queue_free()
	# above everything, like the real tooltip, and dressed like it (the theme of the root does not reach
	# through a CanvasLayer)
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", KDTheme.project_theme().get_stylebox("panel", "TooltipPanel"))
	frame.add_child(KDTip.rich(tip_of(key)))
	layer.add_child(frame)
	var box := _boxes[key] as Control
	frame.position = box.global_position + Vector2(0, box.size.y + 6)
	frame.position.x = minf(frame.position.x, get_viewport_rect().size.x - KDTip.WIDTH - 60.0)
	_pinned = layer

static func _tone(value: float) -> Color:
	if value >= 55.0:
		return Color("#BFE39A")
	if value >= 32.0:
		return Color("#FFD79A")
	return Color("#FF9A8A")


func _write(where: Dictionary, key: StringName, text: String, color: Color = KDTheme.TEXT_LIGHT) -> void:
	var label: Label = where.get(key)
	if label == null:
		return
	label.text = text
	label.add_theme_color_override("font_color", color)


## Shows or hides one of the measures (and the rule before it).
func _show(key: StringName, on: bool) -> void:
	var box: Control = _boxes.get(key)
	if box:
		box.visible = on
	var rule: Control = _rules.get(key)
	if rule:
		rule.visible = on


func _tip(key: StringName, bbcode: String) -> void:
	var box: Control = _boxes.get(key)
	if box:
		box.tooltip_text = bbcode


## The tooltip currently written on a pill (for the tests).
func tip_of(key: StringName) -> String:
	var box: Control = _boxes.get(key)
	return box.tooltip_text if box else ""

