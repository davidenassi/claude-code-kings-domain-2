extends KDTestCase
## Phase 15: six founders, no king. The families form, the community grows, the player chooses the royal house
## and the community becomes a kingdom — and every step of it crosses a save and is written in the chronicle.

const Economy := preload("res://tests/unit/test_economy.gd")


func after_each() -> void:
	Session.end()


static func _couples(w: WorldState, s: SettlementState) -> int:
	var n := 0
	for p in w.people_of(s.id):
		if p.female and p.spouse >= 0 and w.person(p.spouse) != null:
			n += 1
	return n


static func _kinds(w: WorldState) -> Dictionary:
	var out := {}
	for e: Dictionary in w.chronicle:
		out[String(e.get("kind", ""))] = true
	return out


## A careful lord for as many months as it takes the community to meet the conditions of the kingdom.
static func _grow_until_ready(s: GameSession, max_years: int) -> int:
	var k := s.world.player()
	for month in max_years * 12:
		s.advance_days(30)
		Economy.lord_turn(s, 60)
		if CourtSystem.monarchy_blocker(s, k) == "":
			return month + 1
	return -1


func test_the_founders_pair_and_their_children_have_parents() -> void:
	var s := Economy.village(1501)
	var w := s.world
	var st := w.settlements[0]
	for m in 30:
		s.advance_days(30)
		Economy.lord_turn(s, 30)
	assert_true(_couples(w, st) >= 2, "two years later the founders have paired (%d coppie)" % _couples(w, st))
	var children := 0
	for p in w.people_of(st.id):
		if p.spouse >= 0:
			var spouse := w.person(p.spouse)
			assert_not_null(spouse, "%s is married to somebody alive" % p.name)
			if spouse:
				assert_eq(spouse.spouse, p.id, "marriage goes both ways")
				assert_eq(p.family, spouse.family, "husband and wife share one family")
		if p.mother >= 0 or p.father >= 0:
			children += 1
			var mother := w.person(p.mother)
			if mother:
				assert_true(mother.female, "a mother is a woman")
				assert_eq(p.family, mother.family, "%s grows up in the family of the parents" % p.name)
		var f := w.family(p.family)
		assert_not_null(f, "%s belongs to a family" % p.name)
	assert_true(children > 0, "children were born to the couples (%d)" % children)
	var kinds := _kinds(w)
	assert_true(kinds.has("founding_family"), "the chronicle tells the first families")
	assert_true(kinds.has("founding_child"), "and the first child")
	assert_true(kinds.has("founding_first_house"), "and the first house")
	# the tree of a family can be read
	var some := FamilySystem.living_families(w, st)
	assert_true(some.size() >= 2, "there are families to read")
	assert_true(FamilySystem.tree_lines(w, some[0]).size() >= 1, "and each has its tree")


func test_the_crown_waits_for_its_conditions() -> void:
	var s := GameSession.create_new({"campaign_seed": 1502})
	var w := s.world
	var k := w.player()
	var st := w.settlements[0]
	var blocker := CourtSystem.monarchy_blocker(s, k)
	assert_true(blocker.begins_with("Manca ancora"), "at the start the kingdom cannot be founded: %s" % blocker)
	var conditions := CourtSystem.monarchy_conditions(s, k)
	assert_eq(conditions.size(), 6, "six conditions, each with its value")
	for c in conditions:
		assert_true(String(c["value"]) != "", "%s says where it stands" % c["label"])
	var p := w.people_of(st.id)[0]
	var res := s.submit(FoundMonarchyCommand.create(k.id, p.family, p.id))
	assert_false(res.success, "the command refuses")
	assert_eq(res.reason, blocker, "with the same reason the sheet shows")
	assert_false(k.monarchy_founded, "and nothing was crowned")
	# nor laws, edicts or marriages of state without a crown
	var law := s.submit(EnactLawCommand.create(k.id, &"taxation", &"catasto"))
	assert_false(law.success, "no laws without a crown")
	assert_true(law.reason.contains("corona"), law.reason)


