extends KDTestCase
## Phase 8: what stands between the crowns — opinions, pacts, wars, marriages — and the AI that governs
## every realm but the player's.


## A world without the player's village: pure politics, so fifty years cost seconds instead of minutes.
func _political(seed_value: int) -> GameSession:
	var s := GameSession.create_new({"campaign_seed": seed_value})
	s.world.settlements.clear()
	s.world.people.clear()
	s.world.buildings.clear()
	s.world.buildings_changed()
	return s


func _two_realms(s: GameSession) -> Array[KingdomState]:
	var out: Array[KingdomState] = []
	for k in s.world.kingdoms:
		if k.alive and not k.provinces.is_empty() and not k.is_player:
			out.append(k)
		if out.size() == 2:
			break
	return out


func test_the_world_starts_with_opinions_that_come_from_the_facts() -> void:
	var s := _political(801)
	var w := s.world
	assert_true(w.relations.size() > 20, "every pair of realms knows of the other (%d)" % w.relations.size())
	var same := 0
	var different := 0
	var same_total := 0.0
	var different_total := 0.0
	for r: RelationState in w.relations.values():
		var ka := w.kingdom(r.a)
		var kb := w.kingdom(r.b)
		assert_true(r.opinion >= -100.0 and r.opinion <= 100.0, "opinions stay in range")
		if ka.culture == kb.culture and ka.religion == kb.religion:
			same += 1
			same_total += r.opinion
		elif ka.culture != kb.culture and ka.religion != kb.religion:
			different += 1
			different_total += r.opinion
	assert_true(same > 0 and different > 0, "the world holds both kinds of neighbours")
	assert_true(same_total / same > different_total / different,
		"like speaks to like (%.1f contro %.1f)" % [same_total / same, different_total / different])
	# the breakdown says it in words
	var any: RelationState = w.relations.values()[0]
	var labels := PackedStringArray()
	for part: Dictionary in Diplomacy.opinion_breakdown(w, any):
		labels.append(String(part["label"]))
	assert_true(labels.size() >= 3, "the opinion is explained piece by piece: %s" % ",".join(labels))


func test_neighbours_and_shadows_weigh_on_the_opinion() -> void:
	var s := _political(802)
	var w := s.world
	var pair := _two_realms(s)
	var r := Diplomacy.relation(w, pair[0].id, pair[1].id)
	var before := Diplomacy.opinion_target(w, r)
	r.memories.append({"kind": "war_declared", "day": w.day})
	var after := Diplomacy.opinion_target(w, r)
	assert_true(after < before - 20.0, "a war is remembered (%.0f -> %.0f)" % [before, after])
	r.memories.clear()
	r.married = true
	assert_true(Diplomacy.opinion_target(w, r) > before, "a marriage is remembered too")


func test_a_pact_is_signed_or_refused_and_always_says_why() -> void:
	var s := _political(803)
	var w := s.world
	var pair := _two_realms(s)
	var a := pair[0]
	var b := pair[1]
	a.treasury = 500.0
	var r := Diplomacy.relation(w, a.id, b.id)
	r.opinion = 60.0
	var res := s.submit(ProposePactCommand.create(a.id, b.id, &"trade"))
	assert_true(res.success, "the proposal can be made: %s" % res.reason)
	assert_true(bool(res.data["accepted"]), "a friendly crown signs: %s" % res.data.get("reason", ""))
	assert_true(String(res.data["reason"]).contains(b.name), "and the answer names who answered")
	assert_true(Diplomacy.has_pact(w, a.id, b.id, &"trade"), "the pact is in force")
	assert_near(a.treasury, 460.0, 0.01, "the pact is paid for")
	# the pact is a named source in the formula of both realms
	var labels := PackedStringArray()
	for part: Dictionary in KingdomModifiers.stack(s, a.id).breakdown(&"trade.income"):
		labels.append(String(part["label"]))
	assert_true(",".join(labels).contains("Patto commerciale"), "and it shows in the numbers: %s" % ",".join(labels))
	# an alliance needs a non-aggression pact first, and it says so
	var alliance := s.submit(ProposePactCommand.create(a.id, b.id, &"alliance"))
	assert_false(alliance.success, "an alliance out of nothing is refused")
	assert_true(alliance.reason.to_lower().contains("non aggressione"), "with the reason: %s" % alliance.reason)
	# a crown that hates us refuses
	var pair2 := _two_realms(s)
	r.opinion = -80.0
	var refused := s.submit(ProposePactCommand.create(a.id, b.id, &"non_aggression"))
	assert_true(refused.success, "the embassy leaves all the same")
	assert_false(bool(refused.data["accepted"]), "but is sent home")
	assert_true(String(refused.data["reason"]).contains("rifiuta") or String(refused.data["reason"]).contains("stima"),
		"with a readable reason: %s" % refused.data["reason"])


