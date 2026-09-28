extends KDTestCase
## Phase 11: the world knocking at the door — events with real conditions and real consequences, crises that
## last, knowledge that is chosen once, the chronicle that remembers, and the goals of a campaign.


func _village(seed_value: int) -> GameSession:
	var s := GameSession.create_new({"campaign_seed": seed_value})
	SettlementPlanner.place_starter_village(s, s.world.settlements[0].id)
	s.world.player().treasury = 800.0
	return s


func _political(seed_value: int) -> GameSession:
	var s := GameSession.create_new({"campaign_seed": seed_value})
	s.world.settlements.clear()
	s.world.people.clear()
	s.world.buildings.clear()
	s.world.buildings_changed()
	return s


func test_events_are_data_driven_and_readable() -> void:
	var events := Events.all()
	assert_true(events.size() >= 12, "the world has a good handful of things to say (%d)" % events.size())
	for e: Dictionary in events:
		assert_true(String(e.get("text", "")).length() > 30, "%s is told in words" % e["id"])
		var options: Array = e.get("options", [])
		assert_true(options.size() >= 2, "%s leaves a choice" % e["id"])
		for o: Dictionary in options:
			assert_true(String(o.get("text", "")).length() > 3, "every answer says what it is")
			assert_false((o.get("effects", {}) as Dictionary).is_empty(), "and every answer does something")


func test_conditions_are_read_and_never_guessed() -> void:
	var s := _village(1101)
	var k := s.world.player()
	var f := Events.facts(s, k)
	assert_true(f.has("season") and f.has("trust") and f.has("population"), "the facts of the realm are gathered")
	assert_true(Events.matches({}, f), "an event without conditions can always happen")
	assert_false(Events.matches({"min_provinces": 99}, f), "a condition that does not hold stops it")
	assert_true(Events.matches({"has_settlement": true}, f), "and one that holds lets it through")
	assert_false(Events.matches({"unknown_key": 3}, f), "a condition nobody can read never fires an event")
	# the season really is the season
	var season := String(f["season"])
	assert_true(season in ["primavera", "estate", "autunno", "inverno"], "the season is a real one: %s" % season)


func test_an_answer_changes_the_world() -> void:
	var s := _village(1102)
	var w := s.world
	var k := crown_player(s)   # the legitimacy of a crown: a community would gain authority instead
	var village := w.settlements[0]
	var grain_before := village.amount(&"grain")
	var legitimacy_before := k.legitimacy
	Events.apply(s, k, {"stock": {"grain": 50}, "treasury": -30, "legitimacy": 5,
		"favour": {"people": 6}, "unrest": 0.1})
	assert_eq(village.amount(&"grain"), grain_before + 50, "grain really enters the store")
	assert_near(k.treasury, 770.0, 0.01, "the gold really leaves the treasury")
	assert_near(k.legitimacy, legitimacy_before + 5.0, 0.01, "the crown is firmer")
	assert_true(float(k.favour[&"people"]) > 55.0, "the people are pleased")
	assert_true(w.province(village.province).unrest > 0.0, "and the province is restless")


func test_a_crisis_lasts_and_then_passes() -> void:
	var s := _village(1103)
	var w := s.world
	var k := w.player()
	var before := KingdomModifiers.value(s, k.id, &"trade.income", 100.0)
	Events.apply(s, k, {"crisis": {"id": "quarantena", "name": "Quarantena", "days": 60,
		"modifiers": [{"key": "trade.income", "op": "mul", "value": 0.7}]}})
	assert_eq(k.crises.size(), 1, "the realm carries a crisis")
	var during := KingdomModifiers.value(s, k.id, &"trade.income", 100.0)
	assert_true(during < before * 0.85, "and it is felt in the numbers (%.0f contro %.0f)" % [during, before])
	var labels := PackedStringArray()
	for part: Dictionary in KingdomModifiers.stack(s, k.id).breakdown(&"trade.income"):
		labels.append(String(part["label"]))
	assert_true(",".join(labels).contains("Quarantena"), "the crisis says its name in the formula: %s" % ",".join(labels))
	s.advance_days(70)
	assert_eq(k.crises.size(), 0, "after its days it is over")
	assert_near(KingdomModifiers.value(s, k.id, &"trade.income", 100.0), before, 0.001, "and the numbers go back")


