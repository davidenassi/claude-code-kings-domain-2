class_name ArmyLayer
extends Node2D
## The hosts on the map, at three distances: close enough and you see the soldiers themselves, walking in a
## loose block; further out a banner in the colours of the realm with the number of men; from the strategic
## height only the pennant. Armies the player cannot see are not drawn at all (fog of war).

const ATLAS_DIR := "res://assets/people"
const SOLDIERS_MPP := 1.6      ## below this the men are drawn one by one
const BANNER_MPP := 45.0       ## above this even the banner disappears
const MAX_FIGURES := 36
const MAX_PER_REGIMENT := 12
const FIGURE_M := 1.9
## A soldier is drawn at least this tall on screen, but never more than MAX_SCALE times his real size (Phase 18:
## at 26 px and no limit a man stood fifteen metres tall beside the houses)
const MIN_FIGURE_PX := 14.0
const MAX_SCALE := 3.2
const BANNER_PX := 30.0

@export var camera_path: NodePath

var _camera: WorldCamera
var _atlas: Texture2D
var _sprites: Dictionary = {}
var _ppm := 22.0
var _anim_time := 0.0


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	var meta: Dictionary = Defs.read_json(ATLAS_DIR + "/people_atlas.json")
	_atlas = load(ATLAS_DIR + "/" + String(meta["atlas"]))
	_sprites = meta["sprites"]
	_ppm = float(meta.get("ppm", 22.0))
	EventBus.army_changed.connect(func(_id: int) -> void: queue_redraw())
	EventBus.battle_changed.connect(func(_id: int) -> void: queue_redraw())


func _process(delta: float) -> void:
	if _camera == null or not Session.has_game():
		visible = false
		return
	visible = _camera.meters_per_pixel() < BANNER_MPP
	_anim_time += delta
	if visible:
		queue_redraw()


## Where the army stands right now, walking its day's stretch of road.
static func army_position(session: GameSession, a: ArmyState) -> Vector2:
	if a.step_from == a.step_to:
		return a.pos
	var world := session.world
	var frac := (float(world.tick % world.ticks_per_day) + session.clock.tick_alpha()) / float(world.ticks_per_day)
	return a.step_from.lerp(a.step_to, clampf(frac, 0.0, 1.0))


func _draw() -> void:
	var session := Session.current
	var world := session.world
	var me := world.player()
	if me == null:
		return
	var mpp := _camera.meters_per_pixel()
	var view := _camera.visible_world_rect().grow(600.0)
	# where the fighting is: the painted mark of a battle, and of a siege the ring that fills as the walls give
	for b in world.battles:
		var att := world.army(b.attacker)
		var def := world.army(b.defender)
		var seen := (att and Military.can_see(world, me.id, att)) or (def and Military.can_see(world, me.id, def))
		if seen and view.has_point(b.pos):
			_draw_mark(&"mark_battle", b.pos, mpp, 34.0)
	for s in world.sieges:
		var army := world.army(s.army)
		if army == null or not Military.can_see(world, me.id, army) or not view.has_point(army.pos):
			continue
		var radius := 34.0 * mpp
		draw_arc(army.pos, radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(s.progress, 0.02, 1.0), 26,
			Color(0.85, 0.6, 0.2, 0.9), maxf(2.5 * mpp, 0.4), true)
		_draw_mark(&"mark_siege", army.pos, mpp, 26.0)
	for a in Military.visible_armies(world, me.id):
		var pos := army_position(session, a)
		if not view.has_point(pos):
			continue
		var k := world.kingdom(a.kingdom)
		var color := k.color if k else Color.GRAY
		if mpp < SOLDIERS_MPP:
			_draw_soldiers(a, pos, mpp)
		else:
			_draw_banner(a, pos, mpp, color)


## Close to the field the host is its men, regiment by regiment, each a block in ranks with its own pennant
## at the head: on the march the blocks follow one another along the road, at rest they stand side by side
## (Phase 18: it was one loose heap of up to twenty-four figures).
func _draw_soldiers(a: ArmyState, pos: Vector2, mpp: float) -> void:
	var scale := clampf(MIN_FIGURE_PX * mpp / FIGURE_M, 1.0, MAX_SCALE)
	var frame := int(_anim_time * 4.0) % 2
	var walking := a.step_from != a.step_to
	var dir := (a.step_to - a.step_from).normalized() if walking else Vector2(0, 1)
	var face := 1.0 if (a.step_to.x >= a.step_from.x) else -1.0
	var side := Vector2(-dir.y, dir.x) if walking else Vector2(1, 0)
	var gap := 1.35 * scale   # between two men of a rank
	var blocks: Array = []    # [regiment, men drawn, columns]
	var drawn := 0
	for r in a.regiments:
		var count := mini(mini(int(r["men"]), MAX_PER_REGIMENT), MAX_FIGURES - drawn)
		if count <= 0:
			break
		blocks.append([r, count, mini(4, count)])
		drawn += count
	var figures: Array = []
	var pennants: Array = []
	var along := 0.0          # on the march: how far behind the head of the column this block starts
	var across := 0.0         # at rest: where along the line this block starts
	var line_width := 0.0
	for blk: Array in blocks:
		line_width += float(blk[2]) * gap + gap
	for blk: Array in blocks:
		var r: Dictionary = blk[0]
		var count := int(blk[1])
		var cols := int(blk[2])
		var ranks := int(ceil(float(count) / float(cols)))
		var u := Military.unit(r["unit"])
		var look := String(u.id) if u and _sprites.has("%s_idle_0" % u.id) else "idle"
		var id := "%s_%s_%d" % [look, "walk" if walking else "idle", frame if walking else 0]
		var origin: Vector2
		if walking:
			origin = pos - dir * along
			along += float(ranks) * gap + gap * 1.2
		else:
			origin = pos + side * (across - line_width * 0.5 + float(cols) * gap * 0.5)
			across += float(cols) * gap + gap
		for i in count:
			var c := i % cols
			var rank := i / cols
			var p := origin + side * ((float(c) - float(cols - 1) * 0.5) * gap) - dir * (float(rank) * gap)
			# nobody stands exactly on the line
			p += Vector2(sin(float(i) * 2.1 + float(r.get("men", 0))), cos(float(i) * 1.7)) * 0.18 * scale
			figures.append([p.y, id, p, face])
		pennants.append([origin + dir * gap * 0.8, _gonfalon_of(u)])
	figures.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for f: Array in figures:
		_draw_foot_shadow(f[2], scale)
		_draw_sprite(String(f[1]), f[2], scale, float(f[3]), Color.WHITE)
	# each regiment's pennant over its head, as big on screen as the men are
	for p: Array in pennants:
		var tex := KDUi.icon(p[1])
		if tex:
			var h := FIGURE_M * scale * 1.5
			var w := h * float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
			draw_texture_rect(tex, Rect2((p[0] as Vector2) - Vector2(w * 0.5, h + FIGURE_M * scale), Vector2(w, h)), false)


