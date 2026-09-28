extends KDTestCase

const PATH := "user://tests/roundtrip.kds"


func test_roundtrip_preserves_state_and_randomness() -> void:
	var s := GameSession.create_new({"campaign_seed": 555})
	s.advance_days(45)
	s.world.flags["tutorial_step"] = 3
	s.world.rng.stream(&"events").randi()
	var err := SaveSystem.save_to_file(s, PATH, "prova")
	assert_eq(err, OK, "save error")
	var loaded := SaveSystem.load_from_file(PATH)
	assert_not_null(loaded, "load returned null")
	if loaded == null:
		return
	assert_eq(loaded.world.tick, s.world.tick, "tick")
	assert_eq(loaded.world.day, 45)
	assert_eq(int(loaded.world.flags.get("tutorial_step", 0)), 3)
	assert_eq(loaded.date_text(), s.date_text())
	for i in 5:
		assert_eq(loaded.world.rng.stream(&"events").randi(), s.world.rng.stream(&"events").randi(), "rng continuation")
	# the loaded session keeps simulating
	loaded.advance_days(10)
	assert_eq(loaded.world.day, 55)


func test_header_has_save_version() -> void:
	var s := GameSession.create_new({"campaign_seed": 1})
	var data := SaveSystem.build_save_data(s)
	assert_eq(int(data["header"]["save_version"]), SaveMigrator.CURRENT_VERSION)


func test_migrator_rejects_missing_or_future_versions() -> void:
	assert_true(SaveMigrator.migrate({"header": {}}).is_empty(), "missing version rejected")
	assert_true(SaveMigrator.migrate({"header": {"save_version": SaveMigrator.CURRENT_VERSION + 1}}).is_empty(), "future version rejected")
	var ok := SaveMigrator.migrate({"header": {"save_version": SaveMigrator.CURRENT_VERSION}, "world": {}})
	assert_false(ok.is_empty(), "current version accepted")


## Phase 19: saves written by an older build (Phase 18, before the world art pass) still open, are listed with
## their header, play on and are written again the same by this build: a village of thirty still led by its
## founders, and a crowned town of forty years.
func test_saves_of_an_older_build_still_load_and_play_on() -> void:
	for path: String in ["res://tests/fixtures/saves/phase18_village30.kdsave", "res://tests/fixtures/saves/phase18_town.kdsave"]:
		var file := path.get_file()
		# what the older build wrote, before any migration (save_version 5: "order" and "happiness")
		var raw_file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		var raw: Dictionary = JSON.parse_string(raw_file.get_as_text())
		raw_file.close()
		var raw_world: Dictionary = raw["world"]
		var raw_order := {}
		for rk: Dictionary in raw_world["kingdoms"]:
			raw_order[int(rk["id"])] = float(rk.get("order", -1.0))
		var raw_trust := float((raw_world["settlements"][0] as Dictionary).get("happiness", -1.0))
		assert_eq(int(raw["header"]["save_version"]), 5, "%s was written as version 5" % file)
		var header := SaveCatalogue.read_header(path)
		assert_false(header.is_empty(), "%s: the menu reads its header" % file)
		assert_true(String(header.get("date_text", "")) != "", "%s: with the date in words" % file)
		var loaded := SaveSystem.load_from_file(path)
		assert_not_null(loaded, "%s opens" % file)
		if loaded == null:
			continue
		var w := loaded.world
		var people := w.people.size()
		assert_true(people > 0 and w.buildings.size() > 0, "%s: its people and buildings are there (%d, %d)" % [file, people, w.buildings.size()])
		assert_true(w.player() != null and w.player().alive, "%s: and the realm of the player" % file)
		assert_eq(w.day, int(header.get("day", -1)), "%s: on the day the header says" % file)
		# the consolidation (v6): the order of every realm is now its stability, the consent of the village its trust
		for k in w.kingdoms:
			assert_true(absf(k.stability - float(raw_order.get(k.id, -1.0))) < 0.001,
				"%s: %s keeps its order as stability (%.1f)" % [file, k.name, k.stability])
		assert_true(absf(w.settlements[0].trust - raw_trust) < 0.001,
			"%s: the village keeps its consent as trust (%.1f)" % [file, w.settlements[0].trust])
		var day := w.day
		loaded.advance_days(40)
		assert_eq(w.day, day + 40, "%s: the world goes on" % file)
		assert_true(w.people.size() >= people * 0.8, "%s: without losing its people (%d -> %d)" % [file, people, w.people.size()])
		var again := SaveSystem.session_from_data(JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(loaded, "again"))) as Dictionary)
		assert_not_null(again, "%s: written again by this build and read back" % file)
		if again != null:
			assert_eq(again.world.day, w.day, "%s: the same day" % file)
			assert_eq(again.world.people.size(), w.people.size(), "%s: the same people" % file)
			assert_eq(again.world.buildings.size(), w.buildings.size(), "%s: the same buildings" % file)
			assert_eq(again.world.chronicle.size(), w.chronicle.size(), "%s: the same chronicle" % file)
			assert_eq(again.world.player().monarchy_founded, w.player().monarchy_founded, "%s: crowned or not as it was" % file)
			again.dispose()
		loaded.dispose()