func test_a_community_that_grows_chooses_its_royal_house() -> void:
	var s := Economy.village(1503)
	var w := s.world
	var k := w.player()
	var st := w.settlements[0]
	var months := _grow_until_ready(s, 10)
	assert_true(months > 0, "a well governed community meets the conditions within ten years (%d mesi, %s)" % [
		months, CourtSystem.monarchy_blocker(s, k)])
	if months < 0:
		return
	assert_true(months >= 24, "but not before two years together (%d mesi)" % months)
	var kinds := _kinds(w)
	assert_true(kinds.has("founding_village"), "the chronicle saw the village born")
	# the player chooses: the first rooted family, its eldest adult
	var families := FamilySystem.consolidated_families(w, st)
	assert_true(families.size() >= 2, "at least two families could wear the crown")
	var f := families[0]
	var who := CourtSystem.eligible_rulers(w, f)
	assert_true(who.size() >= 1, "the family has somebody of age")
	var p := who[0]
	var authority := k.authority
	var origin := CourtSystem.origin_of(w, f)
	var res := s.submit(FoundMonarchyCommand.create(k.id, f.id, p.id))
	assert_true(res.success, "the royal house is chosen: %s" % res.reason)
	assert_true(k.monarchy_founded, "the monarchy exists")
	assert_eq(k.rank, KingdomState.Rank.KINGDOM, "the community is a kingdom")
	assert_true(k.name.begins_with("Regno di"), "and it is called %s" % k.name)
	assert_eq(k.house, "Casa %s" % f.name, "the family is the royal house")
	assert_eq(k.house_origin, origin, "with the origin its register says")
	assert_eq(k.crowned_day, w.day, "crowned today")
	var ruler := w.ruler_of(k.id)
	assert_not_null(ruler, "a sovereign reigns")
	if ruler:
		assert_eq(ruler.person, p.id, "and it is the person the player chose")
		assert_eq(ruler.name, p.name, "with the same name")
	assert_true(p.is_king, "who now lives as the sovereign of the village")
	assert_true(k.legitimacy >= 25.0 and k.legitimacy <= 90.0, "the legitimacy comes from the authority (%.0f from %.0f)" % [
		k.legitimacy, authority])
	assert_true(k.laws.has(&"succession"), "the realm has its laws")
	assert_eq(k.favour.size(), 5, "and the five powers")
	kinds = _kinds(w)
	for kind in ["founding_royal_house", "founding_crown", "founding_realm"]:
		assert_true(kinds.has(kind), "the chronicle writes %s" % kind)
	assert_false(s.submit(FoundMonarchyCommand.create(k.id, f.id, p.id)).success, "a kingdom is founded only once")
	# the crown now decides, and the realm lives on
	var law := s.submit(EnactLawCommand.create(k.id, &"taxation", &"franchigia"))
	assert_true(law.success, "the first law of the kingdom: %s" % law.reason)
	assert_eq(int(k.records.get(&"laws_changed", 0.0)), 1, "and the realm remembers it changed a law")
	s.advance_days(360 * 3)
	assert_not_null(w.ruler_of(k.id), "three years later a sovereign still reigns")
	assert_true(k.monarchy_founded, "and the kingdom is still a kingdom")


func test_the_founding_crosses_a_save() -> void:
	var s := Economy.village(1504)
	var w := s.world
	for m in 18:
		s.advance_days(30)
		Economy.lord_turn(s, 40)
	var k := w.player()
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s)))
	var loaded := SaveSystem.session_from_data(data)
	var lw := loaded.world
	var lk := lw.player()
	assert_false(lk.monarchy_founded, "a community loads as a community")
	assert_null(lw.ruler_of(lk.id), "nobody is crowned by loading it")
	assert_eq(lw.families.size(), w.families.size(), "the families cross the save")
	assert_true(absf(lk.authority - k.authority) < 0.01, "and the authority (%.1f)" % lk.authority)
	for p: PersonState in w.people.values():
		var q := lw.person(p.id)
		assert_not_null(q, "%s crosses the save" % p.name)
		if q:
			assert_eq(q.family, p.family, "with the family")
			assert_eq(q.spouse, p.spouse, "the spouse")
			assert_eq(q.mother, p.mother, "and the parents")
	for f: FamilyState in w.families.values():
		var g := lw.family(f.id)
		assert_not_null(g, "family %s" % f.name)
		if g:
			assert_eq(g.name, f.name, "same surname")
			assert_eq(g.founding, f.founding, "same standing")
	# the loaded game goes on like the original
	s.advance_days(60)
	loaded.advance_days(60)
	assert_eq(lw.people.size(), w.people.size(), "the same people two months later")
	assert_eq(lw.families.size(), w.families.size(), "and the same families")
	# a crowned kingdom crosses the save as a kingdom
	crown_player(s)
	data = JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s)))
	loaded = SaveSystem.session_from_data(data)
	lk = loaded.world.player()
	assert_true(lk.monarchy_founded, "the kingdom loads as a kingdom")
	assert_eq(lk.house, k.house, "with its house")
	assert_eq(lk.house_origin, k.house_origin, "the origin of the house")
	assert_eq(lk.crowned_day, k.crowned_day, "and the day of the crown")
	assert_not_null(loaded.world.ruler_of(lk.id), "and its sovereign")


