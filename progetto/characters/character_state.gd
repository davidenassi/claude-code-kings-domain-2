class_name CharacterState
extends RefCounted
## A person who counts politically: a ruler, a consort, an heir. Characters live in the world even when they are not
## walking on the map; the king of the player's realm is also a PersonState in the settlement (field `person`).

var id: int = -1
var name: String = ""
var house: String = ""
var female: bool = false
var birth_day: int = 0
## Day of death, INT_MIN while alive.
var death_day: int = -2147483648
var kingdom: int = -1
var traits: Array[StringName] = []
## governo, guerra, diplomazia, intrigo (1..10)
var skills: Dictionary = {}
var consort: int = -1
var parent: int = -1
var children: PackedInt32Array = PackedInt32Array()
## PersonState id when this character also lives on the map (-1 otherwise).
var person: int = -1


func alive() -> bool:
	return death_day == -2147483648


func age_years(day: int) -> int:
	var end := day if alive() else death_day
	return int(floor(float(end - birth_day) / float(PersonState.DAYS_PER_YEAR)))


func skill(key: StringName) -> int:
	return int(skills.get(key, 4))


## Product of what the traits do to the chance of dying (cached: traits do not change by the day).
var _mortality: float = -1.0


func mortality() -> float:
	if _mortality < 0.0:
		_mortality = 1.0
		for td in trait_defs():
			_mortality *= td.mortality
	return _mortality


func trait_defs() -> Array[TraitDef]:
	var out: Array[TraitDef] = []
	for t in traits:
		var td: TraitDef = Defs.get_def("traits", t)
		if td:
			out.append(td)
	return out


func trait_names() -> PackedStringArray:
	var out := PackedStringArray()
	for td in trait_defs():
		out.append(td.display_name)
	return out


func to_dict() -> Dictionary:
	var sk := {}
	for k: StringName in skills.keys():
		sk[String(k)] = int(skills[k])
	return {"id": id, "name": name, "house": house, "female": female, "birth_day": birth_day, "death_day": death_day,
		"kingdom": kingdom, "traits": traits.map(func(t: StringName) -> String: return String(t)), "skills": sk,
		"consort": consort, "parent": parent, "children": Array(children), "person": person}


static func from_dict(d: Dictionary) -> CharacterState:
	var c := CharacterState.new()
	c.id = int(d.get("id", -1))
	c.name = String(d.get("name", ""))
	c.house = String(d.get("house", ""))
	c.female = bool(d.get("female", false))
	c.birth_day = int(d.get("birth_day", 0))
	c.death_day = int(d.get("death_day", -2147483648))
	c.kingdom = int(d.get("kingdom", -1))
	for t: String in d.get("traits", []):
		c.traits.append(StringName(t))
	for k: String in (d.get("skills", {}) as Dictionary).keys():
		c.skills[StringName(k)] = int(d["skills"][k])
	c.consort = int(d.get("consort", -1))
	c.parent = int(d.get("parent", -1))
	for child: float in d.get("children", []):
		c.children.append(int(child))
	c.person = int(d.get("person", -1))
	return c

