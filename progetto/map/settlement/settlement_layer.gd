class_name SettlementLayer
extends Node2D
## Buildings of every settlement, drawn from the building atlas in depth order (y). A construction site shows the
## levelled ground, the building rising from the bottom as work progresses, and a scaffold while it is unfinished.
## Farms change with the season (bare, green, ripe).
##
## World art pass: the simulation stays on its axis-aligned footprints; the picture does not. Every building is
## nudged, turned and scaled a little (`visual_of`, from its id: the same after a reload), fields are strips drawn
## by FieldPainter, roads and paths bend, the ground under a building is an irregular patch of trodden earth, the
## centre of a settlement is an open square, and a path goes down to the river.

const ATLAS_DIR := "res://assets/buildings"
const VISIBLE_MPP := Vector2(2.4, 2.7)   # fully visible below x, hidden above y: further away SettlementMarks draws them
## Rebirth: which settlements are simulated inhabitant by inhabitant is no longer decided by the zoom here but by
## the map on the table (LocalView: the valley is watched; GlobalView: nobody is).

@export var camera_path: NodePath

var _camera: WorldCamera
var _atlas: Texture2D
var _sprites: Dictionary = {}
var _variant_count: Dictionary = {}   # sprite -> how many drawn variants the atlas holds besides it
var _ppm := 8.0
var _last_fade := -1.0
var _month := -1
## settlement id -> [[a, b], ...]: the footpaths people wear between the doors (Phase 18), rebuilt only when the
## buildings change
var _paths: Dictionary = {}
var _paths_version := -1
var _paths_world := 0
## The fenced gardens behind the houses (Phase 18), rebuilt with the footpaths
var _yards: Array[Rect2] = []
## settlement id -> [[a, b], ...]: the first trails out of the nucleus (Rebirth, Phase 3), rebuilt with the footpaths
var _trails: Dictionary = {}
## Every field in one mesh (FieldPainter.build_mesh), rebuilt when the buildings or the month change
var _fields_mesh: ArrayMesh = null
var _fields_key := ""
## What lies on the ground (square, paths, roads, gardens, fields, trodden earth, shadows) is drawn by a child
## behind the buildings and redrawn only when the ground changes: a construction site moving on a notch used to
## redraw every path and every field of the town (world art pass: the town stuttered)
var _ground: Node2D
var _ci: CanvasItem = self
var _ground_key := ""


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	var meta: Dictionary = Defs.read_json(ATLAS_DIR + "/building_atlas.json")
	_atlas = load(ATLAS_DIR + "/" + String(meta["atlas"]))
	_sprites = meta["sprites"]
	_ppm = float(meta.get("ppm", 8.0))
	_ground = Node2D.new()
	_ground.name = "Ground"
	_ground.show_behind_parent = true
	add_child(_ground)
	_ground.draw.connect(_draw_ground)
	for sig: Signal in [EventBus.building_placed, EventBus.building_state_changed, EventBus.building_completed, EventBus.building_removed]:
		sig.connect(func(_id: int) -> void: queue_redraw())
	for sig: Signal in [EventBus.building_placed, EventBus.building_completed, EventBus.building_removed]:
		sig.connect(func(_id: int) -> void: _ground.queue_redraw())
	# a road being laid grows on the ground
	EventBus.building_state_changed.connect(func(id: int) -> void:
		if Session.has_game():
			var b := Session.current.world.building(id)
			if b and b.is_road():
				_ground.queue_redraw())
	EventBus.session_started.connect(func(_s: GameSession) -> void:
		queue_redraw()
		_ground.queue_redraw())
	EventBus.session_loaded.connect(func(_s: GameSession) -> void:
		queue_redraw()
		_ground.queue_redraw())