func test_saves_from_before_the_founders_load_as_kingdoms() -> void:
	var s := GameSession.create_new({"campaign_seed": 1505})
	crown_player(s)
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s)))
	# a version 4 save knew nothing of families nor of a monarchy to found
	data["header"]["save_version"] = 4
	var world: Dictionary = data["world"]
	world.erase("families")
	for kd: Dictionary in world.get("kingdoms", []):
		kd.erase("monarchy_founded")
		kd.erase("authority")
	var loaded := SaveSystem.session_from_data(data)
	assert_not_null(loaded, "the old save loads")
	if loaded == null:
		return
	for k in loaded.world.kingdoms:
		assert_true(k.monarchy_founded, "%s was a kingdom and stays one" % k.name)
	assert_not_null(loaded.world.ruler_of(loaded.world.player().id), "with its sovereign")
	loaded.advance_days(30)
	assert_true(loaded.world.player().monarchy_founded, "and nothing turns it back into a community")


func test_a_community_that_starves_ends_and_the_chronicle_says_so() -> void:
	var s := Economy.village(1506, false)
	var w := s.world
	var st := w.settlements[0]
	st.stock[&"grain"] = 0
	st.stock[&"bread"] = 0
	s.advance_days(360 * 2)
	assert_eq(w.people_of(st.id).size(), 0, "without food and fields nobody is left")
	var k := w.player()
	assert_true(k.records.has(FamilySystem.EXTINCT), "the end is recorded")
	assert_true(_kinds(w).has("founding_extinct"), "and written in the chronicle")


func test_the_founding_stays_in_the_chronicle() -> void:
	var s := GameSession.create_new({"campaign_seed": 1507})
	var w := s.world
	assert_true(_kinds(w).has("founding_arrival"), "the chronicle opens with the founders")
	for i in 700:
		EventBus.chronicle_written.emit({"day": w.day, "kingdom": -1, "kind": "event", "text": "Una prova %d." % i})
	assert_true(_kinds(w).has("founding_arrival"), "and seven hundred later entries do not push the founding out")
	assert_true(w.chronicle.size() <= 601, "while the chronicle keeps its size (%d)" % w.chronicle.size())


func test_the_guide_walks_from_the_founders_to_the_crown() -> void:
	var s := Session.start_new({"campaign_seed": 1508})
	var w := s.world
	var k := w.player()
	var ids := []
	for step: Dictionary in Guide.steps():
		ids.append(String(step.get("id", "")))
	assert_true(ids.find("famiglie") < ids.find("regno") and ids.find("regno") < ids.find("legge"),
		"families, then the crown, then the laws (%s)" % ", ".join(ids))
	assert_false(Guide.is_done(w, {"couples": 1}), "no couples on the first day")
	assert_false(Guide.is_done(w, {"monarchy": true}), "no crown")
	crown_player(s)
	assert_true(Guide.is_done(w, {"monarchy": true}), "the crown closes its step")
	assert_false(Guide.is_done(w, {"laws_changed": 1}), "the default laws are not a choice of the player")
	assert_true(s.submit(EnactLawCommand.create(k.id, &"taxation", &"franchigia")).success, "a law is changed")
	assert_true(Guide.is_done(w, {"laws_changed": 1}), "and that closes the law step")


# --- the interface of the community ------------------------------------------------------------------------

static func _all_text(node: Node) -> String:
	var parts := PackedStringArray()
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	for child in node.get_children():
		parts.append(_all_text(child))
	return "\n".join(parts)


func _open(panel: Control) -> Control:
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	panel.visible = true
	if panel.has_method("refresh"):
		panel.call("refresh")
	return panel


func _drop(panel: Control) -> void:
	(Engine.get_main_loop() as SceneTree).root.remove_child(panel)
	panel.free()


