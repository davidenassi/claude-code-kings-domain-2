class_name RelationState
extends RefCounted
## What two realms are to each other: how they see one another (opinion), what they have signed (pacts),
## whether they are at war, and what they remember. Always stored once per pair, with a < b.

var a: int = -1
var b: int = -1
## -100 (they would burn our fields) .. +100 (we would ride for them).
var opinion: float = 0.0
## pact id -> day it expires (0 = until somebody breaks it).
var pacts: Dictionary = {}
## For the asymmetric pacts (tribute, vassalage): who pays and follows.
var payer: int = -1
var at_war: bool = false
var war_since: int = -1
## No war can be declared before this day.
var truce_until: int = -1
## The two houses are tied by a marriage.
var married: bool = false
## Array of {kind: String, day: int} — the value and the fading come from data/defs/diplomacy.json.
var memories: Array[Dictionary] = []
## Who is winning the war between the two, from the point of view of `a` (negative: `b` is winning).
var war_score: float = 0.0


static func make(p_a: int, p_b: int) -> RelationState:
	var r := RelationState.new()
	r.a = mini(p_a, p_b)
	r.b = maxi(p_a, p_b)
	return r


func other(kingdom_id: int) -> int:
	return b if kingdom_id == a else a


func has_pact(pact_id: StringName) -> bool:
	return pacts.has(pact_id)


func remember(kind: StringName, day: int) -> void:
	memories.append({"kind": String(kind), "day": day})


func to_dict() -> Dictionary:
	var pd := {}
	for k: StringName in pacts.keys():
		pd[String(k)] = int(pacts[k])
	return {"a": a, "b": b, "opinion": opinion, "pacts": pd, "payer": payer, "at_war": at_war,
		"war_since": war_since, "truce_until": truce_until, "married": married, "war_score": war_score,
		"memories": memories.duplicate(true)}


static func from_dict(d: Dictionary) -> RelationState:
	var r := RelationState.new()
	r.a = int(d.get("a", -1))
	r.b = int(d.get("b", -1))
	r.opinion = float(d.get("opinion", 0.0))
	for k: String in (d.get("pacts", {}) as Dictionary).keys():
		r.pacts[StringName(k)] = int(d["pacts"][k])
	r.payer = int(d.get("payer", -1))
	r.at_war = bool(d.get("at_war", false))
	r.war_since = int(d.get("war_since", -1))
	r.truce_until = int(d.get("truce_until", -1))
	r.married = bool(d.get("married", false))
	r.war_score = float(d.get("war_score", 0.0))
	for m: Dictionary in d.get("memories", []):
		r.memories.append({"kind": String(m.get("kind", "")), "day": int(m.get("day", 0))})
	return r

