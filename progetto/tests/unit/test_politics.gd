extends KDTestCase
## Phase 7: the crown as a person and as a balance of powers — rulers, succession, laws, edicts, factions.


func _player(s: GameSession) -> KingdomState:
	return crown_player(s)


func test_every_realm_is_born_with_a_crowned_ruler() -> void:
	var s := GameSession.create_new({"campaign_seed": 701})
	var community := s.world.player()
	assert_false(community.monarchy_founded, "the player starts as a community (Phase 15)")
	assert_null(s.world.ruler_of(community.id), "and nobody reigns over it")
	for k in s.world.kingdoms:
		if k.provinces.is_empty() or k == community:
			continue
		var ruler := s.world.ruler_of(k.id)
		assert_not_null(ruler, "%s has a ruler" % k.name)
		if ruler == null:
			continue
		assert_true(ruler.name != "", "the ruler has a name")
		assert_true(ruler.age_years(s.world.day) >= 16, "%s reigns as an adult (%d)" % [ruler.name, ruler.age_years(s.world.day)])
		assert_true(ruler.traits.size() >= 1, "the ruler has traits")
		assert_true(ruler.skill(&"governo") >= 1, "the ruler has skills")
		assert_true(k.laws.has(&"succession"), "the realm has a law of succession")
		assert_eq(k.favour.size(), 5, "the five powers have an opinion")
	var king_people := 0
	for p: PersonState in s.world.people.values():
		if p.is_king:
			king_people += 1
	assert_eq(king_people, 0, "no king walks the village before the crown")
	_player(s)
	king_people = 0
	for p: PersonState in s.world.people.values():
		if p.is_king:
			king_people += 1
	assert_eq(king_people, 1, "once crowned, the player's king also stands on the map")
	var player_ruler := s.world.ruler_of(_player(s).id)
	assert_true(player_ruler.person >= 0 and s.world.person(player_ruler.person) != null,
		"the king of the chronicle and the king on the map are the same man")


func test_an_adult_heir_inherits_without_a_crisis() -> void:
	var s := GameSession.create_new({"campaign_seed": 702})
	var k := _player(s)
	var old := s.world.ruler_of(k.id)
	var heir := CourtSystem._make_character(s, k, 24, false, s.world.rng.stream(&"test"))
	heir.parent = old.id
	old.children = PackedInt32Array([heir.id])
	var legitimacy_before := k.legitimacy
	CourtSystem._die(s, k, old, s.world.day, "e morto")
	assert_eq(k.ruler, heir.id, "the adult son wears the crown")
	assert_false(k.regency, "no regency for an adult")
	assert_true(k.legitimacy >= legitimacy_before - 1.0, "an orderly succession does not shake the realm")
	var new_ruler := s.world.ruler_of(k.id)
	assert_not_null(new_ruler, "the new ruler is alive")
	assert_true(new_ruler.person >= 0 and s.world.person(new_ruler.person) != null, "and takes his place in the keep")


func test_a_child_heir_reigns_under_a_regency() -> void:
	var s := GameSession.create_new({"campaign_seed": 703})
	var k := _player(s)
	var old := s.world.ruler_of(k.id)
	var child := CourtSystem._make_character(s, k, 7, false, s.world.rng.stream(&"test"))
	child.parent = old.id
	old.children = PackedInt32Array([child.id])
	k.legitimacy = 70.0
	CourtSystem._die(s, k, old, s.world.day, "e morto")
	assert_eq(k.ruler, child.id, "the child inherits")
	assert_true(k.regency, "the realm is held in his name")
	assert_true(k.legitimacy < 70.0, "a child on the throne costs legitimacy (%.1f)" % k.legitimacy)
	assert_true(k.turbulence > 0.0, "and shakes the order")


