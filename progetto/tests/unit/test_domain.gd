extends KDTestCase
## Rebirth, Phase 1: two maps, one simulation. The valley of the homeland is a space of its own (DomainState,
## DomainData); the map of the world is the continent; the local map can never become the global one.


func after_each() -> void:
	Session.end()


func test_a_new_campaign_has_its_valley_and_the_settlement_lives_in_it() -> void:
	var s := GameSession.create_new({"campaign_seed": 2101})
	var w := s.world
	var d := w.domain
	assert_not_null(d, "the campaign has a valley")
	if d == null:
		return
	var st := w.settlements[0]
	assert_true(d.contains_local(st.center), "the settlement stands inside the valley (%s)" % str(st.center))
	assert_true(d.rect().grow(-1500.0).has_point(st.center), "and well inside it, not on its rim")
	for b in w.buildings_of(st.id):
		assert_true(d.contains_local(b.pos), "%s stands in the valley" % b.def_id)
	for p in w.people_of(st.id):
		assert_true(d.contains_local(p.seg_to), "%s walks in the valley" % p.name)
	var wd := WorldData.get_instance()
	assert_eq(wd.province_at(w.settlement_global_pos(st)), w.player().capital,
		"on the map of the world the settlement stands in the home province")
	assert_eq(d.home_province, w.player().capital, "the valley belongs to the home province")
	assert_true(d.size_m.x < wd.size_m.x * 0.1 and d.size_m.y < wd.size_m.y * 0.1,
		"the valley is a small part of the continent (%s)" % str(d.size_m))
	assert_true(d.size_m.x >= 6000.0 and d.size_m.y >= 4000.0, "and big enough for a capital and its fields")


func test_local_and_global_metres_correspond() -> void:
	var s := GameSession.create_new({"campaign_seed": 2102, "homeland": "none"})
	var d := s.world.domain
	for p: Vector2 in [Vector2.ZERO, Vector2(123.5, 4000.25), d.size_m, d.center()]:
		assert_true(d.to_local(d.to_global(p)).distance_to(p) < 0.001, "local -> global -> local is the identity")
	assert_eq(fmod(d.origin_global.x, DomainState.ALIGN_M), 0.0, "the window is aligned to the grids (x)")
	assert_eq(fmod(d.origin_global.y, DomainState.ALIGN_M), 0.0, "the window is aligned to the grids (y)")
	var back := DomainState.from_dict(d.to_dict())
	assert_eq(back.key(), d.key(), "the valley survives a save")


## The valley cut out of the continent grows exactly the trees and rocks the continent had there.
func test_the_valley_keeps_the_trees_and_rocks_of_the_continent() -> void:
	var s := GameSession.create_new({"campaign_seed": 2103, "homeland": "none"})
	var w := s.world
	var d := w.domain
	var ld := DomainData.of(w)
	var wd := WorldData.get_instance()
	assert_true(ld.loaded, "the ground of the valley is there")
	var st := w.settlements[0]
	var local_box := Rect2(st.center - Vector2(300, 300), Vector2(600, 600))
	var global_box := Rect2(d.to_global(local_box.position), local_box.size)
	var here := LocalFeatures.trees_in_rect(ld, local_box)
	var there := LocalFeatures.trees_in_rect(wd, global_box)
	assert_true(here.size() > 50, "a wood around the fire (%d)" % here.size())
	assert_eq(here.size(), there.size(), "the same number of trees as on the continent")
	var same := 0
	for i in mini(here.size(), there.size()):
		if (here[i]["pos"] as Vector2).distance_to((there[i]["pos"] as Vector2) - d.origin_global) < 0.01 \
				and here[i]["species"] == there[i]["species"]:
			same += 1
	assert_eq(same, here.size(), "every tree in the same place and of the same kind")
	var rocks_here := LocalFeatures.outcrops_in_rect(ld, local_box.grow(600.0))
	var rocks_there := LocalFeatures.outcrops_in_rect(wd, global_box.grow(600.0))
	assert_eq(rocks_here.size(), rocks_there.size(), "the same rocks")
	for i in mini(rocks_here.size(), rocks_there.size()):
		assert_eq(rocks_here[i]["id"], rocks_there[i]["id"], "rock ids are kept")
	assert_eq(ld.province_at(st.center), wd.province_at(d.to_global(st.center)), "the same province under the fire")
	assert_true(absf(ld.height_at(st.center) - wd.height_at(d.to_global(st.center))) < 0.01, "the same height")
	assert_false(ld.in_world(Vector2(-10, 10)), "nothing exists past the valley's edge")
	assert_false(ld.in_world(d.size_m + Vector2(1, 1)), "on either side")


