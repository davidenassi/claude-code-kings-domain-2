class_name LocalFeatures
extends RefCounted
## The physical features of the single world at close range: every tree and every rock outcrop has a stable id
## and position derived deterministically from the official map. The simulation (felling, quarrying, placement)
## and the renderer (VegetationLayer) enumerate exactly the same features; what changes during a campaign is
## stored as deltas in TerrainDeltas.
##
## Trees: jittered grid of the "close" vegetation band (data/defs/vegetation.json), density from the canopy raster.
## Outcrops: rocks scattered around every stone/iron deposit of the province data, with a number of charges.
##
## Rebirth (Phase 1): every function takes the map data it works on — the continent (WorldData) or the player's
## valley (DomainData), in the valley's own metres. Hashes and noises are taken at `wd.feature_origin + pos`, so a
## valley cut out of the continent grows exactly the trees the continent had there.

## Trees, bushes and rocks keep this far from the edge of the drawn river (its bank included).
const RIVER_CLEAR_M := 1.5
const KIND_TREE := &"tree"
const KIND_BUSH := &"bush"
const KIND_ROCK := &"rock"
const OUTCROP_TYPES: Array[StringName] = [&"stone", &"iron"]
const OUTCROP_BUCKET_M := 256.0

static var _ready_done := false
static var _spacing := 12.0
static var _bias := 0.8
static var _salt := 120
static var _species_tables: Dictionary = {}   # biome index -> {"ids": Array[StringName], "cum": PackedFloat32Array}
static var _bushes: Dictionary = {&"bush": true}
static var _rock_biomes: Dictionary = {}
static var _rock_chance := 0.04
static var _outcrops: Array[Dictionary] = []      # {id: String, pos: Vector2, size: float, charges: int, deposit: StringName}
static var _outcrop_buckets: Dictionary = {}      # Vector2i -> PackedInt32Array
static var _outcrop_by_id: Dictionary = {}
## The map data the outcrops above were laid out on (they are rebuilt when another map asks).
static var _outcrops_of: WorldData = null


static func ensure_ready() -> void:
	if _ready_done:
		return
	_ready_done = true
	var cfg: Dictionary = Defs.read_json("res://data/defs/vegetation.json")
	for band: Dictionary in cfg.get("bands", []):
		if String(band.get("id", "")) == "close":
			_spacing = float(band["spacing_m"])
			_bias = float(band["density_bias"])
	_salt = int(_spacing * 10.0)
	for biome_id: String in (cfg.get("biome_species", {}) as Dictionary).keys():
		var bd: BiomeDef = Defs.get_def("biomes", StringName(biome_id))
		if bd == null:
			continue
		var ids: Array[StringName] = []
		var cum := PackedFloat32Array()
		var total := 0.0
		for pair: Array in cfg["biome_species"][biome_id]:
			total += float(pair[1])
			ids.append(StringName(pair[0]))
			cum.append(total)
		for i in cum.size():
			cum[i] /= total
		_species_tables[bd.index] = {"ids": ids, "cum": cum}
	var rocks: Dictionary = cfg.get("rocks", {})
	_rock_chance = float(rocks.get("chance", 0.04))
	for b: String in rocks.get("biomes", []):
		var bd: BiomeDef = Defs.get_def("biomes", StringName(b))
		if bd:
			_rock_biomes[bd.index] = true


static func spacing() -> float:
	ensure_ready()
	return _spacing


## Stable key of the tree/decoration cell (gx, gy).
static func tree_key(gx: int, gy: int) -> String:
	return "%d:%d" % [gx, gy]