## Phase 19: a save cut short (the game killed while writing, a full disk) is refused, not half loaded, and the
## previous save of the same slot is still there: the game writes beside it and swaps the files only when done.
func test_a_broken_save_is_refused_and_the_old_one_survives() -> void:
	var s := GameSession.create_new({"campaign_seed": 1905})
	s.advance_days(20)
	var path := "user://tests/broken.kds"
	assert_eq(SaveSystem.save_to_file(s, path, "intera"), OK, "a whole save is written")
	var whole := FileAccess.get_file_as_bytes(path)
	var cut := FileAccess.open(path, FileAccess.WRITE)
	cut.store_buffer(whole.slice(0, whole.size() / 2))
	cut.close()
	assert_null(SaveSystem.load_from_file(path), "half a save is refused")
	assert_true(SaveCatalogue.read_header(path).is_empty(), "and the menu does not list it")
	var junk := FileAccess.open(path, FileAccess.WRITE)
	junk.store_string("{ non è un salvataggio")
	junk.close()
	assert_null(SaveSystem.load_from_file(path), "nor a file that is not a save")
	# writing again over a slot never leaves it without a whole save
	assert_eq(SaveSystem.save_to_file(s, path, "di nuovo"), OK, "the slot is written again")
	assert_false(FileAccess.file_exists(path + SaveSystem.TEMP_SUFFIX), "and no half-written file is left beside it")
	var back := SaveSystem.load_from_file(path)
	assert_not_null(back, "the save of the slot opens")
	if back != null:
		assert_eq(back.world.day, s.world.day, "on its day")
		back.dispose()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	s.dispose()


## Consolidation (v6): the modifiers of a crisis saved by an older build are renamed with the measures they move —
## the old «stability.base» moved the trust of the people, the old «order.base» the stability of the realm.
func test_crises_of_an_older_save_keep_what_they_move() -> void:
	var s := GameSession.create_new({"campaign_seed": 1908})
	var data := SaveSystem.build_save_data(s, "vecchio")
	var world: Dictionary = data["world"]
	var player := int(world["player_kingdom"])
	for k: Dictionary in world["kingdoms"]:
		k["order"] = k["stability"]
		k.erase("stability")
		if int(k["id"]) == player:
			k["crises"] = [{"id": "carestia", "name": "Carestia", "until": 400, "modifiers": [
				{"key": "stability.base", "op": "add", "value": -6.0}, {"key": "order.base", "op": "add", "value": -4.0},
				{"key": "production.grain", "op": "mul", "value": 0.8}]}]
	for st: Dictionary in world["settlements"]:
		st["happiness"] = st["trust"]
		st.erase("trust")
	data["header"]["save_version"] = 5
	var back := SaveSystem.session_from_data(JSON.parse_string(JSON.stringify(data)) as Dictionary)
	assert_not_null(back, "a version 5 save opens")
	if back == null:
		return
	var keys: Array = []
	for m: Dictionary in back.world.player().crises[0]["modifiers"]:
		keys.append(String(m["key"]))
	assert_eq(keys, ["trust.base", "stability.base", "production.grain"], "each modifier moves what it moved before")
	assert_eq(back.world.player().stability, s.world.player().stability, "the order of the realm is its stability")
	assert_eq(back.world.settlements[0].trust, s.world.settlements[0].trust, "the consent of the village is its trust")
	back.dispose()
	s.dispose()

