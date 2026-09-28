class_name SettlementProps
extends Node2D
## The small things around the buildings (world art pass): a woodpile by the woodcutter, stumps and trunks, crates
## and sacks by the stores, hay and a cart at the farmstead, coal by the smithy, a barrel by a house, market
## stalls on the square of a borough. Only drawn — no collision, no gameplay — and only close to the ground.
##
## Each building gets its props from its kind and its id, always the same ones in the same places, and never on
## another building, a road, a garden or the river bank.

const ATLAS_DIR := "res://assets/buildings"
const SHOW_MPP := Vector2(1.3, 1.9)   ## fully visible below x, gone above y
## What each kind of building keeps around it: [prop, chance]. The first that fits in a free spot is used.
const BY_KIND := {
	&"house": [["barrels_0", 0.35], ["woodpile_0", 0.3]],
	&"woodcutter": [["logs_0", 0.9], ["woodpile_1", 0.8], ["stump_1", 0.7], ["stump_0", 0.6], ["logs_1", 0.5]],
	&"quarry": [["stone_1", 0.9], ["cart_0", 0.5], ["stone_0", 0.6]],
	&"mine": [["stone_1", 0.8], ["cart_0", 0.6], ["coal_1", 0.4]],
	&"farm": [["hay_1", 0.7], ["cart_1", 0.55], ["hay_0", 0.4]],
	&"bakery": [["sacks_0", 0.8], ["woodpile_0", 0.7], ["barrels_0", 0.4]],
	&"smith": [["coal_0", 0.9], ["barrels_1", 0.5], ["crates_0", 0.4]],
	&"storehouse": [["crates_1", 0.9], ["sacks_1", 0.7], ["barrels_1", 0.6], ["cart_0", 0.4]],
	&"granary": [["sacks_1", 0.9], ["sacks_0", 0.6], ["cart_1", 0.4]],
	&"barracks": [["crates_0", 0.7], ["barrels_0", 0.6], ["woodpile_0", 0.4]],
	&"keep": [["cart_0", 0.6], ["barrels_1", 0.6], ["crates_1", 0.5]],
	&"camp_store": [["woodpile_0", 0.8], ["sacks_0", 0.7]],
	&"well": [],
}
## People needed for a market on the square, and how many stalls.
const MARKET_PEOPLE := 120

@export var camera_path: NodePath

var _camera: WorldCamera
var _atlas: Texture2D
var _sprites: Dictionary = {}
var _ppm := 16.0
var _items: Array = []          # [y, sprite, pos, flip]
var _version := -1
var _world_id := 0
var _people_step := -1


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	var meta: Dictionary = Defs.read_json(ATLAS_DIR + "/props_atlas.json")
	if meta.is_empty():
		return
	_atlas = load(ATLAS_DIR + "/" + String(meta["atlas"]))
	_sprites = meta["sprites"]
	_ppm = float(meta.get("ppm", 16.0))
	EventBus.session_started.connect(func(_s: GameSession) -> void: _version = -1)
	EventBus.session_loaded.connect(func(_s: GameSession) -> void: _version = -1)


func _process(_delta: float) -> void:
	if _camera == null or not Session.has_game() or _atlas == null:
		visible = false
		return
	var mpp := _camera.meters_per_pixel()
	var fade := 1.0 - smoothstep(SHOW_MPP.x, SHOW_MPP.y, mpp)
	visible = fade > 0.01
	if not visible:
		return
	modulate.a = fade
	var world := Session.current.world
	var people := world.people_of(world.settlements[0].id).size() if not world.settlements.is_empty() else 0
	if world.buildings_version != _version or people / 40 != _people_step or world.get_instance_id() != _world_id:
		_version = world.buildings_version
		_world_id = world.get_instance_id()
		_people_step = people / 40
		_items = props(world)
		queue_redraw()