func test_a_war_breaks_the_pacts_and_calls_the_allies() -> void:
	var s := _political(804)
	var w := s.world
	var realms: Array[KingdomState] = []
	for k in w.kingdoms:
		if k.alive and not k.provinces.is_empty() and not k.is_player:
			realms.append(k)
	var a := realms[0]
	var b := realms[1]
	var c := realms[2]
	Diplomacy.sign(w, b.id, c.id, &"alliance")
	Diplomacy.relation(w, b.id, c.id).opinion = 60.0
	Diplomacy.sign(w, a.id, b.id, &"non_aggression")
	var blocked := DeclareWarCommand.create(a.id, b.id).validate(s)
	assert_true(blocked != "", "a pact stands in the way of a war: %s" % blocked)
	s.submit(BreakPactCommand.create(a.id, b.id, &"non_aggression"))
	assert_false(Diplomacy.has_pact(w, a.id, b.id, &"non_aggression"), "the pact is torn up")
	var res := s.submit(DeclareWarCommand.create(a.id, b.id, "le terre del confine"))
	assert_true(res.success, "now the war can be declared: %s" % res.reason)
	assert_true(Diplomacy.at_war(w, a.id, b.id), "the two realms are at war")
	assert_true(Diplomacy.at_war(w, c.id, a.id), "the ally came when called")
	assert_true(Diplomacy.opinion_target(w, Diplomacy.relation(w, a.id, b.id)) < -40.0, "war poisons the opinion")


func test_peace_leaves_a_truce_that_holds_and_then_runs_out() -> void:
	var s := _political(805)
	var w := s.world
	var pair := _two_realms(s)
	var a := pair[0]
	var b := pair[1]
	Diplomacy.start_war(w, a.id, b.id)
	assert_true(MakePeaceCommand.create(a.id, b.id).validate(s) != "", "nobody makes peace the day after the declaration")
	s.advance_days(3 * 360)   # three years of war tire even a proud crown
	if Diplomacy.at_war(w, a.id, b.id):
		var res := s.submit(MakePeaceCommand.create(a.id, b.id))
		assert_true(res.success and bool(res.data.get("accepted", false)),
			"a tired realm accepts: %s%s" % [res.reason, res.data.get("reason", "")])
	assert_false(Diplomacy.at_war(w, a.id, b.id), "the war is over, asked for or offered")
	var again := DeclareWarCommand.create(a.id, b.id).validate(s)
	assert_true(again.contains("tregua"), "and a truce stands in the way: %s" % again)
	var r := Diplomacy.relation(w, a.id, b.id)
	r.truce_until = w.day
	assert_eq(DeclareWarCommand.create(a.id, b.id).validate(s), "", "when the truce runs out, war is possible again")


func test_a_tribute_moves_gold_every_month() -> void:
	var s := _political(806)
	var w := s.world
	var pair := _two_realms(s)
	var strong := pair[0]
	var weak := pair[1]
	Diplomacy.relation(w, strong.id, weak.id).pacts[&"tribute"] = 0
	Diplomacy.relation(w, strong.id, weak.id).payer = weak.id
	weak.treasury = 400.0
	weak.last_balance = {"taxes": 50.0, "provinces": 50.0}
	var strong_before := strong.treasury
	var weak_before := weak.treasury
	# the payment itself (Phase 16: since the lands yield, a month of income can outweigh the tribute, so the
	# test looks at the tribute and not at the whole balance of the month)
	DiplomacySystem.new()._pay_tribute(w, Diplomacy.relation(w, strong.id, weak.id))
	var paid := weak_before - weak.treasury
	assert_true(paid > 0.0, "the weaker crown pays (%.0f -> %.0f)" % [weak_before, weak.treasury])
	assert_near(strong.treasury - strong_before, paid, 0.01, "and the stronger one cashes in what it pays")


func test_a_marriage_ties_two_houses() -> void:
	var s := _political(807)
	var w := s.world
	var pair := _two_realms(s)
	var a := pair[0]
	var b := pair[1]
	a.treasury = 400.0
	var r := Diplomacy.relation(w, a.id, b.id)
	r.opinion = 55.0
	# both houses need a child old enough
	CourtSystem._make_character(s, a, 20, false, w.rng.stream(&"test"))
	CourtSystem._make_character(s, b, 18, true, w.rng.stream(&"test"))
	var before := Diplomacy.opinion_target(w, r)
	var res := s.submit(ArrangeMarriageCommand.create(a.id, b.id))
	assert_true(res.success, "the match can be proposed: %s" % res.reason)
	assert_true(bool(res.data.get("accepted", false)), "and it is accepted: %s" % res.data.get("reason", ""))
	assert_true(r.married, "the two houses are related")
	assert_true(Diplomacy.opinion_target(w, r) > before + 10.0, "and think better of each other")
	var tied := 0
	for c: CharacterState in w.characters.values():
		var consort := w.character(c.consort)
		if consort and consort.kingdom != c.kingdom:
			tied += 1
	assert_true(tied >= 2, "a child of each court is married to the other (%d)" % tied)


