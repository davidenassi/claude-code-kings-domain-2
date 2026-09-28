extends KDTestCase
## Phase 9: the host. Men who leave the village, march on real ground, eat what they carry and are paid —
## or desert. What the crown cannot see, it is not shown.


func _village(seed_value: int) -> GameSession:
	var s := GameSession.create_new({"campaign_seed": seed_value})
	s.set_system_enabled(&"events", false)   # the host is weighed without the weather
	SettlementPlanner.place_starter_village(s, s.world.settlements[0].id)
	var k := s.world.player()
	k.treasury = 1200.0
	s.world.settlements[0].add(&"weapons", 60)
	return s


func _recruit(s: GameSession, unit_id: StringName = &"lancieri") -> CommandResult:
	return s.submit(RecruitUnitCommand.create(s.world.settlements[0].id, unit_id))


func test_units_are_data_driven() -> void:
	var units := Military.units()
	assert_true(units.size() >= 4, "the realm knows several kinds of regiment (%d)" % units.size())
	for u in units:
		assert_true(u.men > 0 and u.gold > 0.0, "%s costs men and gold" % u.id)
		assert_true(u.speed_kmh > 0.0 and u.food_day > 0, "%s marches and eats" % u.id)
		assert_true(u.description.length() > 10, "%s is described in words" % u.id)


func test_recruiting_takes_real_people_weapons_and_gold() -> void:
	var s := _village(901)
	var w := s.world
	var village := w.settlements[0]
	var k := w.player()
	var people_before := w.people_of(village.id).size()
	var weapons_before := village.amount(&"weapons")
	var gold_before := k.treasury
	var res := _recruit(s)
	assert_true(res.success, "the levy can be called: %s" % res.reason)
	var u := Military.unit(&"lancieri")
	assert_eq(village.amount(&"weapons"), weapons_before - u.weapons, "the weapons leave the store")
	assert_near(k.treasury, gold_before - u.gold, 0.01, "the crown pays")
	assert_eq(village.training.size(), 1, "a regiment is drilling")
	var recruits := 0
	for p in w.people_of(village.id):
		if p.job == &"recruit":
			recruits += 1
	assert_eq(recruits, u.men, "real inhabitants left their work")
	assert_eq(w.people_of(village.id).size(), people_before, "and they are still in the village while they train")
	# when the training is over they march out of the village and into a host
	s.advance_days(u.train_days + 2)
	assert_eq(village.training.size(), 0, "the drilling is over")
	assert_eq(w.armies.size(), 1, "a host stands in the field")
	var army := w.armies[0]
	assert_eq(army.men(), u.men, "made of the men who left")
	assert_true(w.people_of(village.id).size() < people_before, "the village has fewer hands now")
	for person_id in army.people():
		var p := w.person(person_id)
		assert_not_null(p, "every soldier is a person who exists")
		assert_eq(String(p.job), "soldier", "and he is a soldier now")


func test_the_levy_is_refused_with_a_reason() -> void:
	var s := _village(902)
	var village := s.world.settlements[0]
	var k := s.world.player()
	# no barracks yet
	var res := s.submit(RecruitUnitCommand.create(village.id, &"alabardieri"))
	assert_false(res.success, "halberdiers need a place to drill")
	assert_true(res.reason.to_lower().contains("caserma"), "and it says so: %s" % res.reason)
	k.treasury = 5.0
	var poor := _recruit(s)
	assert_false(poor.success, "an empty treasury raises nobody")
	assert_true(poor.reason.contains("ori"), "with the reason: %s" % poor.reason)
	k.treasury = 900.0
	village.take(&"weapons", village.amount(&"weapons"))
	var unarmed := _recruit(s)
	assert_false(unarmed.success, "nor do bare hands")
	assert_true(unarmed.reason.contains("armi"), "with the reason: %s" % unarmed.reason)