## Consolidation: the families live in the Ceti sheet, the conditions of the kingdom in La mia comunità, and the
## Corte exists only once somebody reigns.
func test_the_community_sheets_show_no_sovereign_and_the_families() -> void:
	var s := Session.start_new({"campaign_seed": 1509})
	SettlementPlanner.place_starter_village(s, s.world.settlements[0].id)
	s.advance_days(400)
	var k := s.world.player()
	var estates := _open(EstatesPanel.new()) as EstatesPanel
	estates.refresh()
	var text := _all_text(estates)
	assert_true(text.contains("LA COMUNITÀ"), "the Ceti sheet shows the community")
	assert_true(text.contains("Al lavoro"), "and the groups of its work")
	for f in FamilySystem.living_families(s.world, s.world.settlements[0]):
		assert_true(text.contains("Famiglia %s" % f.name), "the family %s has its card in its group" % f.name)
	assert_true(text.contains("Come casa reale"), "each card says what it would bring to the crown")
	assert_false(text.contains("Legittimità"), "no measure of a crown that does not exist")
	assert_false(text.contains("I POTERI DEL REGNO"), "and no powers of a realm that is not yet")
	var court := _open(CourtPanel.new()) as CourtPanel
	court.refresh()
	assert_true(_all_text(court).contains("Non c'è ancora una corte"), "the Corte says there is none yet")
	var realm := _open(RealmPanel.new()) as RealmPanel
	realm.refresh()
	var realm_text := _all_text(realm)
	assert_true(realm_text.contains("I fondatori"), "the community sheet names the founders")
	assert_true(realm_text.contains("Autorità"), "and its authority")
	assert_true(realm_text.contains("VERSO LA CORONA"), "and lists the conditions of the kingdom")
	for c in CourtSystem.monarchy_conditions(s, k):
		assert_true(realm_text.contains(String(c["label"])), "the condition «%s» is there" % c["label"])
	var bar := _open(TopBar.new()) as TopBar
	bar.refresh()
	var bar_text := _all_text(bar)
	assert_true(bar_text.contains("%d" % roundi(k.authority)), "the top bar shows the authority")
	# the crown: the Corte appears, the Ceti become the powers of the realm with their families
	crown_player(s)
	court.refresh()
	text = _all_text(court)
	assert_false(text.contains("Non c'è ancora una corte"), "once crowned, somebody reigns")
	assert_true(text.contains("IL SOVRANO") and text.contains("Legittimità"), "and the sheet is the court")
	assert_false(text.contains("I POTERI DEL REGNO"), "the powers of the realm are not repeated at court")
	estates.refresh()
	text = _all_text(estates)
	assert_true(text.contains("I POTERI DEL REGNO") and text.contains("Nobiltà"), "the Ceti sheet shows the powers")
	assert_true(text.contains("porta la corona"), "with the royal house above them")
	assert_true(text.contains("LE FAMIGLIE DI SPICCO"), "and the notable families")
	realm.refresh()
	assert_true(_all_text(realm).contains("LA CASA REALE"), "Il mio regno shows the royal house")
	_drop(court)
	_drop(estates)
	_drop(realm)
	_drop(bar)


func test_the_coronation_card_tells_the_birth_of_the_kingdom() -> void:
	var s := Session.start_new({"campaign_seed": 1510})
	var k := crown_player(s)
	var card := _open(CoronationCard.new()) as CoronationCard
	s.clock.set_speed(2)
	card.show_for(k)
	var text := _all_text(card)
	assert_true(card.visible, "the card is shown")
	assert_true(text.contains("Nasce il %s" % k.name), "it names the new kingdom")
	assert_true(text.contains(k.house), "and the royal house")
	assert_true(text.contains("Lunga vita"), "and the cry of the day")
	assert_true(s.clock.is_paused(), "time stands still while it is read")
	card.close()
	assert_false(card.visible, "closed")
	assert_false(s.clock.is_paused(), "and time goes on")
	card.show_end(k)
	assert_true(_all_text(card).contains("Non resta nessuno"), "the same card can tell the end")
	card.close()
	_drop(card)


