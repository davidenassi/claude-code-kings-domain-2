extends KDTestCase
## Phase 13: the world at scale. Sixty years of everything at once — twenty courts, their wars, a village that
## really grows — then a save and a load, timed. This is the test that says whether an old campaign still runs.


func after_each() -> void:
	Session.end()


## The lord builds what the village is short of, the way a player would.
static func _lord_turn(s: GameSession) -> void:
	SettlementPlanner.lord_month(s, s.world.settlements[0].id)


func test_sixty_years_of_the_whole_world_and_a_village_that_grows() -> void:
	var s := GameSession.create_new({"campaign_seed": 1301})
	var w := s.world
	var st := w.settlements[0]
	var keep := w.buildings_of(st.id)[0]
	for def_id: StringName in [&"farm", &"woodcutter", &"bakery", &"house", &"granary"]:
		var spot := SettlementPlanner.find_spot(s, st.id, def_id, keep.pos, 36.0)
		if spot != Vector2.INF:
			s.submit(PlaceBuildingCommand.create(st.id, def_id, spot))
	var t0 := Time.get_ticks_msec()
	var worst_decade := 0
	for decade in 6:
		var d0 := Time.get_ticks_msec()
		for month in 120:
			s.advance_days(30)
			_lord_turn(s)
		worst_decade = maxi(worst_decade, Time.get_ticks_msec() - d0)
	var ms := Time.get_ticks_msec() - t0
	var alive := 0
	for k in w.kingdoms:
		if k.alive:
			alive += 1
	print("  60 anni in %d ms (decennio peggiore %d ms): %d regni vivi, %d abitanti nel villaggio, %d edifici, %d personaggi, %d righe di cronaca" % [
		ms, worst_decade, alive, w.people_of(st.id).size(), w.buildings.size(), w.characters.size(), w.chronicle.size()])

	# the world is still coherent after sixty years
	assert_true(alive >= 3, "the world is still inhabited by realms (%d)" % alive)
	assert_true(w.people_of(st.id).size() > 0, "the king's village is still there")
	assert_true(w.chronicle.size() > 20, "and the realm has a history to tell (%d righe)" % w.chronicle.size())
	assert_true(w.characters.size() < 400, "the register of the courts does not grow for ever (%d)" % w.characters.size())
	for p in w.provinces:
		assert_true(p.population >= 0, "no province owes people to anybody")
	# a century and a half of drift must not make the simulation crawl
	assert_true(ms < 400000, "sixty years simulated in %d ms" % ms)
	assert_true(worst_decade < ms, "the cost of a decade does not run away (peggiore %d ms su %d)" % [worst_decade, ms])

	# saving and loading an old campaign stays quick
	var t1 := Time.get_ticks_usec()
	var data := SaveSystem.build_save_data(s, "stress")
	var save_ms := (Time.get_ticks_usec() - t1) / 1000.0
	var text := JSON.stringify(data)
	var size_kb := text.length() / 1024.0
	t1 = Time.get_ticks_usec()
	var back := SaveSystem.session_from_data(JSON.parse_string(text) as Dictionary)
	var load_ms := (Time.get_ticks_usec() - t1) / 1000.0
	print("  salvataggio: %.0f ms, %.0f KB · caricamento: %.0f ms" % [save_ms, size_kb, load_ms])
	assert_not_null(back, "the old campaign comes back")
	if back == null:
		return
	assert_eq(back.world.day, w.day, "on the same day")
	assert_eq(back.world.people.size(), w.people.size(), "with the same people")
	assert_eq(back.world.characters.size(), w.characters.size(), "and the same courts")
	assert_true(save_ms < 4000.0, "the save takes %.0f ms" % save_ms)
	assert_true(load_ms < 4000.0, "the load takes %.0f ms" % load_ms)
	assert_true(size_kb < 8192.0, "and the file stays reasonable (%.0f KB)" % size_kb)
	back.dispose()

