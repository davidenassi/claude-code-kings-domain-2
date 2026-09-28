extends KDTestCase
## Phase 16: what whole campaigns taught. The food is counted for what the ovens can really bake; what a village
## has beyond its needs is sold; a community signs no treaties and nobody pays two lords; a quarry nobody works in
## calls a hand from the fields; the careful lord never stops the village for a wish it cannot pay.

const Economy := preload("res://tests/unit/test_economy.gd")


func after_each() -> void:
	Session.end()


func test_grain_is_bread_only_as_far_as_the_ovens_bake_it() -> void:
	var s := Economy.village(1651)
	var w := s.world
	var st := w.settlements[0]
	s.advance_days(40)   # the oven is built and a baker works in it
	var ovens := PopulationSystem._ovens(w, st)
	assert_true(ovens.has(&"grain"), "the manned oven bakes grain")
	st.stock[&"bread"] = 0
	st.stock[&"grain"] = 400
	var few := PopulationSystem.food_days(w, st)
	st.stock[&"grain"] = 4000
	var many := PopulationSystem.food_days(w, st)
	var people := w.people_of(st.id).size()
	var all_baked := 4000.0 * float(ovens[&"grain"]["value"]) / (0.25 * people)
	var all_raw := 4000.0 * Defs.resource(&"grain").food_value / (0.25 * people)
	assert_true(many > all_raw, "the oven makes the grain worth more than raw (%.0f > %.0f)" % [many, all_raw])
	assert_true(many <= all_baked + 0.01, "never more than all of it baked (%.0f <= %.0f)" % [many, all_baked])
	assert_true(many > few, "more grain is still more days")
	# the baker leaves the oven: the grain is worth what it is worth raw, however big the oven
	for p in w.people_of(st.id):
		if p.job == &"baker":
			p.job = &"idle"
			p.workplace = -1
	assert_near(PopulationSystem.food_days(w, st), all_raw, 0.5, "an oven nobody works in bakes nothing")


func test_what_is_beyond_the_reserve_is_sold() -> void:
	var s := Economy.village(1652)
	var w := s.world
	var k := w.player()
	var st := w.settlements[0]
	s.advance_days(31)
	var people := w.people_of(st.id).size()
	var reserve := int(float(EconomySystem.bal()["trade"]["reserve_per_person"]["wood"]) * people)
	st.stock[&"wood"] = reserve + 200
	var gold := EconomySystem.sell_surplus(s, k, st)
	assert_true(gold > 0.0, "the merchants pay for the wood beyond the reserve (%.1f)" % gold)
	assert_true(st.amount(&"wood") < reserve + 200 and st.amount(&"wood") >= reserve, "and the reserve stays (%d)" % st.amount(&"wood"))
	st.stock[&"wood"] = reserve
	assert_near(EconomySystem.sell_surplus(s, k, st), 0.0, 0.0001, "nothing is sold from the reserve")
	st.stock[&"grain"] = 5
	st.stock[&"bread"] = 5
	var food_before := st.amount(&"grain") + st.amount(&"bread")
	EconomySystem.sell_surplus(s, k, st)
	assert_eq(st.amount(&"grain") + st.amount(&"bread"), food_before, "and no bread leaves a hungry village")


func test_a_community_signs_no_treaty_and_nobody_pays_two_lords() -> void:
	var s := GameSession.create_new({"campaign_seed": 1653})
	var w := s.world
	var me := w.player()
	var others: Array[KingdomState] = []
	for k in w.kingdoms:
		if k != me and k.alive and not k.provinces.is_empty():
			others.append(k)
	assert_true(Diplomacy.pact_blocker(w, others[0], me, &"trade").contains("comunità"), "a community signs nothing")
	crown_player(s)
	assert_eq(Diplomacy.pact_blocker(w, others[0], me, &"trade"), "", "a kingdom can trade")
	# the player pays a first lord: a second one is refused
	Diplomacy.sign(w, others[0].id, me.id, &"tribute")
	var r := Diplomacy.relation(w, others[0].id, me.id)
	r.payer = me.id
	assert_eq(Diplomacy.lord_of(w, me.id), others[0].id, "the first lord is known")
	var why := Diplomacy.pact_blocker(w, others[1], me, &"tribute")
	if Diplomacy.power(w, me) < Diplomacy.power(w, others[1]):
		assert_true(why.contains("altro signore"), "nobody pays two lords: %s" % why)