## Brief §15.1: woods, rocks, free ground and water around the six — the first quarry is a short walk away.
func test_the_founders_start_near_wood_rock_and_water() -> void:
	var s := GameSession.create_new({"campaign_seed": 1511})
	var st := s.world.settlements[0]
	var wd := SettlementSim.ground(s.world)   # the valley, in its own metres (Rebirth)
	var nearest := INF
	for r in LocalFeatures.outcrops_in_rect(wd, Rect2(st.center - Vector2(400, 400), Vector2(800, 800))):
		if r["deposit"] == &"stone":
			nearest = minf(nearest, r["pos"].distance_to(st.center))
	assert_true(nearest <= 300.0, "rocks within a short walk (%.0f m)" % nearest)
	assert_true(SettlementPlanner.find_spot(s, st.id, &"quarry", st.center, 30.0) != Vector2.INF,
		"and a quarry fits near the fire")
	var water := false
	for k in 24:
		for dist: float in [40.0, 80.0, 120.0, 160.0, 200.0]:
			if wd.water_at(st.center + Vector2.from_angle(TAU * k / 24.0) * dist) != WorldData.WATER_LAND:
				water = true
	assert_true(water, "water within two hundred metres")
	assert_true(LocalFeatures.trees_in_rect(wd, Rect2(st.center - Vector2(150, 150), Vector2(300, 300))).size() > 50,
		"and a wood all around")


## Brief §15.4: before the crown nothing speaks of a king.
func test_events_speak_to_a_community_as_a_community() -> void:
	var s := GameSession.create_new({"campaign_seed": 1512})
	var k := s.world.player()
	assert_eq(Events.words(k, "{Corona} paga la ricostruzione"), "La comunità paga la ricostruzione", "no crown yet")
	assert_eq(Events.words(k, "Doni {alla_corona}"), "Doni alla comunità")
	var f := Events.facts(s, k)
	assert_false(Events.matches({"crowned": true}, f), "an event of the crown does not fire for a community")
	assert_false(Events.matches({"max_legitimacy": 55}, f), "nor one about a shaky crown")
	for e: Dictionary in Events.candidates(s, k):
		assert_false(bool(e.get("when", {}).get("crowned", false)), "%s waits for the crown" % e["id"])
	var words_left := ""
	for e: Dictionary in Events.all():
		for text in [String(e.get("title", "")), String(e.get("text", ""))]:
			var said := Events.words(k, text)
			if not bool(e.get("when", {}).get("crowned", false)) and (said.contains("la corona") or said.contains("La corona")):
				words_left += " %s" % e["id"]
	assert_eq(words_left, "", "no event open to a community speaks of the crown")
	crown_player(s)
	assert_eq(Events.words(k, "{Corona} paga la ricostruzione"), "La corona paga la ricostruzione", "and then the crown")
	assert_true(Events.matches({"crowned": true}, Events.facts(s, k)), "the crown's events can come")


func test_the_community_decides_by_custom_before_the_laws() -> void:
	var s := Session.start_new({"campaign_seed": 1513})
	var panel := _open(GovernmentPanel.new()) as GovernmentPanel
	panel.refresh()
	var text := _all_text(panel)
	assert_true(text.contains("consuetudine"), "the sheet says how the community decides")
	assert_false(text.contains("SUCCESSIONE") or text.contains("Successione"), "no succession law before the crown")
	crown_player(s)
	panel.refresh()
	text = _all_text(panel)
	assert_true(text.to_upper().contains("SUCCESSIONE"), "the laws arrive with the crown")
	_drop(panel)


func test_a_new_game_opens_on_the_six_founders() -> void:
	var s := Session.start_new({"campaign_seed": 1514})
	var k := s.world.player()
	var card := _open(CoronationCard.new()) as CoronationCard
	card.show_start(k)
	var text := _all_text(card)
	assert_true(text.contains("Non possiedi ancora un Regno"), "the words of the brief open the game")
	assert_true(text.contains("sei persone e un territorio da trasformare"), "all of them")
	for p in s.world.people_of(s.world.settlements[0].id):
		assert_true(text.contains(p.name), "%s is named" % p.name)
	assert_true(s.clock.is_paused(), "time waits for the player")
	card.close()
	assert_false(s.clock.is_paused(), "and starts when the card is closed")
	_drop(card)


