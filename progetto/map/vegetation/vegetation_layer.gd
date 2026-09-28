class_name VegetationLayer
extends Node2D
## Trees, tree clusters, bushes and rocks from the painterly atlas (tools/art/draw_vegetation.py), placed
## deterministically from the official map. Bands (data/defs/vegetation.json): single trees up close, clusters at mid
## zoom, enlarged clusters as icons at map zoom (beyond that the painted albedo shows the forests).
## Chunks are built lazily around the camera and released when far.
## Close band: exactly the trees of LocalFeatures (the ones the inhabitants fell), stumps where they were cut,
## quarriable outcrops. Cluster bands thin out over cleared ground. Changes on the ground rebuild only their chunk.

const ATLAS_DIR := "res://assets/environment/vegetation"
const MAX_BUILDS_PER_FRAME := 6
## Milliseconds of chunk building a frame may spend (at least one chunk is always built): the woods with a shape
## cost more to lay out, and six chunks in one frame made the zoom stutter (world art pass)
const BUILD_BUDGET_MS := 4.0
const BUCKET_M := 128.0
## Chunks rebuilt per frame after changes on the ground (felling at high speed must not stall the frame).
const MAX_DIRTY_PER_FRAME := 2
const TYPICAL_SIZE_M := {"singles": 8.0, "clusters": 22.0}

@export var camera_path: NodePath

var _camera: WorldCamera
var _wd: WorldData
var _cfg: Dictionary
var _atlas: Texture2D
var _atlas_size: Vector2
var _sprites: Array[Dictionary] = []
var _by_species: Dictionary = {}       # StringName -> Array[int] sprite indices
var _tables: Dictionary = {}           # "singles"/"clusters" -> {biome index -> {"ids", "cum"}}
var _rock_biomes: Dictionary = {}
var _quad: ArrayMesh
var _bands: Array[Dictionary] = []
var _frame_deadline := 0
var _built_this_frame := 0     # {cfg, node, material, chunks: Dictionary, dirty: Dictionary}
var _stumps: Array = []
var _boulders: Array = []


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	_wd = WorldData.get_instance()
	_cfg = Defs.read_json("res://data/defs/vegetation.json")
	var meta: Dictionary = Defs.read_json(ATLAS_DIR + "/vegetation_atlas.json")
	_atlas = load(ATLAS_DIR + "/" + String(meta["atlas"]))
	_atlas_size = Vector2(float(meta["width"]), float(meta["height"]))
	for s in meta["sprites"]:
		var idx := _sprites.size()
		_sprites.append(s)
		var sp := StringName(s["species"])
		if not _by_species.has(sp):
			_by_species[sp] = []
		(_by_species[sp] as Array).append(idx)
	_tables["singles"] = _weight_table(_cfg["biome_species"])
	_tables["clusters"] = _weight_table(_cfg["biome_clusters"])
	for b in (_cfg["rocks"]["biomes"] as Array):
		var bd: BiomeDef = Defs.get_def("biomes", StringName(b))
		if bd:
			_rock_biomes[bd.index] = true
	_quad = make_quad()
	var shader: Shader = load("res://shaders/vegetation.gdshader")
	for band_cfg in _cfg["bands"]:
		var node := Node2D.new()
		node.name = "Band_" + String(band_cfg["id"])
		node.y_sort_enabled = true
		add_child(node)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		TerrainLayer.apply_style(mat, Defs.read_json(TerrainLayer.STYLE_PATH))
		_bands.append({"cfg": band_cfg, "node": node, "material": mat, "chunks": {}, "dirty": {}, "base": {}})
	_stumps = _by_species.get(&"stump", [])
	_boulders = _by_species.get(&"boulder", [])
	EventBus.terrain_changed.connect(_on_terrain_changed)
	EventBus.session_started.connect(func(_s: GameSession) -> void: _clear_all())
	EventBus.session_loaded.connect(func(_s: GameSession) -> void: _clear_all())


