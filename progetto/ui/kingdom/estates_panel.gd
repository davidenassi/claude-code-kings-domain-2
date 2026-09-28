class_name EstatesPanel
extends KDSheet
## The CETI sheet: the social and political body of the realm, with its families inside it (consolidation: the
## families were a second system with a sheet of their own; now every family lives in its estate).
##
## Before the crown the estates are not yet powers. The sheet shows the community — its people, the groups of its
## work — and every family grouped by what it does, with what it would bring to the crown and the choice of the
## royal house (the conditions of the kingdom are in La mia comunità). After the crown: the five powers of the
## realm — favour, wants, mood, the gift of the crown — each with its notable families, then the cards of those
## families (how much they weigh, who they are, where they come from, how they stand with the crown), with the
## royal house above them, and what the mood of the powers costs the crown.

## What each estate is made of, under its name.
const ESTATE_BLURB := {
	&"royal": "la casa che porta la corona",
	&"nobility": "le casate antiche e quelle imparentate con la corona",
	&"clergy": "la fede organizzata: parroci, monasteri, decime",
	&"merchants": "le botteghe, i mestieri e i traffici",
	&"army": "chi ha servito sotto le armi",
	&"people": "i contadini e le famiglie stimate della comunità",
}
## The groups of the community before the crown, in the order the sheet shows them.
const COMMUNITY_GROUPS: Array[StringName] = [&"people", &"merchants", &"army"]
const COMMUNITY_NAMES := {&"people": "LA GENTE DEI CAMPI", &"merchants": "BOTTEGHE E MESTIERI", &"army": "GENTE D'ARME"}
## "Popolo +8 · fiducia +2 · grano +4%": the words for what a house origin changes.
const MODIFIER_WORDS := {
	&"trust.base": "fiducia", &"production.grain": "grano", &"construction.speed": "cantieri",
	&"trade.income": "commercio", &"stability.base": "stabilità", &"legitimacy.base": "legittimità",
}

## -1 nothing built yet, 0 the community, 1 the powers of the realm.
var _mode := -1
var _signature := ""
# the community
var _community: Label
var _groups: VBoxContainer
# the powers of the realm
var _rows: Dictionary = {}       ## faction id -> meter row
var _mood: Dictionary = {}       ## faction id -> Label with the mood and the laws that moved it
var _notables: Dictionary = {}   ## faction id -> Label with its notable families
var _gifts: Dictionary = {}      ## faction id -> the row that holds its "un dono" button
var _royal: Label
var _families: VBoxContainer
var _effect: Label


func build() -> void:
	pass   # built on the first refresh, once it is known whether a crown exists


func refresh() -> void:
	if not Session.has_game() or column == null:
		return
	var session := Session.current
	var k := session.world.player()
	var home := SettlementHud.player_settlement()
	if k == null:
		return
	var want := 1 if k.monarchy_founded else 0
	if want != _mode:
		_rebuild(want)
	if _mode == 0:
		_refresh_community(session, k, home)
	else:
		_refresh_powers(session, k, home)


func _rebuild(mode: int) -> void:
	# everything but the first child, the gap under the frame that KDSheet puts there before build()
	for i in range(column.get_child_count() - 1, 0, -1):
		var c := column.get_child(i)
		column.remove_child(c)
		c.queue_free()
	_mode = mode
	_signature = ""
	_rows.clear()
	_mood.clear()
	_notables.clear()
	_gifts.clear()
	if mode == 0:
		section("LA COMUNITÀ")
		_community = parchment()
		_groups = box(8)
		return
	section("I POTERI DEL REGNO")
	_royal = parchment()
	var powers := box(6)
	for f: FactionDef in CourtSystem.factions():
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 1)
		powers.add_child(group)
		var row := meter(group, f.display_name)
		(row[2] as Control).tooltip_text = "%s\nVuole: %s\nPeso sulle misure della corona: %.1f" % [
			f.description, ", ".join(f.wants), f.weight]
		(row[2] as Control).mouse_filter = Control.MOUSE_FILTER_PASS
		_rows[f.id] = row
		var mood := SettlementHud._label(group, 13, Color(KDTheme.TEXT_LIGHT, 0.85), false)
		mood.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mood.custom_minimum_size = Vector2(WIDTH - 60, 0)
		_mood[f.id] = mood
		var notables := SettlementHud._label(group, 13, Color("#E9D8A6"), false)
		notables.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notables.custom_minimum_size = Vector2(WIDTH - 60, 0)
		_notables[f.id] = notables
		var gift_row := HBoxContainer.new()
		group.add_child(gift_row)
		_gifts[f.id] = gift_row
	section("LE FAMIGLIE DI SPICCO")
	_families = box(8)
	section("EFFETTO SULLA CORONA")
	_effect = parchment()


