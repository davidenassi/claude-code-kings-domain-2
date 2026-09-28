class_name BuildingDef
extends KDDef
## A building type (data/defs/buildings.json).

const WORK_TYPES: Array[StringName] = [&"fell_trees", &"quarry_rock", &"farm", &"convert"]
const JOBS: Array[StringName] = [&"woodcutter", &"quarrier", &"farmer", &"baker", &"miner", &"smith"]

@export var category: StringName = &"population"
## Footprint in metres (width along x, depth along y) before rotation.
@export var footprint: Vector2 = Vector2(8, 8)
var cost: Dictionary = {}          ## StringName resource -> int
@export var build_hours: float = 40.0
## False for buildings that only exist from the start (keep, shelter).
@export var buildable: bool = true
@export var beds: int = 0
@export var storage: int = 0
@export var is_storage: bool = false
## Which group of goods this store holds ("all", "material", "food").
@export var storage_group: StringName = &"all"
var stores: Array[StringName] = []
@export var job: StringName = &""
@export var workers: int = 0
var work: Dictionary = {}
var requires: Dictionary = {}
@export var service_radius_m: float = 0.0
@export var sprite: StringName = &""
## Line buildings (roads) are placed with two points instead of a footprint.
@export var is_line: bool = false


func load_from(d: Dictionary, errors: PackedStringArray) -> void:
	super.load_from(d, errors)
	category = StringName(d.get("category", "population"))
	var fp: Array = d.get("footprint", [8, 8])
	footprint = Vector2(float(fp[0]), float(fp[1]))
	for k: String in (d.get("cost", {}) as Dictionary).keys():
		cost[StringName(k)] = int(d["cost"][k])
	build_hours = float(d.get("build_hours", 40.0))
	buildable = bool(d.get("buildable", true))
	beds = int(d.get("beds", 0))
	storage = int(d.get("storage", 0))
	is_storage = bool(d.get("is_storage", false))
	storage_group = StringName(d.get("storage_group", "all"))
	for s: String in d.get("stores", []):
		stores.append(StringName(s))
	job = StringName(d.get("job", ""))
	workers = int(d.get("workers", 0))
	work = d.get("work", {})
	requires = d.get("requires", {})
	service_radius_m = float(d.get("service_radius_m", 0.0))
	sprite = StringName(d.get("sprite", String(id)))
	is_line = String(d.get("shape", "")) == "line"
	if footprint.x <= 0.0 or footprint.y <= 0.0:
		errors.append("building %s: invalid footprint" % id)
	if job != &"" and not JOBS.has(job):
		errors.append("building %s: unknown job %s" % [id, job])
	if job != &"" and workers <= 0:
		errors.append("building %s: job without workers" % id)
	if not work.is_empty() and not WORK_TYPES.has(StringName(work.get("type", ""))):
		errors.append("building %s: unknown work type %s" % [id, work.get("type", "")])
	if buildable and build_hours <= 0.0 and not is_line:
		errors.append("building %s: buildable with no build hours" % id)


func work_type() -> StringName:
	return StringName(work.get("type", ""))


## Footprint size after a rotation of 0/90/180/270 degrees (quarter turns).
func size_for(rotation: int) -> Vector2:
	return footprint if rotation % 2 == 0 else Vector2(footprint.y, footprint.x)