## The feature generated in close-band cell (gx, gy): {} if empty, else
## {kind: tree|bush|rock, key, pos, gx, gy, species, biome, variant_hash, tint_hash, density}.
## Rocks here are small decorative stones of rocky biomes (not quarriable); outcrops are separate.
static func cell_feature(wd: WorldData, gx: int, gy: int) -> Dictionary:
	ensure_ready()
	var s := _salt
	var sp := _spacing
	# the dice of a cell are the continent's cell (identical for the continent itself, whose origin is zero)
	var off := cell_offset(wd)
	var hx := gx + off.x
	var hy := gy + off.y
	var pos := Vector2((gx + 0.1 + 0.8 * KDRng.hash01(hx, hy, s)) * sp, (gy + 0.1 + 0.8 * KDRng.hash01(hx, hy, s + 1)) * sp)
	if not wd.in_world(pos) or wd.water_at(pos) != WorldData.WATER_LAND:
		return {}
	if wd.river_clearance(pos) < RIVER_CLEAR_M:
		return {}   # no tree grows in the river or on its gravel bank (Phase 17 check)
	var h3 := KDRng.hash01(hx, hy, s + 2)
	var biome := wd.biome_at(pos)
	var jitter := Vector2(KDRng.hash01(hx, hy, s + 3) - 0.5, KDRng.hash01(hx, hy, s + 4) - 0.5) * 70.0
	var canopy := wd.canopy_smooth(pos + jitter)
	var npos := pos + wd.feature_origin   # where the noises of the woods are read
	# a wood has a shape (world art pass): thick cores and glades (glade_factor, the same the mid zoom draws),
	# ragged margins (margin_noise), and outside it trees in small groups, not a uniform stipple. The factors
	# average to one: the same number of trees overall, so the wood a village can cut does not change on average.
	# The noises cost: a cell whose dice are above the best the shape could give is decided without them.
	var p := 0.0
	var dens := canopy
	if h3 < smoothstep(0.10, 0.55, canopy + 0.15) * _bias * GLADE_MAX + GROVE_MAX:
		dens = canopy + margin_noise(npos)
		p = smoothstep(0.10, 0.55, dens) * _bias * glade_factor(npos)
		if p < 0.2:
			p += grove_chance(npos)   # inside a wood the groves change nothing: not worth their noise
	if h3 < p:
		var species := pick_species(biome, KDRng.hash01(hx, hy, s + 5))
		if species == &"":
			return {}
		return {"kind": KIND_BUSH if _bushes.has(species) else KIND_TREE, "key": tree_key(gx, gy), "pos": pos,
			"gx": gx, "gy": gy, "species": species, "biome": biome, "variant_hash": KDRng.hash01(hx, hy, s + 6),
			"tint_hash": KDRng.hash01(hx, hy, s + 9), "density": dens}
	if _rock_biomes.has(biome) and h3 > 1.0 - _rock_chance:
		return {"kind": KIND_ROCK, "key": tree_key(gx, gy), "pos": pos, "gx": gx, "gy": gy,
			"species": &"rock" if KDRng.hash01(hx, hy, s + 7) < 0.8 else &"boulder", "biome": biome,
			"variant_hash": KDRng.hash01(hx, hy, s + 8), "tint_hash": KDRng.hash01(hx, hy, s + 9), "density": dens}
	return {}


## The tree grid of `wd` starts this many cells into the continent's (zero for the continent and for homelands).
static func cell_offset(wd: WorldData) -> Vector2i:
	if wd.feature_origin == Vector2.ZERO:
		return Vector2i.ZERO
	return Vector2i(roundi(wd.feature_origin.x / _spacing), roundi(wd.feature_origin.y / _spacing))


const GLADE_MAX := 2.7
const GROVE_MAX := 0.102


## Thick cores and real glades of the woods: 0.06..2.7 over cells of 470 m (with the cores that cannot be fuller
## than full, the number of trees stays what it was).
static func glade_factor(pos: Vector2) -> float:
	return lerpf(0.06, GLADE_MAX, smoothstep(0.34, 0.58, value_noise(pos, 470.0, 913)))


## Ragged margins: the edge of a wood wanders in and out by about a hundred metres.
static func margin_noise(pos: Vector2) -> float:
	return (value_noise(pos, 130.0, 57) - 0.5) * 0.30


## Trees and bushes outside the woods, in small groups.
static func grove_chance(pos: Vector2) -> float:
	return (GROVE_MAX - 0.002) * smoothstep(0.66, 0.86, value_noise(pos, 70.0, 31)) + 0.002


## Smooth value noise 0..1 over cells of `cell` metres (deterministic: the same wood every time).
static func value_noise(p: Vector2, cell: float, salt: int) -> float:
	var q := p / cell
	var x0 := int(floor(q.x))
	var y0 := int(floor(q.y))
	var fx := q.x - float(x0)
	var fy := q.y - float(y0)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	# KDRng.hash01 written out four times: this runs for every tree cell the simulation looks at
	var sx := salt * 2147483647
	var ax := x0 * 374761393
	var bx := ax + 374761393
	var ay := y0 * 668265263
	var by := ay + 668265263
	var h := ax ^ ay ^ sx
	h = (h ^ (h >> 13)) * 1274126177
	var a := float((h ^ (h >> 16)) & 0x7fffffff) / 2147483648.0
	h = bx ^ ay ^ sx
	h = (h ^ (h >> 13)) * 1274126177
	var b := float((h ^ (h >> 16)) & 0x7fffffff) / 2147483648.0
	h = ax ^ by ^ sx
	h = (h ^ (h >> 13)) * 1274126177
	var c := float((h ^ (h >> 16)) & 0x7fffffff) / 2147483648.0
	h = bx ^ by ^ sx
	h = (h ^ (h >> 13)) * 1274126177
	var d := float((h ^ (h >> 16)) & 0x7fffffff) / 2147483648.0
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func pick_species(biome: int, h: float) -> StringName:
	var entry: Dictionary = _species_tables.get(biome, {})
	if entry.is_empty():
		return &""
	var cum: PackedFloat32Array = entry["cum"]
	var ids: Array[StringName] = entry["ids"]
	for i in cum.size():
		if h <= cum[i]:
			return ids[i]
	return ids[ids.size() - 1]


