extends KDTestCase
## Culture, religion and national spirits: the identity of a realm and what it really changes.

var wd: WorldData


func before_each() -> void:
	wd = WorldData.get_instance()


func test_every_realm_is_born_with_spirits_from_its_own_land() -> void:
	var s := GameSession.create_new({"campaign_seed": 301})
	var w := s.world
	var seen := {}
	for k in w.kingdoms:
		if k.provinces.is_empty():
			continue
		assert_true(k.spirits.size() >= 1 and k.spirits.size() <= NationalSpiritSystem.MAX_INITIAL,
			"%s has %d spirits" % [k.name, k.spirits.size()])
		for spirit_id in k.spirits:
			var sp: NationalSpiritDef = Defs.get_def("national_spirits", spirit_id)
			assert_not_null(sp, "spirit %s exists" % spirit_id)
			assert_true(sp.can_gain(NationalSpiritSystem.facts(s, k)), "%s: %s fits the land" % [k.name, spirit_id])
		seen[",".join(PackedStringArray(k.spirits.map(func(x: StringName) -> String: return String(x))))] = true
	assert_true(seen.size() >= 3, "different lands, different spirits (%d combinations)" % seen.size())
	# two realms of different geography must differ
	var forest_realm: KingdomState = null
	var dry_realm: KingdomState = null
	for k in w.kingdoms:
		var f := NationalSpiritSystem.facts(s, k)
		if float(f.get("forest_share", 0.0)) > 0.45 and forest_realm == null:
			forest_realm = k
		if float(f.get("forest_share", 1.0)) < 0.3 and dry_realm == null:
			dry_realm = k
	if forest_realm and dry_realm:
		assert_true(forest_realm.spirits != dry_realm.spirits, "%s and %s do not share the same spirits" % [forest_realm.name, dry_realm.name])


func test_modifiers_reach_the_real_numbers() -> void:
	var s := GameSession.create_new({"campaign_seed": 302})
	var w := s.world
	var k := w.player()
	k.spirits = [&"signori_del_legname"]
	k.identity_changed()
	var wood := KingdomModifiers.value(s, k.id, &"production.wood", 3.0)
	assert_true(wood > 3.0 * 1.15, "the realm of timber cuts more (%.2f from 3)" % wood)
	var stack := KingdomModifiers.stack(s, k.id)
	assert_true(stack.breakdown(&"production.wood").size() >= 1, "the bonus says where it comes from")
	var labels := PackedStringArray()
	for part: Dictionary in stack.breakdown(&"production.wood"):
		labels.append(String(part["label"]))
	assert_true(",".join(labels).contains("Signori del legname"), "the spirit appears in the breakdown: %s" % ",".join(labels))
	# the same call through a settlement, with the land adding its own keys
	var st := w.settlements[0]
	var grain := KingdomModifiers.settlement_value(s, st, &"production.grain", 10.0, SettlementSim.field_keys(w, st.center))
	assert_true(grain > 0.0, "fields yield something")
	k.spirits = []
	k.identity_changed()
	var plain := KingdomModifiers.value(s, k.id, &"production.wood", 3.0)
	assert_true(plain < wood, "without the spirit the same forest yields less (%.2f vs %.2f)" % [plain, wood])


func test_a_spirit_evolves_after_the_deeds_it_asks_for() -> void:
	var s := GameSession.create_new({"campaign_seed": 303})
	var w := s.world
	var k := w.player()
	k.spirits = [&"popolo_dei_boschi"]
	k.identity_changed()
	k.spirit_since[&"popolo_dei_boschi"] = 0
	k.records[&"spirits_seeded"] = 1.0
	k.records[&"wood"] = 4200.0
	s.advance_days(32)
	assert_false(k.spirits.has(&"popolo_dei_boschi"), "the old spirit made way")
	assert_true(k.spirits.has(&"signori_del_legname"), "cutting that much wood makes lords of timber: %s" % str(k.spirits))
	assert_true(int(k.spirit_since.get(&"signori_del_legname", -1)) > 0, "the day it was gained is recorded")


func test_work_fills_the_registers_that_feed_the_spirits() -> void:
	var s := GameSession.create_new({"campaign_seed": 304})
	var w := s.world
	var st := w.settlements[0]
	# at the edge of the wood (Rebirth: the valley's woods are masses with open land between them)
	var spot := SettlementPlanner.find_spot(s, st.id, &"woodcutter", st.center + SettlementPlanner.wood_direction(w, st) * 110.0, 0.0)
	s.submit(PlaceBuildingCommand.create(st.id, &"woodcutter", spot))
	s.advance_days(60)
	var k := w.player()
	assert_true(float(k.records.get(&"wood", 0.0)) > 20.0, "the wood cut is written down (%.0f)" % float(k.records.get(&"wood", 0.0)))


func test_a_foreign_province_grows_restless_then_assimilates() -> void:
	var s := GameSession.create_new({"campaign_seed": 305})
	var w := s.world
	var k := crown_player(s)   # the language of the crown: a crown is needed (Phase 15)
	# the crown takes a province of another culture
	var target := -1
	for p in w.provinces:
		if p.is_free() and p.culture != k.culture:
			target = p.id
			break
	assert_true(target >= 0, "there are foreign lands to take")
	s.submit(TransferProvinceCommand.create(target, k.id))
	var p := w.province(target)
	var foreign_culture := p.culture
	assert_true(CultureSystem.friction(s, target) > 0.0, "a foreign province resists")
	s.advance_days(365)
	assert_true(p.unrest > 0.0, "resentment grows (%.2f)" % p.unrest)
	var with_unrest := EconomySystem.province_income(w, k, target)
	p.unrest = 0.0
	var quiet := EconomySystem.province_income(w, k, target)
	assert_true(with_unrest < quiet, "resentment eats the rents (%.2f < %.2f)" % [with_unrest, quiet])
	var years := 0
	while p.culture == foreign_culture and years < 60:
		s.advance_days(360)
		years += 1
	assert_true(p.culture == k.culture, "in the end the province speaks the language of the crown (%d years)" % years)


func test_identity_survives_a_save() -> void:
	var s := GameSession.create_new({"campaign_seed": 306})
	var k := s.world.player()
	k.spirits = [&"gente_di_pietra", &"signori_dei_guadi"]
	k.identity_changed()
	k.spirit_since[&"gente_di_pietra"] = 3
	k.records[&"wood"] = 120.0
	s.world.provinces[k.capital].unrest = 0.3
	s.world.provinces[k.capital].assimilation = 0.45
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s)))
	var loaded := SaveSystem.session_from_data(data)
	assert_not_null(loaded)
	if loaded == null:
		return
	var k2 := loaded.world.player()
	assert_eq(k2.spirits, k.spirits, "spirits kept")
	assert_eq(int(k2.spirit_since.get(&"gente_di_pietra", -1)), 3, "dates kept")
	assert_true(absf(float(k2.records.get(&"wood", 0.0)) - 120.0) < 0.01, "registers kept")
	assert_true(absf(loaded.world.provinces[k2.capital].unrest - 0.3) < 0.01, "unrest kept")
	assert_true(absf(loaded.world.provinces[k2.capital].assimilation - 0.45) < 0.01, "and how far the crown's language has come")
	assert_eq(loaded.world.provinces[k2.capital].culture, s.world.provinces[k.capital].culture, "province culture kept")
	var value_a := KingdomModifiers.value(s, k.id, &"production.stone", 2.0)
	var value_b := KingdomModifiers.value(loaded, k2.id, &"production.stone", 2.0)
	assert_true(absf(value_a - value_b) < 0.001, "the same realm gives the same numbers")

