extends Node
## Whole campaigns, played to the end by CampaignPilot (Phase 16). Run with:
##   godot --headless --path <ROOT> res://tests/campaign/campaign_runner.tscn -- --kd-years=100 --kd-seeds=1,2,3 --kd-label=base
## Writes tests/output/campaign/<label>_<seed>.csv (one row a year) and <label>_report.md: the growth curve from
## six people to a realm, and the checks of the brief — growth stuck or exploding, a measure pinned at the top,
## goods nobody needs, one crown eating the world, all crowns collapsing, crowns that never move.

const RESOURCES := [&"wood", &"stone", &"grain", &"bread", &"iron", &"weapons"]
const MILESTONES := [20, 50, 100, 500, 1000, 5000, 10000, 20000]

var _report: PackedStringArray = []
## What happened to the player's people during the current year, from the notifications.
var _year_counts: Dictionary = {}
## seed -> events lived, to compare the stories of the campaigns at the end
var _stories: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	var args := BootArgs.parse()
	var years := String(args.get("years", "100")).to_int()
	var label := String(args.get("label", "campaign"))
	var seeds: Array[int] = []
	for part in String(args.get("seeds", "1")).split(","):
		seeds.append(part.to_int())
	var out_dir := ProjectSettings.globalize_path("res://tests/output/campaign")
	DirAccess.make_dir_recursive_absolute(out_dir)
	# the CSV files live under res://: without this Godot imports them as translations
	var ignore := FileAccess.open(out_dir.path_join(".gdignore"), FileAccess.WRITE)
	if ignore:
		ignore.close()
	_report.append("# Campagne «%s» — %d anni, semi %s" % [label, years, str(seeds)])
	_report.append("")
	_report.append("Generato da `tests/campaign/campaign_runner.gd` il %s." % Time.get_datetime_string_from_system())
	for seed_value in seeds:
		var t0 := Time.get_ticks_msec()
		var rows := _play(seed_value, years)
		_write_csv(out_dir.path_join("%s_%d.csv" % [label, seed_value]), rows)
		_judge(seed_value, rows, Time.get_ticks_msec() - t0)
		print("[KD:campaign] seed %d: %d anni in %d ms" % [seed_value, years, Time.get_ticks_msec() - t0])
	if _stories.size() >= 2:
		var keys: Array = _stories.keys()
		var shared := 0
		var total := 0
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				var a: PackedStringArray = _stories[keys[i]]
				var b: PackedStringArray = _stories[keys[j]]
				var both := 0
				for x in a:
					if b.has(x):
						both += 1
				shared += both
				total += maxi(a.size() + b.size() - both, 1)
		_report.append("")
		_report.append("## Le storie a confronto")
		_report.append("- Eventi in comune fra due campagne: in media il %d%% di quelli vissuti." % roundi(100.0 * float(shared) / float(maxi(total, 1))))
	var f := FileAccess.open(out_dir.path_join("%s_report.md" % label), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_report) + "\n")
		f.close()
	print("\n".join(_report))
	get_tree().quit(0)


func _play(seed_value: int, years: int) -> Array[Dictionary]:
	var session := GameSession.create_new({"campaign_seed": seed_value})
	var counter := func(_title: String, text: String, kind: StringName, _p: Vector2) -> void:
		var key := String(kind)
		if kind == &"emigration":
			key = "left:" + text.get_slice(":", text.get_slice_count(":") - 1).strip_edges().left(28)
			_year_counts["left"] = int(_year_counts.get("left", 0)) + maxi(text.get_slice(":", 0).count(",") + 1, 1)
		if kind == &"death":
			var cause := text.get_slice(" a ", 0)
			for word in ["è morto ", "è morta "]:
				if cause.contains(word):
					cause = cause.get_slice(word, 1)
			_year_counts["died:" + cause.left(24)] = int(_year_counts.get("died:" + cause.left(24), 0)) + 1
		_year_counts[key] = int(_year_counts.get(key, 0)) + 1
	EventBus.notification.connect(counter)
	var rows: Array[Dictionary] = []
	_year_counts = {}
	rows.append(_row(session, 0))
	for y in years:
		for m in 12:
			session.advance_days(30)
			var choice := CampaignPilot.month(session)
			if not choice.is_empty():
				var key := "ai:" + String(choice.get("kind", "?"))
				_year_counts[key] = int(_year_counts.get(key, 0)) + 1
		rows.append(_row(session, y + 1))
		if not session.world.player().alive:
			break
	EventBus.notification.disconnect(counter)
	session.dispose()   # the next campaign must not write in this one's chronicle
	return rows


