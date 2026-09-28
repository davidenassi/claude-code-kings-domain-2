class_name RealmAiSystem
extends SimSystem
## The crowns that are not the player's. Once a month each one weighs what it could do — improve its lands,
## pass a law, court a neighbour, demand tribute, declare war, ask for peace, marry a son — and does the one
## thing that best fits the person who reigns. Every choice is written down in words (`log_lines`), so a
## kingdom's behaviour can always be read back instead of guessed.

const LOG_KEY := "ai_log"


func _init() -> void:
	id = &"realm_ai"
	frequency = Frequency.MONTH
	order = 34


static func bal() -> Dictionary:
	return Diplomacy.bal().get("ai", {})


func run(session: GameSession, _step: SimStep) -> void:
	var world := session.world
	for k in world.kingdoms:
		if not k.alive or k.is_player or k.provinces.is_empty():
			continue
		take_turn(session, k)


## What this realm decides this month (public so the tests can drive a single turn).
static func take_turn(session: GameSession, k: KingdomState) -> Dictionary:
	var world := session.world
	var mind := DiplomacyAi.personality(world, k.id)
	var best: Dictionary = {}
	for option: Dictionary in _options(session, k, mind):
		if best.is_empty() or float(option["utility"]) > float(best["utility"]):
			best = option
	if best.is_empty() or float(best["utility"]) < 0.3:
		return {}
	_do(session, k, best)
	# a rich crown does more than one thing a month: it improves its lands and takes free ones (Phase 16: the
	# crowns sat on tens of thousands of gold with one decision a month and nothing to spend it on)
	var extra := mini(int(k.treasury / float(bal().get("extra_action_per_gold", 3000.0))), int(bal().get("extra_actions_max", 2)))
	for i in extra:
		var more: Dictionary = {}
		for option: Dictionary in _options(session, k, mind):
			if String(option["kind"]) in ["develop", "claim", "law", "gift"] and (more.is_empty() or float(option["utility"]) > float(more["utility"])):
				more = option
		if more.is_empty():
			break
		_do(session, k, more)
	return best


## What a crown is weighing right now, with the reason for each option. Used by the tests and by the debug
## overlay: it changes nothing in the world.
static func options_for(session: GameSession, k: KingdomState) -> Array:
	return _options(session, k, DiplomacyAi.personality(session.world, k.id))




