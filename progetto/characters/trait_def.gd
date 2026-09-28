class_name TraitDef
extends KDDef
## A trait of a ruler (later of councillors and generals): small numbers, real political weight.

var modifiers: Array[Modifier] = []
## faction id -> favour delta while this person rules.
var factions: Dictionary = {}
## Decision weights for the AI (aggression, piety, greed...): read in Phase 8.
var ai: Dictionary = {}
## Multiplier on the chance of dying of age.
@export var mortality: float = 1.0
## Traits nobody can have together with this one (Phase 17: a ruler was both miserly and generous).
var opposite: Array[StringName] = []


func load_from(d: Dictionary, errors: PackedStringArray) -> void:
	super.load_from(d, errors)
	modifiers = Modifier.list_from_array(d.get("modifiers", []))
	for f: String in (d.get("factions", {}) as Dictionary).keys():
		factions[StringName(f)] = float(d["factions"][f])
	ai = d.get("ai", {})
	mortality = float(d.get("mortality", 1.0))
	for o: String in d.get("opposite", []):
		opposite.append(StringName(o))
	if modifiers.is_empty():
		errors.append("trait %s: no modifiers" % id)

