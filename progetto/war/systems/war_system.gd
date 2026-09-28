class_name WarSystem
extends SimSystem
## Every day of a war: hosts that meet fight, the beaten one breaks and runs, a host alone in enemy land sits
## down in front of the province until it falls, the land where armies pass is ruined, and what is held in
## somebody else's name yields little and grumbles. Rules in data/defs/balance/war.json.


func _init() -> void:
	id = &"war"
	frequency = Frequency.DAY
	order = 29


const LAND_SPREAD := 7   ## devastation and unrest are counted once a week, a week at a time


static func bal() -> Dictionary:
	return War.bal()


func run(session: GameSession, step: SimStep) -> void:
	var world := session.world
	_bury_fallen_realms(session)
	_meet(session)
	for b in world.battles.duplicate():
		_fight(session, b, step.day)
	_sieges(session, step.day)
	if step.day % LAND_SPREAD == 0:
		_land(session, step.day)


## A realm that has lost its last province is no more: its hosts scatter — the men go back to the fields of the
## province where they stand — and its wars end, so what it held by arms goes back to its owners (Phase 19:
## the armies of a fallen crown kept marching, besieging and fighting for it, and its wars stayed open).
static func _bury_fallen_realms(session: GameSession) -> void:
	var world := session.world
	for k in world.kingdoms:
		if k.alive or k.is_player:
			continue
		var scattered := 0
		for a in world.armies.duplicate():
			if a.kingdom != k.id:
				continue
			var p := world.province(a.province)
			if p:
				p.population += a.men()
			world.armies.erase(a)
			EventBus.army_changed.emit(a.id)
			scattered += 1
		for other in Diplomacy.enemies_of(world, k.id):
			Diplomacy.end_war(world, k.id, other)
		if scattered > 0:
			EventBus.chronicle_written.emit({"day": world.day, "kingdom": k.id, "kind": "war",
				"text": "Le ultime schiere di %s si sciolgono: quel regno non esiste più." % k.name})


# --- meeting ------------------------------------------------------------------------------------------------

## Two hosts of realms at war, close enough to see each other's banners, stop and fight.
func _meet(session: GameSession) -> void:
	var world := session.world
	var radius := float((bal().get("battle", {}) as Dictionary).get("contact_radius_m", 2600.0))
	for i in world.armies.size():
		var a := world.armies[i]
		if _battle_of(world, a.id) != null or a.is_empty():
			continue
		for j in range(i + 1, world.armies.size()):
			var b := world.armies[j]
			if b.is_empty() or a.kingdom == b.kingdom or _battle_of(world, b.id) != null:
				continue
			if not Diplomacy.at_war(world, a.kingdom, b.kingdom):
				continue
			if a.pos.distance_to(b.pos) > radius:
				continue
			_start_battle(session, a, b)
			break


static func _battle_of(world: WorldState, army_id: int) -> BattleState:
	for b in world.battles:
		if b.attacker == army_id or b.defender == army_id:
			return b
	return null


static func _start_battle(session: GameSession, attacker: ArmyState, defender: ArmyState) -> void:
	var world := session.world
	# whoever is standing in his own land is the defender; otherwise whoever arrived last attacks
	var p := world.province(defender.province)
	if p and p.owner == attacker.kingdom and p.owner != defender.kingdom:
		var swap := attacker
		attacker = defender
		defender = swap
	var battle := BattleState.new()
	battle.id = world.new_id()
	battle.province = defender.province
	battle.pos = (attacker.pos + defender.pos) * 0.5
	battle.attacker = attacker.id
	battle.defender = defender.id
	battle.day_started = world.day
	battle.losses = {attacker.id: 0, defender.id: 0}
	world.battles.append(battle)
	attacker.path = PackedInt32Array()
	defender.path = PackedInt32Array()
	var g := WorldData.get_instance().province_geo(battle.province)
	var ka := world.kingdom(attacker.kingdom)
	var kd := world.kingdom(defender.kingdom)
	EventBus.chronicle_written.emit({"day": world.day, "kingdom": attacker.kingdom, "other": defender.kingdom, "kind": "battle",
		"text": "%s e %s si scontrano in %s." % [attacker.name, defender.name, g.name if g else "campo aperto"]})
	if (ka and ka.is_player) or (kd and kd.is_player):
		EventBus.notify("Battaglia", "%s contro %s in %s." % [attacker.name, defender.name,
			g.name if g else "campo aperto"], &"war", battle.pos)
	EventBus.battle_changed.emit(battle.id)


# --- fighting -----------------------------------------------------------------------------------------------