static func _options(session: GameSession, k: KingdomState, mind: Dictionary) -> Array:
	var world := session.world
	var cfg := bal()
	var out: Array = []
	var reserve := float(cfg.get("min_treasury_reserve", 60.0))

	# --- peace and war -------------------------------------------------------
	var siege_ripe := _ripest_siege(world, k.id)
	for enemy in Diplomacy.enemies_of(world, k.id):
		var tired := MakePeaceCommand.weariness(session, k.id, enemy)
		var ek := world.kingdom(enemy)
		if ek == null:
			continue
		var winning := War.score_for(world, k.id, enemy)
		var held := War.cedable_provinces(world, k.id, enemy)
		# a siege about to fall is not abandoned for a letter: the walls are worth more than the terms
		var peace_weight := float(cfg.get("siege_peace_brake", 0.45)) if siege_ripe > float(cfg.get("siege_ripe", 0.5)) else 1.0
		if winning > 40.0 and not held.is_empty():
			out.append({"kind": "peace", "target": enemy, "cede": Array(held),
				"utility": (0.6 + winning * 0.004) * peace_weight,
				"reason": "Abbiamo vinto abbastanza: si chiude con %s tenendo %d province." % [ek.name, held.size()]})
		elif tired > 10.0:
			out.append({"kind": "peace", "target": enemy, "utility": (0.45 + tired * 0.01) * peace_weight,
				"reason": "La guerra con %s è costata abbastanza (stanchezza %d)." % [ek.name, roundi(tired)]})
		# the hosts gather before they march: a realm that sends one company at a time loses them one at a time
		var biggest := _biggest_host(world, k.id)
		for host in world.armies:
			if host.kingdom != k.id or not host.path.is_empty() or host.is_empty():
				continue
			if biggest and host.id != biggest.id and host.province != biggest.province \
					and host.men() * 2 <= biggest.men():
				out.append({"kind": "march", "target": biggest.province, "army": host.id, "utility": 1.15,
					"reason": "%s va a unirsi a %s prima di marciare." % [host.name, biggest.name]})
				break
			if host.men() < int(Military.bal().get("ai", {}).get("march_min_men", 8)):
				continue   # four spears do not take a province: they wait for the rest of the levy
			var standing := world.province(host.province)
			if standing and standing.owner == enemy and standing.controller != k.id:
				continue   # it is already sitting on their land: let it hold the siege
			var goal := _war_goal(world, k, enemy)
			if goal >= 0 and goal != host.province:
				out.append({"kind": "march", "target": goal, "army": host.id, "utility": 1.05,
					"reason": "%s muove contro %s." % [host.name, ek.name]})
				break
	if Diplomacy.enemies_of(world, k.id).is_empty() and not k.regency:
		# land hunger: a crown with no free land left on its borders can only grow at somebody's expense
		# (Phase 17 check: while every crown was busy taking free lands, the world went forty years without a war)
		var hungry := _best_free_land(world, k) < 0 and k.monarchy_founded
		for candidate in _neighbours(world, k.id):
			var r := Diplomacy.relation(world, k.id, candidate)
			var target_k := world.kingdom(candidate)
			if target_k == null or not target_k.alive or r.truce_until > world.day:
				continue
			var blocked := false
			for pact_id: StringName in r.pacts.keys():
				blocked = blocked or bool(Diplomacy.pact(pact_id).get("blocks_war", false))
			if blocked:
				continue
			var ratio := Diplomacy.power_ratio(world, k.id, candidate)
			if ratio < float(cfg.get("war_power_margin", 1.25)):
				continue
			var utility := float(mind.get("aggression", 0.25)) * 0.8 + float(mind.get("greed", 0.3)) * 0.3
			utility += clampf((ratio - 1.0) * 0.35, 0.0, 0.5) - r.opinion * 0.006
			utility -= float(mind.get("caution", 0.3)) * 0.25
			if hungry:
				utility += float(cfg.get("land_hunger", 0.12))
			if k.treasury < 0.0:
				utility -= 0.2
			if utility >= float(cfg.get("war_min_utility", 0.62)):
				out.append({"kind": "war", "target": candidate, "utility": utility,
					"reason": "%s è più debole (%.1f contro 1) e non ci ama (%d)." % [target_k.name, ratio, roundi(r.opinion)]})

	# --- pacts and marriages -------------------------------------------------
	for candidate in _known(world, k.id):
		var r := Diplomacy.relation(world, k.id, candidate)
		var target_k := world.kingdom(candidate)
		if target_k == null or not target_k.alive or r.at_war:
			continue
		for pact_id: StringName in [&"non_aggression", &"trade", &"alliance", &"tribute", &"vassalage"]:
			if r.has_pact(pact_id):
				continue
			var def := Diplomacy.pact(pact_id)
			if k.treasury < float(def.get("cost", 0)) + reserve:
				continue
			var requires := StringName(def.get("requires", &""))
			if requires != &"" and not r.has_pact(requires):
				continue
			if bool(def.get("asymmetric", false)) and Diplomacy.power_ratio(world, k.id, candidate) < float(def.get("power_ratio", 2.0)):
				continue
			if Diplomacy.pact_blocker(world, k, target_k, pact_id) != "":
				continue
			if _already_offered(world, k.id, pact_id):
				continue
			# an embassy that came back with nothing does not leave again the next month
			var asked := StringName("offer:%d:%s" % [candidate, pact_id])
			if world.day - int(k.records.get(asked, -99999.0)) < int(cfg.get("offer_again_days", 720)):
				continue
			var verdict := DiplomacyAi.judge_pact(session, k.id, candidate, pact_id)
			if not bool(verdict["accept"]) and not target_k.is_player:
				continue
			var want := 0.35 + r.opinion * 0.004
			match pact_id:
				&"non_aggression":
					# nobody ties his own hands with a realm he could take
					if Diplomacy.power_ratio(world, k.id, candidate) > 1.5 and float(mind.get("aggression", 0.25)) > 0.3:
						continue
					want += float(mind.get("caution", 0.3)) * 0.4
				&"trade": want += float(mind.get("trade", 0.3)) * 0.5
				&"alliance": want += float(mind.get("caution", 0.3)) * 0.3 + (0.3 if Diplomacy.enemies_of(world, k.id).size() > 0 else 0.0)
				&"tribute", &"vassalage": want += float(mind.get("greed", 0.3)) * 0.5 + float(mind.get("authority", 0.3)) * 0.3
			if want >= float(cfg.get("pact_min_utility", 0.35)):
				out.append({"kind": "pact", "target": candidate, "pact": String(pact_id), "utility": want,
					"reason": "Con %s conviene %s (opinione %d)." % [target_k.name, String(def.get("name", pact_id)).to_lower(), roundi(r.opinion)]})
		if not r.married and r.opinion >= float(cfg.get("marriage_min_opinion", 20.0)) \
				and CourtSystem.marriageable(world, k.id) >= 0 and CourtSystem.marriageable(world, candidate) >= 0 \
				and k.treasury > float((Diplomacy.data().get("marriage", {}) as Dictionary).get("cost", 60)) + reserve:
			out.append({"kind": "marriage", "target": candidate, "utility": 0.4 + r.opinion * 0.004,
				"reason": "Un matrimonio con %s vale più di un trattato." % target_k.name})

	# --- the host ------------------------------------------------------------
	var mil: Dictionary = Military.bal().get("ai", {})
	var at_war := not Diplomacy.enemies_of(world, k.id).is_empty()
	var my_power := Military.kingdom_strength(world, k.id)
	var threat := 0.0
	for neighbour in _neighbours(world, k.id):
		threat = maxf(threat, Military.kingdom_strength(world, neighbour))
	# what matters is the biggest host, not the sum: ten bands of four are not an army
	var my_men := 0
	for host in world.armies:
		if host.kingdom == k.id and host.path.is_empty():
			my_men = maxi(my_men, host.men())
	# a crown raises men until it has a host, then it uses it: it does not levy for ever
	# a host that grows with the realm, and a rich crown keeps one even in peace (Phase 16: every crown stopped at
	# 24 men whatever its size, and sat on its gold)
	var enough := int(mil.get("enough_men", 24)) + int(float(mil.get("men_per_province", 3.0)) * k.provinces.size())
	var rich := k.treasury > float(mil.get("standing_army_treasury", 4000.0))
	if my_men < enough and k.treasury > float(mil.get("recruit_min_treasury", 260.0)) \
			and (at_war or rich or my_power < threat * float(mil.get("want_army_power", 2.0))):
		var levy := _affordable_unit(k)
		var muster := _muster_province(world, k, levy)
		if levy and muster >= 0:
			out.append({"kind": "levy", "target": muster, "unit": String(levy.id),
				"utility": 0.44 + float(mind.get("aggression", 0.25)) * 0.4 + (0.3 if at_war else 0.0),
				"reason": "Servono uomini in armi: si leva una compagnia di %s." % levy.display_name.to_lower()})
	if not at_war and k.treasury < 0.0:
		for a in world.armies:
			if a.kingdom == k.id:
				out.append({"kind": "disband", "target": a.id, "utility": 0.55,
					"reason": "Il tesoro è vuoto e la guerra è finita: %s torna ai campi." % a.name})
				break

	# --- the realm at home ---------------------------------------------------
	var poorest := -1
	var max_dev := int(cfg.get("develop_province_max", 8))
	for pid in k.provinces:
		var p := world.province(pid)
		if p == null or p.development >= max_dev:
			continue
		if poorest < 0 or p.development < world.province(poorest).development:
			poorest = pid
	if poorest >= 0:
		var price := DevelopProvinceCommand.cost(session, poorest)
		if k.treasury > price + reserve:
			out.append({"kind": "develop", "target": poorest, "utility": 0.42 + float(mind.get("greed", 0.3)) * 0.2
				+ clampf(k.treasury / 2000.0, 0.0, 0.3), "reason": "Le terre rendono poco: si investe in una provincia."})
	# --- free lands beside the realm (Phase 16): the villages without a lord, taken with gold, not steel ---
	if k.monarchy_founded and Diplomacy.enemies_of(world, k.id).is_empty() and ClaimProvinceCommand.days_to_wait(world, k) == 0:
		var land := _best_free_land(world, k)
		if land >= 0:
			var price := ClaimProvinceCommand.cost(world, k.id, land)
			if k.treasury > price + reserve and k.legitimacy >= float(ClaimProvinceCommand.cfg().get("min_legitimacy", 40.0)):
				var utility := 0.45 + float(mind.get("greed", 0.3)) * 0.35 + clampf(k.treasury / 3000.0, 0.0, 0.2)
				if utility >= float(ClaimProvinceCommand.cfg().get("ai_min_utility", 0.4)):
					out.append({"kind": "claim", "target": land, "utility": utility,
						"reason": "Le terre libere di %s chiedono un signore (%d ori)." % [
							WorldData.get_instance().province_geo(land).name, roundi(price)]})
	if k.treasury > float(cfg.get("law_min_treasury", 260.0)) and not k.regency:
		var law := _preferred_law(k, mind)
		if not law.is_empty():
			out.append({"kind": "law", "group": law["group"], "option": law["option"],
				"utility": 0.4 + float(mind.get("authority", 0.3)) * 0.3, "reason": String(law["reason"])})
	if k.stability < 55.0 and k.treasury > float(cfg.get("edict_min_treasury", 140.0)) \
			and IssueEdictCommand.create(k.id, &"coprifuoco").validate(session) == "":
		out.append({"kind": "edict", "edict": "coprifuoco", "utility": 0.5 + (60.0 - k.stability) * 0.006,
			"reason": "Il regno è in disordine (stabilità %d): coprifuoco." % roundi(k.stability)})
	# gold that buys peace at home: a rich crown courts the power that likes it least (Phase 16)
	var gift_price := GiftFactionCommand.cost(k)
	if k.treasury > gift_price * float(GiftFactionCommand.cfg().get("ai_min_treasury_multiple", 5.0)):
		var coldest: FactionDef = null
		for fd: FactionDef in CourtSystem.factions():
			if GiftFactionCommand.days_to_wait(world, k, fd.id) > 0:
				continue
			if coldest == null or float(k.favour.get(fd.id, 55.0)) < float(k.favour.get(coldest.id, 55.0)):
				coldest = fd
		if coldest and float(k.favour.get(coldest.id, 55.0)) < 65.0:
			out.append({"kind": "gift", "faction": String(coldest.id),
				"utility": 0.42 + (65.0 - float(k.favour.get(coldest.id, 55.0))) * 0.012,
				"reason": "%s mormorano: la corona apre le casse (%d ori)." % [coldest.display_name, roundi(gift_price)]})
	if k.heir_designate < 0 and not k.regency:
		var ruler := world.ruler_of(k.id)
		if ruler and ruler.children.size() >= 2 and float(mind.get("authority", 0.3)) > 0.35:
			out.append({"kind": "heir", "utility": 0.38, "reason": "Meglio dire adesso chi erediterà."})
	return out


