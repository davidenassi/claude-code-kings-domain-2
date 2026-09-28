extends Node
## Phase 19 stress tests, measured. Run with:
##   godot --headless --path <ROOT> res://tests/stress/stress_runner.tscn -- --kd-stress=city,sites,war,pacts,long
##     [--kd-people=1000,2000] [--kd-years=150]
## Builds the worlds of StressWorlds, advances them and times what a player would wait for: a day of the
## simulation (resolved by the day and hour by hour), a month of the lord, the arrival of people, the planner,
## the routes of the armies, a save and a load. Checks that the world is still coherent afterwards.
## Writes tests/output/stress/stress_report.md and prints every line. Exit code 1 if a check fails.

var _lines: PackedStringArray = []
var _failures: PackedStringArray = []


func _ready() -> void:
	await get_tree().process_frame
	var args := BootArgs.parse()
	var which := String(args.get("stress", "city,sites,war,pacts")).split(",", false)
	var sizes: Array[int] = []
	for part in String(args.get("people", "1000,2000")).split(",", false):
		sizes.append(part.to_int())
	_say("# Stress test — %s" % Time.get_datetime_string_from_system())
	_say("")
	if which.has("city"):
		for n in sizes:
			_city(n)
	if which.has("sites"):
		_sites(120)
	if which.has("war"):
		_war(6)
	if which.has("pacts"):
		_pacts()
	if which.has("long"):
		_long(String(args.get("years", "150")).to_int())
	_say("")
	if _failures.is_empty():
		_say("Tutti i controlli di coerenza passati.")
	else:
		_say("CONTROLLI FALLITI:")
		for f in _failures:
			_say("- " + f)
	var dir := ProjectSettings.globalize_path("res://tests/output/stress")
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join("stress_report.md"), FileAccess.WRITE)
	if file:
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _say(line: String) -> void:
	_lines.append(line)
	print(line)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
		_say("  ✗ " + what)


static func _ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0


static func _mb() -> float:
	return OS.get_static_memory_usage() / 1048576.0


## Days advanced one at a time: [average ms, worst ms].
static func _days(session: GameSession, n: int) -> Array[float]:
	var total := 0.0
	var worst := 0.0
	for i in n:
		var t0 := Time.get_ticks_usec()
		session.advance_days(1)
		var ms := _ms(t0)
		total += ms
		worst = maxf(worst, ms)
	return [total / n, worst]


static func _reset_profile(session: GameSession) -> void:
	for s in session.scheduler.systems():
		s.profile_usec = 0
		s.profile_runs = 0


## The four systems that cost the most in total, from the scheduler's own profile: "id total (average × runs)".
static func _top_systems(session: GameSession) -> String:
	var rows: Array = []
	for s in session.scheduler.systems():
		if s.profile_runs > 0:
			rows.append([s.profile_usec / 1000.0, String(s.id), s.profile_runs])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var parts: PackedStringArray = []
	for r in rows.slice(0, 4):
		parts.append("%s %.0f ms (%.2f×%d)" % [r[1], r[0], r[0] / r[2], r[2]])
	return ", ".join(parts)


