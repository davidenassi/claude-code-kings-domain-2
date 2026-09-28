class_name NationalSpiritDef
extends KDDef
## A national spirit (data/defs/national_spirits.json): modifiers plus the conditions that give it, keep it
## or turn it into something else. Conditions are ranges [min, max] over the "facts" of a realm
## (see NationalSpiritSystem.facts).

@export var initial: bool = false
## Earned by deeds at any time (trade, battles, laws, knowledge...), not given by the land at the founding (Phase 17).
@export var earned: bool = false
## fact -> [min, max]; all of them must hold.
var gain: Dictionary = {}
## fact -> [min, max]; any one of them is enough (used together with `gain` as an alternative route).
var gain_any: Dictionary = {}
var modifiers: Array[Modifier] = []
## [{to: StringName, when: {fact: [min, max]}}] — `to` empty: the spirit fades and is gone (Phase 17).
var evolves: Array[Dictionary] = []


func load_from(d: Dictionary, errors: PackedStringArray) -> void:
	super.load_from(d, errors)
	initial = bool(d.get("initial", false))
	earned = bool(d.get("earned", false))
	gain = d.get("gain", {})
	gain_any = d.get("gain_any", {})
	modifiers = Modifier.list_from_array(d.get("modifiers", []))
	for e in d.get("evolves", []):
		evolves.append({"to": StringName((e as Dictionary).get("to", "")), "when": (e as Dictionary).get("when", {})})
	if modifiers.is_empty():
		errors.append("national spirit %s: no modifiers" % id)


static func matches(conditions: Dictionary, facts: Dictionary) -> bool:
	for fact: String in conditions.keys():
		var range_: Array = conditions[fact]
		var value := float(facts.get(fact, 0.0))
		if value < float(range_[0]) or value > float(range_[1]):
			return false
	return true


## True when the spirit can be born from these facts.
func can_gain(facts: Dictionary) -> bool:
	if not gain.is_empty() and matches(gain, facts):
		return true
	for fact: String in gain_any.keys():
		if matches({fact: gain_any[fact]}, facts):
			return true
	return false

