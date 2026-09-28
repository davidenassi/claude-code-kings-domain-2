class_name War
extends RefCounted
## The rules of the fight: how a round of battle is resolved, what the ground is worth, how a siege advances,
## what a war is worth at the negotiating table and what happens to a province that changes hands.
## Data in data/defs/balance/war.json; the state is in BattleState, SiegeState and RelationState.


static func bal() -> Dictionary:
	return Defs.balance("war")


# --- the ground --------------------------------------------------------------------------------------------

## How much the province helps whoever stands on the defensive there.
static func terrain_defense(province_id: int) -> float:
	var cfg: Dictionary = bal().get("battle", {})
	var g := WorldData.get_instance().province_geo(province_id)
	if g == null:
		return 1.0
	var value := float((cfg.get("terrain_defense", {}) as Dictionary).get(String(g.terrain), 1.0))
	if g.has_river:
		value *= float(cfg.get("river_defense", 1.2))
	return value


## Which regiment beats which: horse rides down bowmen, long iron stops horse.
static func matchup(attacker_unit: UnitDef, defender_unit: UnitDef) -> float:
	var cfg: Dictionary = bal().get("battle", {})
	if attacker_unit == null or defender_unit == null:
		return 1.0
	if attacker_unit.category == &"cavalry" and defender_unit.category == &"ranged":
		return float(cfg.get("cavalry_vs_ranged", 1.5))
	if attacker_unit.id == &"alabardieri" and defender_unit.category == &"cavalry":
		return float(cfg.get("halberd_vs_cavalry", 1.6))
	return 1.0


# --- one round of battle -----------------------------------------------------------------------------------

## Damage a side deals in one round, as a number of enemy men put out of the fight.
static func side_damage(world: WorldState, army: ArmyState, enemy: ArmyState, first_round: bool) -> float:
	var cfg: Dictionary = bal().get("battle", {})
	var total := 0.0
	var commander := world.character(army.commander)
	var lead := 1.0 + (float(commander.skill(&"guerra")) - 5.0) * float(cfg.get("commander_weight", 0.03)) if commander else 1.0
	for r in army.regiments:
		var u := Military.unit(r["unit"])
		if u == null:
			continue
		var men := float(int(r["men"]))
		var power := men * float(cfg.get("base_damage", 0.055))
		power *= 1.0 + float(cfg.get("attack_weight", 0.06)) * (u.attack - 8)
		power *= clampf(0.4 + float(r["morale"]) / 100.0 * float(cfg.get("morale_weight", 0.5)) * 2.0, 0.3, 1.6)
		if first_round and u.category == &"ranged":
			power *= float(cfg.get("ranged_first_strike", 1.3))
		# the best matchup this regiment finds in front of it
		var best := 1.0
		for er in enemy.regiments:
			best = maxf(best, matchup(u, Military.unit(er["unit"])))
		total += power * best
	return total * lead


## Applies the men lost to the regiments of a side, proportionally, and takes the heart out of them.
static func apply_losses(world: WorldState, army: ArmyState, amount: float) -> int:
	var cfg: Dictionary = bal().get("battle", {})
	var men := float(army.men())
	if men <= 0.0 or amount <= 0.0:
		return 0
	var lost_total := 0
	var share := minf(amount, men)
	for r in army.regiments.duplicate():
		var men_here := float(int(r["men"]))
		if men_here <= 0.0:
			continue
		var lost := int(round(share * men_here / men))
		if lost <= 0 and share >= 1.0 and lost_total == 0:
			lost = 1
		lost = mini(lost, int(men_here))
		if lost > 0:
			MilitarySystem._lose_men(world, r, lost)
			lost_total += lost
		r["morale"] = maxf(float(r["morale"]) - float(cfg.get("morale_loss_per_casualty", 2.2)) * float(lost), 0.0)
	var gone: Array[Dictionary] = []
	for r in army.regiments:
		if int(r["men"]) <= 0:
			gone.append(r)
	for r in gone:
		army.regiments.erase(r)
	return lost_total


# --- what the war is worth ---------------------------------------------------------------------------------

## The advantage of `kingdom_id` over the other in this war, 0..100 (negative when it is losing).
static func score_for(world: WorldState, kingdom_id: int, other_id: int) -> float:
	var r := Diplomacy.relation(world, kingdom_id, other_id)
	if r == null:
		return 0.0
	var value := r.war_score if r.a == kingdom_id else -r.war_score
	var cfg: Dictionary = bal().get("war_score", {})
	if r.at_war and r.war_since >= 0:
		var years := float(world.day - r.war_since) / float(PersonState.DAYS_PER_YEAR)
		value += years * float(cfg.get("per_year_of_war", -4.0))
	return clampf(value, -float(cfg.get("max", 100.0)), float(cfg.get("max", 100.0)))


