class_name Guide
extends RefCounted
## The first steps of a reign. Every step closes by itself when the state of the world says it is done: no
## pretend objectives, no hand on the player's hand. The step reached lives in `world.flags["guide_step"]`,
## so it is saved with the campaign and a loaded game picks it up where it was.

const PATH := "res://data/defs/guide.json"
const FLAG := "guide_step"
const DONE := 1 << 20   ## the guide is finished or was closed


static var _steps: Array = []


static func steps() -> Array:
	if _steps.is_empty():
		var d: Variant = Defs.read_json(PATH)
		if d is Dictionary:
			_steps = (d as Dictionary).get("steps", [])
	return _steps


static func current_index(world: WorldState) -> int:
	return int(world.flags.get(FLAG, 0))


static func current(world: WorldState) -> Dictionary:
	var i := current_index(world)
	var all := steps()
	return all[i] if i >= 0 and i < all.size() else {}


static func finished(world: WorldState) -> bool:
	return current_index(world) >= steps().size()


## Closes the guide for good (the player asked for it).
static func dismiss(world: WorldState) -> void:
	world.flags[FLAG] = DONE


## Looks at the world and moves on as many steps as are already done. True when something changed.
static func advance(world: WorldState) -> bool:
	if finished(world):
		return false
	var moved := false
	while not finished(world):
		var step := current(world)
		if step.is_empty() or not is_done(world, step.get("done", {})):
			break
		world.flags[FLAG] = current_index(world) + 1
		moved = true
	return moved


## The conditions a step can ask for, all read from the real state of the realm.
static func is_done(world: WorldState, cond: Dictionary) -> bool:
	if cond.is_empty():
		return false
	var k := world.player()
	if k == null:
		return false
	var settlement: SettlementState = null
	for s in world.settlements:
		if s.kingdom == k.id:
			settlement = s
			break
	if cond.has("building"):
		if settlement == null:
			return false
		var wanted := StringName(cond["building"])
		var built := 0
		for b in world.buildings_of(settlement.id):
			if b.def_id == wanted and b.is_active():
				built += 1
		if built < int(cond.get("count", 1)):
			return false
	if cond.has("people"):
		if settlement == null or world.people_of(settlement.id).size() < int(cond["people"]):
			return false
	if cond.has("laws_changed") and float(k.records.get(&"laws_changed", 0.0)) < float(cond["laws_changed"]):
		return false
	if cond.has("monarchy") and k.monarchy_founded != bool(cond["monarchy"]):
		return false
	if cond.has("couples"):
		var couples := 0
		if settlement:
			for p in world.people_of(settlement.id):
				if p.female and p.spouse >= 0 and world.person(p.spouse) != null:
					couples += 1
		if couples < int(cond["couples"]):
			return false
	if cond.has("laws") and k.laws.size() < int(cond["laws"]):
		return false
	if cond.has("technologies") and k.technologies.size() < int(cond["technologies"]):
		return false
	if cond.has("armies"):
		var hosts := 0
		for a in world.armies:
			if a.kingdom == k.id:
				hosts += 1
		if hosts < int(cond["armies"]):
			return false
	return true

