class_name TerrainDeltas
extends RefCounted
## Everything that has changed on the ground since the map was generated: felled trees (stumps that regrow, or
## ground cleared for good under buildings and fields) and quarried rocks. Saved with the game.
## Listeners are told through EventBus.terrain_changed(world_pos) so renderers rebuild only what changed.

const CLEARED_FOR_GOOD := -1
const BUCKET_M := 64.0
## No stump is waiting to come back (the scan of the felled trees can be skipped for good).
const NEVER := 1 << 30

## tree key "gx:gy" -> day the tree was felled (CLEARED_FOR_GOOD: no stump, never regrows)
var felled: Dictionary = {}
## outcrop rock id -> charges used
var rock_used: Dictionary = {}
## First day a stump could stand again: before it, SettlementSim skips the whole scan. Not saved: a fresh
## zero makes the first day after loading rescan and work it out again.
var next_regrow_day: int = 0
## felled trees per 64 m bucket (rebuilt, not saved): lets the map thin out tree clusters over cleared land
var _felled_buckets: Dictionary = {}


func is_felled(key: String) -> bool:
	return felled.has(key)


func has_stump(key: String) -> bool:
	return felled.has(key) and int(felled[key]) != CLEARED_FOR_GOOD


func fell(tree: Dictionary, day: int, for_good: bool = false) -> void:
	var key: String = tree["key"]
	var was := felled.has(key)
	felled[key] = CLEARED_FOR_GOOD if for_good else day
	if not for_good and next_regrow_day > 0:
		# this stump cannot be back before the shortest regrowth: the scan can still wait until then
		next_regrow_day = mini(next_regrow_day, day + _min_regrow_days())
	if not was:
		_bucket_add(key, 1)
	EventBus.terrain_changed.emit(tree["pos"])


static func _min_regrow_days() -> int:
	var range_days: Array = Defs.balance("settlement").get("stump_regrow_days", [60, 120])
	return int(range_days[0])


## A stump grows back into a standing tree.
func regrow(key: String, pos: Vector2) -> void:
	if felled.erase(key):
		_bucket_add(key, -1)
		EventBus.terrain_changed.emit(pos)


func rock_charges_left(rock: Dictionary) -> int:
	return int(rock["charges"]) - int(rock_used.get(rock["id"], 0))


func use_rock_charge(rock: Dictionary) -> bool:
	if rock_charges_left(rock) <= 0:
		return false
	rock_used[rock["id"]] = int(rock_used.get(rock["id"], 0)) + 1
	if rock_charges_left(rock) <= 0:
		EventBus.terrain_changed.emit(rock["pos"])
	return true


func felled_near(pos: Vector2) -> int:
	return int(_felled_buckets.get(Vector2i(int(floor(pos.x / BUCKET_M)), int(floor(pos.y / BUCKET_M))), 0))


## Buckets use the tree cell centre, so counts can be rebuilt from the saved keys alone.
func _bucket_add(key: String, n: int) -> void:
	var parts := key.split(":")
	var sp := LocalFeatures.spacing()
	var c := Vector2((parts[0].to_int() + 0.5) * sp, (parts[1].to_int() + 0.5) * sp)
	var k := Vector2i(int(floor(c.x / BUCKET_M)), int(floor(c.y / BUCKET_M)))
	var v := int(_felled_buckets.get(k, 0)) + n
	if v <= 0:
		_felled_buckets.erase(k)
	else:
		_felled_buckets[k] = v


func to_dict() -> Dictionary:
	return {"felled": felled.duplicate(), "rock_used": rock_used.duplicate()}


static func from_dict(d: Dictionary) -> TerrainDeltas:
	var t := TerrainDeltas.new()
	for key: String in (d.get("felled", {}) as Dictionary).keys():
		t.felled[key] = int(d["felled"][key])
		t._bucket_add(key, 1)
	for key: String in (d.get("rock_used", {}) as Dictionary).keys():
		t.rock_used[key] = int(d["rock_used"][key])
	return t