func test_the_player_is_asked_and_the_ai_answers_by_itself() -> void:
	var s := _village(1104)
	var w := s.world
	var k := w.player()
	var e := Events.event(&"monaco_viaggiante")
	EventSystem.fire(s, k, e, w.day)
	assert_eq(w.pending_events.size(), 1, "the king is asked")
	var pending: Dictionary = w.pending_events[0]
	var research_before := k.research
	var res := s.submit(ChooseEventOptionCommand.create(int(pending["id"]), 0))
	assert_true(res.success, "and he can answer: %s" % res.reason)
	assert_eq(w.pending_events.size(), 0, "the matter is closed")
	assert_true(k.research > research_before, "with the consequences of his answer")
	# an AI crown decides on its own, with the head of whoever reigns
	var other: KingdomState = null
	for other_k in w.kingdoms:
		if not other_k.is_player and other_k.alive and not other_k.provinces.is_empty():
			other = other_k
			break
	var chronicle_before := w.chronicle.size()
	var treasury_before := other.treasury
	var stability_before := other.stability
	EventSystem.fire(s, other, Events.event(&"banditi_nei_boschi"), w.day)
	assert_eq(w.pending_events.size(), 0, "nobody asks the king about another realm")
	assert_true(other.treasury != treasury_before or other.stability != stability_before, "but the other crown decides and pays")
	# consolidation: the chronicle keeps the player's history and what changes the world, not the others' affairs
	assert_eq(w.chronicle.size(), chronicle_before, "and its bandits are its own business, not a line of our chronicle")


func test_an_unanswered_event_is_decided_by_the_court() -> void:
	var s := _village(1105)
	var w := s.world
	var k := w.player()
	EventSystem.fire(s, k, Events.event(&"mercante_straniero"), w.day)
	assert_eq(w.pending_events.size(), 1, "the embassy waits")
	s.advance_days(60)
	assert_eq(w.pending_events.size(), 0, "silence is an answer too")
	# consolidation: an ordinary fortune is not history, a crisis is — the court's answer to it is written down
	var before := w.chronicle.size()
	EventSystem.fire(s, k, Events.event(&"incendio_del_granaio"), w.day)
	s.advance_days(60)
	var written := false
	for line: Dictionary in w.chronicle.slice(before):
		if String(line["text"]).contains(Events.words(k, String(Events.event(&"incendio_del_granaio")["title"]))):
			written = true
	assert_true(written, "and the court wrote down what it decided on a crisis")


func test_knowledge_is_chosen_once_per_branch() -> void:
	var s := _village(1106)
	var k := s.world.player()
	k.research = 5000.0
	var before := KingdomModifiers.value(s, k.id, &"production.grain", 100.0)
	var res := s.submit(AdoptTechnologyCommand.create(k.id, &"rotazione"))
	assert_true(res.success, "the realm can learn: %s" % res.reason)
	assert_true(k.technologies.has(&"rotazione"), "and it knows it")
	assert_true(KingdomModifiers.value(s, k.id, &"production.grain", 100.0) > before * 1.1,
		"the fields yield more for it")
	var labels := PackedStringArray()
	for part: Dictionary in KingdomModifiers.stack(s, k.id).breakdown(&"production.grain"):
		labels.append(String(part["label"]))
	assert_true(",".join(labels).contains("Rotazione"), "and the formula says where it comes from: %s" % ",".join(labels))
	var twice := s.submit(AdoptTechnologyCommand.create(k.id, &"bonifica"))
	assert_false(twice.success, "the other road of the same branch is closed")
	assert_true(twice.reason.to_lower().contains("strada"), "and it says why: %s" % twice.reason)
	k.research = 0.0
	var poor := s.submit(AdoptTechnologyCommand.create(k.id, &"mulini"))
	assert_false(poor.success, "and without points nothing is learned")
	assert_true(poor.reason.contains("sapere"), "with the reason: %s" % poor.reason)


func test_the_realm_learns_month_by_month() -> void:
	var s := _village(1107)
	var k := s.world.player()
	var rate := ResearchSystem.points_per_month(s, k)
	assert_true(rate > 0.0, "a realm with lands and workshops learns something (%.1f)" % rate)
	var before := k.research
	s.advance_days(70)
	assert_true(k.research > before, "and the points really pile up (%.0f -> %.0f)" % [before, k.research])