func _save_load(session: GameSession, label: String) -> void:
	var t0 := Time.get_ticks_usec()
	var data := SaveSystem.build_save_data(session, label)
	var build_ms := _ms(t0)
	t0 = Time.get_ticks_usec()
	var text := JSON.stringify(data)
	var json_ms := _ms(t0)
	t0 = Time.get_ticks_usec()
	var parsed: Variant = JSON.parse_string(text)
	var parse_ms := _ms(t0)
	t0 = Time.get_ticks_usec()
	var back := SaveSystem.session_from_data(parsed as Dictionary) if parsed is Dictionary else null
	var load_ms := _ms(t0)
	_say("- Salvataggio: dati %.0f ms + JSON %.0f ms, %.0f KB · caricamento: parse %.0f ms + mondo %.0f ms" % [
		build_ms, json_ms, text.length() / 1024.0, parse_ms, load_ms])
	_check(back != null, "%s: the save comes back" % label)
	if back:
		_check(back.world.people.size() == session.world.people.size(), "%s: same people after load" % label)
		_check(back.world.buildings.size() == session.world.buildings.size(), "%s: same buildings after load" % label)
		_check(back.world.armies.size() == session.world.armies.size(), "%s: same armies after load" % label)
		back.dispose()
	# the shelf: files on disk, the list of the menu, the automatic saves that take turns
	SaveSystem.save_dir = "user://tests/stress_shelf"
	for entry in SaveCatalogue.list():
		SaveCatalogue.remove(String(entry["path"]))
	t0 = Time.get_ticks_usec()
	SaveSystem.save_to_file(session, SaveSystem.slot_path("stress"), label)
	var write_ms := _ms(t0)
	t0 = Time.get_ticks_usec()
	var from_disk := SaveSystem.load_from_file(SaveSystem.slot_path("stress"))
	var read_ms := _ms(t0)
	if from_disk:
		from_disk.dispose()
	t0 = Time.get_ticks_usec()
	SaveCatalogue.read_header(SaveSystem.slot_path("stress"))
	var header_ms := _ms(t0)
	for i in 4:
		SaveCatalogue.autosave(session)
	t0 = Time.get_ticks_usec()
	SaveCatalogue.autosave(session)
	var autosave_ms := _ms(t0)
	t0 = Time.get_ticks_usec()
	var shelf := SaveCatalogue.list()
	var list_ms := _ms(t0)
	var bytes := FileAccess.get_file_as_bytes(SaveSystem.slot_path("stress")).size()
	_say("- Su disco: scrittura %.0f ms (%.0f KB compressi), lettura %.0f ms · intestazione per il menu %.0f ms · elenco di %d salvataggi %.0f ms · un salvataggio automatico con la rotazione %.0f ms" % [
		write_ms, bytes / 1024.0, read_ms, header_ms, shelf.size(), list_ms, autosave_ms])
	for entry in SaveCatalogue.list():
		SaveCatalogue.remove(String(entry["path"]))
	SaveSystem.save_dir = SaveSystem.SAVE_DIR


func _coherent(session: GameSession, label: String) -> void:
	var world := session.world
	for p in world.provinces:
		_check(p.population >= 0, "%s: province %d has %d people" % [label, p.id, p.population])
		if p.owner >= 0:
			var k := world.kingdom(p.owner)
			_check(k != null and k.alive, "%s: province %d owned by a dead or missing realm %d" % [label, p.id, p.owner])
	for a in world.armies:
		_check(a.men() > 0, "%s: army %d with %d men still in the field" % [label, a.id, a.men()])
		_check(world.province(a.province) != null, "%s: army %d in no province (%d)" % [label, a.id, a.province])
		_check(world.kingdom(a.kingdom) != null and world.kingdom(a.kingdom).alive, "%s: army %d of a dead realm" % [label, a.id])
	for k in world.kingdoms:
		if not k.alive:
			continue
		var seen := {}
		var walk := Diplomacy.liege_of(world, k.id)
		while walk >= 0 and not seen.has(walk):
			seen[walk] = true
			walk = Diplomacy.liege_of(world, walk)
		_check(walk < 0, "%s: the lords of %s go round in a circle" % [label, k.name])
		for other in world.kingdoms:
			if other.id <= k.id or not other.alive:
				continue
			if Diplomacy.at_war(world, k.id, other.id):
				for pact_id: StringName in Diplomacy.relation(world, k.id, other.id).pacts.keys():
					_check(not bool(Diplomacy.pact(pact_id).get("blocks_war", false)),
						"%s: %s and %s at war with a %s" % [label, k.name, other.name, pact_id])
	for s in world.settlements:
		for res: StringName in s.stock.keys():
			_check(int(s.stock[res]) >= 0, "%s: %s holds %d %s" % [label, s.name, int(s.stock[res]), res])
	for p: PersonState in world.people.values():
		_check(world.settlement(p.settlement) != null, "%s: %s lives nowhere" % [label, p.name])


# --- the scenarios -------------------------------------------------------------------------------------------