## The free land beside the realm most worth its price: people and fertile ground for the gold.
static func _best_free_land(world: WorldState, k: KingdomState) -> int:
	var wd := WorldData.get_instance()
	var best := -1
	var best_value := 0.0
	var seen := {}
	for pid in k.provinces:
		var g := wd.province_geo(pid)
		if g == null:
			continue
		for n: Dictionary in g.neighbors:
			var q := world.province(int(n["id"]))
			if q == null or not q.is_free() or seen.has(q.id):
				continue
			seen[q.id] = true
			var price := ClaimProvinceCommand.cost(world, k.id, q.id)
			var value := (float(q.population) + 200.0) * (0.5 + wd.province_geo(q.id).fertility) / maxf(price, 1.0)
			if value > best_value:
				best_value = value
				best = q.id
	return best


## The best regiment the crown can pay for today (the levies of the AI ask no barracks: they are the old
## feudal muster, spears and nothing else).
static func _affordable_unit(k: KingdomState) -> UnitDef:
	var best: UnitDef = null
	for u in Military.units():
		if not (u.requires as Dictionary).is_empty():
			continue
		if k.treasury < u.gold * 2.0:
			continue
		if best == null or u.gold > best.gold:
			best = u
	return best


## Where the men come from: where a host of ours is already standing, so the levy joins it, otherwise the
## most populous province of the realm.
static func _muster_province(world: WorldState, k: KingdomState, u: UnitDef) -> int:
	if u == null:
		return -1
	var standing := -1
	var standing_men := 0
	for host in world.armies:
		if host.kingdom == k.id and host.path.is_empty() and host.men() > standing_men:
			standing = host.province
			standing_men = host.men()
	if standing >= 0:
		var p := world.province(standing)
		if p and p.owner == k.id and p.population >= u.men * 6:
			return standing
	var best := -1
	for pid in k.provinces:
		var p := world.province(pid)
		if p == null or p.population < u.men * 6:
			continue
		if best < 0 or p.population > world.province(best).population:
			best = pid
	return best


