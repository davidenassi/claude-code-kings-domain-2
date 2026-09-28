extends KDTestCase
## Phase 17: a second, third and fifth game must not tell the same story. More events, and mostly conditional;
## spirits that grow, worsen, turn, branch and fade; rulers whose character changes the realm and passes to their
## children; aims in many fields; a chronicle that remembers the great works and the bad years.

const Economy := preload("res://tests/unit/test_economy.gd")
const KNOWN_WHEN := ["season", "has_settlement", "at_war", "at_peace", "min_war_years", "min_provinces", "min_population",
	"min_trust", "max_trust", "min_legitimacy", "max_legitimacy", "max_stability", "min_unrest", "crowned",
	"min_year", "min_families", "min_treasury", "max_treasury", "min_prestige", "ruler_trait", "ruler_min_age", "regency",
	"heir", "has_pact", "favour_below", "favour_above", "has_building", "capital_river", "capital_mountain",
	"capital_forest", "min_foreign_provinces", "min_wars", "has_spirit", "no_crisis"]
const KNOWN_EFFECTS := ["treasury", "legitimacy", "stability", "prestige", "turbulence", "research", "trust", "favour",
	"stock", "unrest", "devastation", "kill_people", "crisis", "spirit", "opinion_neighbour", "chronicle", "chain",
	"chain_days", "authority", "arrivals", "departures"]


func after_each() -> void:
	Session.end()


func test_the_events_are_many_varied_and_mostly_conditional() -> void:
	var all := Events.all()
	assert_true(all.size() >= 50, "at least fifty events (%d)" % all.size())
	var categories := {}
	var conditional := 0
	for e: Dictionary in all:
		assert_true(String(e.get("category", "")) != "", "%s has a category" % e["id"])
		categories[String(e.get("category", ""))] = true
		var when: Dictionary = e.get("when", {})
		for key: String in when.keys():
			assert_true(key in KNOWN_WHEN, "%s asks for a condition the game can read: %s" % [e["id"], key])
		# more than "there is a village": something about what the realm is
		var specific := when.keys().filter(func(k: String) -> bool: return k != "has_settlement")
		if not specific.is_empty() or bool(e.get("chain_only", false)):
			conditional += 1
		assert_true((e.get("options", []) as Array).size() >= 2, "%s offers a choice" % e["id"])
		for o: Dictionary in e.get("options", []):
			for key: String in (o.get("effects", {}) as Dictionary).keys():
				assert_true(key in KNOWN_EFFECTS, "%s has an effect the game knows: %s" % [e["id"], key])
			var chain := String(o.get("effects", {}).get("chain", ""))
			if chain != "":
				assert_false(Events.event(StringName(chain)).is_empty(), "%s chains to an event that exists" % e["id"])
	assert_true(categories.size() >= 10, "in ten fields at least (%s)" % ", ".join(PackedStringArray(categories.keys())))
	assert_true(float(conditional) / float(all.size()) >= 0.9, "and nearly all of them ask for something (%d of %d)" % [conditional, all.size()])


func test_what_the_realm_is_decides_what_can_happen() -> void:
	var s := Economy.village(1701)
	var w := s.world
	var k := w.player()
	s.advance_days(60)
	var f := Events.facts(s, k)
	assert_false(Events.matches({"ruler_trait": "pio"}, f), "no ruler, no pious ruler")
	assert_true(Events.matches({"has_building": "farm"}, f), "the village has a farm")
	assert_false(Events.matches({"has_building": "smith"}, f), "and no smithy")
	assert_eq(Events.matches({"capital_river": true}, f), WorldData.get_instance().province_geo(k.capital).has_river,
		"the river of the capital is read from the map")
	assert_false(Events.matches({"favour_below": {"people": 99}}, f), "a community has no powers to be below anything")
	crown_player(s)
	var ruler := w.ruler_of(k.id)
	ruler.traits = [&"pio"]
	f = Events.facts(s, k)
	assert_true(Events.matches({"ruler_trait": "pio"}, f), "a pious ruler is seen")
	assert_true(Events.matches({"favour_below": {"people": 99}}, f), "and the powers of the kingdom now exist")
	assert_true(Events.matches({"min_families": 1}, f), "the families of the capital are counted")
	var pool := Events.candidates(s, k).map(func(e: Dictionary) -> String: return String(e["id"]))
	assert_false(pool.has("usurai_tornano"), "a sequel never comes by itself")


func test_a_sequel_comes_when_its_time_comes() -> void:
	var s := GameSession.create_new({"campaign_seed": 1702})
	s.set_system_enabled(&"events", true)
	var k := crown_player(s)
	k.treasury = 0.0
	var loan := Events.event(&"usurai")
	EventSystem.choose(s, k, loan, 0, s.world.day)
	assert_near(k.treasury, 300.0, 0.01, "the loan arrives")
	assert_true(s.world.pending_events.filter(func(p: Dictionary) -> bool: return String(p["event"]) == "usurai_tornano").is_empty(),
		"and the usurers do not come back the same day")
	var due := float(k.records.get(&"chain_due:usurai_tornano", -1.0))
	assert_true(due > float(s.world.day) + 300.0, "they come back in a year (%d days)" % int(due - s.world.day))
	s.advance_days(400)
	var came := s.world.pending_events.any(func(p: Dictionary) -> bool: return String(p["event"]) == "usurai_tornano") \
		or k.records.has(&"event_day:usurai_tornano")
	assert_true(came, "a year later they knock at the door")