func _row(session: GameSession, year: int) -> Dictionary:
	var world := session.world
	var k := world.player()
	var home: SettlementState = null
	var village_people := 0
	var buildings := 0
	for s in world.settlements:
		if s.kingdom == k.id:
			if home == null:
				home = s
			village_people += world.people_of(s.id).size()
			buildings += world.buildings_of(s.id).size()
	var realm_pop := 0
	for pid in k.provinces:
		realm_pop += world.province(pid).population
	var world_pop := 0
	var owned := 0
	var free := 0
	for p in world.provinces:
		world_pop += p.population
		if p.is_free():
			free += 1
		else:
			owned += 1
	var alive := 0
	var biggest := 0
	var biggest_name := ""
	var wars := 0
	for other in world.kingdoms:
		if other.alive and not other.provinces.is_empty():
			alive += 1
			if other.provinces.size() > biggest:
				biggest = other.provinces.size()
				biggest_name = other.name
		wars += int(other.records.get(&"wars_declared", 0.0))
	var ai_count := 0
	var ai_treasury := 0.0
	var ai_totals := {}
	for other in world.kingdoms:
		if other.is_player or not other.alive or other.provinces.is_empty():
			continue
		ai_count += 1
		ai_treasury += other.treasury
		for key: StringName in [&"provinces_claimed", &"provinces_developed", &"levies_raised", &"laws_enacted", &"pacts_signed"]:
			ai_totals[key] = int(ai_totals.get(key, 0)) + int(other.records.get(key, 0.0))
	var at_war := 0
	for r: RelationState in world.relations.values():
		if r.at_war:
			at_war += 1
	var men := 0
	for a in world.armies:
		if a.kingdom == k.id:
			men += a.men()
	var fmin := 100.0
	var fmax := 0.0
	for key: StringName in k.favour.keys():
		if String(key).begins_with("_"):
			continue   # the remembered bias of past laws, not a power
		fmin = minf(fmin, float(k.favour[key]))
		fmax = maxf(fmax, float(k.favour[key]))
	var row := {
		"year": year, "crowned": 1 if k.monarchy_founded else 0, "village": village_people, "realm_pop": realm_pop,
		"provinces": k.provinces.size(), "treasury": roundi(k.treasury), "buildings": buildings,
		"food_days": roundi(PopulationSystem.food_days(world, home)) if home else 0,
		"trust": roundi(home.trust) if home else 0, "authority": roundi(k.authority),
		"legitimacy": roundi(k.legitimacy) if k.monarchy_founded else -1,
		"stability": roundi(k.stability) if k.monarchy_founded else -1,
		"prestige": roundi(k.prestige) if k.monarchy_founded else -1,
		"favour_min": roundi(fmin) if k.monarchy_founded else -1, "favour_max": roundi(fmax) if k.monarchy_founded else -1,
		"families": FamilySystem.living_families(world, home).size() if home else 0,
		"techs": k.technologies.size(), "laws_changed": roundi(float(k.records.get(&"laws_changed", 0.0))),
		"men": men, "enemies": Diplomacy.enemies_of(world, k.id).size(),
		"world_alive": alive, "world_biggest": biggest, "world_biggest_name": biggest_name, "world_owned": owned,
		"world_free": free, "world_pop": world_pop, "world_wars_declared": wars, "world_at_war": at_war,
		"ai_treasury": roundi(ai_treasury / maxf(float(ai_count), 1.0)), "ai_claimed": int(ai_totals.get(&"provinces_claimed", 0)),
		"ai_developed": int(ai_totals.get(&"provinces_developed", 0)), "ai_levies": int(ai_totals.get(&"levies_raised", 0)),
		"ai_laws": int(ai_totals.get(&"laws_enacted", 0)), "ai_pacts": int(ai_totals.get(&"pacts_signed", 0)),
	}
	for res: StringName in RESOURCES:
		row[String(res)] = home.amount(res) if home else 0
	row["cap_material"] = home.capacity(world, &"material") if home else 0
	row["cap_food"] = home.capacity(world, &"food") if home else 0
	row["born"] = int(_year_counts.get("birth", 0))
	row["died"] = int(_year_counts.get("death", 0))
	row["left"] = int(_year_counts.get("left", 0))
	var why := PackedStringArray()
	for key: String in _year_counts.keys():
		if key.begins_with("left:"):
			why.append("%s x%d" % [key.substr(5), int(_year_counts[key])])
	row["left_why"] = "|".join(why).replace(",", ";")
	var crown := PackedStringArray()
	for key: String in _year_counts.keys():
		if key.begins_with("ai:"):
			crown.append("%s=%d" % [key.substr(3), int(_year_counts[key])])
	row["crown_did"] = " ".join(crown)
	var causes := PackedStringArray()
	for key: String in _year_counts.keys():
		if key.begins_with("died:"):
			causes.append("%s x%d" % [key.substr(5), int(_year_counts[key])])
	row["died_why"] = "|".join(causes).replace(",", ";")
	row["free_beds"] = PopulationSystem.free_beds(world, home) if home else 0
	row["sites"] = world.buildings_of(home.id).filter(func(b: BuildingState) -> bool: return not b.is_active()).size() if home else 0
	var jobs := {}
	if home:
		for p in world.people_of(home.id):
			jobs[p.job] = int(jobs.get(p.job, 0)) + 1
	row["jobs"] = " ".join(PackedStringArray(jobs.keys().map(func(j: Variant) -> String: return "%s=%d" % [j, jobs[j]])))
	var kinds := {}
	if home:
		for b in world.buildings_of(home.id):
			if b.is_active() and not b.is_road():
				kinds[b.def_id] = int(kinds.get(b.def_id, 0)) + 1
	row["built"] = " ".join(PackedStringArray(kinds.keys().map(func(d: Variant) -> String: return "%s=%d" % [d, kinds[d]])))
	var outlook := PopulationSystem.harvest_outlook(session, home) if home else {}
	row["carried"] = int(outlook.get("carried", 0))
	row["store_days"] = roundi(float(outlook.get("store_days", 0.0)))
	# Phase 17: the story of the campaign — events lived, spirits carried, who reigned and how
	var events_seen := PackedStringArray()
	for key: StringName in k.records.keys():
		if String(key).begins_with("event_day:"):
			events_seen.append(String(key).substr(10))
	events_seen.sort()
	row["events_seen"] = " ".join(events_seen)
	row["spirits"] = " ".join(PackedStringArray(k.spirits.map(func(x: StringName) -> String: return String(x))))
	row["spirits_past"] = " ".join(PackedStringArray(k.spirits_past.map(func(x: StringName) -> String: return String(x))))
	var ruler := world.ruler_of(k.id)
	row["ruler"] = ("%s[%s]" % [ruler.name, "+".join(PackedStringArray(ruler.traits.map(func(x: StringName) -> String: return String(x))))]) if ruler else ""
	row["trade"] = roundi(float(k.last_balance.get("trade", 0.0)))
	row["imports"] = roundi(float(k.last_balance.get("imports", 0.0)))
	row["rents"] = roundi(float(k.last_balance.get("provinces", 0.0)))
	row["balance"] = roundi(float(k.last_balance.get("total", 0.0)))
	_year_counts = {}
	return row


