class_name SettlementMarks
extends Node2D
## Settlements seen from afar (Phase 18). Between the zoom of the houses and the zoom of the map a village was
## a few pixels lost under the woods. Here every real building is drawn as a simple block that never gets
## smaller than a few pixels — a roof, a field in its season, the keep in stone — over the trodden ground
## around the doors, with its roads: a hamlet reads as a hamlet and a town as a town, and the growth of the
## place (six founders, a village of thirty, a borough of two hundred, a town of a thousand) is seen from the
## height of a province. Only drawn: nothing here exists that is not a building of the world.

## Fades in quickly, over the sprites of SettlementLayer that fade out a little later underneath: two layers at
## half strength at the same zoom read as a washed-out smudge (seen at 2.5 m/px)
const SHOW_MPP := Vector2(2.15, 2.4)
const HIDE_MPP := Vector2(26.0, 40.0)   ## fades out between these (the map pins take over)
const MIN_PX := 3.2                     ## a building is never smaller than this on screen
## Opaque, so the patches of neighbouring buildings merge into one ground instead of stacking into spots.
const GROUND := Color(0.64, 0.59, 0.44)
const GROUND_EDGE := Color(0.47, 0.47, 0.31)
const ROOFS := [Color(0.62, 0.30, 0.22), Color(0.55, 0.33, 0.24), Color(0.66, 0.40, 0.26), Color(0.50, 0.27, 0.20)]
const STONE := Color(0.62, 0.60, 0.56)
const TIMBER := Color(0.47, 0.35, 0.24)
const ROAD := Color(0.66, 0.56, 0.40, 0.9)

@export var camera_path: NodePath

var _camera: WorldCamera
var _drawn_mpp := -1.0
var _version := -1
var _world_id := 0
var _month := -1
var _drawn_view := Rect2()


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	EventBus.session_started.connect(func(_s: GameSession) -> void: queue_redraw())
	EventBus.session_loaded.connect(func(_s: GameSession) -> void: queue_redraw())


static func fade_at(mpp: float) -> float:
	return smoothstep(SHOW_MPP.x, SHOW_MPP.y, mpp) * (1.0 - smoothstep(HIDE_MPP.x, HIDE_MPP.y, mpp))


func _process(_delta: float) -> void:
	if _camera == null or not Session.has_game():
		visible = false
		return
	var mpp := _camera.meters_per_pixel()
	var fade := fade_at(mpp)
	visible = fade > 0.001
	if not visible:
		return
	modulate.a = fade
	var world := Session.current.world
	var month := int(Session.current.calendar.date_of(world.day)["month"])
	var view := _camera.visible_world_rect()
	# the blocks keep their size on screen: redraw when the zoom has moved enough, when the buildings or the
	# season change, or when the view leaves what was drawn
	if absf(mpp - _drawn_mpp) > _drawn_mpp * 0.08 or world.buildings_version != _version or month != _month \
			or world.get_instance_id() != _world_id \
			or not _drawn_view.encloses(view):
		_drawn_mpp = mpp
		_version = world.buildings_version
		_world_id = world.get_instance_id()
		_month = month
		_drawn_view = view.grow(maxf(view.size.x, view.size.y) * 0.5)
		queue_redraw()


func _draw() -> void:
	if not Session.has_game() or _camera == null:
		return
	var world := Session.current.world
	var mpp := maxf(_drawn_mpp, 0.1)
	var min_m := MIN_PX * mpp
	for s in world.settlements:
		var list: Array[BuildingState] = world.buildings_of(s.id)
		if list.is_empty() or not _drawn_view.grow(600.0).has_point(s.center):
			continue
		# the trodden ground around the doors: overlapping patches make the shape of the place — first every
		# rim, then every fill, so the rims show only on the outside
		var wd := SettlementSim.ground(world)
		for pass_i in 2:
			for b in list:
				if b.is_road() or b.def().work_type() == &"farm":
					continue   # a farm is its field, drawn by FieldPainter: no disc of trodden earth under it
				var fp := b.def().footprint
				var r := maxf(maxf(fp.x, fp.y) * 0.5 + 4.0, min_m * 0.9)
				# the trodden ground stops at the bank: it never paints over the river
				r = minf(r, maxf(wd.river_clearance(b.pos) - 1.0, maxf(fp.x, fp.y) * 0.5))
				if pass_i == 0:
					draw_circle(b.pos, r + mpp * 1.2, GROUND_EDGE)
				else:
					draw_circle(b.pos, r, GROUND)
		for b in list:
			if b.is_road() and b.progress() > 0.0:
				draw_line(b.a, b.a.lerp(b.b, b.progress()), ROAD, maxf(BuildingState.road_width(), mpp * 1.4))
		var blocks := list.filter(func(b: BuildingState) -> bool: return not b.is_road())
		blocks.sort_custom(func(a: BuildingState, b: BuildingState) -> bool: return a.pos.y < b.pos.y)
		for b: BuildingState in blocks:
			_draw_block(b, min_m, mpp)


func _draw_block(b: BuildingState, min_m: float, mpp: float) -> void:
	var def := b.def()
	var fp := def.footprint
	var size := Vector2(maxf(fp.x, min_m), maxf(fp.y, min_m))
	var rect := Rect2(b.pos - size * 0.5, size)
	var unfinished := not b.is_active()
	if def.work_type() == &"farm":
		# the same strips the close zoom draws (FieldPainter), in flat colours, and the farmstead as a roof
		FieldPainter.draw_flat(self, b, _month, 0.5 if unfinished else 1.0)
		var stead := Rect2(rect.position + Vector2(rect.size.x * 0.12, 1.5), Vector2(maxf(rect.size.x * 0.34, min_m), maxf(6.0, min_m)))
		draw_rect(stead, ROOFS[int(KDRng.hash01(b.id, 3, 771) * ROOFS.size()) % ROOFS.size()].darkened(0.1))
		return
	var colour: Color
	match b.def_id:
		&"keep", &"barracks", &"well":
			colour = STONE
		&"storehouse", &"granary", &"camp_store", &"woodcutter", &"quarry", &"mine":
			colour = TIMBER
		_:
			colour = ROOFS[int(KDRng.hash01(b.id, 3, 771) * ROOFS.size()) % ROOFS.size()]
	if unfinished:
		colour = Color(colour.lerp(Color(0.7, 0.62, 0.48), 0.5), 0.75)
	# the same small shift as the sprite of the close zoom (SettlementLayer.visual_of): the blocks of a village
	# seen from afar are not squares on a grid either (the turn of a couple of degrees does not show from here,
	# and a transform per block cost a batch per block while the camera zooms)
	var look := SettlementLayer.visual_of(b)
	var at: Vector2 = b.pos + look["offset"]
	var box := Rect2(at - size * 0.5 * float(look["scale"]), size * float(look["scale"]))
	draw_rect(Rect2(box.position + Vector2(mpp * 0.8, mpp * 0.8), box.size), Color(0.1, 0.08, 0.05, 0.35))
	draw_rect(box, colour.darkened(0.18))
	draw_rect(Rect2(box.position, Vector2(box.size.x, box.size.y * 0.5)), colour.lightened(0.08))
	if b.def_id == &"keep":
		# the seat of the crown: a darker tower in the middle, seen from far away
		var tower := size * 0.45
		draw_rect(Rect2(at - tower * 0.5, tower), STONE.darkened(0.35))