func test_the_host_gathers_on_the_map_of_the_world() -> void:
	var s := GameSession.create_new({"campaign_seed": 2104})
	var w := s.world
	var st := w.settlements[0]
	SettlementPlanner.place_starter_village(s, st.id)
	st.add(&"weapons", 40)
	w.player().treasury = 900.0
	var res := s.submit(RecruitUnitCommand.create(st.id, &"lancieri"))
	assert_true(res.success, res.reason)
	s.advance_days(Military.unit(&"lancieri").train_days + 2)
	assert_eq(w.armies.size(), 1, "the host is raised")
	if w.armies.is_empty():
		return
	var army := w.armies[0]
	assert_true(army.pos.distance_to(w.settlement_global_pos(st)) < 400.0,
		"it gathers by its capital on the map of the world (%.0f m)" % army.pos.distance_to(w.settlement_global_pos(st)))
	assert_eq(WorldData.get_instance().province_at(army.pos), st.province, "in the home province")
	assert_true(Military.can_resupply(w, army) >= float((Military.bal().get("supply", {}) as Dictionary).get("friendly_refill_per_day", 2.5)) - 0.001,
		"and it eats from its capital (the valley's settlement seen from the world)")


func test_the_valley_travels_with_the_save() -> void:
	var s := GameSession.create_new({"campaign_seed": 2105})
	SettlementPlanner.place_starter_village(s, s.world.settlements[0].id)
	s.advance_days(40)
	var data := SaveSystem.build_save_data(s)
	var back := SaveSystem.session_from_data(JSON.parse_string(JSON.stringify(data)))
	assert_not_null(back, "the save opens")
	if back == null:
		return
	assert_not_null(back.world.domain, "with its valley")
	assert_eq(back.world.domain.key(), s.world.domain.key(), "the same valley")
	assert_eq(back.world.settlements[0].center, s.world.settlements[0].center, "the settlement where it was")
	assert_eq(back.world.terrain.felled.size(), s.world.terrain.felled.size(), "the same stumps")


## A save of the single map (v6): everything in metres of the continent. The migration cuts its valley and
## moves every position and every tree key: the world after the migration is exactly the world before.
func test_a_single_map_save_moves_into_its_valley_exactly() -> void:
	var s := GameSession.create_new({"campaign_seed": 2106, "homeland": "none"})   # the single map's own valley
	var st := s.world.settlements[0]
	SettlementPlanner.place_starter_village(s, st.id)
	for m in 4:
		s.advance_days(30)
		SettlementPlanner.lord_month(s, st.id, 60)
	var now := SaveSystem.build_save_data(s)
	var now_text := JSON.stringify(now["world"])
	# the same world as the single map saved it: back to continent metres, no valley, version 6
	var old: Dictionary = JSON.parse_string(now_text)
	var origin := s.world.domain.origin_global
	SaveMigrator.move_into_valley(old, -origin)
	old.erase("domain")
	var v6 := {"header": {"save_version": 6}, "world": old}
	assert_true(float((old["settlements"] as Array)[0]["x"]) > 5000.0, "the old save speaks in metres of the continent")
	var migrated := SaveMigrator.migrate(JSON.parse_string(JSON.stringify(v6)))
	assert_eq(int(migrated["header"]["save_version"]), SaveMigrator.CURRENT_VERSION, "migrated to the current version")
	var world: Dictionary = migrated["world"]
	assert_eq(DomainState.from_dict(world["domain"]).key(), s.world.domain.key(), "the same valley is cut")
	var expected: Dictionary = JSON.parse_string(now_text)   # the same JSON path the save file takes
	assert_eq(_diff(world["buildings"], expected["buildings"]), "", "every building where it was")
	assert_eq(_diff(world["people"], expected["people"]), "", "every person where they were")
	assert_eq(_diff(world["terrain"], expected["terrain"]), "", "every stump and every quarried rock")
	assert_eq(_diff(world["settlements"], expected["settlements"]), "", "the settlement itself")
	var session := SaveSystem.session_from_data(migrated)
	assert_not_null(session, "and the migrated world plays on")
	if session:
		session.advance_days(10)
		assert_true(session.world.people_of(session.world.settlements[0].id).size() > 0, "with its people")