func _city(people: int) -> void:
	_say("## Città di %d abitanti" % people)
	var mem0 := _mb()
	var session := GameSession.create_new({"campaign_seed": 1901})
	var s := session.world.settlements[0]
	var made := StressWorlds.grow_city(session, people)
	_say("- Costruita: %d edifici (%d senza posto) in %.0f ms di planner · %d abitanti accolti in %.0f ms (ultimo gruppo di 25: %.0f ms)" % [
		made["buildings"], made["failed"], made["place_ms"], made["people"], made["welcome_ms"], made["welcome_last_batch_ms"]])
	_reset_profile(session)
	var agg := _days(session, 30)
	_say("- Giorno risolto per aggregato (villaggio non guardato): media %.1f ms, peggiore %.1f ms · %s" % [agg[0], agg[1], _top_systems(session)])
	SettlementSim.set_observed(session, {s.id: true})
	_reset_profile(session)
	var hourly := _days(session, 3)
	_say("- Giorno ora per ora (villaggio guardato): media %.0f ms, peggiore %.0f ms (= %.1f ms per ora di gioco) · %s" % [
		hourly[0], hourly[1], hourly[0] / session.world.ticks_per_day, _top_systems(session)])
	SettlementSim.set_observed(session, {})
	var t0 := Time.get_ticks_usec()
	SettlementPlanner.lord_month(session, s.id, people * 2)
	_say("- Un mese del signore (planner): %.0f ms" % _ms(t0))
	t0 = Time.get_ticks_usec()
	var home := PopulationSystem._free_home(session.world, s)
	_say("- Cercare un letto libero: %.1f ms (%s)" % [_ms(t0), "trovato" if home else "tutti occupati"])
	_reset_profile(session)
	var agg_year := _days(session, 330)
	_say("- Un anno dopo: %d abitanti, %d edifici · giorno medio %.1f ms, peggiore %.1f ms · %s" % [
		session.world.people_of(s.id).size(), session.world.buildings_of(s.id).size(), agg_year[0], agg_year[1],
		_top_systems(session)])
	_save_load(session, "city_%d" % people)
	_coherent(session, "city_%d" % people)
	_say("- Memoria statica: %.0f MB → %.0f MB · oggetti %d" % [mem0, _mb(), Performance.get_monitor(Performance.OBJECT_COUNT)])
	session.dispose()
	_say("")


func _sites(count: int) -> void:
	_say("## %d cantieri aperti insieme (città di 600 abitanti)" % count)
	var session := GameSession.create_new({"campaign_seed": 1902})
	var s := session.world.settlements[0]
	StressWorlds.grow_city(session, 600)
	var before := session.world.buildings_of(s.id).size()
	var t0 := Time.get_ticks_usec()
	var opened := StressWorlds.open_sites(session, count)
	_say("- Aperti %d cantieri in %.0f ms" % [opened, _ms(t0)])
	_reset_profile(session)
	var agg := _days(session, 20)
	var done := 0
	for b in session.world.buildings_of(s.id):
		if b.def_id == &"house" and b.is_active():
			done += 1
	_say("- 20 giorni per aggregato: media %.1f ms, peggiore %.1f ms · %s" % [agg[0], agg[1], _top_systems(session)])
	SettlementSim.set_observed(session, {s.id: true})
	_reset_profile(session)
	var hourly := _days(session, 2)
	_say("- 2 giorni ora per ora: media %.0f ms, peggiore %.0f ms · %s" % [hourly[0], hourly[1], _top_systems(session)])
	var active := 0
	var sites := 0
	for b in session.world.buildings_of(s.id):
		if b.is_active():
			active += 1
		elif not b.is_road():
			sites += 1
	_say("- Dopo 22 giorni: %d edifici finiti (erano %d), %d cantieri ancora aperti" % [active, before, sites])
	_check(active > before, "sites: some of the %d sites are finished after 22 days" % opened)
	_coherent(session, "sites")
	session.dispose()
	_say("")