func test_an_empty_quarry_calls_a_hand_from_the_fields() -> void:
	var s := Economy.village(1654)
	var w := s.world
	var st := w.settlements[0]
	s.advance_days(60)
	st.stock[&"grain"] = 900
	st.stock[&"bread"] = 400
	st.stock[&"wood"] = 200
	var spot := SettlementPlanner.find_spot(s, st.id, &"quarry", st.center, 30.0, false, 900.0)
	assert_true(spot != Vector2.INF, "a quarry fits")
	var res := s.submit(PlaceBuildingCommand.create(st.id, &"quarry", spot))
	var quarry := w.building(int(res.data["building"]))
	for i in 60:
		s.advance_days(1)
		if quarry.is_active():
			break
	assert_true(quarry.is_active(), "the quarry is built")
	for p in w.people_of(st.id):
		if p.job == &"idle" or p.job == &"builder":
			p.job = &"farmer"   # everybody in the fields, as in the villages that never cut a stone again
	SettlementSim.assign_jobs(w, st)
	var quarriers := w.people_of(st.id).filter(func(p: PersonState) -> bool: return p.job == &"quarrier").size()
	assert_true(quarriers >= 1, "with the granary full, a farmer goes to the quarry (%d)" % quarriers)


func test_the_careful_lord_does_not_stop_for_what_it_cannot_pay() -> void:
	var s := Economy.village(1655)
	var w := s.world
	var st := w.settlements[0]
	s.advance_days(90)
	st.stock[&"stone"] = 0   # the ovens and the granaries cannot be paid
	st.stock[&"wood"] = 300
	var before := w.buildings_of(st.id).size()
	for m in 6:
		SettlementPlanner.lord_month(s, st.id)
		s.advance_days(30)
	assert_true(w.buildings_of(st.id).size() > before, "it builds what it can instead (%d → %d)" % [before, w.buildings_of(st.id).size()])
	assert_false(SettlementPlanner.affordable(w, st, Defs.building(&"bakery")) and st.amount(&"stone") < 14,
		"and knows an oven without stone cannot be paid")


func test_an_edict_rests_before_it_can_come_back() -> void:
	var s := GameSession.create_new({"campaign_seed": 1656})
	var k := crown_player(s)
	k.treasury = 1000.0
	var people_before := float(k.favour.get(&"people", 55.0))
	assert_true(s.submit(IssueEdictCommand.create(k.id, &"coprifuoco")).success, "the curfew is proclaimed")
	assert_near(float(k.favour.get(&"_law_bias_people", 0.0)), 0.0, 0.001, "an edict leaves no lasting grudge")
	assert_true(float(k.favour[&"people"]) < people_before, "but the people feel it now")
	s.advance_days(35)
	assert_false(k.edicts.has(&"coprifuoco"), "a season later it is over")
	var again := IssueEdictCommand.create(k.id, &"coprifuoco").validate(s)
	assert_true(again.contains("riproclamare"), "and it cannot come back at once: %s" % again)
	s.advance_days(200)
	assert_eq(IssueEdictCommand.create(k.id, &"coprifuoco").validate(s), "", "after the rest it can")


func test_a_wide_realm_pays_for_its_administration() -> void:
	var s := GameSession.create_new({"campaign_seed": 1657})
	var k := crown_player(s)
	assert_near(EconomySystem.administration_share(k), 0.0, 0.001, "a realm of one land pays no officials")
	var taken := 0
	for p in s.world.provinces:
		if taken >= 30:
			break
		if p.is_free():
			s.world.set_province_owner(p.id, k.id)
			taken += 1
	var share := EconomySystem.administration_share(k)
	assert_true(share > 0.3 and share <= 0.8, "thirty lands later a good share of the rents goes to the officials (%.2f)" % share)


func test_gold_buys_peace_at_home_once_a_year() -> void:
	var s := GameSession.create_new({"campaign_seed": 1658})
	var k := crown_player(s)
	k.treasury = 2000.0
	k.favour[&"nobility"] = 30.0
	var price := GiftFactionCommand.cost(k)
	var res := s.submit(GiftFactionCommand.create(k.id, &"nobility"))
	assert_true(res.success, "the crown courts the nobility: %s" % res.reason)
	assert_near(k.treasury, 2000.0 - price, 0.01, "and pays for it")
	assert_true(float(k.favour[&"nobility"]) > 35.0, "the nobles are warmer (%.0f)" % float(k.favour[&"nobility"]))
	assert_true(float(k.favour.get(&"_law_bias_nobility", 0.0)) > 0.0, "and they remember it")
	var again := GiftFactionCommand.create(k.id, &"nobility").validate(s)
	assert_true(again.contains("quest'anno"), "not twice in a year: %s" % again)


func test_prestige_remembers_deeds_and_never_sits_on_the_top() -> void:
	var s := GameSession.create_new({"campaign_seed": 1659})
	var k := crown_player(s)
	s.advance_days(14)
	var before := k.prestige
	CourtSystem.add_prestige(k, 20.0)
	s.advance_days(14)   # the weekly measures run again: the deed must not vanish
	assert_true(k.prestige > before + 5.0, "a deed is still there after the measures run (%.1f → %.1f)" % [before, k.prestige])
	CourtSystem.add_prestige(k, 5000.0)
	s.advance_days(14)
	assert_true(k.prestige < 100.0, "however great the deeds, prestige is not pinned at 100 (%.1f)" % k.prestige)