## "" when two JSON values are the same (numbers within a millimetre), else where they first differ.
static func _diff(a: Variant, b: Variant, at: String = "") -> String:
	if (a is float or a is int) and (b is float or b is int):
		return "" if absf(float(a) - float(b)) < 0.001 else "%s: %s != %s" % [at, str(a), str(b)]
	if typeof(a) != typeof(b):
		return "%s: %s != %s" % [at, str(a), str(b)]
	if a is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return "%s: %d keys != %d" % [at, (a as Dictionary).size(), (b as Dictionary).size()]
		for k: Variant in (a as Dictionary).keys():
			if not (b as Dictionary).has(k):
				return "%s.%s missing" % [at, str(k)]
			var d := _diff(a[k], b[k], "%s.%s" % [at, str(k)])
			if d != "":
				return d
		return ""
	if a is Array:
		if (a as Array).size() != (b as Array).size():
			return "%s: %d items != %d" % [at, (a as Array).size(), (b as Array).size()]
		for i in (a as Array).size():
			var d := _diff(a[i], b[i], "%s[%d]" % [at, i])
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s != %s" % [at, str(a), str(b)]


## The two maps in the game scene: separate cameras, separate limits, and no zoom from one to the other.
func test_the_game_has_two_maps_and_no_zoom_joins_them() -> void:
	Session.start_new({"campaign_seed": 2107})
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var local_view: LocalView = main.get("local_view")
	var global_view: GlobalView = main.get("global_view")
	assert_not_null(local_view, "there is a map of the valley")
	assert_not_null(global_view, "there is a map of the world")
	if local_view == null or global_view == null:
		main.queue_free()
		return
	assert_true(main.call("is_local"), "the game opens in the valley")
	var hud: SettlementHud = main.get("hud")
	assert_not_null(hud.get("_build"), "the HUD builds on the map of the valley")
	assert_not_null(hud.get("_local"), "and picks the buildings there")
	assert_not_null(hud.get("_interaction"), "the HUD picks provinces and hosts on the map of the world")
	assert_not_null(hud.get("_controller"), "and switches its map modes")
	var minimap: Minimap = hud.get("_minimap")
	assert_eq(minimap.space(), MapSpace.LOCAL, "the corner map shows the valley")
	assert_true(local_view.visible and not global_view.visible, "one map on the table at a time")
	assert_true(local_view.camera.enabled and not global_view.camera.enabled, "one camera at a time")
	# the farthest the valley goes is still far closer than the nearest the world comes
	assert_true(local_view.camera.max_meters_per_pixel < global_view.camera.min_meters_per_pixel,
		"local max %.1f m/px < global min %.1f m/px" % [local_view.camera.max_meters_per_pixel, global_view.camera.min_meters_per_pixel])
	assert_true(global_view.camera.min_meters_per_pixel > SettlementLayer.VISIBLE_MPP.y,
		"the world never comes close enough to show a house")
	# zooming out as far as the wheel goes stays in the valley
	var cam := local_view.camera
	cam.focus_on(local_view.home_point(), 1000.0, true)
	assert_true(cam.meters_per_pixel() <= local_view.max_mpp() + 0.001, "the valley's camera stops at the valley (%.2f)" % cam.meters_per_pixel())
	var view := cam.visible_world_rect()
	var allowed := Session.current.world.domain.rect().grow(LocalView.EDGE_MARGIN_M + 1.0)
	assert_true(allowed.encloses(view) or view.size.x > allowed.size.x or view.size.y > allowed.size.y,
		"and never looks past its misty rim (%s)" % str(view))
	assert_true(SettlementSim.is_detailed(Session.current, Session.current.world.settlements[0].id),
		"the valley on the table is lived hour by hour")
	# across to the world
	main.call("toggle_map")
	await tree.process_frame
	assert_false(main.call("is_local"), "Tab takes the player to the world")
	assert_true(global_view.visible and not local_view.visible, "the world is on the table")
	assert_true(global_view.camera.enabled and not local_view.camera.enabled, "with its own camera")
	assert_false(SettlementSim.is_detailed(Session.current, Session.current.world.settlements[0].id),
		"and the valley goes on by the day")
	assert_eq(minimap.space(), MapSpace.GLOBAL, "the corner map shows the continent")
	var home := global_view.home_point()
	assert_eq(WorldData.get_instance().province_at(home), Session.current.world.player().capital,
		"the world opens on the homeland")
	global_view.camera.focus_on(home, 0.1, true)
	assert_true(global_view.camera.meters_per_pixel() >= GlobalView.MIN_MPP - 0.001, "the world never shows the houses")
	main.call("toggle_map")
	await tree.process_frame
	assert_true(main.call("is_local"), "and back to the valley")
	main.queue_free()
	await tree.process_frame