func test_rulers_have_no_contradiction_and_pass_their_character_on() -> void:
	var s := GameSession.create_new({"campaign_seed": 1703})
	var w := s.world
	var k := crown_player(s)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var inherited := 0
	var parent := CharacterState.new()
	parent.traits = [&"guerriero", &"avaro"]
	for i in 200:
		var c := CharacterState.new()
		CourtSystem.pick_traits(c, rng, parent)
		for t_id in c.traits:
			var td := Defs.get_def("traits", t_id) as TraitDef
			var others := c.traits.filter(func(o: StringName) -> bool: return o != t_id)
			assert_false(CourtSystem.traits_clash(others, td), "%s does not clash with %s" % [t_id, str(others)])
		if c.traits.has(&"guerriero") or c.traits.has(&"avaro"):
			inherited += 1
	assert_true(inherited > 60, "children take after their parent (%d of 200)" % inherited)
	assert_true(Defs.all("traits").size() >= 20, "twenty traits to combine (%d)" % Defs.all("traits").size())
	# the change of ruler changes the realm: a warlike head and a prudent one do not weigh war the same
	var ruler := w.ruler_of(k.id)
	ruler.traits = [&"guerriero", &"ambizioso", &"impulsivo"]
	var bold := DiplomacyAi.personality(w, k.id)
	ruler.traits = [&"prudente", &"diplomatico", &"clemente"]
	var wise := DiplomacyAi.personality(w, k.id)
	assert_true(float(bold["aggression"]) > float(wise["aggression"]) + 0.5, "a new head, a new policy (%.2f vs %.2f)" % [
		float(bold["aggression"]), float(wise["aggression"])])


func test_spirits_are_earned_and_can_fade() -> void:
	var s := GameSession.create_new({"campaign_seed": 1704})
	var w := s.world
	var k := crown_player(s)
	k.spirits.clear()
	k.records[&"spirits_seeded"] = 1.0
	k.records[&"trade_gold"] = 3000.0
	NationalSpiritSystem.new().run(s, SimStep.new())
	assert_true(k.spirits.has(&"popolo_di_mercanti"), "trade earns a spirit (%s)" % str(k.spirits))
	# a memory fades with the years
	k.spirits.append(&"carestia_ricordata")
	k.spirit_since[&"carestia_ricordata"] = w.day - 26 * PersonState.DAYS_PER_YEAR
	NationalSpiritSystem.new().run(s, SimStep.new())
	assert_false(k.spirits.has(&"carestia_ricordata"), "an old famine is forgotten after a generation")
	assert_true(k.spirits_past.has(&"carestia_ricordata"), "but the realm remembers it once had it")
	assert_true(w.chronicle.any(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "spirit_lost"), "and the chronicle says so")
	var branching := 0
	for sp: NationalSpiritDef in Defs.all("national_spirits"):
		if sp.evolves.size() >= 2:
			branching += 1
	assert_true(Defs.all("national_spirits").size() >= 30, "thirty spirits (%d)" % Defs.all("national_spirits").size())
	assert_true(branching >= 4, "several can go more than one way (%d)" % branching)


func test_the_chronicle_remembers_great_works_revolts_and_long_peace() -> void:
	var s := Economy.village(1705)
	var w := s.world
	var k := crown_player(s)
	s.advance_days(120)
	assert_true(w.chronicle.any(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "first_building"),
		"the first oven, the first granary... are written down")
	k.stability = 5.0
	CourtSystem._revolt_watch(s, k, w.day)
	assert_true(w.chronicle.any(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "revolt"), "a revolt is written down")
	k.stability = 70.0
	CourtSystem._revolt_watch(s, k, w.day)
	assert_true(w.chronicle.any(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "revolt_over"), "and its end")
	k.legitimacy = 80.0
	for i in 3:
		CourtSystem._stability_year(k)
	assert_eq(int(k.records.get(&"stable_best", 0.0)), 3, "three believed and obeyed years count for the long peace")


func test_people_can_arrive_and_leave_with_an_event() -> void:
	var s := Economy.village(1706)
	var w := s.world
	var st := w.settlements[0]
	var before := w.people_of(st.id).size()
	var came := PopulationSystem.welcome(s, st, 4, w.day, "arrivano")
	assert_eq(came, 4, "four settlers arrive")
	assert_eq(w.people_of(st.id).size(), before + 4, "and live in the village")
	for p in w.people_of(st.id).slice(before):
		assert_not_null(w.family(p.family), "%s comes with a family" % p.name)
	var gone := PopulationSystem.send_away(s, st, 2, w.day)
	assert_true(gone >= 1, "and some can leave (%d)" % gone)


func test_every_campaign_has_its_own_fate() -> void:
	var a := GameSession.create_new({"campaign_seed": 1707})
	var b := GameSession.create_new({"campaign_seed": 1708})
	var different := 0
	for e: Dictionary in Events.all():
		var wa := Events.weight_in_campaign(a, e)
		var wb := Events.weight_in_campaign(b, e)
		var base := float(e.get("weight", 1.0))
		assert_true(wa >= base * 0.25 - 0.001 and wa <= base * 1.8 + 0.001, "%s keeps a sensible weight (%.2f of %.2f)" % [e["id"], wa, base])
		if absf(wa - wb) > base * 0.3:
			different += 1
	assert_true(different > Events.all().size() / 3, "two campaigns weigh their events differently (%d of %d)" % [different, Events.all().size()])
	assert_near(Events.weight_in_campaign(a, Events.event(&"peste")), Events.weight_in_campaign(a, Events.event(&"peste")), 0.0001,
		"and the fate of a campaign does not change while it is played")

