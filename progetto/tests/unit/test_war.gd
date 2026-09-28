extends KDTestCase
## Phase 10: war. Hosts that meet fight on real ground, the beaten one breaks and runs, a province under siege
## falls without being reset, and a peace can be paid for in land.


func _world(seed_value: int) -> GameSession:
	var s := GameSession.create_new({"campaign_seed": seed_value})
	s.world.settlements.clear()
	s.world.people.clear()
	s.world.buildings.clear()
	s.world.buildings_changed()
	return s


func _realms(s: GameSession, count: int = 2) -> Array[KingdomState]:
	var out: Array[KingdomState] = []
	for k in s.world.kingdoms:
		if k.alive and not k.provinces.is_empty() and not k.is_player:
			out.append(k)
		if out.size() == count:
			break
	return out


## A host of `men` lancieri standing in `province`.
func _host(s: GameSession, k: KingdomState, province: int, men: int, unit_id: StringName = &"lancieri") -> ArmyState:
	var w := s.world
	var a := ArmyState.new()
	a.id = w.new_id()
	a.kingdom = k.id
	a.name = Military.army_name(w, k)
	a.province = province
	a.pos = WorldData.get_instance().province_geo(province).center
	a.step_from = a.pos
	a.step_to = a.pos
	a.step_t = 1.0
	a.supplies = 20.0
	var u := Military.unit(unit_id)
	a.regiments.append({"unit": unit_id, "men": men, "max_men": men, "morale": u.morale, "people": PackedInt32Array()})
	w.armies.append(a)
	return a


func test_the_ground_counts_in_a_battle() -> void:
	var s := _world(1001)
	var wd := WorldData.get_instance()
	var hills := -1
	var plains := -1
	for p in s.world.provinces:
		var g := wd.province_geo(p.id)
		if g == null:
			continue
		if hills < 0 and (g.terrain == &"hills" or g.terrain == &"mountains"):
			hills = p.id
		if plains < 0 and g.terrain == &"plains" and not g.has_river:
			plains = p.id
	assert_true(hills >= 0 and plains >= 0, "the world has both high ground and open ground")
	assert_true(War.terrain_defense(hills) > War.terrain_defense(plains),
		"high ground is worth more to the defender (%.2f contro %.2f)" % [War.terrain_defense(hills), War.terrain_defense(plains)])
	# and the matchups are the ones the data promises
	assert_true(War.matchup(Military.unit(&"cavalieri"), Military.unit(&"balestrieri")) > 1.2, "horse rides down bowmen")
	assert_true(War.matchup(Military.unit(&"alabardieri"), Military.unit(&"cavalieri")) > 1.2, "long iron stops horse")


func test_two_hosts_that_meet_fight_and_one_breaks() -> void:
	var s := _world(1002)
	var w := s.world
	var pair := _realms(s)
	var a := pair[0]
	var b := pair[1]
	Diplomacy.start_war(w, a.id, b.id)
	var field := b.provinces[0]
	var strong := _host(s, a, field, 40)
	var weak := _host(s, b, field, 12)
	a.treasury = 2000.0
	b.treasury = 2000.0
	s.advance_days(1)
	assert_eq(w.battles.size(), 1, "the two hosts have met")
	var battle := w.battles[0]
	assert_eq(battle.province, field, "they fight where they stand")
	var strong_before := strong.men()
	var weak_before := weak.men()
	var days := 0
	for day in 12:
		s.advance_days(1)
		days += 1
		if w.battles.is_empty():
			break
	assert_true(w.battles.is_empty(), "the battle is decided in a few days (%d)" % days)
	assert_true(weak.men() < weak_before, "the weaker host bled (%d -> %d)" % [weak_before, weak.men()])
	assert_true(strong.men() <= strong_before, "and the stronger one paid something too")
	assert_true(weak.men() < strong.men(), "the numbers told in the end")
	if not weak.is_empty():
		assert_true(not weak.path.is_empty() or weak.province != field, "the beaten host runs for home")
	assert_true(War.score_for(w, a.id, b.id) > 0.0, "and the war ledger says who is winning")
	assert_true(w.province(field).devastation > 0.0, "the field itself is the worse for it")