static func _gonfalon_of(u: UnitDef) -> StringName:
	if u == null:
		return &"gonfalon_foot"
	match u.category:
		&"cavalry":
			return &"gonfalon_horse"
		&"ranged":
			return &"gonfalon_bow"
	return &"gonfalon_foot"


## Far from the field a host is a gonfalon: the painted pennant of what it is made of, with a disc of the
## realm's colour at its head. It was a tinted figure of a man before, which read as a smudge.
func _draw_banner(a: ArmyState, pos: Vector2, mpp: float, color: Color) -> void:
	var tex := KDUi.icon(_gonfalon_for(a))
	if tex == null:
		var frame := int(_anim_time * 2.0) % 2
		_draw_sprite("banner_%d" % frame, pos, BANNER_PX * mpp / 2.6, 1.0, color)
		return
	# it keeps its size on the screen; a bigger host flies a bigger one
	var h := BANNER_PX * mpp * (0.9 + clampf(float(a.men()) / 140.0, 0.0, 0.55))
	var w := h * float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
	var rect := Rect2(pos - Vector2(w * 0.5, h), Vector2(w, h))
	draw_texture_rect(tex, rect, false)
	draw_circle(Vector2(rect.get_center().x, rect.position.y + h * 0.30), h * 0.12, color)
	# how many men march under it, on a small plate at its foot: drawn in screen pixels (scaled by the zoom)
	var font := KDFonts.serif_bold()
	var text := "%d" % a.men()
	var fs := 13
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_set_transform(pos + Vector2(0, 2.0 * mpp), 0.0, Vector2(mpp, mpp))
	draw_rect(Rect2(-tw * 0.5 - 5.0, 0.0, tw + 10.0, fs + 5.0), Color(0.16, 0.11, 0.07, 0.85))
	draw_rect(Rect2(-tw * 0.5 - 5.0, 0.0, tw + 10.0, fs + 5.0), Color(color, 0.9), false, 1.5)
	draw_string(font, Vector2(-tw * 0.5, fs), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.96, 0.91, 0.78))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Which pennant: the arm that weighs most in the host.
static func _gonfalon_for(a: ArmyState) -> StringName:
	var best := &"gonfalon_foot"
	var best_men := 0
	for r in a.regiments:
		var u := Military.unit(r["unit"])
		if u == null or int(r["men"]) <= best_men:
			continue
		best_men = int(r["men"])
		match u.category:
			&"cavalry":
				best = &"gonfalon_horse"
			&"ranged":
				best = &"gonfalon_bow"
			_:
				best = &"gonfalon_foot"
	return best

func _draw_sprite(id: String, feet: Vector2, scale: float, face: float, tint: Color) -> void:
	var s: Dictionary = _sprites.get(id, {})
	if s.is_empty():
		return
	var rect: Array = s["rect"]
	var pv: Array = s["pivot"]
	var src := Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	var size := src.size / _ppm * scale
	var offset := Vector2(float(pv[0]), float(pv[1])) / _ppm * scale
	var dst: Rect2
	if face >= 0.0:
		dst = Rect2(feet - offset, size)
	else:
		dst = Rect2(Vector2(feet.x + offset.x, feet.y - offset.y), Vector2(-size.x, size.y))
	draw_texture_rect_region(_atlas, dst, src, tint)


## A man standing in the sun has something under him: without it he floats over the grass. A scaled circle
## around a local origin, not a polygon at world coordinates (float precision breaks the triangulation).
func _draw_foot_shadow(feet: Vector2, scale: float) -> void:
	draw_set_transform(feet + Vector2(0.28, 0.06) * scale, 0.0, Vector2(0.52, 0.20) * scale)
	draw_circle(Vector2.ZERO, 1.0, Color(0.10, 0.09, 0.06, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A painted mark that keeps its size on the screen, standing over the place it speaks of.
func _draw_mark(icon: StringName, at: Vector2, mpp: float, px: float) -> void:
	var tex := KDUi.icon(icon)
	if tex == null:
		return
	var h := px * mpp
	var w := h * float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
	draw_texture_rect(tex, Rect2(at - Vector2(w * 0.5, h * 0.5), Vector2(w, h)), false)

