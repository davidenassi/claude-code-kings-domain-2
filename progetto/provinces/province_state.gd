class_name ProvinceState
extends RefCounted
## Dynamic state of one province (the static geography is in ProvinceGeo, same id).
## Population here is the aggregate estimate used for the provinces far from the camera; later phases
## replace it with settlements and individuals where they are materialised.

const NO_OWNER := -1

var id: int = -1
## Kingdom id owning the province, NO_OWNER for free lands (villages without a crown).
var owner: int = NO_OWNER
## Kingdom id actually controlling it (differs from owner during occupation).
var controller: int = NO_OWNER
var population: int = 0
## 0 = wild land, 1 = scattered villages ... 10 = developed heartland.
var development: int = 0
## 0..1, war and raids damage (recovers over time in later phases).
var devastation: float = 0.0
## Culture and religion really living there today (they start from the map and can change slowly).
var culture: StringName = &""
var religion: StringName = &""
## 0..1: resentment of a province ruled by a foreign crown (cuts its rents).
var unrest: float = 0.0
## 0..1: how far the language (and the faith) of the ruling crown has taken root; at 1 the province changes.
var assimilation: float = 0.0
var conversion: float = 0.0


func is_free() -> bool:
	return owner == NO_OWNER


func is_occupied() -> bool:
	return controller != owner


func to_dict() -> Dictionary:
	return {"id": id, "owner": owner, "controller": controller, "population": population,
		"development": development, "devastation": devastation, "culture": String(culture),
		"religion": String(religion), "unrest": unrest, "assimilation": assimilation, "conversion": conversion}


static func from_dict(d: Dictionary) -> ProvinceState:
	var p := ProvinceState.new()
	p.id = int(d.get("id", -1))
	p.owner = int(d.get("owner", NO_OWNER))
	p.controller = int(d.get("controller", p.owner))
	p.population = int(d.get("population", 0))
	p.development = int(d.get("development", 0))
	p.devastation = float(d.get("devastation", 0.0))
	p.culture = StringName(d.get("culture", ""))
	p.religion = StringName(d.get("religion", ""))
	p.unrest = float(d.get("unrest", 0.0))
	p.assimilation = float(d.get("assimilation", 0.0))
	p.conversion = float(d.get("conversion", 0.0))
	return p

