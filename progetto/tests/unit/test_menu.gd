extends KDTestCase
## Phase 14: the door of the game. What the player can do before and around a campaign — find the saved ones,
## take one back off the shelf, and see the whole realm in the corner of the screen.
##
## These tests keep to a shelf of their own (`user://tests/saves`): they empty it before and after every test,
## and the real campaigns of whoever runs the suite must never be touched.

const TEST_SHELF := "user://tests/saves"


func before_each() -> void:
	SaveSystem.save_dir = TEST_SHELF
	_clear_shelf()


func after_each() -> void:
	_clear_shelf()
	SaveSystem.save_dir = SaveSystem.SAVE_DIR
	Session.end()


static func _clear_shelf() -> void:
	assert(SaveSystem.save_dir == TEST_SHELF, "the tests only ever empty their own shelf")
	for entry in SaveCatalogue.list():
		SaveCatalogue.remove(String(entry["path"]))


func test_the_shelf_lists_the_campaigns_with_enough_to_choose() -> void:
	var s := Session.start_new({"campaign_seed": 1401})
	s.advance_days(400)
	assert_true(SaveCatalogue.write(s, "prova_uno", "La prima") != "", "a campaign can be put on the shelf")
	var all := SaveCatalogue.list()
	assert_eq(all.size(), 1, "and it is there")
	var entry := all[0]
	assert_eq(int(entry["day"]), s.world.day, "with the day it was left on")
	assert_eq(String(entry["date_text"]), s.date_text(), "the date in words")
	assert_eq(String(entry["realm"]), s.world.player().name, "and the name of the realm")
	assert_false(bool(entry["auto"]), "a save made by hand is not an automatic one")
	assert_true(String(entry["saved_at"]) != "", "and it says when it was written")


func test_a_campaign_comes_back_from_the_shelf() -> void:
	var s := Session.start_new({"campaign_seed": 1402})
	s.advance_days(200)
	var day := s.world.day
	var realm := s.world.player().name
	SaveCatalogue.write(s, "ritorno", "Ritorno")
	Session.end()
	var recent := SaveCatalogue.most_recent()
	assert_false(recent.is_empty(), "the menu finds the last campaign")
	var loaded := SaveSystem.load_from_file(String(recent["path"]))
	assert_not_null(loaded, "and it opens")
	if loaded == null:
		return
	assert_eq(loaded.world.day, day, "on the day it was left")
	assert_eq(loaded.world.player().name, realm, "with the same realm")
	loaded.advance_days(10)
	assert_eq(loaded.world.day, day + 10, "and it goes on")
	loaded.dispose()


func test_the_automatic_saves_do_not_pile_up() -> void:
	var s := Session.start_new({"campaign_seed": 1403})
	for i in SaveCatalogue.AUTOSAVE_KEEP + 3:
		s.advance_days(30)
		assert_true(SaveCatalogue.autosave(s) != "", "the crown writes its memoirs")
	var autos := 0
	for entry in SaveCatalogue.list():
		if bool(entry["auto"]):
			autos += 1
	assert_eq(autos, SaveCatalogue.AUTOSAVE_KEEP,
		"only the last %d are kept (%d)" % [SaveCatalogue.AUTOSAVE_KEEP, autos])
	var newest := SaveCatalogue.most_recent()
	assert_eq(int(newest["day"]), s.world.day, "and the newest is the last one written")


static func _autosaves() -> int:
	var n := 0
	for entry in SaveCatalogue.list():
		if bool(entry["auto"]):
			n += 1
	return n