## True when an embassy of ours with the same offer is still waiting for an answer.
static func _already_offered(world: WorldState, kingdom_id: int, pact_id: StringName) -> bool:
	for offer: Dictionary in world.offers:
		if int(offer.get("from", -1)) == kingdom_id and String(offer.get("pact", "")) == String(pact_id):
			return true
	return false


## How far along the closest-to-falling of our sieges is (0 when we are besieging nobody).
static func _ripest_siege(world: WorldState, kingdom_id: int) -> float:
	var best := 0.0
	for sg in world.sieges:
		if sg.besieger == kingdom_id:
			best = maxf(best, sg.progress)
	return best


## The strongest host of a realm: the one the others go and join.
static func _biggest_host(world: WorldState, kingdom_id: int) -> ArmyState:
	var best: ArmyState = null
	for a in world.armies:
		if a.kingdom != kingdom_id or a.is_empty():
			continue
		if best == null or a.men() > best.men():
			best = a
	return best



## The enemy province worth marching on: the nearest one still in their hands.
static func _war_goal(world: WorldState, k: KingdomState, enemy: int) -> int:
	var wd := WorldData.get_instance()
	var home := wd.province_geo(k.capital)
	var best := -1
	var best_d := INF
	for p in world.provinces:
		if p.owner != enemy or p.controller == k.id:
			continue
		var g := wd.province_geo(p.id)
		if g == null or home == null:
			continue
		var d := g.center.distance_to(home.center)
		if d < best_d:
			best_d = d
			best = p.id
	return best