## Writes a deed of this war into the pair's ledger (positive for `kingdom_id`).
static func add_score(world: WorldState, kingdom_id: int, other_id: int, amount: float) -> void:
	var r := Diplomacy.relation(world, kingdom_id, other_id)
	if r == null:
		return
	var cfg: Dictionary = bal().get("war_score", {})
	var signed := amount if r.a == kingdom_id else -amount
	r.war_score = clampf(r.war_score + signed, -float(cfg.get("max", 100.0)), float(cfg.get("max", 100.0)))


## Provinces `kingdom_id` holds today but does not own, taken from `other_id`.
static func occupied_provinces(world: WorldState, kingdom_id: int, other_id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for p in world.provinces:
		if p.owner == other_id and p.controller == kingdom_id:
			out.append(p.id)
	return out


## The province where a settlement of the player's crown stands. The whole game lives there: it can be besieged
## and occupied, but no treaty hands it over (Phase 19: accepting a peace that asked for it gave the village to
## the enemy and left the ruler with nothing to rule, without a word). When the war ends it goes back.
static func is_player_seat(world: WorldState, province_id: int) -> bool:
	for s in world.settlements:
		if s.province == province_id:
			var k := world.kingdom(s.kingdom)
			if k and k.is_player:
				return true
	return false


## What can be asked at the peace table: the provinces held by arms, except the seat of the player's crown.
static func cedable_provinces(world: WorldState, kingdom_id: int, other_id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for pid in occupied_provinces(world, kingdom_id, other_id):
		if not is_player_seat(world, pid):
			out.append(pid)
	return out


# --- taking and giving land --------------------------------------------------------------------------------

## The province falls: it is held, not owned. Its people, its buildings and its fields stay exactly where they are.
static func occupy(session: GameSession, province_id: int, kingdom_id: int) -> void:
	var world := session.world
	var p := world.province(province_id)
	if p == null or p.controller == kingdom_id:
		return
	p.controller = kingdom_id
	p.unrest = minf(p.unrest + 0.08, 1.0)   # foreign soldiers in the square are felt at once
	var g := WorldData.get_instance().province_geo(province_id)
	var owner := world.kingdom(p.owner)
	var taker := world.kingdom(kingdom_id)
	EventBus.province_owner_changed.emit(province_id, p.owner, p.owner, &"occupied")
	EventBus.chronicle_written.emit({"day": world.day, "kingdom": kingdom_id, "other": p.owner, "kind": "occupation",
		"text": "%s occupa %s." % [taker.name if taker else "?", g.name if g else "una provincia"]})
	if (owner and owner.is_player) or (taker and taker.is_player):
		EventBus.notify("Provincia occupata", "%s è in mano a %s." % [g.name if g else "Una provincia",
			taker.name if taker else "?"], &"war", g.center if g else Vector2.ZERO)


## The occupier leaves: the province goes back to its crown, with whatever the war left of it.
static func liberate(world: WorldState, province_id: int) -> void:
	var p := world.province(province_id)
	if p == null or not p.is_occupied():
		return
	p.controller = p.owner
	EventBus.province_owner_changed.emit(province_id, p.owner, p.owner, &"liberated")


## A province changes crown for good, at the peace table. Nothing is reset: people, buildings and unrest stay.
static func cede(session: GameSession, province_id: int, to_kingdom: int) -> void:
	var world := session.world
	var p := world.province(province_id)
	if p == null:
		return
	var old := world.set_province_owner(province_id, to_kingdom)
	p.controller = to_kingdom
	p.unrest = maxf(p.unrest, 0.35)   # a people handed over does not forget in a season
	for s in world.settlements:
		if s.province == province_id:
			s.kingdom = to_kingdom
	EventBus.province_owner_changed.emit(province_id, old, to_kingdom, &"conquest")
	var g := WorldData.get_instance().province_geo(province_id)
	var taker := world.kingdom(to_kingdom)
	EventBus.chronicle_written.emit({"day": world.day, "kingdom": to_kingdom, "other": old, "kind": "conquest",
		"text": "%s passa a %s con la pace." % [g.name if g else "Una provincia", taker.name if taker else "?"]})