func _write_csv(path: String, rows: Array[Dictionary]) -> void:
	if rows.is_empty():
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var keys: Array = rows[0].keys()
	f.store_line(",".join(PackedStringArray(keys.map(func(x: Variant) -> String: return String(x)))))
	for row in rows:
		f.store_line(",".join(PackedStringArray(keys.map(func(x: Variant) -> String: return str(row.get(x, ""))))))
	f.close()


## The checks of the brief, in words.
func _judge(seed_value: int, rows: Array[Dictionary], ms: int) -> void:
	var last: Dictionary = rows[rows.size() - 1]
	_report.append("")
	_report.append("## Seme %d — %d anni in %.0f s" % [seed_value, int(last["year"]), ms / 1000.0])
	# the curve
	var reached := PackedStringArray()
	for goal in MILESTONES:
		var when := -1
		for row in rows:
			if int(row["realm_pop"]) >= goal:
				when = int(row["year"])
				break
		reached.append("%d → %s" % [goal, "anno %d" % when if when >= 0 else "mai"])
	var crowned := -1
	for row in rows:
		if int(row["crowned"]) == 1:
			crowned = int(row["year"])
			break
	_report.append("- Corona: %s. Villaggio a fine campagna: %d abitanti, %d edifici, %d famiglie." % [
		"anno %d" % crowned if crowned >= 0 else "MAI", int(last["village"]), int(last["buildings"]), int(last["families"])])
	_report.append("- Curva del regno (abitanti di tutte le sue province): %s. Fine: %d abitanti in %d province." % [
		", ".join(reached), int(last["realm_pop"]), int(last["provinces"])])
	# stuck and exploding
	var best := 0
	var stuck := 0
	var longest_stuck := 0
	var max_growth := 0.0
	for i in range(1, rows.size()):
		var a := int(rows[i - 1]["realm_pop"])
		var b := int(rows[i]["realm_pop"])
		if a > 0:
			max_growth = maxf(max_growth, float(b - a) / float(a))
		if b > best:
			best = b
			stuck = 0
		else:
			stuck += 1
			longest_stuck = maxi(longest_stuck, stuck)
	_report.append("- Crescita annua massima %.0f %%; il più lungo periodo senza superare il massimo: %d anni." % [
		max_growth * 100.0, longest_stuck])
	# measures pinned at the top
	var pinned := PackedStringArray()
	for key in ["legitimacy", "stability", "prestige", "favour_max", "trust", "authority"]:
		var years_top := 0
		for row in rows:
			if key == "authority" and int(row["crowned"]) == 1:
				continue   # the authority of the community is not a measure of the kingdom
			if int(row[key]) >= 98:
				years_top += 1
		if years_top >= 20:
			pinned.append("%s (%d anni ≥ 98)" % [key, years_top])
	_report.append("- Misure inchiodate al massimo: %s." % (", ".join(pinned) if not pinned.is_empty() else "nessuna"))
	# goods
	var goods := PackedStringArray()
	for res: StringName in RESOURCES:
		var cap_key := "cap_food" if res in [&"grain", &"bread"] else "cap_material"
		var full := 0
		var tail := rows.slice(maxi(rows.size() - 20, 0))
		for row in tail:
			if int(row[cap_key]) > 0 and int(row[String(res)]) >= int(0.8 * float(row[cap_key])):
				full += 1
		var peak := 0
		for row in rows:
			peak = maxi(peak, int(row[String(res)]))
		goods.append("%s fine %d / max %d%s" % [res, int(last[String(res)]), peak, " (depositi pieni %d degli ultimi 20 anni)" % full if full >= 10 else ""])
	_report.append("- Scorte: %s." % ", ".join(goods))
	var min_treasury := 1 << 30
	for row in rows:
		min_treasury = mini(min_treasury, int(row["treasury"]))
	_report.append("- Tesoro: minimo %d, fine %d. Tecnologie %d, leggi cambiate %d, uomini in armi %d." % [
		min_treasury, int(last["treasury"]), int(last["techs"]), int(last["laws_changed"]), int(last["men"])])
	# the world
	var first: Dictionary = rows[0]
	_report.append("- Mondo: regni vivi %d → %d; il più grande %s con %d province su %d possedute (%d libere); guerre dichiarate %d; popolazione %d → %d." % [
		int(first["world_alive"]), int(last["world_alive"]), String(last["world_biggest_name"]), int(last["world_biggest"]),
		int(last["world_owned"]), int(last["world_free"]), int(last["world_wars_declared"]), int(first["world_pop"]), int(last["world_pop"])])
	var quiet := 0
	var longest_quiet := 0
	for i in range(1, rows.size()):
		if int(rows[i]["world_wars_declared"]) == int(rows[i - 1]["world_wars_declared"]):
			quiet += 1
			longest_quiet = maxi(longest_quiet, quiet)
		else:
			quiet = 0
	_report.append("- Il più lungo periodo senza una nuova guerra nel mondo: %d anni." % longest_quiet)
	# the story: what happened to this realm and nobody else
	var rulers := PackedStringArray()
	for row in rows:
		var r := String(row.get("ruler", ""))
		if r != "" and (rulers.is_empty() or rulers[rulers.size() - 1] != r):
			rulers.append(r)
	var seen := String(last.get("events_seen", "")).split(" ", false)
	_report.append("- La storia: %d eventi diversi vissuti; spiriti a fine campagna: %s; spiriti perduti: %s." % [
		seen.size(), String(last.get("spirits", "")).replace(" ", ", "), String(last.get("spirits_past", "")).replace(" ", ", ")])
	_report.append("- Sovrani: %s." % ", ".join(rulers))
	_stories[seed_value] = seen