static func _preferred_law(k: KingdomState, mind: Dictionary) -> Dictionary:
	var wanted: Array = []
	if float(mind.get("greed", 0.0)) > 0.35:
		wanted.append({"group": "taxation", "option": "catasto", "reason": "Una corona che conta le monete vuole il catasto."})
	if float(mind.get("trade", 0.0)) > 0.35:
		wanted.append({"group": "guilds", "option": "gilde_libere", "reason": "Le gilde libere riempiono le casse dei mercanti e le nostre."})
	if float(mind.get("piety", 0.0)) > 0.4:
		wanted.append({"group": "faith", "option": "tolleranza", "reason": "Una corona devota lascia pregare e fa pagare."})
	if float(mind.get("authority", 0.0)) > 0.45:
		wanted.append({"group": "succession", "option": "seniority", "reason": "Meglio un re anziano che un re bambino."})
	for w: Dictionary in wanted:
		if StringName(k.laws.get(StringName(w["group"]), &"")) != StringName(w["option"]):
			return w
	return {}


static func _do(session: GameSession, k: KingdomState, choice: Dictionary) -> void:
	var world := session.world
	var kind := String(choice["kind"])
	var result: CommandResult = null
	match kind:
		"war":
			result = session.submit(DeclareWarCommand.create(k.id, int(choice["target"]), String(choice["reason"])))
			if result.success:
				KingdomModifiers.record(world, k.id, &"wars_declared", 1.0)
		"peace":
			result = session.submit(MakePeaceCommand.create(k.id, int(choice["target"]),
				PackedInt32Array(choice.get("cede", []))))
		"march":
			result = session.submit(MoveArmyCommand.create(int(choice["army"]), int(choice["target"])))
		"pact":
			world.kingdom(k.id).records[StringName("offer:%d:%s" % [int(choice["target"]), String(choice["pact"])])] = float(world.day)
			result = session.submit(ProposePactCommand.create(k.id, int(choice["target"]), StringName(choice["pact"])))
			if result.success and bool(result.data.get("accepted", false)):
				KingdomModifiers.record(world, k.id, &"pacts_signed", 1.0)
		"marriage":
			result = session.submit(ArrangeMarriageCommand.create(k.id, int(choice["target"])))
		"claim":
			result = session.submit(ClaimProvinceCommand.create(k.id, int(choice["target"])))
		"gift":
			result = session.submit(GiftFactionCommand.create(k.id, StringName(choice["faction"])))
		"develop":
			result = session.submit(DevelopProvinceCommand.create(k.id, int(choice["target"])))
			if result.success:
				KingdomModifiers.record(world, k.id, &"provinces_developed", 1.0)
		"law":
			result = session.submit(EnactLawCommand.create(k.id, StringName(choice["group"]), StringName(choice["option"])))
			if result.success:
				KingdomModifiers.record(world, k.id, &"laws_enacted", 1.0)
		"edict":
			result = session.submit(IssueEdictCommand.create(k.id, StringName(choice["edict"])))
		"levy":
			var u := Military.unit(StringName(choice["unit"]))
			var army := Military.raise_from_province(session, k, int(choice["target"]), u)
			if army:
				KingdomModifiers.record(world, k.id, &"levies_raised", 1.0)
				result = CommandResult.ok()
		"disband":
			var army := world.army(int(choice["target"]))
			if army:
				Military.dissolve_into_province(world, army)
				result = CommandResult.ok()
		"heir":
			var ruler := world.ruler_of(k.id)
			var pick := -1
			for child_id in ruler.children:
				var c := world.character(child_id)
				if c and c.alive() and (pick < 0 or c.skill(&"governo") > world.character(pick).skill(&"governo")):
					pick = c.id
			if pick >= 0:
				result = session.submit(DesignateHeirCommand.create(k.id, pick))
	var outcome := ""
	if result and not result.success:
		outcome = " — non riuscito: %s" % result.reason
	elif result and result.data.has("accepted") and not bool(result.data["accepted"]):
		outcome = " — %s" % String(result.data.get("reason", "rifiutato"))
	log_line(session, "%s: %s%s" % [k.name, String(choice["reason"]), outcome], k.id, kind)