func test_without_heirs_the_dynasty_falls_into_crisis() -> void:
	var s := GameSession.create_new({"campaign_seed": 704})
	var k := _player(s)
	var old := s.world.ruler_of(k.id)
	for c: CharacterState in s.world.characters.values():
		if c.id != old.id:
			c.death_day = s.world.day - 1
	old.children = PackedInt32Array()
	k.legitimacy = 70.0
	CourtSystem._die(s, k, old, s.world.day, "e morto")
	assert_true(k.ruler != old.id and k.ruler >= 0, "somebody is crowned all the same")
	assert_true(k.legitimacy < 55.0, "but the new branch is contested (%.1f)" % k.legitimacy)
	assert_true(k.turbulence >= 15.0, "and the realm is shaken")


func test_succession_follows_the_law_in_force() -> void:
	var s := GameSession.create_new({"campaign_seed": 705})
	var k := _player(s)
	var old := s.world.ruler_of(k.id)
	var rng := s.world.rng.stream(&"test")
	var elder := CourtSystem._make_character(s, k, 30, false, rng)
	elder.skills[&"governo"] = 2
	elder.skills[&"diplomazia"] = 2
	var younger := CourtSystem._make_character(s, k, 20, false, rng)
	younger.skills[&"governo"] = 9
	younger.skills[&"diplomazia"] = 9
	elder.parent = old.id
	younger.parent = old.id
	old.children = PackedInt32Array([younger.id, elder.id])
	k.laws[&"succession"] = &"primogeniture"
	assert_eq(CourtSystem.heir_of(s.world, k).id, elder.id, "primogeniture crowns the eldest")
	k.laws[&"succession"] = &"elective"
	assert_eq(CourtSystem.heir_of(s.world, k).id, younger.id, "an elective realm picks the most capable")
	k.laws[&"succession"] = &"seniority"
	assert_eq(CourtSystem.heir_of(s.world, k).id, elder.id, "seniority crowns the oldest of the house")
	k.heir_designate = younger.id
	assert_eq(CourtSystem.heir_of(s.world, k).id, younger.id, "a named heir comes before the law")


func test_a_law_has_winners_and_losers() -> void:
	var s := GameSession.create_new({"campaign_seed": 706})
	var k := _player(s)
	k.treasury = 500.0
	k.legitimacy = 60.0
	var nobility_before := float(k.favour[&"nobility"])
	var merchants_before := float(k.favour[&"merchants"])
	var taxes_before := KingdomModifiers.value(s, k.id, &"treasury.tax_income", 100.0)
	var res := s.submit(EnactLawCommand.create(k.id, &"taxation", &"catasto"))
	assert_true(res.success, "the catasto can be promulgated: %s" % res.reason)
	assert_near(k.treasury, 350.0, 0.01, "the law is paid for")
	assert_true(float(k.favour[&"nobility"]) < nobility_before, "the nobility resents being measured")
	assert_true(k.turbulence > 0.0, "the realm is shaken")
	var taxes_after := KingdomModifiers.value(s, k.id, &"treasury.tax_income", 100.0)
	assert_true(taxes_after > taxes_before * 1.1, "and the crown collects more (%.1f vs %.1f)" % [taxes_after, taxes_before])
	var labels := PackedStringArray()
	for part: Dictionary in KingdomModifiers.stack(s, k.id).breakdown(&"treasury.tax_income"):
		labels.append(String(part["label"]))
	assert_true(",".join(labels).contains("Catasto"), "the law says its name in the numbers: %s" % ",".join(labels))
	# the opposite law of the same group replaces it
	k.treasury = 500.0
	assert_true(s.submit(EnactLawCommand.create(k.id, &"taxation", &"franchigia")).success, "one law per group")
	assert_eq(StringName(k.laws[&"taxation"]), &"franchigia", "the group keeps a single law")
	assert_true(float(k.favour[&"merchants"]) > merchants_before, "the merchants are pleased")


func test_a_law_can_be_refused_with_a_reason() -> void:
	var s := GameSession.create_new({"campaign_seed": 707})
	var k := _player(s)
	k.treasury = 5.0
	var res := s.submit(EnactLawCommand.create(k.id, &"guilds", &"gilde_libere"))
	assert_false(res.success, "an empty treasury cannot pay for laws")
	assert_true(res.reason.contains("ori"), "and it says why: %s" % res.reason)
	k.treasury = 500.0
	k.legitimacy = 20.0
	assert_false(s.submit(EnactLawCommand.create(k.id, &"taxation", &"catasto")).success, "a weak crown cannot impose a catasto")
	k.legitimacy = 60.0
	assert_true(s.submit(EnactLawCommand.create(k.id, &"taxation", &"catasto")).success, "a firm one can")
	assert_false(s.submit(EnactLawCommand.create(k.id, &"taxation", &"catasto")).success, "and not twice")