func _on_terrain_changed(pos: Vector2) -> void:
	for band in _bands:
		var cs := float(band["cfg"]["chunk_m"])
		var reach := 16.0 + float(band["cfg"].get("clear_m", 0.0))
		# the change can touch sprites of the neighbouring chunks too (building footprints, cluster radius)
		for oy in [-1, 0, 1]:
			for ox in [-1, 0, 1]:
				var key := Vector2i(int(floor((pos.x + ox * reach) / cs)), int(floor((pos.y + oy * reach) / cs)))
				if (band["chunks"] as Dictionary).has(key):
					band["dirty"][key] = true


func _clear_all() -> void:
	for band in _bands:
		for key in (band["chunks"] as Dictionary).keys():
			var n: Node = band["chunks"][key]
			if n:
				n.queue_free()
		(band["chunks"] as Dictionary).clear()
		(band["dirty"] as Dictionary).clear()


func _weight_table(src: Dictionary) -> Dictionary:
	var out := {}
	for biome_id in src.keys():
		var bdef: BiomeDef = Defs.get_def("biomes", StringName(biome_id))
		if bdef == null:
			continue
		var ids: Array[StringName] = []
		var cum := PackedFloat32Array()
		var total := 0.0
		for pair in src[biome_id]:
			if not _by_species.has(StringName(pair[0])):
				continue
			total += float(pair[1])
			ids.append(StringName(pair[0]))
			cum.append(total)
		for i in cum.size():
			cum[i] /= total
		out[bdef.index] = {"ids": ids, "cum": cum}
	return out


static func make_quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _process(_delta: float) -> void:
	if _camera == null:
		return
	var mpp := _camera.meters_per_pixel()
	var view := _camera.visible_world_rect()
	var budget := MAX_BUILDS_PER_FRAME
	_frame_deadline = Time.get_ticks_usec() + int(BUILD_BUDGET_MS * 1000.0)
	_built_this_frame = 0
	for band in _bands:
		var cfg: Dictionary = band["cfg"]
		var lo := float(cfg["min_mpp"])
		var hi := float(cfg["max_mpp"])
		var node: Node2D = band["node"]
		var active := mpp >= lo and mpp < hi
		if not active:
			if node.visible:
				node.visible = false
			_release_far(band, view, true)
			continue
		node.visible = true
		var fade := clampf((hi - mpp) / (hi * 0.15), 0.0, 1.0)
		if lo > 0.0:
			fade = minf(fade, clampf((mpp - lo) / (lo * 0.25), 0.0, 1.0))
		var mat: ShaderMaterial = band["material"]
		mat.set_shader_parameter("fade", fade)
		var icon_px := float(cfg["icon_px"])
		var typical := float(TYPICAL_SIZE_M.get(String(cfg.get("sprites", "singles")), 8.0))
		var scale_f := 1.0 if icon_px <= 0.0 else maxf(1.0, icon_px * mpp / typical)
		mat.set_shader_parameter("icon_scale", scale_f)
		_rebuild_dirty(band, MAX_DIRTY_PER_FRAME)
		budget = _ensure_chunks(band, view, budget)
		_release_far(band, view, false)


## Rebuilds changed chunks in place (new node first, then the old one goes: no flicker).
func _rebuild_dirty(band: Dictionary, budget: int) -> int:
	var dirty: Dictionary = band["dirty"]
	for key: Vector2i in dirty.keys():
		if budget <= 0:
			break
		dirty.erase(key)
		var chunks: Dictionary = band["chunks"]
		if not chunks.has(key):
			continue
		var old: Node = chunks[key]
		chunks[key] = _build_chunk(band, key)
		if old:
			old.queue_free()
		budget -= 1
	return budget


func _ensure_chunks(band: Dictionary, view: Rect2, budget: int) -> int:
	var cfg: Dictionary = band["cfg"]
	var cs := float(cfg["chunk_m"])
	var margin := cs * 0.5
	var r := view.grow(margin)
	var x0 := int(floor(r.position.x / cs))
	var y0 := int(floor(r.position.y / cs))
	var x1 := int(floor(r.end.x / cs))
	var y1 := int(floor(r.end.y / cs))
	var chunks: Dictionary = band["chunks"]
	var wanted: Array[Vector2i] = []
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var key := Vector2i(cx, cy)
			if not chunks.has(key):
				wanted.append(key)
	if wanted.is_empty():
		return budget
	var center := view.get_center() / cs
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) - center).length_squared() < (Vector2(b) - center).length_squared())
	for key in wanted:
		if budget <= 0 or (_built_this_frame > 0 and Time.get_ticks_usec() > _frame_deadline):
			break
		chunks[key] = _build_chunk(band, key)
		budget -= 1
		_built_this_frame += 1
	return budget