## Standing and felled trees/bushes whose position lies inside `rect` (felled ones included; filter with deltas).
static func trees_in_rect(wd: WorldData, rect: Rect2, include_bushes: bool = true) -> Array[Dictionary]:
	ensure_ready()
	var out: Array[Dictionary] = []
	var gx0 := int(floor(rect.position.x / _spacing)) - 1
	var gy0 := int(floor(rect.position.y / _spacing)) - 1
	var gx1 := int(floor(rect.end.x / _spacing))
	var gy1 := int(floor(rect.end.y / _spacing))
	for gy in range(gy0, gy1 + 1):
		for gx in range(gx0, gx1 + 1):
			var f := cell_feature(wd, gx, gy)
			if f.is_empty() or f["kind"] == KIND_ROCK:
				continue
			if f["kind"] == KIND_BUSH and not include_bushes:
				continue
			if rect.has_point(f["pos"]):
				out.append(f)
	return out


static func tree_by_key(wd: WorldData, key: String) -> Dictionary:
	var parts := key.split(":")
	if parts.size() != 2:
		return {}
	return cell_feature(wd, parts[0].to_int(), parts[1].to_int())


# --- outcrops -----------------------------------------------------------------------------------

static func _ensure_outcrops(wd: WorldData) -> void:
	ensure_ready()
	if _outcrops_of == wd:
		return
	_outcrops_of = wd
	_outcrops = []
	_outcrop_buckets = {}
	_outcrop_by_id = {}
	_build_outcrops(wd)


static func _build_outcrops(wd: WorldData) -> void:
	var bal: Dictionary = Defs.balance("settlement")
	var bounds := Rect2(Vector2.ZERO, wd.size_m).grow(float(bal.get("outcrop_radius_m", 34.0)) + 8.0)
	var radius := float(bal.get("outcrop_radius_m", 34.0))
	var counts: Array = bal.get("outcrop_rocks", [6, 14])
	var charges: Array = bal.get("rock_charges", [7, 10])
	for g in wd.provinces:
		for di in g.deposits.size():
			var dep: Dictionary = g.deposits[di]
			if not OUTCROP_TYPES.has(dep["type"]):
				continue
			var center: Vector2 = dep["pos"]
			if not bounds.has_point(center):
				continue   # a deposit of the continent outside the valley
			var n := int(lerpf(float(counts[0]), float(counts[1]), clampf(float(dep["richness"]) - 0.5, 0.0, 1.0)))
			var salt := g.id * 131 + di * 17
			for i in n:
				var a := TAU * KDRng.hash01(salt, i, 901)
				var r := radius * sqrt(KDRng.hash01(salt, i, 902))
				var pos := center + Vector2(cos(a), sin(a)) * r
				if not wd.in_world(pos) or wd.water_at(pos) != WorldData.WATER_LAND or wd.river_clearance(pos) < RIVER_CLEAR_M + 1.0:
					continue
				var rock := {"id": "%d:%d:%d" % [g.id, di, i], "pos": pos, "deposit": dep["type"],
					"size": lerpf(2.2, 4.5, KDRng.hash01(salt, i, 903)),
					"charges": int(lerpf(float(charges[0]), float(charges[1]) + 0.99, KDRng.hash01(salt, i, 904))),
					"variant_hash": KDRng.hash01(salt, i, 905)}
				var idx := _outcrops.size()
				_outcrops.append(rock)
				_outcrop_by_id[rock["id"]] = idx
				var bk := Vector2i(int(floor(pos.x / OUTCROP_BUCKET_M)), int(floor(pos.y / OUTCROP_BUCKET_M)))
				var list: PackedInt32Array = _outcrop_buckets.get(bk, PackedInt32Array())
				list.append(idx)
				_outcrop_buckets[bk] = list


static func outcrops_in_rect(wd: WorldData, rect: Rect2) -> Array[Dictionary]:
	_ensure_outcrops(wd)
	var out: Array[Dictionary] = []
	for by in range(int(floor(rect.position.y / OUTCROP_BUCKET_M)), int(floor(rect.end.y / OUTCROP_BUCKET_M)) + 1):
		for bx in range(int(floor(rect.position.x / OUTCROP_BUCKET_M)), int(floor(rect.end.x / OUTCROP_BUCKET_M)) + 1):
			for idx in _outcrop_buckets.get(Vector2i(bx, by), PackedInt32Array()):
				var r: Dictionary = _outcrops[idx]
				if rect.has_point(r["pos"]):
					out.append(r)
	return out


static func outcrop(wd: WorldData, rock_id: String) -> Dictionary:
	_ensure_outcrops(wd)
	return _outcrops[_outcrop_by_id[rock_id]] if _outcrop_by_id.has(rock_id) else {}