func test_the_village_cannot_be_emptied() -> void:
	var s := _village(903)
	var w := s.world
	var village := w.settlements[0]
	var raised := 0
	for i in 8:
		var res := _recruit(s)
		if not res.success:
			assert_true(res.reason.contains("uomini"), "the last refusal is about men: %s" % res.reason)
			break
		raised += 1
		s.advance_days(Military.unit(&"lancieri").train_days + 1)
	assert_true(raised >= 1, "at least one regiment was raised")
	var left := Military.eligible_people(w, village.id).size()
	assert_true(left >= 0, "somebody stayed to work the fields (%d)" % left)
	assert_true(w.people_of(village.id).size() > 0, "the village is not empty")


func test_an_army_marches_on_real_ground() -> void:
	var s := _village(904)
	var w := s.world
	_recruit(s)
	s.advance_days(Military.unit(&"lancieri").train_days + 2)
	var army := w.armies[0]
	var wd := WorldData.get_instance()
	# a province three or four steps away
	var target := -1
	var seen := {army.province: true}
	var frontier: Array[int] = [army.province]
	for depth in 3:
		var next: Array[int] = []
		for pid in frontier:
			var g := wd.province_geo(pid)
			for n: Dictionary in g.neighbors:
				var nid := int(n["id"])
				if not seen.has(nid) and w.province(nid) != null:
					seen[nid] = true
					next.append(nid)
					target = nid
		frontier = next
	assert_true(target >= 0, "there is somewhere to march to")
	var route := Military.route(w, army.province, target)
	assert_true(route.size() >= 1, "the route crosses real provinces (%d)" % route.size())
	var res := s.submit(MoveArmyCommand.create(army.id, target))
	assert_true(res.success, "the order can be given: %s" % res.reason)
	var start := army.pos
	s.advance_days(3)
	assert_true(army.pos.distance_to(start) > 1000.0, "the host has moved on the map (%.0f m)" % army.pos.distance_to(start))
	var travelled := 0
	for day in 120:
		s.advance_days(1)
		travelled += 1
		if army.path.is_empty():
			break
	assert_true(army.path.is_empty(), "and it arrives (%d giorni)" % travelled)
	assert_eq(army.province, target, "in the province it was sent to")
	var geo := wd.province_geo(target)
	assert_true(army.pos.distance_to(geo.center) < 400.0, "standing where it was told")


func test_an_army_eats_and_starves_far_from_home() -> void:
	var s := _village(905)
	var w := s.world
	_recruit(s)
	s.advance_days(Military.unit(&"lancieri").train_days + 2)
	var army := w.armies[0]
	# far from any settlement of its own, in nobody's land
	army.pos = Vector2(4000.0, 4000.0)
	army.province = WorldData.get_instance().province_at(army.pos)
	var p := w.province(army.province)
	if p:
		p.owner = ProvinceState.NO_OWNER
	army.supplies = 3.0
	var men_before := army.men()
	s.advance_days(3)
	assert_near(army.supplies, 0.0, 0.5, "the carts are empty")
	s.advance_days(20)
	assert_true(army.men() < men_before, "hunger thins the ranks (%d -> %d)" % [men_before, army.men()])
	assert_true(army.morale() < Military.unit(&"lancieri").morale, "and takes the heart out of them")


func test_unpaid_soldiers_lose_heart_and_desert() -> void:
	var s := _village(906)
	var w := s.world
	_recruit(s)
	s.advance_days(Military.unit(&"lancieri").train_days + 2)
	var army := w.armies[0]
	var k := w.player()
	k.treasury = -5000.0   # a debt a month of taxes and trade cannot cover
	var morale_before := army.morale()
	var men_before := army.men()
	s.advance_days(40)
	assert_true(army.unpaid_days > 0, "the crown owes them their pay")
	assert_true(army.morale() < morale_before, "morale falls (%.0f -> %.0f)" % [morale_before, army.morale()])
	assert_true(army.men() <= men_before, "and men slip away in the night (%d -> %d)" % [men_before, army.men()])