func _release_far(band: Dictionary, view: Rect2, all_chunks: bool) -> void:
	var cfg: Dictionary = band["cfg"]
	var cs := float(cfg["chunk_m"])
	var keep := view.grow(cs * 2.0)
	var chunks: Dictionary = band["chunks"]
	for key: Vector2i in chunks.keys():
		var rect := Rect2(Vector2(key) * cs, Vector2(cs, cs))
		if all_chunks or not keep.intersects(rect):
			var n: Node = chunks[key]
			if n:
				n.queue_free()
			chunks.erase(key)
			(band["base"] as Dictionary).erase(key)
			(band["dirty"] as Dictionary).erase(key)


## What the map generates in a chunk before any change on the ground (computed once per chunk, then filtered).
## Close band: [pos, alive_sprite, stump_sprite (-1 none), key, shade, moisture]; clusters: [pos, sprite, shade, moisture].
func _base_items(band: Dictionary, key: Vector2i) -> Array:
	var cache: Dictionary = band["base"]
	if cache.has(key):
		return cache[key]
	var cfg: Dictionary = band["cfg"]
	var cs := float(cfg["chunk_m"])
	var spacing := float(cfg["spacing_m"])
	var bias := float(cfg["density_bias"])
	var table: Dictionary = _tables[String(cfg.get("sprites", "singles"))]
	var close := String(cfg.get("sprites", "singles")) == "singles"
	var clear_above := INF if close else float(_cfg.get("clusters_below_m", INF))
	var origin := Vector2(key) * cs
	var chunk_rect := Rect2(origin, Vector2(cs, cs))
	var out: Array = []
	var gx0 := int(floor(origin.x / spacing))
	var gy0 := int(floor(origin.y / spacing))
	var n_cells := int(ceil(cs / spacing))
	if close:
		for j in n_cells:
			for i in n_cells:
				var f := LocalFeatures.cell_feature(_wd, gx0 + i, gy0 + j)
				if f.is_empty() or not chunk_rect.has_point(f["pos"]):
					continue
				var alive := _pick_from(StringName(f["species"]), float(f["variant_hash"]))
				if alive < 0:
					continue
				var stump := -1
				if f["kind"] == LocalFeatures.KIND_TREE and not _stumps.is_empty():
					stump = int(_stumps[int(float(f["variant_hash"]) * _stumps.size()) % _stumps.size()])
				var key_s := "" if f["kind"] == LocalFeatures.KIND_ROCK else String(f["key"])
				var dens := float(f["density"])
				var shade := 0.6 * float(f["tint_hash"]) + 0.4 * clampf(1.2 - dens * 1.3, 0.0, 1.0)
				out.append([f["pos"], alive, stump, key_s, shade, _wd.moisture_smooth(f["pos"])])
	else:
		var salt := int(spacing * 10.0)
		for j in n_cells:
			for i in n_cells:
				var gx := gx0 + i
				var gy := gy0 + j
				var pos := Vector2((gx + 0.1 + 0.8 * KDRng.hash01(gx, gy, salt)) * spacing, (gy + 0.1 + 0.8 * KDRng.hash01(gx, gy, salt + 1)) * spacing)
				if not chunk_rect.has_point(pos):
					continue
				if not _wd.in_world(pos) or _wd.water_at(pos) != WorldData.WATER_LAND or _wd.height_at(pos) > clear_above:
					continue
				var h3 := KDRng.hash01(gx, gy, salt + 2)
				var jitter := Vector2(KDRng.hash01(gx, gy, salt + 3) - 0.5, KDRng.hash01(gx, gy, salt + 4) - 0.5) * 70.0
				var dens := _wd.canopy_smooth(pos + jitter) + LocalFeatures.margin_noise(pos)
				# a wood has glades, thick cores and ragged margins: the same shape the single trees of the close
				# zoom follow (LocalFeatures), so nothing jumps when the camera comes down
				var p := smoothstep(0.10, 0.55, dens) * bias * LocalFeatures.glade_factor(pos) \
					+ LocalFeatures.grove_chance(pos) * 0.5
				if h3 >= p:
					continue
				var sprite := _pick_sprite(table, _wd.biome_at(pos), KDRng.hash01(gx, gy, salt + 5), KDRng.hash01(gx, gy, salt + 6))
				if sprite < 0:
					continue
				# and its crowns come in stands of one tone, darker or lighter, not one tint per tree
				var stand := value_noise(pos, 260.0, 457)
				var shade := 0.35 * KDRng.hash01(gx, gy, salt + 9) + 0.40 * stand + 0.25 * clampf(1.2 - dens * 1.3, 0.0, 1.0)
				out.append([pos, sprite, shade, _wd.moisture_smooth(pos)])
	cache[key] = out
	return out