# --- before the crown: the community and its families -----------------------------------------------------

func _refresh_community(session: GameSession, k: KingdomState, home: SettlementState) -> void:
	var world := session.world
	if home == null:
		_community.text = "Nessuno vive più nella comunità."
		return
	var people := world.people_of(home.id)
	var by_estate := FamilySystem.families_by_estate(world, k, home)
	var families := 0
	for estate: StringName in by_estate.keys():
		families += (by_estate[estate] as Array).size()
	var rooted := FamilySystem.consolidated_families(world, home).size()
	var lines := PackedStringArray()
	lines.append("%s: %d abitanti, %d famiglie (%d radicate)." % [home.name, people.size(), families, rooted])
	lines.append("Al lavoro: %s." % work_groups_text(world, home))
	lines.append("Nobiltà, clero, mercanti e artigiani, esercito e popolo come poteri del regno nasceranno con la corona. " +
		"Oggi la comunità è fatta di famiglie, raggruppate qui per il lavoro che fanno: quando La mia comunità dice che " +
		"il Regno può nascere, è qui che si sceglie la casa reale.")
	_community.text = "\n".join(lines)
	var blocker := CourtSystem.monarchy_blocker(session, k)
	var signature := "%s|%d" % [blocker, world.day / 30]
	for estate: StringName in COMMUNITY_GROUPS:
		for item: Array in by_estate.get(estate, []):
			signature += ",%d:%d" % [(item[0] as FamilyState).id, int(item[2])]
	if signature == _signature:
		return
	_signature = signature
	clear(_groups)
	for estate: StringName in COMMUNITY_GROUPS:
		var list: Array = by_estate.get(estate, [])
		if list.is_empty():
			continue
		section_in(_groups, String(COMMUNITY_NAMES[estate]))
		var blurb := SettlementHud._label(_groups, 13, Color(KDTheme.TEXT_LIGHT, 0.8), false)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(WIDTH - 60, 0)
		var words := String(ESTATE_BLURB[estate])
		blurb.text = "%s%s — %d %s." % [words.left(1).to_upper(), words.substr(1), list.size(),
			"famiglia" if list.size() == 1 else "famiglie"]
		for item: Array in list:
			_family_card(_groups, session, k, item[0] as FamilyState, float(item[1]), estate, true)
	if families == 0:
		var none := SettlementHud._label(_groups, 14, Color(KDTheme.TEXT_LIGHT, 0.8), false)
		none.text = "Nessuna famiglia vive più nella comunità."


## "12 contadini, 5 nelle botteghe e nei cantieri, 2 in armi, 4 bambini, 3 senza lavoro": the professional
## groups of a settlement, in the words of its estates.
static func work_groups_text(world: WorldState, s: SettlementState) -> String:
	var groups: Dictionary = FamilySystem.bal().get("origin_jobs", {})
	var of_job := {}
	for origin: String in groups.keys():
		for job: String in groups[origin]:
			of_job[job] = origin
	var counts := {"farmers": 0, "artisans": 0, "soldiers": 0, "child": 0, "idle": 0}
	for p in world.people_of(s.id):
		var job := String(p.job)
		if of_job.has(job):
			counts[of_job[job]] = int(counts[of_job[job]]) + 1
		elif job == "child":
			counts["child"] = int(counts["child"]) + 1
		elif job != "king":
			counts["idle"] = int(counts["idle"]) + 1
	var parts := PackedStringArray()
	for entry: Array in [["farmers", "nei campi"], ["artisans", "nelle botteghe e nei cantieri"], ["soldiers", "in armi"],
			["child", "bambini"], ["idle", "senza lavoro"]]:
		var n := int(counts[entry[0]])
		if n > 0:
			parts.append("%d %s" % [n, entry[1]])
	return ", ".join(parts) if not parts.is_empty() else "nessuno"