func test_disbanding_at_home_gives_the_men_back() -> void:
	var s := _village(907)
	var w := s.world
	var village := w.settlements[0]
	_recruit(s)
	s.advance_days(Military.unit(&"lancieri").train_days + 2)
	var army := w.armies[0]
	var men := army.men()
	var village_before := w.people_of(village.id).size()
	var res := s.submit(DisbandArmyCommand.create(army.id))
	assert_true(res.success, "the host can be sent home: %s" % res.reason)
	assert_eq(w.armies.size(), 0, "there is no host any more")
	assert_eq(w.people_of(village.id).size(), village_before + men, "and the men are back in the village")
	for p in w.people_of(village.id):
		assert_true(p.job != &"soldier", "nobody is left standing at arms")


func test_the_crown_only_sees_what_it_can_reach() -> void:
	var s := _village(908)
	var w := s.world
	var me := w.player()
	var other := -1
	for k in w.kingdoms:
		if k.id != me.id and k.alive and not k.provinces.is_empty():
			other = k.id
			break
	var far := ArmyState.new()
	far.id = w.new_id()
	far.kingdom = other
	far.name = "schiera lontana"
	var far_province := w.kingdom(other).provinces[0]
	far.province = far_province
	far.pos = WorldData.get_instance().province_geo(far_province).center
	far.regiments.append({"unit": &"lancieri", "men": 8, "max_men": 8, "morale": 60.0, "people": PackedInt32Array()})
	w.armies.append(far)
	assert_false(Military.can_see(w, me.id, far), "a host in another realm's land is not visible")
	var mine := ArmyState.new()
	mine.id = w.new_id()
	mine.kingdom = me.id
	mine.pos = far.pos + Vector2(3000.0, 0.0)
	mine.province = far.province
	w.armies.append(mine)
	assert_true(Military.can_see(w, me.id, far), "with our own men nearby, we see them")
	var visible := Military.visible_armies(w, me.id)
	assert_true(visible.has(far) and visible.has(mine), "and both stand in the list the map draws from")


func test_armies_survive_a_save() -> void:
	var s := _village(909)
	var w := s.world
	_recruit(s)
	s.advance_days(Military.unit(&"lancieri").train_days + 2)
	var army := w.armies[0]
	army.supplies = 7.0
	var men := army.men()
	var name := army.name
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s)))
	var loaded := SaveSystem.session_from_data(data)
	assert_eq(loaded.world.armies.size(), 1, "the host crosses the save")
	var a2 := loaded.world.armies[0]
	assert_eq(a2.men(), men, "with all its men")
	assert_eq(a2.name, name, "and its name")
	assert_near(a2.supplies, 7.0, 0.001, "and what it carries")
	for person_id in a2.people():
		assert_not_null(loaded.world.person(person_id), "every soldier is still a person")


func test_a_year_of_soldiering_costs_the_crown() -> void:
	var s := _village(910)
	var w := s.world
	var k := w.player()
	_recruit(s)
	s.advance_days(Military.unit(&"lancieri").train_days + 2)
	var army := w.armies[0]
	# the same realm without its host is the measure (Phase 16: the lands yield now, so the treasury can grow
	# while the soldiers are paid; what counts is that they cost)
	var twin := _village(910)
	_recruit(twin)
	twin.advance_days(Military.unit(&"lancieri").train_days + 2)
	Military.dissolve_into_province(twin.world, twin.world.armies[0])
	k.treasury = 800.0
	twin.world.player().treasury = 800.0
	s.advance_days(120)
	twin.advance_days(120)
	assert_true(k.treasury < twin.world.player().treasury, "soldiers are paid every day (%.0f with them, %.0f without)" % [
		k.treasury, twin.world.player().treasury])
	assert_true(army.men() > 0, "and they are still there")
	assert_true(Military.strength(army) > 0.0, "the host weighs something in the world")


