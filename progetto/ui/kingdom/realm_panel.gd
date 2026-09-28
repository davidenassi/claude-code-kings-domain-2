class_name RealmPanel
extends KDSheet
## The REGNO sheet: who you are (house, culture, religion), the royal house, the crises passing over the realm,
## what your land made of you (the national spirits), what you are aiming at (the goals of the campaign) and, folded,
## the exact formula of the realm — every modifier with the source it comes from (level 3: opened on request).
##
## Before the crown it is LA MIA COMUNITÀ: the founders, the authority, the trust, and the conditions of the kingdom
## (consolidation: they were on the Famiglie sheet; the families themselves now live in the Ceti sheet).

const KEY_ORDER: Array[StringName] = [&"production.wood", &"production.stone", &"production.iron", &"production.grain",
	&"production.grain_irrigated", &"production.arid_land", &"production.bread", &"production.weapons",
	&"construction.speed", &"construction.road_cost", &"construction.fortification_cost",
	&"treasury.tax_income", &"trade.income", &"administration.control", &"population.growth",
	&"settlement.urban_growth", &"trust.base", &"stability.base", &"stability.tolerance", &"military.infantry_defense",
	&"military.levy_size", &"military.fortification", &"research.speed"]

var _arms: ArmsView
var _title: Label
var _subtitle: Label
var _identity: Label
var _crown_title: Label
var _crown: Label
var _conditions: VBoxContainer
var _crises: VBoxContainer
var _goals: VBoxContainer
var _spirits: VBoxContainer
var _effects: VBoxContainer


func build() -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	_arms = ArmsView.new()
	_arms.custom_minimum_size = Vector2(52, 60)
	head.add_child(_arms)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	_title = SettlementHud._label(names, 22, KDTheme.GOLD, true)
	_subtitle = SettlementHud._label(names, 14, KDTheme.TEXT_LIGHT, false)
	_identity = parchment()
	# the inhabitants left the bars of the HUD (Phase 18 review): they are one click from here; their families
	# are in the Ceti sheet
	var people_row := HBoxContainer.new()
	people_row.add_theme_constant_override("separation", 8)
	column.add_child(people_row)
	var people_btn := Button.new()
	people_btn.text = "Abitanti"
	people_btn.icon = KDUi.icon(&"people")
	people_btn.expand_icon = true
	people_btn.add_theme_constant_override("icon_max_width", 22)
	people_btn.focus_mode = Control.FOCUS_NONE
	people_btn.tooltip_text = "Chi vive nel regno e cosa fa, nome per nome (P). Le famiglie e i loro ceti sono nella scheda Ceti (T)."
	KDTheme.button_styles(people_btn)
	people_btn.pressed.connect(func() -> void:
		var host := get_parent() as PanelHost
		if host:
			host.open(&"people"))
	people_row.add_child(people_btn)
	# before the crown: the road to the kingdom; after: the royal house
	_crown_title = section("VERSO LA CORONA")
	_crown = parchment()
	_conditions = box(3)
	section("CRISI IN CORSO")
	_crises = box(3)
	section("OBIETTIVI")
	_goals = box(3)
	section("SPIRITI DEL REGNO")
	_spirits = box(6)
	section("LA FORMULA DEL REGNO")
	# level 3 of the information: every modifier with its sources, opened on request (consolidation)
	var unfold := Button.new()
	unfold.text = "Mostra tutte le voci e le loro fonti"
	unfold.toggle_mode = true
	unfold.focus_mode = Control.FOCUS_NONE
	KDTheme.button_styles(unfold)
	column.add_child(unfold)
	_effects = box(2)
	_effects.visible = false
	unfold.toggled.connect(func(on: bool) -> void:
		_effects.visible = on
		unfold.text = "Nascondi la formula" if on else "Mostra tutte le voci e le loro fonti")


