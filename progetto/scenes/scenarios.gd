class_name Scenarios
extends RefCounted
## Development scenarios chosen with --kd-scenario (screenshots, trials, benchmarks). They only use the game's own
## commands and planners on the running session. Moved out of scenes/main.gd in the Rebirth (Phase 1), so the
## game shell does nothing but hold the two maps.


static func apply(sess: GameSession, args: Dictionary, crown: Callable) -> void:
	var scenario := String(args.get("scenario", ""))
	if args.has("no-events"):
		sess.set_system_enabled(&"events", false)   # clean screenshots: no card in front of the lens
	if args.has("speed"):
		sess.clock.set_speed(String(args["speed"]).to_int())
	if scenario.begins_with("village") and not sess.world.settlements.is_empty():
		SettlementPlanner.place_starter_village(sess, sess.world.settlements[0].id)
	if scenario == "village_grown" and not sess.world.settlements.is_empty():
		# a village that has had a few years: for looking at a street rather than at four buildings
		var home := sess.world.settlements[0]
		home.add(&"wood", 200)
		home.add(&"stone", 80)
		for i in 7:
			var spot := SettlementPlanner.find_spot(sess, home.id, &"house", home.center, 30.0 + i * 4.0)
			if spot != Vector2.INF:
				sess.submit(PlaceBuildingCommand.create(home.id, &"house", spot))
		sess.advance_days(160)
	if scenario in ["community_ready", "coronation", "kingdom", "kingdom_grown"] and not sess.world.settlements.is_empty():
		# the six founders grown into a village that could choose its royal house (Phase 15): for trying the
		# choice at once and for the screenshots of the families and of the coronation
		SettlementPlanner.place_starter_village(sess, sess.world.settlements[0].id)
		for month in 12 * 10:
			sess.advance_days(30)
			SettlementPlanner.lord_month(sess, sess.world.settlements[0].id, 60)
			if CourtSystem.monarchy_blocker(sess, sess.world.player()) == "":
				break
		if scenario == "coronation":
			# crowned with the interface already open, so the moment is shown as the player would see it
			(Engine.get_main_loop() as SceneTree).create_timer(0.3).timeout.connect(crown)
		elif scenario.begins_with("kingdom"):
			# a kingdom already standing when the interface opens: for the sheets of the realm (Phase 18 audit)
			crown_first_family(sess)
			if scenario == "kingdom_grown":
				# and twenty more years of a careful ruler (or --kd-years): lands, laws, a larger capital
				var pilot: GDScript = load("res://tests/campaign/campaign_pilot.gd")   # dev tooling, loaded only here
				for month in 12 * String(args.get("years", "20")).to_int():
					sess.advance_days(30)
					pilot.month(sess)
	if scenario == "war" and not sess.world.settlements.is_empty():
		# a host of ours and an enemy one in front of the village: for screenshots and for trying the battle
		SettlementPlanner.place_starter_village(sess, sess.world.settlements[0].id)
		var home := sess.world.settlements[0]
		home.add(&"weapons", 40)
		var me := sess.world.player()
		me.treasury = 900.0
		sess.submit(RecruitUnitCommand.create(home.id, &"lancieri"))
		sess.advance_days(Military.unit(&"lancieri").train_days + 1)
		for other in sess.world.kingdoms:
			if other.id == me.id or not other.alive or other.provinces.is_empty():
				continue
			other.treasury = 2000.0
			Diplomacy.start_war(sess.world, other.id, me.id)
			var enemy := ArmyState.new()
			enemy.id = sess.world.new_id()
			enemy.kingdom = other.id
			enemy.name = Military.army_name(sess.world, other)
			enemy.province = home.province
			# far enough to sit down and besiege, not to charge (armies live in the metres of the continent)
			enemy.pos = sess.world.settlement_global_pos(home) + Vector2(3400.0, 900.0)
			enemy.step_from = enemy.pos
			enemy.step_to = enemy.pos
			enemy.supplies = 20.0
			enemy.regiments.append({"unit": &"alabardieri", "men": 12, "max_men": 12, "morale": 70.0,
				"people": PackedInt32Array()})
			sess.world.armies.append(enemy)
			break
		sess.advance_days(12)
	if scenario == "army" and not sess.world.settlements.is_empty():
		# a village with a host already in the field: for screenshots and for trying the marches
		SettlementPlanner.place_starter_village(sess, sess.world.settlements[0].id)
		var village := sess.world.settlements[0]
		village.add(&"weapons", 40)
		sess.world.player().treasury = 900.0
		sess.submit(RecruitUnitCommand.create(village.id, &"lancieri"))
		sess.advance_days(Military.unit(&"lancieri").train_days + 1)
	if scenario.begins_with("stress_") and not sess.world.settlements.is_empty():
		# Phase 19: worlds pushed past a normal campaign, for the frame rate under load (dev tooling, loaded
		# only here): a town of --kd-people inhabitants, or every realm in arms and at war with its neighbours
		var stress: GDScript = load("res://tests/stress/stress_worlds.gd")
		if scenario == "stress_city":
			stress.grow_city(sess, String(args.get("people", "1500")).to_int())
		elif scenario == "stress_war":
			SettlementPlanner.place_starter_village(sess, sess.world.settlements[0].id)
			stress.raise_wars(sess, 6)
			sess.advance_days(20)
	if args.has("event"):
		# for screenshots and for trying a single event: put it in front of the king right away
		var wanted := Events.event(StringName(args["event"]))
		if not wanted.is_empty() and sess.world.player():
			EventSystem.fire(sess, sess.world.player(), wanted, sess.world.day)
	if args.has("days"):
		sess.advance_days(String(args["days"]).to_int())
	if args.has("hours"):
		for i in String(args["hours"]).to_int():
			sess.step_tick()


## The coronation scenario: the first rooted family is chosen, its eldest adult crowned.
static func crown_first_family(sess: GameSession) -> void:
	if sess == null:
		return
	var k := sess.world.player()
	var home := sess.world.settlements[0]
	for f in FamilySystem.consolidated_families(sess.world, home):
		var who := CourtSystem.eligible_rulers(sess.world, f)
		if not who.is_empty():
			var res := sess.submit(FoundMonarchyCommand.create(k.id, f.id, who[0].id))
			if not res.success:
				push_warning("coronation scenario: %s" % res.reason)
			return