# --- after the crown: the powers of the realm ----------------------------------------------------------------

func _refresh_powers(session: GameSession, k: KingdomState, home: SettlementState) -> void:
	var world := session.world
	var by_estate := FamilySystem.families_by_estate(world, k, home) if home else {}
	var limit := int(FamilySystem.estates_cfg().get("notable_per_estate", 3))
	# the royal house above the estates
	var royal := CourtSystem.royal_family_of(world, k)
	var kin := PackedStringArray()
	var kin_ids := FamilySystem.kin_of(world, royal)
	for item: Array in by_estate.get(&"nobility", []):
		var f: FamilyState = item[0]
		if kin_ids.has(f.id):
			kin.append("Casa %s" % f.name)
	_royal.text = "%s porta la corona: sta sopra i ceti, e ognuno di loro la giudica col suo favore.%s" % [
		k.house, "" if kin.is_empty() else "\nImparentate con la casa reale: %s." % ", ".join(kin)]
	var cfg: Dictionary = CourtSystem.bal().get("factions", {})
	var leg: Dictionary = CourtSystem.bal().get("legitimacy", {})
	var ord_cfg: Dictionary = CourtSystem.bal().get("stability", {})
	var hostile_below := float(leg.get("hostile_below", 30.0))
	var warning := float(cfg.get("hostile_warning", 28.0))
	var hostile := 0
	var discontent := 0.0
	var hostile_names := PackedStringArray()
	for f: FactionDef in CourtSystem.factions():
		var favour := float(k.favour.get(f.id, 55.0))
		set_meter(_rows[f.id], favour)
		if favour < hostile_below:
			hostile += 1
			hostile_names.append(f.display_name.to_lower())
		discontent += maxf(55.0 - favour, 0.0) * f.weight
		var parts := PackedStringArray()
		parts.append(_mood_word(favour, hostile_below, warning))
		parts.append("chiede %s" % ", ".join(f.wants))
		var bias := float(k.favour.get(StringName("_law_bias_%s" % f.id), 0.0))
		if absf(bias) >= 0.5:
			parts.append("per le decisioni della corona %+.0f" % bias)
		var rival_names := PackedStringArray()
		for r in f.rivals:
			var rd := Defs.get_def("factions", r) as FactionDef
			if rd:
				rival_names.append(rd.display_name.to_lower())
		if not rival_names.is_empty():
			parts.append("mal sopporta %s" % ", ".join(rival_names))
		(_mood[f.id] as Label).text = " · ".join(parts)
		var list: Array = by_estate.get(f.id, [])
		var names := PackedStringArray()
		for item: Array in list.slice(0, limit):
			names.append("%s (%d)" % [_family_title(item[0] as FamilyState, f.id), roundi(float(item[1]))])
		var notable_text := "Famiglie: %s" % ", ".join(names) if not names.is_empty() else ""
		if list.size() > limit:
			notable_text += " · e altre %d" % (list.size() - limit)
		if notable_text == "" and f.id == &"clergy":
			notable_text = "Nessuna famiglia della comunità è ancora entrata nel clero."
		(_notables[f.id] as Label).text = notable_text
		(_notables[f.id] as Label).visible = notable_text != ""
		var gift_row: HBoxContainer = _gifts[f.id]
		clear(gift_row)
		command_button(gift_row, "Un dono (%d ori)" % roundi(GiftFactionCommand.cost(k)), GiftFactionCommand.create(k.id, f.id),
			"Feste, terre, privilegi: %s +%d, e la corona se ne ricorda come di una legge. Una volta l'anno." % [
				f.display_name.to_lower(), roundi(float(GiftFactionCommand.cfg().get("favour", 10.0)))])
	_refresh_family_cards(session, k, by_estate, limit)
	var lines := PackedStringArray()
	if hostile > 0:
		lines.append("Poteri ostili: %s — la legittimità ne perde %d." % [
			", ".join(hostile_names), roundi(absf(float(leg.get("hostile_faction", -10.0))) * hostile)])
	else:
		lines.append("Nessun potere è ostile alla corona.")
	lines.append("Malcontento pesato: %d — la stabilità del regno ne perde %d." % [
		roundi(discontent), roundi(discontent * float(ord_cfg.get("faction_discontent_weight", 0.5)))])
	var clergy := float(k.favour.get(&"clergy", 55.0))
	lines.append("Il clero (%d) muove la legittimità di %+.1f." % [
		roundi(clergy), (clergy - 55.0) * float(leg.get("clergy_weight", 0.12))])
	lines.append("Misure attuali: legittimità %d · stabilità %d · turbolenza %d." % [
		roundi(k.legitimacy), roundi(k.stability), roundi(k.turbulence)])
	lines.append("Il favore si muove con la fiducia degli abitanti, le paghe arretrate, le leggi in vigore e l'indole del sovrano.")
	_effect.text = "\n".join(lines)