func _build_chunk(band: Dictionary, key: Vector2i) -> Node2D:
	var cfg: Dictionary = band["cfg"]
	var cs := float(cfg["chunk_m"])
	var spacing := float(cfg["spacing_m"])
	var close := String(cfg.get("sprites", "singles")) == "singles"
	var origin := Vector2(key) * cs
	var chunk_rect := Rect2(origin, Vector2(cs, cs))
	var world: WorldState = Session.current.world if Session.has_game() else null
	var footprints: Array[Rect2] = []
	# the woods keep away from the houses: clusters are drawn bigger than the trees they stand for, and one
	# of them next to a village covered it whole at mid zoom (Phase 18 audit). Yards, gardens and pastures
	# open a clearing around every building; roads keep their own width.
	var clear_m := float(cfg.get("clear_m", 4.0))
	# beyond the clearing, a worked margin where the woods thin out (world art pass): cut for firewood and
	# timber, grazed, the woods come back only slowly
	var margin_m := float(cfg.get("margin_m", 0.0))
	# the footprints near each 128 m cell (grown by the worked margin): a cluster looks only at those (with every
	# building of a town for every cluster, building a chunk took a tenth of a second and the zoom stuttered)
	var buckets := {}
	if world:
		for b: BuildingState in world.buildings.values():
			var r := b.rect().grow(4.0 if b.is_road() else clear_m)
			if r.intersects(chunk_rect.grow(24.0 + clear_m + margin_m)):
				footprints.append(r)
				var reach := r.grow(margin_m + 1.0)
				for cy in range(int(floor(reach.position.y / BUCKET_M)), int(floor(reach.end.y / BUCKET_M)) + 1):
					for cx in range(int(floor(reach.position.x / BUCKET_M)), int(floor(reach.end.x / BUCKET_M)) + 1):
						var key_b := Vector2i(cx, cy)
						if not buckets.has(key_b):
							buckets[key_b] = [] as Array[Rect2]
						(buckets[key_b] as Array[Rect2]).append(r)
	var items: Array = []  # [y, pos, sprite_index, tint, moisture, scale]
	if close:
		for base: Array in _base_items(band, key):
			var sprite: int = base[1]
			var tree_key: String = base[3]
			if world and tree_key != "" and world.terrain.is_felled(tree_key):
				sprite = int(base[2]) if world.terrain.has_stump(tree_key) else -1
			if sprite < 0:
				continue
			var pos: Vector2 = base[0]
			items.append([pos.y, pos, sprite, base[4], base[5], 1.0])
	else:
		var none: Array[Rect2] = []
		for base: Array in _base_items(band, key):
			var pos: Vector2 = base[0]
			var near: Array[Rect2] = buckets.get(Vector2i(int(floor(pos.x / BUCKET_M)), int(floor(pos.y / BUCKET_M))), none)
			# worked woods and building plots: the cluster is gone
			if world and (world.terrain.felled_near(pos) >= 3 or _in_footprints(pos, near)):
				continue
			if margin_m > 0.0 and not near.is_empty():
				var d := _distance_to_rects(pos, near)
				if d < margin_m and KDRng.hash01(int(pos.x), int(pos.y), 4471) > d / margin_m:
					continue
			items.append([pos.y, pos, base[1], base[2], base[3], 1.0])
	# quarriable outcrops (close and mid zoom), smaller as they are worked
	if spacing <= 64.0 and not _boulders.is_empty():
		for r in LocalFeatures.outcrops_in_rect(chunk_rect):
			var left := int(r["charges"]) if world == null else world.terrain.rock_charges_left(r)
			if left <= 0:
				continue
			var sprite := int(_boulders[int(float(r["variant_hash"]) * _boulders.size()) % _boulders.size()])
			var scale := float(r["size"]) / 4.0 * lerpf(0.55, 1.0, float(left) / float(r["charges"])) * (1.0 if close else 1.6)
			items.append([(r["pos"] as Vector2).y, r["pos"], sprite, float(r["variant_hash"]), 0.5, scale])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _quad
	mm.instance_count = items.size()
	for k in items.size():
		var it: Array = items[k]
		var s: Dictionary = _sprites[int(it[2])]
		var rect: Array = s["rect"]
		var size_m: Array = s["size_m"]
		var pv: Array = s["pivot"]
		var sc := float(it[5])
		# no two trees of a wood are the same size, and half of them face the other way: without this the
		# forest reads as a regular stipple of identical dots instead of a wood
		var vary := 1.0
		var flip := 1.0
		if is_equal_approx(sc, 1.0):
			var seed_f := fposmod(float(it[3]) * 7.31 + (it[1] as Vector2).x * 0.013, 1.0)
			vary = 0.78 + 0.46 * seed_f
			flip = -1.0 if fposmod(float(it[3]) * 13.7, 1.0) < 0.5 else 1.0
		var w := float(size_m[0]) * sc * vary * flip
		var h := float(size_m[1]) * sc * vary
		var local: Vector2 = (it[1] as Vector2) - origin
		mm.set_instance_transform_2d(k, Transform2D(Vector2(w, 0), Vector2(0, h), local))
		mm.set_instance_color(k, Color(float(pv[0]) / float(rect[2]), float(pv[1]) / float(rect[3]), float(it[3]), float(it[4])))
		mm.set_instance_custom_data(k, Color(float(rect[0]) / _atlas_size.x, float(rect[1]) / _atlas_size.y,
			float(rect[2]) / _atlas_size.x, float(rect[3]) / _atlas_size.y))
	var inst := MultiMeshInstance2D.new()
	inst.multimesh = mm
	inst.texture = _atlas
	inst.material = band["material"]
	inst.position = origin
	(band["node"] as Node2D).add_child(inst)
	return inst