func _fight(session: GameSession, battle: BattleState, day: int) -> void:
	var world := session.world
	var cfg: Dictionary = bal().get("battle", {})
	var attacker := world.army(battle.attacker)
	var defender := world.army(battle.defender)
	if attacker == null or defender == null or attacker.is_empty() or defender.is_empty():
		_end_battle(session, battle, defender if attacker == null or attacker.is_empty() else attacker,
			attacker if attacker == null or attacker.is_empty() else defender, day)
		return
	var ground := War.terrain_defense(battle.province)
	for round_index in int(cfg.get("rounds_per_day", 3)):
		var first := battle.rounds == 0
		var attack_damage := War.side_damage(world, attacker, defender, first) / ground
		var defend_damage := War.side_damage(world, defender, attacker, first)
		battle.rounds += 1
		var lost_defender := War.apply_losses(world, defender, attack_damage)
		var lost_attacker := War.apply_losses(world, attacker, defend_damage)
		battle.losses[battle.defender] = int(battle.losses.get(battle.defender, 0)) + lost_defender
		battle.losses[battle.attacker] = int(battle.losses.get(battle.attacker, 0)) + lost_attacker
		if attacker.is_empty() or defender.is_empty():
			break
		var rout := float(cfg.get("rout_below_morale", 22.0))
		if attacker.morale() < rout or defender.morale() < rout:
			break
	var rout_level := float(cfg.get("rout_below_morale", 22.0))
	if defender.is_empty() or (defender.morale() < rout_level and not attacker.is_empty()):
		_end_battle(session, battle, attacker, defender, day)
	elif attacker.is_empty() or attacker.morale() < rout_level:
		_end_battle(session, battle, defender, attacker, day)
	elif day - battle.day_started >= int(cfg.get("max_days", 6)):
		# neither broke: both draw off, bloodied
		_end_battle(session, battle, null, null, day)
	var p := world.province(battle.province)
	if p:
		p.devastation = minf(p.devastation + float((bal().get("occupation", {}) as Dictionary).get("devastation_battle", 0.05)), 1.0)
	EventBus.battle_changed.emit(battle.id)


static func _end_battle(session: GameSession, battle: BattleState, winner: ArmyState, loser: ArmyState, day: int) -> void:
	var world := session.world
	var cfg: Dictionary = bal().get("battle", {})
	battle.outcome = {"winner": winner.id if winner else -1, "loser": loser.id if loser else -1, "day": day}
	world.battles.erase(battle)
	var g := WorldData.get_instance().province_geo(battle.province)
	if winner and loser:
		# the beaten host loses more men as it breaks, then runs for the nearest friendly land
		var extra := float(loser.men()) * float(cfg.get("rout_extra_losses", 0.18))
		War.apply_losses(world, loser, extra)
		for r in winner.regiments:
			r["morale"] = minf(float(r["morale"]) + float(cfg.get("winner_morale", 6.0)), 100.0)
		_retreat(session, loser)
		var kw := world.kingdom(winner.kingdom)
		var kl := world.kingdom(loser.kingdom)
		if kw:
			CourtSystem.add_prestige(kw, float(cfg.get("winner_prestige", 10.0)))
			KingdomModifiers.record(world, kw.id, &"battles_won", 1.0)
		if kl:
			CourtSystem.add_prestige(kl, float(cfg.get("loser_prestige", -8.0)))
		var score: Dictionary = bal().get("war_score", {})
		War.add_score(world, winner.kingdom, loser.kingdom, float(score.get("per_battle_won", 18.0))
			+ float(battle.losses.get(loser.id, 0)) * float(score.get("per_enemy_men_lost", 0.5)))
		EventBus.chronicle_written.emit({"day": day, "kingdom": winner.kingdom, "other": loser.kingdom, "kind": "battle_won",
			"text": "%s batte %s in %s: %d caduti contro %d." % [winner.name, loser.name, g.name if g else "campo aperto",
				int(battle.losses.get(loser.id, 0)), int(battle.losses.get(winner.id, 0))]})
		if (kw and kw.is_player) or (kl and kl.is_player):
			EventBus.notify("Battaglia decisa", "%s vince in %s." % [winner.name, g.name if g else "campo aperto"],
				&"war", battle.pos)
	else:
		# the two sides of the line, from the hosts that are still in the field
		var side_a := world.army(battle.attacker)
		var side_d := world.army(battle.defender)
		EventBus.chronicle_written.emit({"day": day, "kingdom": side_a.kingdom if side_a else -1,
			"other": side_d.kingdom if side_d else -1, "kind": "battle_drawn",
			"text": "Lo scontro in %s finisce senza vincitori." % [g.name if g else "campo aperto"]})
	EventBus.battle_changed.emit(battle.id)