func test_an_edict_lasts_thirty_days_and_then_expires() -> void:
	var s := GameSession.create_new({"campaign_seed": 708})
	var k := _player(s)
	k.treasury = 300.0
	assert_true(s.submit(IssueEdictCommand.create(k.id, &"turni_lunghi")).success, "the edict is issued")
	var fast := KingdomModifiers.value(s, k.id, &"construction.speed", 1.0)
	assert_true(fast > 1.1, "long shifts build faster (%.2f)" % fast)
	s.advance_days(10)
	assert_true(k.edicts.has(&"turni_lunghi"), "after ten days it still holds")
	s.advance_days(25)
	assert_false(k.edicts.has(&"turni_lunghi"), "after thirty it is gone")
	assert_true(KingdomModifiers.value(s, k.id, &"construction.speed", 1.0) < fast, "and the works slow down again")
	k.treasury = 300.0
	assert_true(s.submit(IssueEdictCommand.create(k.id, &"coprifuoco")).success, "the curfew is issued")
	assert_true(s.submit(IssueEdictCommand.create(k.id, &"coprifuoco", true)).success, "and revoked")
	assert_false(k.edicts.has(&"coprifuoco"), "the edict is no longer in force")


func test_the_measures_of_the_crown_follow_the_facts() -> void:
	var s := GameSession.create_new({"campaign_seed": 709})
	var k := _player(s)
	var ruler := s.world.ruler_of(k.id)
	var heir := CourtSystem._make_character(s, k, 22, false, s.world.rng.stream(&"test"))
	heir.parent = ruler.id
	ruler.children = PackedInt32Array([heir.id])
	for f: FactionDef in Defs.all("factions"):
		k.favour[f.id] = 75.0
	k.legitimacy = 50.0
	s.advance_days(120)
	var strong := k.legitimacy
	assert_true(strong > 50.0, "an heir and contented powers make a firmer crown (%.1f)" % strong)
	assert_true(k.prestige > 0.0, "and the realm has a standing")
	for f: FactionDef in Defs.all("factions"):
		k.favour[f.id] = 10.0
	k.heir_designate = -1
	heir.death_day = s.world.day
	ruler.children = PackedInt32Array()
	s.advance_days(240)
	assert_true(k.legitimacy < strong - 5.0, "hostile powers and no heir wear it down (%.1f)" % k.legitimacy)
	assert_true(k.stability < 100.0, "and the order of the realm suffers (%.1f)" % k.stability)


func test_sixty_years_of_reigns_without_errors() -> void:
	var s := GameSession.create_new({"campaign_seed": 710})
	var k := _player(s)
	var last := k.ruler
	var changes := 0
	for year in 60:
		s.advance_days(360)
		if k.ruler != last:
			changes += 1
			last = k.ruler
		assert_true(k.ruler >= 0, "there is always somebody on the throne (year %d)" % year)
		assert_true(k.legitimacy >= 0.0 and k.legitimacy <= 100.0, "legitimacy stays in range (%.1f)" % k.legitimacy)
		assert_true(k.stability >= 0.0 and k.stability <= 100.0, "order stays in range (%.1f)" % k.stability)
	assert_true(changes >= 2, "sixty years saw at least two new rulers (%d)" % changes)
	var ruler := s.world.ruler_of(k.id)
	assert_not_null(ruler, "and the realm ends with a crowned head")