func refresh() -> void:
	if not Session.has_game() or column == null:
		return
	var session := Session.current
	var world := session.world
	var k := world.player()
	if k == null:
		return
	_arms.arms = k.coat_of_arms
	_title.text = k.name
	var people := 0
	for s in world.settlements:
		if s.kingdom == k.id:
			people += world.people_of(s.id).size()
	var home := SettlementHud.player_settlement()
	var lines := PackedStringArray()
	if not k.monarchy_founded:
		# before the crown the sheet is the community's: who came first, the families, how firmly it decides
		var families: Array = FamilySystem.living_families(world, home) if home else []
		var rooted := FamilySystem.consolidated_families(world, home).size() if home else 0
		_subtitle.text = "Comunità · %s · %d abitanti · %d famiglie · %d oro" % [
			home.tier_name(people) if home else "", people, families.size(), roundi(k.treasury)]
		lines.append("I fondatori: %s." % ", ".join(_founders(world)))
		var parts := FamilySystem.authority_parts(world, k)
		var why := PackedStringArray()
		for key: String in parts.keys():
			if not key.begins_with("_") and absf(float(parts[key])) >= 0.5:
				why.append("%s %+d" % [key.to_lower(), roundi(float(parts[key]))])
		lines.append("Autorità %d — la capacità della comunità di decidere insieme (verso %d: %s)." % [
			roundi(k.authority), roundi(float(parts.get("_target", 0.0))), ", ".join(why)])
		lines.append("Fiducia %d — quanto gli abitanti credono in chi li guida." % roundi(home.trust if home else 0.0))
		lines.append("Non c'è ancora un sovrano: qui sotto le condizioni del Regno. La casa reale si sceglie fra le famiglie, nella scheda Ceti (%d famiglie, %d radicate)." % [
			families.size(), rooted])
	else:
		_subtitle.text = "%s · %s · %d province · %d abitanti · %d oro" % [k.rank_label(), k.house,
			k.provinces.size(), people, roundi(k.treasury)]
		if k.house_origin != &"":
			var origin := CourtSystem.origin_def(k.house_origin)
			lines.append("%s — %s. %s" % [k.house, String(origin.get("name", "")).to_lower(), String(origin.get("text", ""))])
	var culture: CultureDef = Defs.get_def("cultures", k.culture)
	var religion: ReligionDef = Defs.get_def("religions", k.religion)
	if culture:
		lines.append("Cultura %s — %s" % [culture.display_name, culture.description])
	if religion:
		lines.append("Religione %s — %s" % [religion.display_name, religion.description])
	_identity.text = "\n\n".join(lines)
	_refresh_crown(session, k)
	_refresh_crises(session, k)

	clear(_goals)
	for row: Dictionary in Objectives.progress(session, k):
		check_line(_goals, bool(row["done"]), String(row["name"]),
			"%d / %d" % [int(row["value"]), int(row["target"])], String(row["description"]),
			Color("#BFE39A") if bool(row["done"]) else KDTheme.TEXT_LIGHT)

	clear(_spirits)
	if k.spirits.is_empty():
		var none := SettlementHud._label(_spirits, 14, Color(KDTheme.TEXT_LIGHT, 0.8), false)
		none.text = "Nessuno ancora: la terra deve ancora dire la sua."
	for spirit_id in k.spirits:
		var sp: NationalSpiritDef = Defs.get_def("national_spirits", spirit_id)
		if sp == null:
			continue
		var head := SettlementHud._label(_spirits, 15, Color("#E9D8A6"), true)
		head.text = "%s  (dal %d)" % [sp.display_name, session.calendar.year_of(int(k.spirit_since.get(spirit_id, 0)))]
		var body := SettlementHud._label(_spirits, 13, Color(KDTheme.TEXT_LIGHT, 0.9), false)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(WIDTH - 60, 0)
		var effects := PackedStringArray()
		for m: Modifier in sp.modifiers:
			effects.append("%s %s" % [Modifier.label_for(m.key), m.describe()])
		body.text = "%s\n%s" % [sp.description, " · ".join(effects)]

	clear(_effects)
	var stack := KingdomModifiers.stack(session, k.id)
	for key in KEY_ORDER:
		var parts := stack.breakdown(key)
		if parts.is_empty():
			continue
		var multiplicative := _is_multiplicative(parts)
		var total := stack.apply(key, 1.0) if multiplicative else stack.apply(key, 0.0)
		var shown := (total - 1.0) * 100.0 if multiplicative else total
		var good := shown > 0.0
		if Modifier.lower_is_better(key):
			good = shown < 0.0
		var sources := PackedStringArray()
		for part: Dictionary in parts:
			sources.append("%s %s" % [part["label"], Modifier.new(key, int(part["op"]), float(part["value"])).describe()])
		line(_effects, Modifier.label_for(key),
			("%+.0f%%" % shown) if multiplicative else ("%+.2f" % shown),
			"\n".join(sources), Color("#BFE39A") if good else Color("#FFB09A"))