## Consolidation: the families live inside the estates. Before the crown a family belongs to the group of the work
## that fills its register; after the crown the royal house stands apart, and the influential houses and those
## married into the royal house are the nobility. Nothing is stored: old saves are sorted by themselves.
func test_the_families_live_inside_the_estates() -> void:
	var s := GameSession.create_new({"campaign_seed": 1511})
	var w := s.world
	var k := w.player()
	var home := w.settlements[0]
	var families: Array[FamilyState] = FamilySystem.living_families(w, home)
	assert_true(families.size() >= 3, "the founders make their families (%d)" % families.size())
	families[0].records[&"farmer"] = 400.0
	families[1].records[&"smith"] = 400.0
	families[2].records[&"soldier"] = 400.0
	assert_eq(FamilySystem.estate_of(w, k, families[0]), &"people", "a family of farmers is of the people")
	assert_eq(FamilySystem.estate_of(w, k, families[1]), &"merchants", "a family of craftsmen of the merchants and artisans")
	assert_eq(FamilySystem.estate_of(w, k, families[2]), &"army", "a family of soldiers of the army")
	var grouped := FamilySystem.families_by_estate(w, k, home)
	var counted := 0
	for estate: StringName in grouped.keys():
		assert_false(estate == &"nobility" or estate == FamilySystem.ROYAL, "no nobility and no royal house before the crown")
		counted += (grouped[estate] as Array).size()
	assert_eq(counted, families.size(), "every living family is in one estate")
	# the crown
	crown_player(s)
	var royal := CourtSystem.royal_family_of(w, k)
	assert_not_null(royal, "the royal house is a family of the community")
	assert_eq(FamilySystem.estate_of(w, k, royal), FamilySystem.ROYAL, "and it stands apart")
	var other: FamilyState = null
	for f in families:
		if f.id != royal.id:
			other = f
			break
	other.records = {&"farmer": 400.0}
	assert_eq(FamilySystem.estate_of(w, k, other), &"people", "a family of the fields stays with the people")
	# a wedding with the royal house makes a noble house
	var groom: PersonState = null
	var bride: PersonState = null
	for p in w.people_of(home.id):
		if p.family == other.id and groom == null:
			groom = p
		elif p.family == royal.id and not p.is_king and bride == null:
			bride = p
	if groom and bride:
		groom.spouse = bride.id
		bride.spouse = groom.id
		assert_eq(FamilySystem.estate_of(w, k, other), &"nobility", "a family married into the royal house is noble")
	# an old, large, industrious house is noble too
	var elder: FamilyState = null
	for f in families:
		if f.id != royal.id and f.id != other.id:
			elder = f
			break
	elder.founding = true
	elder.founded_day = w.day - 30 * 360
	elder.records[&"children"] = 10.0
	elder.records[&"smith"] = 5000.0
	assert_true(FamilySystem.influence(w, elder) >= 70.0, "an old house weighs (%.0f)" % FamilySystem.influence(w, elder))
	assert_eq(FamilySystem.estate_of(w, k, elder), &"nobility", "and sits with the nobility")
	# a save from before the consolidation did not keep the royal family: it is found again
	var back := SaveSystem.session_from_data(JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s))) as Dictionary)
	back.world.player().royal_family = -1
	assert_eq(CourtSystem.royal_family_of(back.world, back.world.player()).id, royal.id, "and found again after a load")
	back.dispose()
	s.dispose()


## Consolidation: a large realm does not flood the Ceti sheet — a few notable families per estate, the others
## counted ("e altre N").
func test_many_families_do_not_flood_the_estates_sheet() -> void:
	var s := Session.start_new({"campaign_seed": 1513})
	var w := s.world
	var home := w.settlements[0]
	crown_player(s)
	PopulationSystem.welcome(s, home, 60, w.day, "prova")   # sixty newcomers, each with a family of his own
	var by := FamilySystem.families_by_estate(w, w.player(), home)
	var families := 0
	for estate: StringName in by.keys():
		families += (by[estate] as Array).size()
	assert_true(families >= 60, "the realm has many families (%d)" % families)
	var panel := _open(EstatesPanel.new()) as EstatesPanel
	panel.refresh()
	var limit := int(FamilySystem.estates_cfg().get("notable_per_estate", 3))
	assert_true(panel._families.get_child_count() <= limit * FamilySystem.ESTATE_ORDER.size(),
		"at most %d cards for each estate (%d cards for %d families)" % [limit, panel._families.get_child_count(), families])
	assert_true(_all_text(panel).contains("e altre"), "and the others are counted, not listed")
	_drop(panel)