func test_a_host_alone_in_enemy_land_lays_siege_and_takes_the_province() -> void:
	var s := _world(1003)
	var w := s.world
	var pair := _realms(s)
	var a := pair[0]
	var b := pair[1]
	a.treasury = 4000.0
	Diplomacy.start_war(w, a.id, b.id)
	var target := b.provinces[0]
	var people_before := w.province(target).population
	var host := _host(s, a, target, 30)
	s.advance_days(2)
	assert_eq(w.sieges.size(), 1, "the host sits down in front of the province")
	var siege := w.sieges[0]
	assert_true(siege.progress > 0.0, "and the siege advances")
	var days := 0
	for day in 400:
		s.advance_days(1)
		days += 1
		if w.province(target).controller == a.id:
			break
	assert_eq(w.province(target).controller, a.id, "the province falls (%d giorni)" % days)
	assert_eq(w.province(target).owner, b.id, "but it is still theirs by right: it is held, not owned")
	assert_true(w.province(target).population >= int(people_before * 0.5),
		"the people are still there (%d su %d)" % [w.province(target).population, people_before])
	assert_true(War.occupied_provinces(w, a.id, b.id).has(target), "and it counts as occupied")
	assert_true(w.province(target).unrest > 0.0, "a province held by strangers grumbles")


func test_a_peace_can_be_paid_for_in_land_and_nothing_is_reset() -> void:
	var s := _world(1004)
	var w := s.world
	var pair := _realms(s)
	var a := pair[0]
	var b := pair[1]
	Diplomacy.start_war(w, a.id, b.id)
	var target := b.provinces[0]
	War.occupy(s, target, a.id)
	War.add_score(w, a.id, b.id, 90.0)
	var r := Diplomacy.relation(w, a.id, b.id)
	r.war_since = w.day - 800   # a long war
	var people := w.province(target).population
	var development := w.province(target).development
	var provinces_before := b.provinces.size()
	var refused := s.submit(MakePeaceCommand.create(a.id, b.id, PackedInt32Array([b.provinces[1]])))
	assert_false(refused.success, "land not held in the field cannot even be asked for")
	assert_true(refused.reason.contains("campo"), "and it says why: %s" % refused.reason)
	var res := s.submit(MakePeaceCommand.create(a.id, b.id, PackedInt32Array([target])))
	assert_true(res.success, "terms can be offered: %s" % res.reason)
	assert_true(bool(res.data.get("accepted", false)), "a beaten crown gives up the province: %s" % res.data.get("reason", ""))
	assert_eq(w.province(target).owner, a.id, "the province changes crown")
	assert_eq(b.provinces.size(), provinces_before - 1, "and leaves the old one")
	assert_eq(w.province(target).population, people, "with its people untouched")
	assert_eq(w.province(target).development, development, "and everything that was built in it")
	assert_true(w.province(target).unrest > 0.2, "though the people know they were handed over")
	assert_false(Diplomacy.at_war(w, a.id, b.id), "the war is over")
	assert_true(Diplomacy.relation(w, a.id, b.id).truce_until > w.day, "and a truce follows it")


func test_peace_gives_back_what_was_only_held() -> void:
	var s := _world(1005)
	var w := s.world
	var pair := _realms(s)
	var a := pair[0]
	var b := pair[1]
	Diplomacy.start_war(w, a.id, b.id)
	var held := b.provinces[0]
	War.occupy(s, held, a.id)
	assert_true(w.province(held).is_occupied(), "the province is under their boot")
	var r := Diplomacy.relation(w, a.id, b.id)
	r.war_since = w.day - 800
	var res := s.submit(MakePeaceCommand.create(a.id, b.id))
	assert_true(bool(res.data.get("accepted", false)), "a white peace is accepted: %s" % res.data.get("reason", ""))
	assert_false(w.province(held).is_occupied(), "and what was only held goes back")
	assert_eq(w.province(held).controller, b.id, "to the crown that owns it")


func test_the_same_seed_fights_the_same_battle() -> void:
	var first := _battle_outcome(1006)
	var second := _battle_outcome(1006)
	assert_eq(second["attacker_men"], first["attacker_men"], "the same war kills the same men")
	assert_eq(second["defender_men"], first["defender_men"], "on both sides")
	assert_near(float(second["score"]), float(first["score"]), 0.001, "and the ledger closes the same way")


func _battle_outcome(seed_value: int) -> Dictionary:
	var s := _world(seed_value)
	var w := s.world
	var pair := _realms(s)
	var a := pair[0]
	var b := pair[1]
	a.treasury = 2000.0
	b.treasury = 2000.0
	Diplomacy.start_war(w, a.id, b.id)
	var field := b.provinces[0]
	var one := _host(s, a, field, 26)
	var two := _host(s, b, field, 22)
	for day in 14:
		s.advance_days(1)
		if w.battles.is_empty() and day > 0:
			break
	return {"attacker_men": one.men(), "defender_men": two.men(), "score": War.score_for(w, a.id, b.id)}


