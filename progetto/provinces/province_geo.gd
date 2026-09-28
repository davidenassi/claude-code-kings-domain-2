class_name ProvinceGeo
extends RefCounted
## Static geography of a province, from data/world/provinces.json. Never changes during a campaign
## (dynamic data lives in ProvinceState).

var id: int = -1
var name: String = ""
var center: Vector2 = Vector2.ZERO     ## label/capital point (far from the edges)
var centroid: Vector2 = Vector2.ZERO
var area_km2: float = 0.0
var inner_radius_m: float = 0.0
var terrain: StringName = &"plains"
var biomes: Dictionary = {}            ## biome id -> share
var elevation_mean: float = 0.0
var elevation_max: float = 0.0
var forest: float = 0.0
var fertility: float = 0.0
var moisture: float = 0.0
var temperature: float = 0.0
var coastal: bool = false
var has_river: bool = false
var has_lake: bool = false
var culture: StringName = &""
var religion: StringName = &""
## [{id: int, length_m: float, type: StringName}]
var neighbors: Array[Dictionary] = []
## [{type: StringName, pos: Vector2, richness: float}]
var deposits: Array[Dictionary] = []


static func from_dict(d: Dictionary) -> ProvinceGeo:
	var p := ProvinceGeo.new()
	p.id = int(d.get("id", -1))
	p.name = String(d.get("name", ""))
	var c: Array = d.get("center", [0, 0])
	p.center = Vector2(float(c[0]), float(c[1]))
	var cc: Array = d.get("centroid", [0, 0])
	p.centroid = Vector2(float(cc[0]), float(cc[1]))
	p.area_km2 = float(d.get("area_km2", 0.0))
	p.inner_radius_m = float(d.get("inner_radius_m", 0.0))
	p.terrain = StringName(d.get("terrain", "plains"))
	p.biomes = d.get("biomes", {})
	p.elevation_mean = float(d.get("elevation_mean", 0.0))
	p.elevation_max = float(d.get("elevation_max", 0.0))
	p.forest = float(d.get("forest", 0.0))
	p.fertility = float(d.get("fertility", 0.0))
	p.moisture = float(d.get("moisture", 0.0))
	p.temperature = float(d.get("temperature", 0.0))
	p.coastal = bool(d.get("coastal", false))
	p.has_river = bool(d.get("river", false))
	p.has_lake = bool(d.get("lake", false))
	p.culture = StringName(d.get("culture", ""))
	p.religion = StringName(d.get("religion", ""))
	for n in d.get("neighbors", []):
		p.neighbors.append({"id": int(n["id"]), "length_m": float(n["length_m"]), "type": StringName(n["type"])})
	for dep in d.get("deposits", []):
		p.deposits.append({"type": StringName(dep["type"]), "pos": Vector2(float(dep["x"]), float(dep["y"])),
			"richness": float(dep["richness"])})
	return p


func neighbor_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for n in neighbors:
		out.append(int(n["id"]))
	return out