## Every prop of every settlement: [y, sprite, pos, flip], sorted by depth.
static func props(world: WorldState) -> Array:
	var out: Array = []
	var taken: Array[Rect2] = []
	var roads := SettlementSim.active_roads(world)
	var wd := SettlementSim.ground(world)
	var yards := SettlementLayer.yards(world)
	for b: BuildingState in world.buildings.values():
		if not b.is_road():
			taken.append(b.rect().grow(0.8))
	for y in yards:
		taken.append(y)
	var ids := world.buildings.keys()
	ids.sort()
	for id: int in ids:
		var b: BuildingState = world.buildings[id]
		if b.is_road() or not b.is_active():
			continue
		var wants: Array = BY_KIND.get(b.def_id, [])
		if wants.is_empty():
			continue
		var spots := _spots(b)
		var k := 0
		for want: Array in wants:
			if KDRng.hash01(b.id, k, 5511) >= float(want[1]):
				k += 1
				continue
			for s in spots.size():
				var spot: Vector2 = spots[(s + int(KDRng.hash01(b.id, k, 5512) * spots.size())) % spots.size()]
				var foot := Rect2(spot - Vector2(1.4, 0.9), Vector2(2.8, 1.4))
				if _blocked(foot, taken, roads, wd):
					continue
				taken.append(foot)
				out.append([spot.y, String(want[0]), spot, KDRng.hash01(b.id, k, 5513) < 0.5])
				break
			k += 1
	# the market: stalls around the square of a settlement big enough to have one
	for s in world.settlements:
		var people := world.people_of(s.id).size()
		if people < MARKET_PEOPLE:
			continue
		var stalls := mini(2 + (people - MARKET_PEOPLE) / 80, 6)
		for i in 12:
			if stalls <= 0:
				break
			var a := TAU * (float(i) / 12.0 + KDRng.hash01(s.id, i, 5521) * 0.05)
			var spot := s.center + Vector2(cos(a), sin(a) * 0.8) * (9.0 + KDRng.hash01(s.id, i, 5522) * 4.0)
			var foot := Rect2(spot - Vector2(2.0, 1.0), Vector2(4.0, 1.6))
			if _blocked(foot, taken, roads, wd):
				continue
			taken.append(foot)
			out.append([spot.y, "stall_%d" % (i % 2), spot, false])
			stalls -= 1
	out.sort_custom(func(a: Array, c: Array) -> bool: return a[0] < c[0])
	return out


## Where a prop may stand beside a building: along its sides and in front, never behind (the roof is there).
static func _spots(b: BuildingState) -> Array[Vector2]:
	var r := b.rect()
	var out: Array[Vector2] = []
	var cy := r.get_center().y
	if b.def_id == &"farm":
		# in the yard of the farmstead, beside the house and the haystack
		var yard_y := r.position.y + 7.5
		for x in [r.position.x + 3.0, r.end.x - 3.0, r.get_center().x + 5.0, r.get_center().x - 5.0]:
			out.append(Vector2(x, yard_y))
		return out
	for t in [0.35, 0.8]:
		out.append(Vector2(r.position.x - 1.8, lerpf(cy, r.end.y, t)))
		out.append(Vector2(r.end.x + 1.8, lerpf(cy, r.end.y, t)))
	out.append(Vector2(r.position.x + r.size.x * 0.2, r.end.y + 1.6))
	out.append(Vector2(r.end.x - r.size.x * 0.2, r.end.y + 1.6))
	return out


static func _blocked(foot: Rect2, taken: Array[Rect2], roads: Array[BuildingState], wd: WorldData) -> bool:
	for t in taken:
		if t.intersects(foot):
			return true
	for p: Vector2 in [foot.get_center(), foot.position, foot.end]:
		if wd.water_at(p) != WorldData.WATER_LAND or wd.river_clearance(p) < 1.5:
			return true
		for road in roads:
			if road.covers(p, 0.8):
				return true
	return false


func _draw() -> void:
	for it: Array in _items:
		var s: Dictionary = _sprites.get(String(it[1]), {})
		if s.is_empty():
			continue
		var rect: Array = s["rect"]
		var pv: Array = s["pivot"]
		var src := Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
		var size := src.size / _ppm
		var feet: Vector2 = it[2]
		var offset := Vector2(float(pv[0]), float(pv[1])) / _ppm
		if bool(it[3]):
			# mirrored: the same crate seen from the other side
			draw_texture_rect_region(_atlas, Rect2(Vector2(feet.x + offset.x, feet.y - offset.y), Vector2(-size.x, size.y)), src)
		else:
			draw_texture_rect_region(_atlas, Rect2(feet - offset, size), src)