## The beaten host runs for the nearest land of its own crown.
static func _retreat(session: GameSession, army: ArmyState) -> void:
	var world := session.world
	if army.is_empty():
		return
	var home := -1
	var best := INF
	var wd := WorldData.get_instance()
	for p in world.provinces:
		if p.owner != army.kingdom:
			continue
		var g := wd.province_geo(p.id)
		if g == null:
			continue
		var d := g.center.distance_to(army.pos)
		if d < best:
			best = d
			home = p.id
	if home >= 0 and home != army.province:
		army.path = Military.route(world, army.province, home)
	for r in army.regiments:
		r["morale"] = maxf(float(r["morale"]) - 10.0, 0.0)


# --- sieges -------------------------------------------------------------------------------------------------

func _sieges(session: GameSession, day: int) -> void:
	var world := session.world
	var cfg: Dictionary = bal().get("siege", {})
	# a host alone in enemy land sits down in front of the province
	for a in world.armies:
		if a.is_empty() or not a.path.is_empty() or _battle_of(world, a.id) != null:
			continue
		var p := world.province(a.province)
		if p == null or p.owner < 0 or p.owner == a.kingdom or p.controller == a.kingdom:
			continue
		if not Diplomacy.at_war(world, p.owner, a.kingdom):
			continue
		if _siege_of(world, a.province) == null:
			var siege := SiegeState.new()
			siege.id = world.new_id()
			siege.province = a.province
			siege.besieger = a.kingdom
			siege.army = a.id
			siege.day_started = day
			world.sieges.append(siege)
			var g := WorldData.get_instance().province_geo(a.province)
			var owner := world.kingdom(p.owner)
			var taker := world.kingdom(a.kingdom)
			EventBus.chronicle_written.emit({"day": day, "kingdom": a.kingdom, "other": p.owner, "kind": "siege",
				"text": "%s pone l'assedio a %s." % [a.name, g.name if g else "una provincia"]})
			if (owner and owner.is_player) or (taker and taker.is_player):
				EventBus.notify("Assedio", "%s assedia %s." % [a.name, g.name if g else "una provincia"], &"war", a.pos)
	for siege in world.sieges.duplicate():
		var army := world.army(siege.army)
		var p := world.province(siege.province)
		if army == null or army.is_empty() or p == null or army.province != siege.province \
				or not Diplomacy.at_war(world, p.owner, siege.besieger) or p.controller == siege.besieger:
			world.sieges.erase(siege)
			continue
		var needed := float(cfg.get("days_base", 30.0)) + float(cfg.get("days_per_development", 6.0)) * p.development
		needed += float(cfg.get("days_per_wall_level", 25.0)) * _walls(world, siege.province)
		siege.progress += float(cfg.get("progress_per_attacker", 0.9)) * clampf(float(army.men()) / 12.0, 0.4, 2.5) / maxf(needed, 1.0)
		# what the siege does to the people inside is counted with the rest of their consent (PopulationSystem)
		if siege.progress >= 1.0:
			War.occupy(session, siege.province, siege.besieger)
			War.add_score(world, siege.besieger, p.owner, float((bal().get("war_score", {}) as Dictionary).get("per_province_occupied", 22.0)))
			KingdomModifiers.record(world, siege.besieger, &"provinces_occupied", 1.0)
			world.sieges.erase(siege)


static func _siege_of(world: WorldState, province_id: int) -> SiegeState:
	for s in world.sieges:
		if s.province == province_id:
			return s
	return null


## How well a province is walled: for now the settlements of the realm, later real walls (Fase 12).
static func _walls(world: WorldState, province_id: int) -> float:
	var level := 0.0
	for s in world.settlements:
		if s.province != province_id:
			continue
		for b in world.buildings_of(s.id):
			if b.is_active() and b.def().id == &"keep":
				level += 0.6
			elif b.is_active() and b.def().id == &"barracks":
				level += 0.3
	return level


# --- what war does to the land -------------------------------------------------------------------------------

func _land(session: GameSession, day: int) -> void:
	var world := session.world
	var cfg: Dictionary = bal().get("occupation", {})
	var trampled := {}
	for a in world.armies:
		var p := world.province(a.province)
		if p == null or p.owner == a.kingdom or p.owner < 0:
			continue
		if Diplomacy.at_war(world, p.owner, a.kingdom):
			trampled[p.id] = true
	for p in world.provinces:
		if trampled.has(p.id):
			p.devastation = minf(p.devastation + float(cfg.get("devastation_per_day", 0.004)) * LAND_SPREAD, 1.0)
		elif p.devastation > 0.0:
			p.devastation = maxf(p.devastation - float(cfg.get("recover_devastation_per_day", 0.0009)) * LAND_SPREAD, 0.0)
		if p.is_occupied():
			p.unrest = minf(p.unrest + float(cfg.get("unrest_per_day", 0.002)) * LAND_SPREAD, 1.0)

