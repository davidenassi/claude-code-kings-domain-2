class_name WorldConstants
extends RefCounted
## Access to the official map's global dimensions. Reads data/world/world_meta.json when present,
## otherwise falls back to the architecture defaults (used before the map is generated).

const META_PATH := "res://data/world/world_meta.json"
const DEFAULT_SIZE := Vector2(112000.0, 72000.0)

static var _meta: Dictionary = {}
static var _loaded: bool = false


static func meta() -> Dictionary:
	if not _loaded:
		_loaded = true
		var data: Variant = Defs.read_json(META_PATH) if FileAccess.file_exists(META_PATH) else null
		_meta = data if data is Dictionary else {}
	return _meta


static func world_size() -> Vector2:
	var m := meta()
	if m.has("world_width_m") and m.has("world_height_m"):
		return Vector2(float(m["world_width_m"]), float(m["world_height_m"]))
	return DEFAULT_SIZE


static func reload() -> void:
	_loaded = false
	_meta = {}