## The cards of the notable families: the royal house first, then the most influential of every estate.
func _refresh_family_cards(session: GameSession, k: KingdomState, by_estate: Dictionary, limit: int) -> void:
	var world := session.world
	var signature := "%d" % (world.day / 30)
	for estate: StringName in FamilySystem.ESTATE_ORDER:
		for item: Array in (by_estate.get(estate, []) as Array).slice(0, limit):
			signature += ",%d:%s:%d" % [(item[0] as FamilyState).id, estate, int(item[2])]
	if signature == _signature:
		return
	_signature = signature
	clear(_families)
	var shown := 0
	for estate: StringName in FamilySystem.ESTATE_ORDER:
		for item: Array in (by_estate.get(estate, []) as Array).slice(0, limit):
			_family_card(_families, session, k, item[0] as FamilyState, float(item[1]), estate, false)
			shown += 1
	if shown == 0:
		var none := SettlementHud._label(_families, 14, Color(KDTheme.TEXT_LIGHT, 0.8), false)
		none.text = "Nessuna famiglia vive più nel regno."


static func _family_title(f: FamilyState, estate: StringName) -> String:
	return "Casa %s" % f.name if estate == FamilySystem.ROYAL or estate == &"nobility" else "Famiglia %s" % f.name


## One family: how much it weighs, its estate, who they are, what they have done — and, before the crown, what it
## would bring to the crown and the choice of the royal house; after, how it stands with the crown.
func _family_card(parent: Control, session: GameSession, k: KingdomState, f: FamilyState, influence: float,
		estate: StringName, with_choice: bool) -> void:
	var world := session.world
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", KDTheme.dark_panel())
	parent.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var name_label := SettlementHud._label(head, 16, KDTheme.GOLD, true)
	name_label.text = "%s%s" % [_family_title(f, estate), "  ·  fondatrice" if f.founding else ""]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var weight := SettlementHud._label(head, 13, KDTheme.TEXT_LIGHT, false)
	weight.text = "influenza %d" % roundi(influence)
	weight.tooltip_text = "Quanto conta questa famiglia: se è fondatrice, gli anni, i membri, i figli, il lavoro fatto per tutti."
	weight.mouse_filter = Control.MOUSE_FILTER_PASS
	if not with_choice:
		var where := SettlementHud._label(col, 13, Color("#E9D8A6"), false)
		where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		where.custom_minimum_size = Vector2(WIDTH - 90, 0)
		where.text = _estate_line(world, k, f, estate)
	# who they are: the essential tree
	var tree := SettlementHud._label(col, 13, Color(KDTheme.TEXT_LIGHT, 0.92), false)
	tree.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tree.custom_minimum_size = Vector2(WIDTH - 90, 0)
	var lines := FamilySystem.tree_lines(world, f)
	tree.text = "\n".join(lines if with_choice else lines.slice(0, 3))
	# its history: what its members have done since it began
	var activity := SettlementHud._label(col, 12, Color(KDTheme.TEXT_LIGHT, 0.7), false)
	activity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	activity.custom_minimum_size = Vector2(WIDTH - 90, 0)
	activity.text = "Dal %d: %s" % [session.calendar.year_of(f.founded_day), FamilySystem.activity_text(f)]
	if not with_choice:
		return
	var origin := CourtSystem.origin_def(CourtSystem.origin_of(world, f))
	var brings := SettlementHud._label(col, 13, Color("#E9D8A6"), false)
	brings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brings.custom_minimum_size = Vector2(WIDTH - 90, 0)
	brings.text = "Come casa reale: %s — %s\n%s" % [String(origin.get("name", "?")), String(origin.get("text", "")),
		_effects_text(origin)]
	# the choice: one button for every adult who could wear the crown
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 4)
	col.add_child(buttons)
	var eligible := CourtSystem.eligible_rulers(world, f)
	for p in eligible:
		var title := "Regina" if p.female else "Re"
		command_button(buttons, "Scegli come Casa Reale: %s %s" % [title, p.name],
			FoundMonarchyCommand.create(k.id, f.id, p.id),
			"La Casa %s diventa la casa reale e %s %s viene %s %s del Regno. La scelta non si torna indietro." % [
				f.name, p.name, f.name, "incoronata prima" if p.female else "incoronato primo", title])
	if eligible.is_empty():
		var none := SettlementHud._label(buttons, 12, Color(KDTheme.TEXT_LIGHT, 0.7), false)
		none.text = "Nessun adulto di questa famiglia potrebbe oggi portare la corona."