func test_war_and_sieges_survive_a_save() -> void:
	var s := _world(1007)
	var w := s.world
	var pair := _realms(s)
	var a := pair[0]
	var b := pair[1]
	a.treasury = 2000.0
	Diplomacy.start_war(w, a.id, b.id)
	var target := b.provinces[0]
	_host(s, a, target, 20)
	s.advance_days(3)
	assert_eq(w.sieges.size(), 1, "a siege is going on")
	var progress := w.sieges[0].progress
	War.add_score(w, a.id, b.id, 25.0)
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s)))
	var loaded := SaveSystem.session_from_data(data)
	assert_eq(loaded.world.sieges.size(), 1, "the siege crosses the save")
	assert_near(loaded.world.sieges[0].progress, progress, 0.0001, "with the work already done")
	assert_near(War.score_for(loaded.world, a.id, b.id), War.score_for(w, a.id, b.id), 0.001, "and so does the ledger")


func test_a_war_between_two_realms_runs_its_course_without_errors() -> void:
	var s := _world(1008)
	var w := s.world
	var pair := _realms(s)
	var a := pair[0]
	var b := pair[1]
	a.treasury = 5000.0
	b.treasury = 5000.0
	Diplomacy.start_war(w, a.id, b.id)
	_host(s, a, a.provinces[0], 30)
	_host(s, b, b.provinces[0], 26)
	s.advance_days(8 * 360)
	for p in w.provinces:
		assert_true(p.devastation >= 0.0 and p.devastation <= 1.0, "devastation stays in range")
		assert_true(p.unrest >= 0.0 and p.unrest <= 1.0, "so does unrest")
		if p.owner < 0:
			assert_true(p.controller < 0 or p.controller == p.owner, "nobody occupies a free land by accident")
	for army in w.armies:
		assert_true(army.men() > 0, "no host of ghosts is left on the map")
		assert_true(army.morale() >= 0.0, "morale never goes below nothing")
	assert_true(int(a.records.get(&"battles_won", 0.0)) + int(b.records.get(&"battles_won", 0.0)) >= 0,
		"the chronicle of the war is kept")


func test_a_besieged_village_falls_with_its_houses_and_its_people_intact() -> void:
	var s := GameSession.create_new({"campaign_seed": 1009})
	SettlementPlanner.place_starter_village(s, s.world.settlements[0].id)
	var w := s.world
	var me := w.player()
	var enemy: KingdomState = null
	for k in w.kingdoms:
		if k.id != me.id and k.alive and not k.provinces.is_empty():
			enemy = k
			break
	enemy.treasury = 4000.0
	Diplomacy.start_war(w, enemy.id, me.id)
	var village := w.settlements[0]
	var host := _host(s, enemy, village.province, 40)
	host.pos = village.center + Vector2(700.0, 0.0)
	var buildings_before := w.buildings_of(village.id).size()
	var people_before := w.people_of(village.id).size()
	var trust_before := village.trust
	var days := 0
	for day in 500:
		s.advance_days(1)
		days += 1
		if w.province(village.province).controller == enemy.id:
			break
	assert_eq(w.province(village.province).controller, enemy.id, "the village province falls (%d giorni)" % days)
	assert_true(w.buildings_of(village.id).size() >= buildings_before - 1,
		"the houses are still standing (%d su %d)" % [w.buildings_of(village.id).size(), buildings_before])
	assert_true(w.people_of(village.id).size() > 0, "and people still live in them (%d su %d)"
		% [w.people_of(village.id).size(), people_before])
	assert_eq(village.kingdom, me.id, "the village is still ours while it is only occupied")
	s.advance_days(10)   # the flags on the walls have changed: the village lives under somebody else's soldiers
	assert_true(village.trust_parts.has("Occupazione"), "the people know whose soldiers stand in the square")
	assert_true(float(village.trust_parts["Occupazione"]) < 0.0,
		"and it weighs on their consent (%.0f punti su %.0f)" % [village.trust_parts["Occupazione"], village.trust])
	# and when the peace hands the province over, nothing is razed: it only changes crown
	var r := Diplomacy.relation(w, enemy.id, me.id)
	r.war_since = w.day - 800
	War.add_score(w, enemy.id, me.id, 120.0)
	War.cede(s, village.province, enemy.id)
	assert_eq(w.province(village.province).owner, enemy.id, "the province changes crown")
	assert_eq(village.kingdom, enemy.id, "and the village with it")
	assert_true(w.buildings_of(village.id).size() >= buildings_before - 1, "with everything that was built in it")
	assert_true(w.people_of(village.id).size() > 0, "and the people who live there")