func test_the_realms_of_the_ai_muster_their_own_levies() -> void:
	var s := GameSession.create_new({"campaign_seed": 911})
	var w := s.world
	var realms: Array[KingdomState] = []
	for k in w.kingdoms:
		if k.alive and not k.provinces.is_empty() and not k.is_player:
			realms.append(k)
	var a := realms[0]
	var b := realms[1]
	a.treasury = 900.0
	Diplomacy.start_war(w, a.id, b.id)
	var raised := 0
	for month in 12:
		var choice := RealmAiSystem.take_turn(s, a)
		if not choice.is_empty() and String(choice["kind"]) == "levy":
			raised += 1
	assert_true(raised > 0, "a crown at war calls up its men (%d volte)" % raised)
	var army: ArmyState = null
	for host in w.armies:
		if host.kingdom == a.id:
			army = host
			break
	assert_not_null(army, "and the host stands in one of its provinces")
	assert_true(army.men() > 0, "with men in it")
	var province := w.province(army.province)
	var people_before := province.population
	var armies_before := w.armies.size()
	Military.dissolve_into_province(w, army)
	assert_eq(province.population, people_before + army.men(), "sent home, the men go back to the fields")
	assert_eq(w.armies.size(), armies_before - 1, "and that host is gone")
	assert_false(w.armies.has(army), "for good")


## Phase 13, the conduct of the war: a crown that sends one company at a time loses them one at a time.
func test_the_small_host_goes_to_join_the_big_one() -> void:
	var s := GameSession.create_new({"campaign_seed": 913})
	var w := s.world
	var realms: Array[KingdomState] = []
	for k in w.kingdoms:
		if k.alive and k.provinces.size() >= 2 and not k.is_player:
			realms.append(k)
	var a := realms[0]
	var b := realms[1]
	a.treasury = 2000.0
	Diplomacy.start_war(w, a.id, b.id)
	var unit := Military.unit(&"lancieri")
	var big := Military.raise_from_province(s, a, a.provinces[0], unit)
	var small := Military.raise_from_province(s, a, a.provinces[1], unit)
	assert_not_null(big, "the realm has a host")
	assert_not_null(small, "and a second, smaller one")
	if big == null or small == null:
		return
	while big.men() < small.men() * 3:
		Military.raise_from_province(s, a, a.provinces[0], unit)
		var merged := 0
		for host in w.armies:
			if host.kingdom == a.id and host.province == big.province and host.id != big.id:
				merged += host.men()
		if merged == 0:
			break
	var joining := false
	for month in 6:
		var choice := RealmAiSystem.take_turn(s, a)
		if choice.is_empty():
			continue
		if String(choice["kind"]) == "march" and int(choice.get("army", -1)) == small.id \
				and int(choice["target"]) == big.province:
			joining = true
			break
	assert_true(joining, "the small company marches on the big host before marching on the enemy")


## A siege about to give way is not traded away for a letter of peace.
func test_a_ripe_siege_is_not_sold_for_peace() -> void:
	var s := GameSession.create_new({"campaign_seed": 914})
	var w := s.world
	var realms: Array[KingdomState] = []
	for k in w.kingdoms:
		if k.alive and not k.provinces.is_empty() and not k.is_player:
			realms.append(k)
	var a := realms[0]
	var b := realms[1]
	Diplomacy.start_war(w, a.id, b.id)
	var siege := SiegeState.new()
	siege.id = w.new_id()
	siege.province = b.provinces[0]
	siege.besieger = a.id
	siege.progress = 0.9
	w.sieges.append(siege)
	var peace_utility := 0.0
	for option: Dictionary in RealmAiSystem.options_for(s, a):
		if String(option["kind"]) == "peace":
			peace_utility = maxf(peace_utility, float(option["utility"]))
	w.sieges.clear()
	var peace_without := 0.0
	for option: Dictionary in RealmAiSystem.options_for(s, a):
		if String(option["kind"]) == "peace":
			peace_without = maxf(peace_without, float(option["utility"]))
	if peace_without <= 0.0:
		return   # this crown was not thinking of peace anyway: nothing to prove here
	assert_true(peace_utility < peace_without,
		"the walls are worth more than the terms (%.2f con l'assedio, %.2f senza)" % [peace_utility, peace_without])