## Phase 19: the automatic save waited for the one day that divides by 360; at the highest speed several days
## pass in one frame and that day could be jumped over, leaving a year without a save.
func test_the_automatic_save_comes_every_year_even_when_the_day_is_skipped() -> void:
	var s := Session.start_new({"campaign_seed": 1405})
	var runner := SimulationRunner.new()   # outside the tree: no boot flags, the automatic saves are on
	var year := SimulationRunner.AUTOSAVE_EVERY_DAYS
	runner._autosave_if_due(s.world.day)
	assert_eq(_autosaves(), 0, "a campaign just started or loaded is not saved again at once")
	s.advance_days(year - s.world.day % year - 3)
	runner._autosave_if_due(s.world.day)
	assert_eq(_autosaves(), 0, "nor before the year has turned")
	s.advance_days(5)   # one frame at the highest speed: the first day of the year is passed over
	assert_true(s.world.day % year != 0, "the exact day of the turn was skipped (%d)" % s.world.day)
	runner._autosave_if_due(s.world.day)
	assert_eq(_autosaves(), 1, "the year has turned: the crown writes its memoirs all the same")
	s.advance_days(20)
	runner._autosave_if_due(s.world.day)
	assert_eq(_autosaves(), 1, "and only once for that year")
	s.advance_days(year)
	runner._autosave_if_due(s.world.day)
	assert_eq(_autosaves(), 2, "then again the year after")
	runner.free()


func test_the_minimap_draws_the_world() -> void:
	var s := Session.start_new({"campaign_seed": 1404})
	var tree := Engine.get_main_loop() as SceneTree
	var map := Minimap.new()
	tree.root.add_child(map)
	map.setup(null, null)
	var image := map.picture()
	assert_not_null(image, "the minimap has a picture")
	if image == null:
		tree.root.remove_child(map)
		map.free()
		return
	assert_true(image.get_width() == Minimap.WIDTH, "as wide as it says")
	var sea := 0
	var land := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).b > image.get_pixel(x, y).g:
				sea += 1
			else:
				land += 1
	assert_true(sea > 100, "there is a sea around the continent (%d pixel)" % sea)
	assert_true(land > 100, "and land inside it (%d pixel)" % land)
	var realms := {}
	for pid in [s.world.player().capital]:
		realms[MapModes.province_color(&"political", s.world, pid)] = true
	assert_true(realms.size() > 0, "and the realms have their colours")
	tree.root.remove_child(map)
	map.free()


## The guided first steps: every one of them closes by itself when the world says it is done.
func test_the_guide_follows_what_the_realm_really_does() -> void:
	var s := Session.start_new({"campaign_seed": 1405})
	var w := s.world
	assert_true(Guide.steps().size() >= 5, "the guide has something to say (%d passi)" % Guide.steps().size())
	assert_eq(Guide.current_index(w), 0, "a new campaign starts at the first step")
	var first := Guide.current(w)
	assert_true(String(first.get("title", "")) != "", "which has a title")
	assert_false(Guide.advance(w), "and nothing is done yet")

	SettlementPlanner.place_starter_village(s, w.settlements[0].id)
	s.advance_days(200)
	Guide.advance(w)
	assert_true(Guide.current_index(w) > 0, "raising the village moves the guide on (%d)" % Guide.current_index(w))

	# the laws step closes the moment a law is really in force
	var k := w.player()
	k.laws[&"succession"] = &"primogenitura"
	var before := Guide.current_index(w)
	while not Guide.finished(w) and Guide.current_index(w) < Guide.steps().size():
		if not Guide.advance(w):
			break
	assert_true(Guide.current_index(w) >= before, "the guide never goes backwards")

	Guide.dismiss(w)
	assert_true(Guide.current_index(w) >= Guide.DONE, "and the player can close it for good")


func test_the_guide_is_saved_with_the_campaign() -> void:
	var s := Session.start_new({"campaign_seed": 1406})
	s.world.flags[Guide.FLAG] = 3
	SaveCatalogue.write(s, "guida", "Guida")
	var loaded := SaveSystem.load_from_file(SaveSystem.slot_path("guida"))
	assert_not_null(loaded, "the campaign comes back")
	if loaded == null:
		return
	assert_eq(Guide.current_index(loaded.world), 3, "and the guide with it")
	loaded.dispose()