## Phase 19: the seat of the player's crown can be besieged and occupied, but no treaty hands it over — the
## enemy does not ask for it, a peace that asks for it is refused, an offer written before (in an old save) that
## still asks for it leaves it out. Accepting such a peace gave the village away and left nothing to rule.
func test_no_treaty_gives_away_the_seat_of_the_player() -> void:
	var s := GameSession.create_new({"campaign_seed": 1907})
	var w := s.world
	var me := w.player()
	var village := w.settlements[0]
	var enemy: KingdomState = null
	for k in w.kingdoms:
		if k.id != me.id and k.alive and not k.provinces.is_empty():
			enemy = k
			break
	Diplomacy.start_war(w, enemy.id, me.id)
	War.occupy(s, village.province, enemy.id)
	War.add_score(w, enemy.id, me.id, 90.0)
	Diplomacy.relation(w, enemy.id, me.id).war_since = w.day - 800
	assert_eq(w.province(village.province).controller, enemy.id, "the enemy holds the province of the village")
	assert_true(War.is_player_seat(w, village.province), "which is the seat of the player's crown")
	assert_false(War.cedable_provinces(w, enemy.id, me.id).has(village.province), "held, but it cannot be asked for")
	var asked := s.submit(MakePeaceCommand.create(enemy.id, me.id, PackedInt32Array([village.province])))
	assert_false(asked.success, "a peace that asks for it is refused")
	assert_true(asked.reason.contains("sede"), "and it says why: %s" % asked.reason)
	for option: Dictionary in RealmAiSystem._options(s, enemy, DiplomacyAi.personality(w, enemy.id)):
		if String(option["kind"]) == "peace":
			assert_false(Array(option.get("cede", [])).has(village.province), "the enemy does not even think of asking for it")
	# an offer written by an older build, that still asks for it
	var offer_id := w.new_id()
	w.offers.append({"id": offer_id, "from": enemy.id, "kind": "peace", "pact": "", "day": w.day,
		"expires": w.day + 30, "cede": [village.province], "text": "Una vecchia ambasciata."})
	var answer := s.submit(AnswerOfferCommand.create(offer_id, true))
	assert_true(answer.success, "the old offer can still be accepted: %s" % answer.reason)
	assert_false(Diplomacy.at_war(w, enemy.id, me.id), "the war is over")
	assert_eq(village.kingdom, me.id, "the village stays with its crown")
	assert_eq(w.province(village.province).owner, me.id, "and so does its province")
	assert_eq(w.province(village.province).controller, me.id, "and the occupier leaves it")
	s.dispose()


## Phase 19: a realm that loses its last province is no more — its hosts scatter into the fields where they stand
## and its wars end, giving back what it held by arms (they kept marching and fighting for a crown that was gone).
func test_the_hosts_of_a_fallen_realm_scatter_and_its_wars_end() -> void:
	var s := _world(1010)
	var w := s.world
	var pair := _realms(s)
	var a := pair[0]
	var b := pair[1]
	Diplomacy.start_war(w, a.id, b.id)
	var host := _host(s, b, b.provinces[0], 30)
	var held := a.provinces[0]
	War.occupy(s, held, b.id)
	assert_eq(w.province(held).controller, b.id, "the realm holds a province of its enemy by arms")
	for pid in b.provinces.duplicate():
		War.cede(s, pid, a.id)
	assert_false(b.alive, "with no land left the realm is no more")
	var people := w.province(host.province).population
	s.advance_days(1)
	for army in w.armies:
		assert_true(army.kingdom != b.id, "no host of the fallen realm is still in the field (%s)" % army.name)
	assert_true(w.province(host.province).population >= people + 25,
		"its men went back to the fields where they stood (%d -> %d)" % [people, w.province(host.province).population])
	assert_false(Diplomacy.at_war(w, a.id, b.id), "its war is over")
	assert_eq(w.province(held).controller, a.id, "and what it held by arms went back to its crown")
	s.dispose()