func test_the_court_survives_a_save() -> void:
	var s := GameSession.create_new({"campaign_seed": 711})
	var k := _player(s)
	k.treasury = 500.0
	s.submit(EnactLawCommand.create(k.id, &"faith", &"tolleranza"))
	s.submit(IssueEdictCommand.create(k.id, &"granai_aperti"))
	s.advance_days(12)
	var before := KingdomModifiers.value(s, k.id, &"trade.income", 1.0)
	var ruler_name := s.world.ruler_of(k.id).name
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s)))
	var loaded := SaveSystem.session_from_data(data)
	var k2 := loaded.world.player()
	assert_not_null(loaded.world.ruler_of(k2.id), "the ruler crosses the save")
	assert_eq(loaded.world.ruler_of(k2.id).name, ruler_name, "with his name")
	assert_eq(StringName(k2.laws[&"faith"]), &"tolleranza", "the laws cross it too")
	assert_near(KingdomModifiers.value(loaded, k2.id, &"trade.income", 1.0), before, 0.0001, "and the numbers are the same")
	assert_eq(k2.favour.size(), k.favour.size(), "the powers keep their opinions")
	assert_true(k2.edicts.has(&"granai_aperti"), "the edict is still running")


func _taxes_of_a_month_at_order(seed_value: int, stability_value: float) -> float:
	var s := GameSession.create_new({"campaign_seed": seed_value})
	var k := _player(s)
	for day in 31:
		k.stability = stability_value
		s.advance_days(1)
	return float(k.last_balance["taxes"])


func test_a_realm_in_disorder_collects_less() -> void:
	var orderly := _taxes_of_a_month_at_order(712, 100.0)
	var troubled := _taxes_of_a_month_at_order(712, 20.0)
	assert_true(orderly > 0.0, "an obeyed crown collects its tax (%.2f)" % orderly)
	assert_true(troubled < orderly * 0.95, "where the crown is not obeyed the tax is evaded (%.2f vs %.2f)" % [troubled, orderly])
	assert_true(troubled > 0.0, "but something still reaches the treasury")


## Consolidation: the chronicle keeps the history, not the traffic. The deeds of the player's realm and whatever
## the others do to it are written; of the other crowns only what changes the world.
func test_the_chronicle_keeps_the_history_not_the_traffic() -> void:
	var s := GameSession.create_new({"campaign_seed": 1912})
	var w := s.world
	var me := w.player_kingdom
	var others: Array[int] = []
	for k in w.kingdoms:
		if k.id != me and k.alive:
			others.append(k.id)
	var before := w.chronicle.size()
	var day := w.day
	EventBus.chronicle_written.emit({"day": day, "kingdom": others[0], "other": others[1], "kind": "march", "text": "Una marcia fra altri."})
	EventBus.chronicle_written.emit({"day": day, "kingdom": others[0], "other": others[1], "kind": "pact", "text": "Un patto fra altri."})
	EventBus.chronicle_written.emit({"day": day, "kingdom": others[0], "other": others[1], "kind": "siege", "text": "Un assedio fra altri."})
	assert_eq(w.chronicle.size(), before, "the traffic of the other crowns is not history")
	EventBus.chronicle_written.emit({"day": day, "kingdom": others[0], "other": me, "kind": "siege", "text": "Il nemico assedia le nostre terre."})
	EventBus.chronicle_written.emit({"day": day, "kingdom": me, "kind": "law", "text": "Una legge nostra."})
	EventBus.chronicle_written.emit({"day": day, "kingdom": others[0], "other": others[1], "kind": "war", "text": "Una guerra fra altri."})
	EventBus.chronicle_written.emit({"day": day, "kingdom": others[1], "kind": "succession", "text": "Un re nuovo altrove."})
	var texts: Array = []
	for e: Dictionary in w.chronicle.slice(before):
		texts.append(String(e["text"]))
	assert_eq(texts, ["Il nemico assedia le nostre terre.", "Una legge nostra.", "Una guerra fra altri.", "Un re nuovo altrove."],
		"what touches the realm, and what changes the world, is written")
	assert_eq(int(w.chronicle[before]["other"]), me, "with the realm it touched")
	var back := SaveSystem.session_from_data(JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s))) as Dictionary)
	assert_eq(int(back.world.chronicle[before]["other"]), me, "also after a load")
	back.dispose()
	s.dispose()