## Smooth value noise 0..1 (kept here for the callers of Phase 18; the woods use LocalFeatures.value_noise).
static func value_noise(p: Vector2, cell: float, salt: int) -> float:
	return LocalFeatures.value_noise(p, cell, salt)


## Distance from a point to the nearest of these (already grown) rectangles; 0 inside one.
static func _distance_to_rects(pos: Vector2, rects: Array[Rect2]) -> float:
	var best := INF
	for r in rects:
		var dx := maxf(maxf(r.position.x - pos.x, 0.0), pos.x - r.end.x)
		var dy := maxf(maxf(r.position.y - pos.y, 0.0), pos.y - r.end.y)
		best = minf(best, sqrt(dx * dx + dy * dy))
	return best


static func _in_footprints(pos: Vector2, rects: Array[Rect2]) -> bool:
	for r in rects:
		if r.has_point(pos):
			return true
	return false


func _pick_sprite(table: Dictionary, biome: int, h_species: float, h_variant: float) -> int:
	var entry: Dictionary = table.get(biome, {})
	if entry.is_empty():
		return -1
	var cum: PackedFloat32Array = entry["cum"]
	var ids: Array[StringName] = entry["ids"]
	for i in cum.size():
		if h_species <= cum[i]:
			return _pick_from(ids[i], h_variant)
	return _pick_from(ids[ids.size() - 1], h_variant)


func _pick_from(species: StringName, h: float) -> int:
	var list: Array = _by_species.get(species, [])
	if list.is_empty():
		return -1
	return int(list[mini(int(h * list.size()), list.size() - 1)])