## The readable memory of what the AI did and why (last `log_size` lines).
static func log_line(session: GameSession, text: String, kingdom_id: int, kind: String) -> void:
	var lines: Array = session.runtime.get(LOG_KEY, [])
	lines.append({"day": session.world.day, "kingdom": kingdom_id, "kind": kind, "text": text})
	var maximum := int(bal().get("log_size", 120))
	while lines.size() > maximum:
		lines.remove_at(0)
	session.runtime[LOG_KEY] = lines


static func log_lines(session: GameSession) -> Array:
	return session.runtime.get(LOG_KEY, [])


# --- who a realm can see ----------------------------------------------------------------------------------

static func _neighbours(world: WorldState, kingdom_id: int) -> PackedInt32Array:
	var wd := WorldData.get_instance()
	var k := world.kingdom(kingdom_id)
	var seen := {}
	var out := PackedInt32Array()
	if k == null:
		return out
	for pid in k.provinces:
		var g := wd.province_geo(pid)
		if g == null:
			continue
		for n: Dictionary in g.neighbors:
			var np := world.province(int(n["id"]))
			if np and np.owner >= 0 and np.owner != kingdom_id and not seen.has(np.owner):
				seen[np.owner] = true
				out.append(np.owner)
	return out


## Neighbours plus the realms one already has something with: a crown does not write to the unknown.
static func _known(world: WorldState, kingdom_id: int) -> PackedInt32Array:
	var out := _neighbours(world, kingdom_id)
	var seen := {}
	for id_value in out:
		seen[id_value] = true
	for r: RelationState in world.relations.values():
		if r.a != kingdom_id and r.b != kingdom_id:
			continue
		var other_id := r.other(kingdom_id)
		if not seen.has(other_id) and (not r.pacts.is_empty() or r.married or absf(r.opinion) > 25.0):
			seen[other_id] = true
			out.append(other_id)
	return out