func _process(_delta: float) -> void:
	if _camera == null:
		return
	var mpp := _camera.meters_per_pixel()
	var fade := 1.0 - smoothstep(VISIBLE_MPP.x, VISIBLE_MPP.y, mpp)
	visible = fade > 0.001
	if absf(fade - _last_fade) > 0.01:
		_last_fade = fade
		modulate.a = fade
	if Session.has_game():
		var m := int(Session.current.calendar.date_of(Session.current.world.day)["month"])
		if m != _month:
			_month = m
			queue_redraw()
			_ground.queue_redraw()
		# the square widens and the roads are graded as the people grow: the ground follows, in steps
		var people := 0
		for s in Session.current.world.settlements:
			people += Session.current.world.people_of(s.id).size() / 20
		var key := "%d" % people
		if key != _ground_key:
			_ground_key = key
			_ground.queue_redraw()


func sprite_for(b: BuildingState, month: int) -> StringName:
	var def := b.def()
	if def.work_type() == &"farm":
		# the farmstead alone: the field under it is drawn by FieldPainter, strip by strip, by the season
		if _sprites.has("farmstead"):
			return &"farmstead_1" if KDRng.hash01(b.id, 2, 9123) < 0.5 and _sprites.has("farmstead_1") else &"farmstead"
		var sow := int(def.work.get("sow_month", 3))
		var harvest := int(def.work.get("harvest_month", 8))
		if month >= harvest and b.crop >= 1.0:
			return &"farm_ripe"
		if month >= sow and month < harvest:
			return &"farm_green"
		return &"farm_bare"
	return _variant(def.sprite, b.id)


## How the picture of a building departs from its logical footprint: a small shift (at most 4% of its size),
## a turn of a couple of degrees, a scale within 5%. Only the picture: placement, work and paths use the
## footprint. The same building always gets the same values (its id), so nothing moves after a reload.
static func visual_of(b: BuildingState) -> Dictionary:
	var fp := b.def().footprint
	var span := minf(fp.x, fp.y)
	var off := Vector2(KDRng.hash01(b.id, 11, 7001) - 0.5, KDRng.hash01(b.id, 12, 7001) - 0.5) * 2.0 * span * 0.04
	var turn := (KDRng.hash01(b.id, 13, 7001) - 0.5) * 2.0 * deg_to_rad(2.5)
	var scale := 1.0 + (KDRng.hash01(b.id, 14, 7001) - 0.5) * 2.0 * 0.05
	if b.def_id in [&"keep", &"farm"]:
		turn *= 0.3   # the big ones hardly turn: a keep leaning is a keep falling
		scale = 1.0 + (scale - 1.0) * 0.4
	return {"offset": off, "turn": turn, "scale": scale}


## The same building drawn more than one way: when the atlas has `house_1`, `house_2`… next to `house`, every
## building keeps one of them for good, chosen by its id — a village of identical clones reads as a prototype.
func _variant(sprite: StringName, building_id: int) -> StringName:
	var count := int(_variant_count.get(sprite, -1))
	if count < 0:
		count = 0
		while _sprites.has("%s_%d" % [sprite, count + 1]):
			count += 1
		_variant_count[sprite] = count
	if count == 0:
		return sprite
	var pick := mini(int(KDRng.hash01(building_id, 17, 9173) * float(count + 1)), count)
	return sprite if pick == 0 else StringName("%s_%d" % [sprite, pick])


static func site_sprite(size: Vector2) -> StringName:
	var area := size.x * size.y
	if area <= 20.0:
		return &"site_s"
	if area <= 70.0:
		return &"site_m"
	if area <= 150.0:
		return &"site_l"
	return &"site_xl"