func _war(per_realm: int) -> void:
	_say("## Molti eserciti, molte guerre (%d reggimenti per regno)" % per_realm)
	var session := GameSession.create_new({"campaign_seed": 1903})
	var world := session.world
	SettlementPlanner.place_starter_village(session, world.settlements[0].id)
	var made := StressWorlds.raise_wars(session, per_realm)
	var owners_changed := [0]
	var battles := {}
	var on_owner := func(_p: int, _o: int, _n: int, _r: StringName) -> void: owners_changed[0] += 1
	var on_battle := func(id: int) -> void: battles[id] = true
	EventBus.province_owner_changed.connect(on_owner)
	EventBus.battle_changed.connect(on_battle)
	_say("- %d eserciti in campo, %d guerre dichiarate (rifiutate: %s)" % [made["armies"], made["wars"], str(made["refused"])])
	# the routes the hosts ask for, between random provinces of the continent
	var land: Array[int] = []
	for p in world.provinces:
		if WorldData.get_instance().province_geo(p.id) != null:
			land.append(p.id)
	var worst := 0.0
	var total := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1903
	for i in 200:
		var t0 := Time.get_ticks_usec()
		Military.route(world, land[rng.randi_range(0, land.size() - 1)], land[rng.randi_range(0, land.size() - 1)])
		var ms := _ms(t0)
		total += ms
		worst = maxf(worst, ms)
	_say("- Percorso di un esercito (Dijkstra su %d province): media %.2f ms, peggiore %.2f ms" % [land.size(), total / 200.0, worst])
	_reset_profile(session)
	var year := _days(session, 360)
	EventBus.province_owner_changed.disconnect(on_owner)
	EventBus.battle_changed.disconnect(on_battle)
	var alive := 0
	for k in world.kingdoms:
		if k.alive:
			alive += 1
	var at_war := 0
	for r: RelationState in world.relations.values():
		if r.at_war:
			at_war += 1
	_say("- Un anno di guerra: giorno medio %.1f ms, peggiore %.1f ms · %s" % [year[0], year[1], _top_systems(session)])
	_say("- Dopo un anno: %d eserciti, %d battaglie combattute, %d province passate di mano, %d guerre ancora aperte, %d regni vivi" % [
		world.armies.size(), battles.size(), owners_changed[0], at_war, alive])
	_save_load(session, "war")
	_coherent(session, "war")
	session.dispose()
	_say("")


func _pacts() -> void:
	_say("## Diplomazia fitta")
	var session := GameSession.create_new({"campaign_seed": 1904})
	var world := session.world
	# the realms of the AI are crowned from the start; the player's community is not, and signs nothing
	var signed := StressWorlds.weave_pacts(session)
	var parts: PackedStringArray = []
	for key: StringName in signed.keys():
		parts.append("%s %d" % [key, signed[key]])
	_say("- Patti firmati: %s" % ", ".join(parts))
	_coherent(session, "pacts (signed)")
	_reset_profile(session)
	var years := _days(session, 720)
	var still := {}
	var at_war := 0
	for r: RelationState in world.relations.values():
		for pact_id: StringName in r.pacts.keys():
			still[pact_id] = int(still.get(pact_id, 0)) + 1
		if r.at_war:
			at_war += 1
	parts.clear()
	for key: StringName in still.keys():
		parts.append("%s %d" % [key, still[key]])
	_say("- Due anni dopo: giorno medio %.1f ms, peggiore %.1f ms · %s" % [years[0], years[1], _top_systems(session)])
	_say("- Patti ancora in vigore: %s · guerre aperte %d" % [", ".join(parts), at_war])
	_save_load(session, "pacts")
	_coherent(session, "pacts")
	session.dispose()
	_say("")


## A whole campaign played by CampaignPilot (the careful ruler of Phase 16), decade by decade: what a long game
## costs, what grows in the world and in memory, and whether the save of the end still comes back.
func _long(years: int) -> void:
	_say("## Campagna lunga: %d anni con il pilota automatico" % years)
	var session := GameSession.create_new({"campaign_seed": 1905})
	var world := session.world
	var mem0 := _mb()
	for decade in maxi(years / 10, 1):
		var t0 := Time.get_ticks_usec()
		for m in 120:
			session.advance_days(30)
			CampaignPilot.month(session)
		var home: SettlementState = null
		for s in world.settlements:
			if s.kingdom == world.player_kingdom:
				home = s
				break
		var alive := 0
		for k in world.kingdoms:
			if k.alive:
				alive += 1
		_say("- Anno %d: decennio in %.1f s · villaggio %d abitanti, %d edifici · %d personaggi, %d famiglie, %d righe di cronaca, %d eserciti, %d regni vivi · memoria %.0f MB, oggetti %d" % [
			(decade + 1) * 10, _ms(t0) / 1000.0, world.people_of(home.id).size() if home else 0,
			world.buildings_of(home.id).size() if home else 0, world.characters.size(), world.families.size(),
			world.chronicle.size(), world.armies.size(), alive, _mb(), Performance.get_monitor(Performance.OBJECT_COUNT)])
		if world.player() == null or not world.player().alive:
			break
	_say("- Memoria statica: %.0f MB all'inizio, %.0f MB alla fine" % [mem0, _mb()])
	_save_load(session, "long")
	_coherent(session, "long")
	session.dispose()
	_say("")

