class_name BattleState
extends RefCounted
## Two hosts that have met and are fighting it out, in a real province, for a few days.

var id: int = -1
var province: int = -1
var pos: Vector2 = Vector2.ZERO
var attacker: int = -1      ## army id of the one who walked in
var defender: int = -1
var day_started: int = 0
var rounds: int = 0
## Men lost so far, by army id.
var losses: Dictionary = {}
## Written when it ends: {"winner": army id, "loser": army id, "day": int}
var outcome: Dictionary = {}


func armies() -> PackedInt32Array:
	return PackedInt32Array([attacker, defender])


func to_dict() -> Dictionary:
	var ls := {}
	for k: int in losses.keys():
		ls[str(k)] = int(losses[k])
	return {"id": id, "province": province, "pos": [pos.x, pos.y], "attacker": attacker, "defender": defender,
		"day_started": day_started, "rounds": rounds, "losses": ls, "outcome": outcome.duplicate()}


static func from_dict(d: Dictionary) -> BattleState:
	var b := BattleState.new()
	b.id = int(d.get("id", -1))
	b.province = int(d.get("province", -1))
	var p: Array = d.get("pos", [0, 0])
	b.pos = Vector2(float(p[0]), float(p[1]))
	b.attacker = int(d.get("attacker", -1))
	b.defender = int(d.get("defender", -1))
	b.day_started = int(d.get("day_started", 0))
	b.rounds = int(d.get("rounds", 0))
	for k: String in (d.get("losses", {}) as Dictionary).keys():
		b.losses[int(k)] = int(d["losses"][k])
	b.outcome = (d.get("outcome", {}) as Dictionary).duplicate()
	return b