func _draw_sprite(id: StringName, ground_center: Vector2, reveal: float = 1.0, alpha: float = 1.0, look: Dictionary = {}) -> void:
	var s: Dictionary = _sprites.get(String(id), {})
	if s.is_empty():
		return
	var rect: Array = s["rect"]
	var pv: Array = s["pivot"]
	var src := Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	# drawn around a local origin at the ground point, with the building's own small shift, turn and scale
	if not look.is_empty():
		draw_set_transform(ground_center + look["offset"], float(look["turn"]), Vector2.ONE * float(look["scale"]))
	else:
		draw_set_transform(ground_center, 0.0, Vector2.ONE)
	var dst := Rect2(-Vector2(float(pv[0]), float(pv[1])) / _ppm, src.size / _ppm)
	if reveal < 1.0:
		# grow from the bottom: keep the lower part of the sprite
		var keep_h := src.size.y * clampf(reveal, 0.0, 1.0)
		src = Rect2(src.position.x, src.end.y - keep_h, src.size.x, keep_h)
		dst = Rect2(dst.position.x, dst.end.y - keep_h / _ppm, dst.size.x, keep_h / _ppm)
		if keep_h < 0.5:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
	draw_texture_rect_region(_atlas, dst, src, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	if not Session.has_game():
		return
	var world := Session.current.world
	var list: Array = []
	for b: BuildingState in world.buildings.values():
		if not b.is_road():
			list.append(b)
	list.sort_custom(func(a: BuildingState, b: BuildingState) -> bool: return a.pos.y + a.def().footprint.y * 0.5 < b.pos.y + b.def().footprint.y * 0.5)
	for b: BuildingState in list:
		var def := b.def()
		var look := visual_of(b)
		if b.is_active():
			_draw_sprite(sprite_for(b, _month), b.pos, 1.0, 1.0, look)
			continue
		var fp := def.footprint
		_draw_sprite(site_sprite(fp), b.pos)
		var materials := 0.0
		var total := 0.0
		for res: StringName in def.cost.keys():
			total += float(def.cost[res])
			materials += float(b.delivered.get(res, 0))
		var prog := b.progress()
		if prog > 0.0:
			_draw_sprite(sprite_for(b, _month), b.pos, 0.15 + 0.85 * prog, 0.95, look)
		_draw_scaffold(b.rect(), prog)
		if total > 0.0 and materials < total:
			# a pile grows as the materials arrive
			var pile := clampf(materials / total, 0.0, 1.0)
			var at := b.rect().end - Vector2(1.6, 0.9)
			draw_rect(Rect2(at - Vector2(1.8 * pile + 0.4, 0.6), Vector2(1.8 * pile + 0.4, 0.6)), Color(0.55, 0.40, 0.24, 0.9))


## Everything that lies on the ground, drawn by the Ground child (behind the buildings).
func _draw_ground() -> void:
	if not Session.has_game():
		return
	_ci = _ground
	var world := Session.current.world
	# the version of the buildings starts again in every world: a loaded game must not inherit the paths of the last
	if world.buildings_version != _paths_version or world.get_instance_id() != _paths_world:
		_paths_version = world.buildings_version
		_paths_world = world.get_instance_id()
		_paths.clear()
		FieldPainter.clear_cache()
		_yards = yards(world)
		for s in world.settlements:
			_paths[s.id] = footpaths(world, s)
			# the path to the water: to the water point of the nucleus (Rebirth, Phase 3), else to the nearest bank
			var landing := Nucleus.water_path(world, s)
			if landing.is_empty():
				landing = river_path(world, s)
			else:
				landing.append(6)
			if not landing.is_empty():
				(_paths[s.id] as Array).append(landing)
		_trails = {}
		for s in world.settlements:
			_trails[s.id] = Nucleus.trails(world, s)
	# the open square at the heart of each settlement, the first trails out of it, then the worn footpaths and
	# the roads: all on the ground
	for s in world.settlements:
		_draw_square(s, world.people_of(s.id).size(), Nucleus.hearth_of(world, s) != null)
	for s in world.settlements:
		# the trails the founders walked toward the wood and the fields: where the village will grow; they fade
		# as the streets of a real village take their place
		var fade := 1.0 - smoothstep(30.0, 90.0, float(world.people_of(s.id).size()))
		if fade <= 0.01:
			continue
		for tr: Array in _trails.get(s.id, []):
			_draw_track(tr[0], tr[1], 0.55, Color(PATH_FILL, PATH_FILL.a * 0.8 * fade), Color(PATH_EDGE, PATH_EDGE.a * fade),
				0.35, int(tr[0].x * 5.0 + tr[1].y * 11.0), false, 0.12)
	for s in world.settlements:
		for edge: Array in _paths.get(s.id, []):
			var served := float(edge[2]) if edge.size() > 2 else 1.0
			var half := minf(0.65 + 0.32 * log(served), 2.4)
			var fill := PATH_FILL.lerp(Color(0.62, 0.52, 0.36, 0.78), clampf(log(served) / 3.5, 0.0, 1.0))
			_draw_track(edge[0], edge[1], half, fill, PATH_EDGE, 0.30, int(edge[0].x * 7.0 + edge[0].y * 13.0), served >= 12.0, 0.10)
	var level := {}
	for s in world.settlements:
		level[s.id] = road_level(world.people_of(s.id).size())
	var list: Array = []
	for b: BuildingState in world.buildings.values():
		if b.is_road():
			_draw_road(b, int(level.get(b.settlement, 1)))
		else:
			list.append(b)
	for yard in _yards:
		_draw_yard(yard)
	var key := "%d|%d|%d" % [world.get_instance_id(), world.buildings_version, _month]
	if key != _fields_key:
		_fields_key = key
		var farms: Array = []
		for b: BuildingState in list:
			if b.is_active() and b.def().work_type() == &"farm" and _sprites.has("farmstead"):
				farms.append(b)
		_fields_mesh = FieldPainter.build_mesh(farms, _month, true)
	if _fields_mesh and _fields_mesh.get_surface_count() > 0:
		_ground.draw_mesh(_fields_mesh, null)
	for b: BuildingState in list:
		_draw_ground_patch(b)
		if _stands_up(b):
			var look := visual_of(b)
			_draw_shadow(b.pos + look["offset"] + Vector2(0.0, b.def().footprint.y * 0.20), b.def().footprint.x * float(look["scale"]), _height_of(b))
	_ci = self


# --- roads and footpaths (Phase 18: they were flat brown rectangles) -------------------------------------

const PATH_FILL := Color(0.56, 0.47, 0.32, 0.42)
const PATH_EDGE := Color(0.40, 0.33, 0.22, 0.16)
const ROAD_STYLES := [
	# a track: narrow, grass between the ruts
	{"width": 0.62, "fill": Color(0.58, 0.48, 0.32, 0.78), "edge": Color(0.38, 0.30, 0.19, 0.30), "jitter": 0.30, "ruts": false},
	# a dirt road: wheel ruts, a darker verge
	{"width": 0.85, "fill": Color(0.62, 0.50, 0.33, 0.95), "edge": Color(0.36, 0.28, 0.18, 0.45), "jitter": 0.22, "ruts": true},
	# a main road: packed gravel, lighter, with a firm edge
	{"width": 1.0, "fill": Color(0.70, 0.62, 0.48, 1.0), "edge": Color(0.42, 0.37, 0.30, 0.65), "jitter": 0.12, "ruts": true},
]


## How grand the roads of a settlement look: a track for a hamlet, a dirt road for a village, gravel for a town.
static func road_level(people: int) -> int:
	if people < 30:
		return 0
	if people < 150:
		return 1
	return 2


func _draw_road(r: BuildingState, level: int) -> void:
	var style: Dictionary = ROAD_STYLES[clampi(level, 0, ROAD_STYLES.size() - 1)]
	var half := BuildingState.road_width() * 0.5 * float(style["width"])
	var done := r.progress()
	var end := r.a.lerp(r.b, done)
	if done < 0.999:
		# the line of the road still to be laid, pegged out on the grass
		_draw_track(end, r.b, half * 0.7, Color(0.42, 0.36, 0.26, 0.22), Color(0, 0, 0, 0), 0.2, r.id, false)
	if done > 0.0:
		# a road bends a little where it was worn (the logical line stays straight: walking speed uses it)
		var bend := 0.05 if level < 2 else 0.025
		_draw_track(r.a, end, half, style["fill"], style["edge"], float(style["jitter"]), r.id, bool(style["ruts"]), bend)
		# where it starts and ends the ground is trodden wider: a small clearing, not a square cut
		for p: Vector2 in [r.a, end]:
			_ci.draw_set_transform(p, 0.0, Vector2.ONE)
			_ci.draw_circle(Vector2.ZERO, half * 1.9, Color(style["fill"], float((style["fill"] as Color).a) * 0.55))
			_ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A strip of trodden or laid earth from a to b with irregular edges (the same noise for the same strip, so it
## does not shimmer), an optional darker verge and two wheel ruts. Built around a local origin: a polygon of
## a few metres at world coordinates of 34 km loses its points to float precision.
func _draw_track(a: Vector2, b: Vector2, half: float, fill: Color, edge: Color, jitter: float, seed_value: int, ruts: bool,
		bend: float = 0.0) -> void:
	var length := a.distance_to(b)
	if length < 0.3:
		return
	var dir := (b - a) / length
	var normal := Vector2(-dir.y, dir.x)
	var n := maxi(int(ceil(length / 1.4)), 2)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	# a gentle S or C: two sine arcs of deterministic height, zero at the ends so the track still meets its doors
	var arc1 := (KDRng.hash01(seed_value, 1, 4417) - 0.5) * 2.0 * bend * length
	var arc2 := (KDRng.hash01(seed_value, 2, 4417) - 0.5) * bend * length * 0.8
	var centre := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		centre.append(normal * (arc1 * sin(t * PI) + arc2 * sin(t * TAU)))
	for i in n + 1:
		var t := float(i) / float(n)
		var p := dir * (length * t) + centre[i]
		var wl := half * (1.0 + (KDRng.hash01(seed_value, i, 311) - 0.5) * 2.0 * jitter)
		var wr := half * (1.0 + (KDRng.hash01(seed_value, i, 577) - 0.5) * 2.0 * jitter)
		# the ends round off instead of stopping square
		var taper := minf(minf(t, 1.0 - t) * length / maxf(half, 0.01), 1.0)
		taper = sqrt(taper) if taper < 1.0 else 1.0
		left.append(p + normal * wl * maxf(taper, 0.35))
		right.append(p - normal * wr * maxf(taper, 0.35))
	_ci.draw_set_transform(a, 0.0, Vector2.ONE)
	if edge.a > 0.0:
		var verge := PackedVector2Array()
		for i in left.size():
			verge.append(left[i] + normal * 0.35)
		for i in range(right.size() - 1, -1, -1):
			verge.append(right[i] - normal * 0.35)
		_ci.draw_colored_polygon(verge, edge)
	var body := PackedVector2Array(left)
	for i in range(right.size() - 1, -1, -1):
		body.append(right[i])
	_ci.draw_colored_polygon(body, fill)
	if ruts and length > 2.0:
		var rut := Color(fill.r * 0.72, fill.g * 0.70, fill.b * 0.68, fill.a * 0.8)
		for side: float in [-0.42, 0.42]:
			var line := PackedVector2Array()
			for i in range(1, n):
				line.append(dir * (length * float(i) / float(n)) + centre[i] + normal * half * side)
			if line.size() >= 2:
				_ci.draw_polyline(line, rut, 0.22)
	_ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The paths people wear between the doors of a settlement: the shortest net that links every door to the
## others and to the common fire (a minimum spanning tree), never across the river and never too long. Only
## drawn: walking speed still comes from the roads the player lays.
static func footpaths(world: WorldState, s: SettlementState) -> Array:
	var nodes := PackedVector2Array([s.center])
	var wd := SettlementSim.ground(world)
	for b in world.buildings_of(s.id):
		if b.is_road() or not b.is_active():
			continue
		if b.def_id == Nucleus.HEARTH or b.def_id == Nucleus.WATER_POINT:
			continue   # the fire is the centre the paths start from; the water has its own path
		nodes.append(b.pos + Vector2(0.0, b.def().footprint.y * 0.5 + 0.6))   # in front of the door
	var n := nodes.size()
	if n < 2:
		return []
	var in_tree := PackedByteArray()
	in_tree.resize(n)
	var best := PackedFloat32Array()
	var parent := PackedInt32Array()
	best.resize(n)
	parent.resize(n)
	for i in n:
		best[i] = INF
		parent[i] = -1
	best[0] = 0.0
	var out: Array = []
	var order: Array[int] = []
	for step in n:
		var pick := -1
		for i in n:
			if in_tree[i] == 0 and (pick < 0 or best[i] < best[pick]):
				pick = i
		if pick < 0 or best[pick] == INF:
			break
		in_tree[pick] = 1
		order.append(pick)
		for i in n:
			if in_tree[i] == 1:
				continue
			var d := nodes[pick].distance_to(nodes[i])
			if d < best[i] and d < 140.0 and not _crosses_river(wd, nodes[pick], nodes[i]):
				best[i] = d
				parent[i] = pick
	# how many doors each path serves (the size of the branch behind it): the paths near the centre carry
	# the whole village and are worn into streets, the last ones to a single farm stay a trace in the grass
	var served := PackedInt32Array()
	served.resize(n)
	for i in range(order.size() - 1, -1, -1):
		var node := order[i]
		served[node] += 1
		if parent[node] >= 0:
			served[parent[node]] += served[node]
	for node in order:
		if parent[node] >= 0:
			out.append([nodes[parent[node]], nodes[node], served[node]])
	return out


## A garden behind or beside every house, where there is room: tilled earth in rows and a fence of posts. Only
## drawn, chosen by the id of the house, and never over another building, a road, a path's door or the river.
static func yards(world: WorldState) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var wd := SettlementSim.ground(world)
	var roads := SettlementSim.active_roads(world)
	for b: BuildingState in world.buildings.values():
		if b.def_id != &"house" or not b.is_active():
			continue
		var fp := b.def().footprint
		var w := 5.0 + 2.5 * KDRng.hash01(b.id, 5, 311)
		var h := 4.0 + 2.0 * KDRng.hash01(b.id, 6, 311)
		var options: Array[Rect2] = [
			Rect2(b.pos.x - w * 0.5, b.pos.y - fp.y * 0.5 - 1.2 - h, w, h),     # behind
			Rect2(b.pos.x + fp.x * 0.5 + 1.2, b.pos.y - h * 0.5, w, h),         # to the east
			Rect2(b.pos.x - fp.x * 0.5 - 1.2 - w, b.pos.y - h * 0.5, w, h),     # to the west
		]
		var first := int(KDRng.hash01(b.id, 7, 311) * 3.0) % 3
		for k in 3:
			var r: Rect2 = options[(first + k) % 3]
			if _yard_fits(world, wd, roads, r, out):
				out.append(r)
				break
	return out


static func _yard_fits(world: WorldState, wd: WorldData, roads: Array[BuildingState], r: Rect2, taken: Array[Rect2]) -> bool:
	for other in taken:
		if other.grow(1.0).intersects(r):
			return false
	var probes := [r.get_center(), r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]
	for p: Vector2 in probes:
		if wd.water_at(p) != WorldData.WATER_LAND or wd.river_clearance(p) < 1.5:
			return false
		for road in roads:
			if road.covers(p, 1.0):
				return false
	for other: BuildingState in world.buildings.values():
		if not other.is_road() and other.rect().grow(1.0).intersects(r):
			return false
	return true


const YARD_SOIL := Color(0.45, 0.34, 0.22, 0.85)
const YARD_ROW := Color(0.33, 0.25, 0.16, 0.55)
const YARD_GREEN := Color(0.40, 0.52, 0.25, 0.8)
const FENCE := Color(0.36, 0.26, 0.16, 0.95)


func _draw_yard(r: Rect2) -> void:
	# built around a local origin: small shapes at world coordinates of 34 km lose their points
	_ci.draw_set_transform(r.position, 0.0, Vector2.ONE)
	var size := r.size
	_ci.draw_rect(Rect2(Vector2.ZERO, size), YARD_SOIL)
	var rows := int(size.y / 0.9)
	for i in rows:
		var y := 0.45 + i * 0.9
		_ci.draw_line(Vector2(0.4, y), Vector2(size.x - 0.4, y), YARD_ROW, 0.22)
		# a few rows already green: cabbages, beans
		if (i + int(r.position.x)) % 3 == 0:
			_ci.draw_line(Vector2(0.6, y - 0.25), Vector2(size.x - 0.6, y - 0.25), YARD_GREEN, 0.3)
	# the fence: rails and a post every metre and a half, a gap for the gate on the side nearest the house
	var corners := [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		if i == 2:
			var mid := a.lerp(b, 0.5)
			_ci.draw_line(a, mid + (a - b).normalized() * 0.7, FENCE, 0.14)
			_ci.draw_line(mid - (a - b).normalized() * 0.7, b, FENCE, 0.14)
		else:
			_ci.draw_line(a, b, FENCE, 0.14)
		var n := maxi(int(a.distance_to(b) / 1.5), 1)
		for k in n + 1:
			var p := a.lerp(b, float(k) / float(n))
			_ci.draw_rect(Rect2(p - Vector2(0.14, 0.14), Vector2(0.28, 0.28)), FENCE)
	_ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The open ground at the heart of a settlement, where the paths meet: a patch of trodden earth around the
## common fire (or the well, or the keep), growing with the people — a hamlet has a clearing, a village a
## square, a borough a market place.
func _draw_square(s: SettlementState, people: int, has_hearth: bool = false) -> void:
	if people < 8 and not has_hearth:
		return
	var r := 7.0 + minf(float(people), 400.0) * 0.035
	if has_hearth:
		# the square of the common fire: from the first day, as wide as the ground nobody may build on
		r = maxf(r, Nucleus.square_radius() + 1.5)
	# stamped with soft stains (Rebirth, Phase 3: two flat polygons one over the other read as a cut-out): a wide one
	# in the middle and a ring of smaller ones pushed out by the id, so the edge is ragged and soft
	var blob := NucleusLayer.soft_blob()
	_ci.draw_texture_rect(blob, Rect2(s.center - Vector2(r * 1.25, r * 1.05), Vector2(r * 2.5, r * 2.1)), false,
		Color(0.56, 0.47, 0.32, 0.62))
	for k in 7:
		var a := TAU * (float(k) + KDRng.hash01(s.id, 90 + k, 7005) * 0.6) / 7.0
		var d := r * (0.45 + 0.3 * KDRng.hash01(s.id, 100 + k, 7005))
		var size := r * (0.8 + 0.5 * KDRng.hash01(s.id, 110 + k, 7005))
		var at := s.center + Vector2(cos(a), sin(a) * 0.82) * d
		_ci.draw_texture_rect(blob, Rect2(at - Vector2(size, size * 0.84) * 0.5, Vector2(size, size * 0.84)), false,
			Color(0.54, 0.45, 0.30, 0.42))
	# the trodden middle, lighter and dustier
	_ci.draw_texture_rect(blob, Rect2(s.center - Vector2(r * 0.7, r * 0.55), Vector2(r * 1.4, r * 1.1)), false,
		Color(0.64, 0.55, 0.39, 0.45))


## The path the settlement wore down to the water: from the square to the nearest point of the river bank, if the
## river is close (people fetch water, wash, water the animals). Returns [from, to] or [].
static func river_path(world: WorldState, s: SettlementState) -> Array:
	var wd := SettlementSim.ground(world)
	var start := s.center
	if wd.river_clearance(start) > 260.0:
		return []
	var best := Vector2.INF
	var best_d := INF
	for k in 24:
		var dir := Vector2.from_angle(TAU * float(k) / 24.0)
		var d := 6.0
		while d < 260.0:
			var p := start + dir * d
			if wd.river_clearance(p) < 2.0:
				if d < best_d:
					best_d = d
					best = start + dir * maxf(d - 2.5, 4.0)
				break
			d += 4.0
	if best == Vector2.INF:
		return []
	# a path that would cut through a building goes round it: here it simply is not drawn
	for b: BuildingState in world.buildings_of(s.id):
		if b.is_road():
			continue
		if segment_hits_rect(start, best, b.rect().grow(0.5)):
			return []
	return [start, best, 6]   # six doors worth of traffic: everybody goes to the water


static func segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var c: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return true
	return false


static func _crosses_river(wd: WorldData, a: Vector2, b: Vector2) -> bool:
	var n := int(ceil(a.distance_to(b) / 3.0))
	for i in n + 1:
		if wd.river_clearance(a.lerp(b, float(i) / float(maxi(n, 1)))) < 0.5:
			return true
	return false


func _draw_scaffold(r: Rect2, prog: float) -> void:
	var col := Color(0.42, 0.30, 0.18, 0.9)
	var h := lerpf(1.2, 4.5, clampf(prog, 0.0, 1.0))
	for x: float in [r.position.x + 0.4, r.end.x - 0.4]:
		draw_line(Vector2(x, r.end.y), Vector2(x, r.end.y - h), col, 0.18)
	var y := r.end.y - 1.0
	while y > r.end.y - h:
		draw_line(Vector2(r.position.x + 0.2, y), Vector2(r.end.x - 0.2, y), col, 0.14)
		y -= 1.3


# --- what lies on the ground: the trodden earth and the shadow ------------------------------------------

## The sun of the map comes from the north-west, the same direction the terrain shader lights the relief
## with: everything that stands casts its shadow to the south-east, or the village looks pasted on the grass.
const SUN := Vector2(0.42, 0.30)
const SHADOW := Color(0.10, 0.09, 0.06, 0.26)
const TRODDEN := Color(0.46, 0.38, 0.25, 0.34)


## Bare earth around what is lived in: nobody keeps the grass under his own door. A ploughed field is already
## ground: it gets neither the trodden ring nor a shadow.
func _stands_up(b: BuildingState) -> bool:
	var def := b.def()
	if def.work_type() == &"farm" or b.is_road():
		return false
	if not _sprites.has(String(sprite_for(b, _month))):
		return false   # drawn by another layer (the fire and the water point of the nucleus: NucleusLayer)
	return _height_of(b) > def.footprint.y * 0.45


## The trodden earth around a building: an irregular patch, wider in front of the door where people come and go,
## never the same twice (its outline comes from the id).
func _draw_ground_patch(b: BuildingState) -> void:
	if not _stands_up(b):
		return
	var fp := b.def().footprint
	var r := minf(fp.x, fp.y) * 0.78 + 1.2
	var centre: Vector2 = b.pos + visual_of(b)["offset"] + Vector2(0.0, fp.y * 0.16)
	# soft stains, not a polygon (Rebirth, Phase 3): one under the building, one wider in front of the door where
	# people come and go, one to a side chosen by the id
	var blob := NucleusLayer.soft_blob()
	var w := r * 2.3
	_ci.draw_texture_rect(blob, Rect2(centre - Vector2(w, w * 0.8) * 0.5, Vector2(w, w * 0.8)), false, TRODDEN)
	var front := centre + Vector2((KDRng.hash01(b.id, 61, 7003) - 0.5) * r * 0.5, fp.y * 0.45)
	_ci.draw_texture_rect(blob, Rect2(front - Vector2(r * 1.6, r * 0.9) * 0.5, Vector2(r * 1.6, r * 0.9)), false, TRODDEN)
	var side := centre + Vector2((1.0 if KDRng.hash01(b.id, 62, 7003) < 0.5 else -1.0) * fp.x * 0.55, fp.y * 0.1)
	_ci.draw_texture_rect(blob, Rect2(side - Vector2(r, r * 0.8) * 0.5, Vector2(r, r * 0.8)), false,
		Color(TRODDEN, TRODDEN.a * 0.8))


## The shadow of a standing thing: an ellipse at its feet, leaning away from the sun. Drawn as a circle
## scaled around a local origin: an ellipse of half a metre built at world coordinates of 34 km loses its
## points to float precision and the triangulation fails.
func _draw_shadow(at: Vector2, width_m: float, height_m: float) -> void:
	var lean := SUN * height_m * 0.42
	var rx := maxf(width_m * 0.55, 0.3)
	var ry := maxf(width_m * 0.20, 0.35)
	_ci.draw_set_transform(at + lean, 0.0, Vector2(rx, ry))
	_ci.draw_circle(Vector2.ZERO, 1.0, SHADOW)
	_ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## How tall a thing stands, from the sprite that draws it: a keep throws more shade than a well.
func _height_of(b: BuildingState) -> float:
	var s: Dictionary = _sprites.get(String(sprite_for(b, _month)), {})
	if s.is_empty():
		return b.def().footprint.y
	var size: Array = s.get("size_m", [b.def().footprint.x, b.def().footprint.y])
	return float(size[1])