func test_the_chronicle_remembers_and_survives_a_save() -> void:
	var s := _village(1108)
	var w := s.world
	assert_true(w.chronicle.size() > 0, "the founding of the realm is already written (%d righe)" % w.chronicle.size())
	var before := w.chronicle.size()
	EventBus.chronicle_written.emit({"day": w.day, "kingdom": w.player().id, "kind": "event", "text": "Una prova."})
	assert_eq(w.chronicle.size(), before + 1, "and every deed adds its line")
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s)))
	var loaded := SaveSystem.session_from_data(data)
	assert_eq(loaded.world.chronicle.size(), w.chronicle.size(), "the chronicle crosses the save")
	assert_eq(String(loaded.world.chronicle[loaded.world.chronicle.size() - 1]["text"]), "Una prova.",
		"with the last thing that happened")


func test_the_goals_of_a_campaign_are_measured_on_real_things() -> void:
	var s := _village(1109)
	var k := s.world.player()
	var rows := Objectives.progress(s, k)
	assert_true(rows.size() >= 10, "there are many things to aim at (%d)" % rows.size())
	var fields := {}
	for row: Dictionary in rows:
		fields[String(row["category"])] = true
	assert_true(fields.size() >= 8, "in different fields, not only conquest (%s)" % ", ".join(PackedStringArray(fields.keys())))
	for row: Dictionary in rows:
		assert_true(int(row["target"]) > 0, "%s has a target" % row["name"])
		assert_true(int(row["value"]) >= 0, "%s has a real measure" % row["name"])
	assert_eq(int(rows[2]["value"]), 0, "a community without a crown has no dynasty yet")
	crown_player(s)
	rows = Objectives.progress(s, k)
	assert_true(int(rows[2]["value"]) >= 1, "the first crowned ruler counts for the dynasty")
	k.treasury = 100000.0
	assert_true(bool(Objectives.progress(s, k)[3]["done"]), "and a full treasury closes its goal")


func test_five_campaigns_of_a_century_tell_different_stories() -> void:
	var stories: Array = []
	for seed_value in [1201, 1202, 1203, 1204, 1205]:
		stories.append(_run_century(seed_value))
	for story: Dictionary in stories:
		assert_true(int(story["alive"]) >= 3, "the world survives the century (seed %d)" % story["seed"])
		assert_true(int(story["chronicle"]) > 20, "and it has something to tell (%d righe)" % story["chronicle"])
	var signatures := {}
	for story: Dictionary in stories:
		signatures[String(story["signature"])] = true
	assert_eq(signatures.size(), stories.size(), "five seeds, five different histories")
	var borders := {}
	var dynasties := {}
	for story: Dictionary in stories:
		borders[String(story["borders"])] = true
		dynasties[int(story["rulers"])] = true
	assert_true(borders.size() > 1, "the political map ends up drawn differently (%d forme su %d)" % [borders.size(), stories.size()])
	assert_true(dynasties.size() > 1, "and so do the dynasties (%s)" % str(dynasties.keys()))
	print("  100y: %s" % str(stories.map(func(x: Dictionary) -> String:
		return "%d regni/%d guerre/%d cronaca" % [x["alive"], x["wars"], x["chronicle"]])))


func _run_century(seed_value: int) -> Dictionary:
	var s := _political(seed_value)
	var w := s.world
	s.advance_days(100 * 360)
	var alive := 0
	var wars := 0
	var rulers := 0
	var biggest := 0
	var spirits := {}
	for k in w.kingdoms:
		if k.alive and not k.provinces.is_empty():
			alive += 1
		wars += int(k.records.get(&"wars_declared", 0.0))
		rulers += int(k.records.get(&"rulers_crowned", 0.0))
		biggest = maxi(biggest, k.provinces.size())
		for spirit in k.spirits:
			spirits[spirit] = true
	var shape := PackedStringArray()
	for k in w.kingdoms:
		shape.append(str(k.provinces.size()))
	return {"seed": seed_value, "alive": alive, "wars": wars, "rulers": rulers, "biggest": biggest,
		"chronicle": w.chronicle.size(), "spirits": spirits.size(), "borders": ",".join(shape),
		"signature": "%d|%d|%d|%d|%d" % [alive, wars, rulers, biggest, w.chronicle.size()]}