## Before the crown: the conditions of the kingdom, one by one. After: the royal house — who reigns, since when,
## who follows, which families are bound to it.
func _refresh_crown(session: GameSession, k: KingdomState) -> void:
	var world := session.world
	clear(_conditions)
	if not k.monarchy_founded:
		_crown_title.text = "VERSO LA CORONA"
		_crown.text = ("Quando tutte le condizioni sono vere, nella scheda Ceti ogni famiglia radicata mostra chi dei suoi " +
			"potrebbe portare la corona, e cosa porterebbe al Regno.")
		for c in CourtSystem.monarchy_conditions(session, k):
			var ok := bool(c["ok"])
			check_line(_conditions, ok, String(c["label"]), String(c["value"]), "",
				Color("#BFE39A") if ok else Color("#FFB09A"))
		return
	_crown_title.text = "LA CASA REALE"
	var lines := PackedStringArray()
	var ruler := world.ruler_of(k.id)
	var reign := "sul trono dal %d" % session.calendar.year_of(k.crowned_day) if k.crowned_day >= 0 else ""
	if ruler:
		lines.append("%s regna: %s %s, %d anni%s." % [k.house, "la regina" if ruler.female else "il re", ruler.name,
			ruler.age_years(world.day), "" if reign == "" else ", " + reign])
	else:
		lines.append("%s non ha un sovrano: il trono è vacante." % k.house)
	var heir := CourtSystem.heir_of(world, k)
	lines.append("Erede: %s." % ("%s, %d anni" % [heir.name, heir.age_years(world.day)] if heir else "nessuno — la casata è a rischio"))
	var royal := CourtSystem.royal_family_of(world, k)
	if royal:
		var kin := PackedStringArray()
		for fid: int in FamilySystem.kin_of(world, royal).keys():
			var f := world.family(fid)
			if f:
				kin.append("Famiglia %s" % f.name)
		var among := world.members_of(royal.id).size()
		lines.append("%s%s." % ["La famiglia di origine, i %s, conta %d membri fra la gente del regno" % [royal.name, among]
			if among > 0 else "La famiglia di origine, i %s, vive ormai a corte" % royal.name,
			"" if kin.is_empty() else "; imparentate con la corona: " + ", ".join(kin)])
	lines.append("La corte, l'erede da designare e la legittimità della casata sono nella scheda Corte (Q).")
	_crown.text = "\n".join(lines)


func _refresh_crises(session: GameSession, k: KingdomState) -> void:
	clear(_crises)
	if k.crises.is_empty():
		var none := SettlementHud._label(_crises, 14, Color(KDTheme.TEXT_LIGHT, 0.8), false)
		none.text = "Nessuna: il regno tira il fiato." if k.monarchy_founded else "Nessuna: la comunità tira il fiato."
	for crisis: Dictionary in k.crises:
		var effects := PackedStringArray()
		for m: Modifier in Modifier.list_from_array(crisis.get("modifiers", [])):
			effects.append("%s %s" % [Modifier.label_for(m.key), m.describe()])
		line(_crises, String(crisis.get("name", "Crisi")),
			"ancora %d giorni" % maxi(int(crisis["until"]) - session.world.day, 0),
			" · ".join(effects), Color("#E2A06F"))


static func _is_multiplicative(parts: Array) -> bool:
	for part: Dictionary in parts:
		if int(part["op"]) == Modifier.Op.MUL:
			return true
	return false


## The six who came first, with a cross for those who are gone.
static func _founders(world: WorldState) -> PackedStringArray:
	var out := PackedStringArray()
	var fams: Array = []
	for f: FamilyState in world.families.values():
		if f.founding and not f.founders.is_empty():
			fams.append(f)
	fams.sort_custom(func(a: FamilyState, b: FamilyState) -> bool: return a.founders[0] < b.founders[0])
	for f: FamilyState in fams:
		var p := world.person(f.founders[0])
		out.append("%s %s" % [p.name, f.name] if p else "%s (†)" % f.name)
	return out

