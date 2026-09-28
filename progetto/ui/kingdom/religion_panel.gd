class_name ReligionPanel
extends KDSheet
## The RELIGIONE sheet (Phase 18): the faith of the crown and what it gives, how much the clergy weighs on the
## legitimacy, the law of faith in force, and the faiths of the lands — the provinces of another faith, how far
## their conversion has come and the unrest the difference brings. The faith is not the clergy: the clergy is an
## estate, and its favour, its wants, the gift of the crown and its families are on the Ceti sheet (consolidation:
## this sheet had a second meter of the same favour and a second gift button).

var _faith: Label
var _effects: VBoxContainer
var _clergy: VBoxContainer
var _law: VBoxContainer
var _lands: VBoxContainer
var _crown_only: Array[Control] = []
var _signature := ""


func build() -> void:
	section("LA FEDE")
	_faith = parchment()
	_effects = box(2)
	_crown_only.append(GovernmentPanel._bar_of(section("IL CLERO E LA CORONA")))
	_clergy = box(2)
	_crown_only.append(GovernmentPanel._bar_of(section("LA LEGGE DI FEDE")))
	_law = box(4)
	section("LE FEDI DELLE TERRE")
	_lands = box(2)


func refresh() -> void:
	if not Session.has_game() or column == null:
		return
	var session := Session.current
	var world := session.world
	var k := world.player()
	if k == null:
		return
	var religion: ReligionDef = Defs.get_def("religions", k.religion)
	_faith.text = ("%s — %s" % [religion.display_name, religion.description]) if religion else "Nessuna fede dichiarata."
	if not k.monarchy_founded:
		_faith.text += "\n\nLa comunità prega come pregavano i padri; il clero come potere del regno nascerà con la corona."
	# rebuilt when something it shows changes, and once a month for the slow work of the conversions
	var signature := "%s|%s|%d|%d|%d|%d" % [k.religion, str(k.laws), roundi(float(k.favour.get(&"clergy", 55.0))),
		roundi(k.treasury / 25.0), k.provinces.size(), world.day / 30]
	for c in _crown_only:
		c.visible = k.monarchy_founded
	_clergy.visible = k.monarchy_founded
	_law.visible = k.monarchy_founded
	if signature == _signature:
		return
	_signature = signature
	clear(_effects)
	if religion:
		for m in religion.modifiers:
			line(_effects, Modifier.label_for(m.key), m.describe(), "Effetto della fede, sempre in vigore",
				Color("#BFD9E3"))
	if k.monarchy_founded:
		_refresh_clergy(session, k)
		_refresh_law(k)
	_refresh_lands(session, k)


func _refresh_clergy(session: GameSession, k: KingdomState) -> void:
	clear(_clergy)
	var leg: Dictionary = CourtSystem.bal().get("legitimacy", {})
	var favour := float(k.favour.get(&"clergy", 55.0))
	var weight := float(leg.get("clergy_weight", 0.12)) * KingdomModifiers.stack(session, k.id).multiplier(&"legitimacy.from_clergy")
	line(_clergy, "Peso sulla legittimità", "%+.1f" % ((favour - 55.0) * weight),
		"Il favore del clero è %d. Ogni punto sopra 55 aggiunge %.2f alla legittimità verso cui la corona tende; sotto 55 ne toglie." % [
			roundi(favour), weight],
		Color("#BFE39A") if favour >= 55.0 else Color("#FFB09A"))
	if favour < float(leg.get("hostile_below", 30.0)):
		line(_clergy, "Il clero è ostile", "%d" % roundi(float(leg.get("hostile_faction", -10.0))),
			"Un potere ostile toglie legittimità finché non torna sopra %d." % roundi(float(leg.get("hostile_below", 30.0))),
			Color("#FFB09A"))
	var where := SettlementHud._label(_clergy, 13, Color(KDTheme.TEXT_LIGHT, 0.85), false)
	where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	where.custom_minimum_size = Vector2(WIDTH - 60, 0)
	where.text = "Il clero è un ceto: il suo favore, le sue richieste, il dono della corona e le sue famiglie sono nella scheda Ceti (T)."


func _refresh_law(k: KingdomState) -> void:
	clear(_law)
	for g: Dictionary in Laws.groups():
		if StringName(g["id"]) != &"faith":
			continue
		var in_force_id := StringName(k.laws.get(&"faith", &""))
		var current := "nessuna: la corona lascia la fede al clero"
		for o: Dictionary in g.get("options", []):
			if StringName(o["id"]) == in_force_id:
				current = String(o.get("name", in_force_id))
		line(_law, "In vigore", current, "", KDTheme.GOLD)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_law.add_child(row)
		for o: Dictionary in g.get("options", []):
			var option_id := StringName(o["id"])
			var btn := command_button(row, String(o.get("name", option_id)),
				EnactLawCommand.create(k.id, &"faith", option_id), GovernmentPanel._tip(o, in_force_id == option_id, -1))
			if in_force_id == option_id:
				btn.add_theme_color_override("font_disabled_color", KDTheme.GOLD)


func _refresh_lands(session: GameSession, k: KingdomState) -> void:
	clear(_lands)
	var world := session.world
	var wd := WorldData.get_instance()
	var by_faith := {}
	var others: Array = []
	for pid in k.provinces:
		var p := world.province(pid)
		if p == null:
			continue
		by_faith[p.religion] = int(by_faith.get(p.religion, 0)) + 1
		if p.religion != k.religion:
			others.append(p)
	for rid: StringName in by_faith.keys():
		var rd: ReligionDef = Defs.get_def("religions", rid)
		line(_lands, rd.display_name if rd else String(rid), "%d %s" % [by_faith[rid], "provincia" if int(by_faith[rid]) == 1 else "province"],
			"", KDTheme.GOLD if rid == k.religion else Color("#FFD79A"))
	var tolerance := KingdomModifiers.stack(session, k.id).additive(&"stability.tolerance")
	line(_lands, "Tolleranza del regno", "%+.0f" % tolerance,
		"Dalla fede, dalle leggi e dagli spiriti: ogni punto toglie un poco dell'attrito delle terre di un'altra fede.")
	if others.is_empty():
		var note := SettlementHud._label(_lands, 13, Color(KDTheme.TEXT_LIGHT, 0.75), false)
		note.text = "Tutte le terre del regno pregano come la corona."
		return
	var head := SettlementHud._label(_lands, 14, Color("#E9D8A6"), true)
	head.text = "TERRE DI UN'ALTRA FEDE"
	others.sort_custom(func(a: ProvinceState, b: ProvinceState) -> bool: return a.conversion > b.conversion)
	for p: ProvinceState in others.slice(0, 12):
		var rd: ReligionDef = Defs.get_def("religions", p.religion)
		line(_lands, "%s — %s" % [wd.provinces[p.id].name, rd.display_name if rd else String(p.religion)],
			"conversione %d%%" % roundi(clampf(p.conversion, 0.0, 1.0) * 100.0),
			"La fede della corona si fa strada anno dopo anno, più in fretta nelle terre sviluppate. Malcontento %d%%." % roundi(p.unrest * 100.0),
			Color("#FFB09A") if p.unrest > 0.4 else KDTheme.TEXT_LIGHT)
	if others.size() > 12:
		var more := SettlementHud._label(_lands, 13, Color(KDTheme.TEXT_LIGHT, 0.7), false)
		more.text = "…e altre %d." % (others.size() - 12)