func test_the_ai_governs_its_realm_and_says_why() -> void:
	var s := _political(808)
	var w := s.world
	var acted := 0
	for k in w.kingdoms:
		if k.is_player or not k.alive or k.provinces.is_empty():
			continue
		k.treasury = 900.0
		var choice := RealmAiSystem.take_turn(s, k)
		if not choice.is_empty():
			acted += 1
			assert_true(String(choice["reason"]).length() > 10, "every choice comes with a motive: %s" % choice["reason"])
	assert_true(acted >= 3, "the crowns of the world do something with their gold (%d)" % acted)
	var lines := RealmAiSystem.log_lines(s)
	assert_true(lines.size() >= acted, "and what they did is written down (%d righe)" % lines.size())
	var joined := PackedStringArray()
	for line: Dictionary in lines:
		joined.append(String(line["text"]))
	var text := "\n".join(joined)
	assert_true(text.contains("Regno") or text.contains("Signoria"), "the log names the realms:\n%s" % text.substr(0, 300))


func test_different_rulers_lead_to_different_worlds() -> void:
	var warlike := _run_world(809, [&"guerriero", &"crudele"], 25)
	var peaceful := _run_world(809, [&"mercantile", &"generoso"], 25)
	assert_true(int(warlike["wars"]) > int(peaceful["wars"]),
		"crowns of war make more wars than crowns of trade (%d contro %d)" % [warlike["wars"], peaceful["wars"]])
	assert_true(int(peaceful["pacts"]) + int(peaceful["developed"]) > 0, "and the peaceful ones do something else with their years")
	print("  25y: guerrieri %d guerre / %d patti, mercanti %d guerre / %d patti" % [
		warlike["wars"], warlike["pacts"], peaceful["wars"], peaceful["pacts"]])


## Runs a world where every AI ruler carries the same traits, and counts what happened.
func _run_world(seed_value: int, ruler_traits: Array, years: int) -> Dictionary:
	var s := _political(seed_value)
	var w := s.world
	for k in w.kingdoms:
		if k.is_player:
			continue
		var ruler := w.ruler_of(k.id)
		if ruler:
			ruler.traits.clear()
			for t: StringName in ruler_traits:
				ruler.traits.append(t)
		k.treasury = 600.0
	s.advance_days(years * 360)
	var wars := 0
	var pacts := 0
	var developed := 0
	for k in w.kingdoms:
		wars += int(k.records.get(&"wars_declared", 0.0))
		pacts += int(k.records.get(&"pacts_signed", 0.0))
		developed += int(k.records.get(&"provinces_developed", 0.0))
	return {"wars": wars, "pacts": pacts, "developed": developed, "session": s}


func test_fifty_years_of_twenty_realms() -> void:
	var s := _political(810)
	var w := s.world
	var t0 := Time.get_ticks_msec()
	s.advance_days(50 * 360)
	var ms := Time.get_ticks_msec() - t0
	var wars := 0
	var pacts := 0
	var developed := 0
	var alive := 0
	for k in w.kingdoms:
		if k.alive and not k.provinces.is_empty():
			alive += 1
		wars += int(k.records.get(&"wars_declared", 0.0))
		pacts += int(k.records.get(&"pacts_signed", 0.0))
		developed += int(k.records.get(&"provinces_developed", 0.0))
		assert_true(k.legitimacy >= 0.0 and k.legitimacy <= 100.0, "%s keeps a legitimacy in range" % k.name)
		if k.alive and not k.provinces.is_empty() and k.monarchy_founded:   # a community has no head to keep
			assert_not_null(w.ruler_of(k.id), "%s still has a crowned head" % k.name)
	for r: RelationState in w.relations.values():
		assert_true(r.a != r.b, "nobody is at war with himself")
		assert_true(r.opinion >= -100.0 and r.opinion <= 100.0, "opinions stay in range")
		if r.at_war:
			assert_true(r.war_since >= 0, "a war knows when it started")
	print("  50y: %d regni vivi, %d guerre, %d patti, %d province sviluppate, %d ms" % [alive, wars, pacts, developed, ms])
	assert_true(alive >= 5, "the world is still full of crowns (%d)" % alive)
	assert_true(wars + pacts + developed > 0, "and fifty years left a mark (%d guerre, %d patti, %d province)" % [wars, pacts, developed])
	assert_true(RealmAiSystem.log_lines(s).size() > 0, "the motives of the last decisions can be read")


func test_diplomacy_survives_a_save() -> void:
	var s := _political(811)
	var w := s.world
	var pair := _two_realms(s)
	var a := pair[0]
	var b := pair[1]
	Diplomacy.sign(w, a.id, b.id, &"non_aggression")
	Diplomacy.relation(w, a.id, b.id).remember(&"gift", w.day)
	Diplomacy.relation(w, a.id, b.id).opinion = 42.0
	w.offers.append({"id": 9901, "from": a.id, "kind": "pact", "pact": "trade", "day": w.day,
		"expires": w.day + 20, "text": "prova"})
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s)))
	var loaded := SaveSystem.session_from_data(data)
	var lw := loaded.world
	assert_true(Diplomacy.has_pact(lw, a.id, b.id, &"non_aggression"), "the pact crosses the save")
	assert_near(Diplomacy.opinion(lw, a.id, b.id), 42.0, 0.001, "and so does the opinion")
	assert_eq(Diplomacy.relation(lw, a.id, b.id).memories.size(), 1, "the memories too")
	assert_eq(lw.offers.size(), 1, "the ambassador is still waiting")