## "Nobiltà · imparentata con la casa reale · il ceto è fedele alla corona (74) · chiede terre, …"
static func _estate_line(world: WorldState, k: KingdomState, f: FamilyState, estate: StringName) -> String:
	if estate == FamilySystem.ROYAL:
		return "Casa reale · porta la corona"
	var fd := Defs.get_def("factions", estate) as FactionDef
	var parts := PackedStringArray()
	parts.append(fd.display_name if fd else String(estate))
	if FamilySystem.married_into(world, f, CourtSystem.royal_family_of(world, k)):
		parts.append("imparentata con la casa reale")
	if fd:
		var favour := float(k.favour.get(estate, 55.0))
		var hostile_below := float((CourtSystem.bal().get("legitimacy", {}) as Dictionary).get("hostile_below", 30.0))
		var warning := float((CourtSystem.bal().get("factions", {}) as Dictionary).get("hostile_warning", 28.0))
		parts.append("con la corona come il suo ceto: %s (%d)" % [_mood_word(favour, hostile_below, warning), roundi(favour)])
		parts.append("chiede %s" % ", ".join(fd.wants))
	return " · ".join(parts)


## "Popolo +8 · fiducia +2 · grano +4%": what a house origin changes, in words.
static func _effects_text(origin: Dictionary) -> String:
	var parts := PackedStringArray()
	var favour: Dictionary = origin.get("favour", {})
	for fid: String in favour.keys():
		var fd := Defs.get_def("factions", StringName(fid)) as FactionDef
		parts.append("%s %+d" % [fd.display_name if fd else fid, int(favour[fid])])
	for m: Dictionary in origin.get("modifiers", []):
		var word := String(MODIFIER_WORDS.get(StringName(m.get("key", "")), m.get("key", "")))
		var value := float(m.get("value", 0.0))
		if String(m.get("op", "add")) == "mul":
			parts.append("%s %+d%%" % [word, roundi((value - 1.0) * 100.0)])
		else:
			parts.append("%s %+d" % [word, roundi(value)])
	return " · ".join(parts)


static func _mood_word(favour: float, hostile_below: float, warning: float) -> String:
	if favour < hostile_below:
		return "ostile"
	if favour < warning + 12.0:
		return "freddo"
	if favour >= 72.0:
		return "fedele"
	return "quieto"

