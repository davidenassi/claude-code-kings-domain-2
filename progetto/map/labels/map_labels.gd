class_name MapLabels
extends Control
## Names and coats of arms on the map, drawn in screen space with zoom-dependent fading. Hierarchy:
## - kingdoms: engraved spaced capitals sized to the realm, laid along the realm's main axis with a gentle arch, big shield;
## - lordships and the player's domain: smaller capitals with a small shield (the player's with a gold halo);
## - provinces: book serif at regional zoom.
## Greedy placement: higher-priority labels first, overlapping ones are skipped.

const INK := Color(0.16, 0.10, 0.05)
const PAPER := Color(0.96, 0.91, 0.78)
const GOLD := Color(0.93, 0.76, 0.33)

@export var camera_path: NodePath

var _camera: WorldCamera
var _wd: WorldData
var _last_view := Rect2()
var _layout: Dictionary = {}   # kingdom id -> {anchor: Vector2, angle: float, extent_m: float}
var _dirty := true
var drawn_count := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_camera = get_node_or_null(camera_path) as WorldCamera
	_wd = WorldData.get_instance()
	EventBus.province_owner_changed.connect(func(_p: int, _o: int, _n: int, _r: StringName) -> void: _dirty = true)
	EventBus.session_started.connect(func(_s: GameSession) -> void: _dirty = true)
	EventBus.session_loaded.connect(func(_s: GameSession) -> void: _dirty = true)


## Label point of a realm: the owned province centre closest to the area-weighted centroid (always inside the realm).
static func realm_anchor(world: WorldState, wd: WorldData, k: KingdomState) -> Vector2:
	return realm_layout(wd, k).get("anchor", Vector2.INF)


## Anchor, main axis angle (radians, kept readable within ±22°) and extent along that axis.
static func realm_layout(wd: WorldData, k: KingdomState) -> Dictionary:
	if k.provinces.is_empty():
		return {}
	var acc := Vector2.ZERO
	var total := 0.0
	for pid in k.provinces:
		var g := wd.provinces[pid]
		acc += g.centroid * g.area_km2
		total += g.area_km2
	var c := acc / maxf(total, 0.001)
	var best := wd.provinces[k.provinces[0]].center
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	for pid in k.provinces:
		var g := wd.provinces[pid]
		if g.center.distance_squared_to(c) < best.distance_squared_to(c):
			best = g.center
		var d := g.centroid - c
		sxx += d.x * d.x * g.area_km2
		syy += d.y * d.y * g.area_km2
		sxy += d.x * d.y * g.area_km2
	var angle := 0.5 * atan2(2.0 * sxy, sxx - syy) if k.provinces.size() >= 3 else 0.0
	if angle > PI * 0.5:
		angle -= PI
	elif angle < -PI * 0.5:
		angle += PI
	angle = clampf(angle, deg_to_rad(-22.0), deg_to_rad(22.0))
	var axis := Vector2.from_angle(angle)
	var lo := INF
	var hi := -INF
	for pid in k.provinces:
		var g := wd.provinces[pid]
		var t := (g.centroid - c).dot(axis)
		lo = minf(lo, t - g.inner_radius_m)
		hi = maxf(hi, t + g.inner_radius_m)
	return {"anchor": best, "angle": angle, "extent_m": maxf(hi - lo, 2000.0)}


func _process(_delta: float) -> void:
	if not Session.has_game() or _camera == null:
		return
	if _dirty:
		_dirty = false
		_layout.clear()
		for k in Session.current.world.kingdoms:
			if k.alive and not k.provinces.is_empty():
				_layout[k.id] = realm_layout(_wd, k)
		queue_redraw()
	var view := _camera.visible_world_rect()
	if view != _last_view:
		_last_view = view
		queue_redraw()


static func _band(mpp: float, in_a: float, in_b: float, out_a: float, out_b: float) -> float:
	return smoothstep(in_a, in_b, mpp) * (1.0 - smoothstep(out_a, out_b, mpp))


func _draw() -> void:
	drawn_count = 0
	if not Session.has_game() or _camera == null:
		return
	var world := Session.current.world
	var mpp := _camera.meters_per_pixel()
	var screen := get_viewport_rect()
	var taken: Array[Rect2] = []

	var order: Array[KingdomState] = []
	for k in world.kingdoms:
		if _layout.has(k.id):
			order.append(k)
	order.sort_custom(func(a: KingdomState, b: KingdomState) -> bool:
		if a.is_player != b.is_player:
			return a.is_player
		if a.rank != b.rank:
			return a.rank > b.rank
		return a.provinces.size() > b.provinces.size())
	for k in order:
		if _draw_realm(k, _layout[k.id], mpp, screen, taken):
			drawn_count += 1

	var pa := _band(mpp, 0.9, 1.5, 9.0, 14.0)
	if pa > 0.01:
		var font := KDFonts.serif_bold()
		var view := _camera.visible_world_rect().grow(2000.0)
		# a province with a real settlement is named by the settlement itself: two pins with the same name a
		# few hundred metres apart read as two places (Phase 18 audit)
		var settled := {}
		for s in world.settlements:
			settled[s.province] = true
		for g in _wd.provinces:
			if not view.has_point(g.center) or settled.has(g.id):
				continue
			var p := _camera.world_to_screen(g.center)
			var fs := 15
			var tw := font.get_string_size(g.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			# a painted pin over the name, as big as the place is populous: the map says where people live
			var state := world.province(g.id)
			var pin := KDUi.icon(_pin_for(state.population if state else 0))
			var ph := 0.0
			var rect := Rect2(p.x - tw * 0.5 - 4, p.y - fs, tw + 8, fs + 6)
			if pin:
				ph = 30.0 if (state and state.population >= 8000) else 25.0
				rect = rect.merge(Rect2(p.x - ph * 0.4, p.y - fs - ph - 1.0, ph * 0.8, ph))
			if not screen.intersects(rect) or _overlaps(rect, taken):
				continue
			taken.append(rect)
			if pin:
				var pw := ph * float(pin.get_width()) / maxf(float(pin.get_height()), 1.0)
				var pin_rect := Rect2(p.x - pw * 0.5, p.y - fs - ph - 1.0, pw, ph)
				draw_texture_rect(pin, pin_rect, false, Color(1, 1, 1, pa))
				if state and state.owner >= 0:
					var owner := world.kingdom(state.owner)
					if owner:
						draw_circle(pin_rect.get_center() - Vector2(0.0, ph * 0.06), ph * 0.115, Color(owner.color, pa * 0.95))
			var baseline := Vector2(p.x - tw * 0.5, p.y)
			draw_string_outline(font, baseline, g.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(PAPER, 0.30 * pa))
			draw_string_outline(font, baseline, g.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(PAPER, 0.85 * pa))
			draw_string(font, baseline, g.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.22, 0.14, 0.06, pa))
			drawn_count += 1
	_draw_settlements(world, mpp, screen, taken)


## The places where people actually live: a painted pin with the name on a plate under it. They appear when
## the settlement sprites are too small to read and fade out when the camera comes down among the houses.
func _draw_settlements(world: WorldState, mpp: float, screen: Rect2, taken: Array[Rect2]) -> void:
	var alpha := _band(mpp, 0.55, 1.4, 26.0, 40.0)
	if alpha <= 0.01:
		return
	var view := _camera.visible_world_rect().grow(600.0)
	var font := KDFonts.serif_bold()
	for s in world.settlements:
		# the settlement lives in the valley; on this map it stands where its valley is on the continent
		var at := world.settlement_global_pos(s)
		if not view.has_point(at):
			continue
		var people := world.people_of(s.id).size()
		var pin := KDUi.icon(_pin_for(people))
		var p := _camera.world_to_screen(at)
		# the pin stands above the houses and the name under them: both used to sit on the village itself and
		# hid it (Phase 18 audit). When the place is big enough on screen to be read, the pin steps aside.
		var r_px := minf(built_radius(world, s) / mpp, 220.0)
		var pin_alpha := alpha * (1.0 - smoothstep(45.0, 80.0, r_px))
		var h := 30.0 if people >= 400 else (26.0 if people >= 60 else 22.0)
		var w := h * float(pin.get_width()) / maxf(float(pin.get_height()), 1.0) if pin else h * 0.8
		var rect := Rect2(p.x - w * 0.5, p.y - r_px * 0.8 - h, w, h)
		var fs := 13
		var tw := font.get_string_size(s.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var plate_rect := Rect2(p.x - tw * 0.5 - 12.0, p.y + r_px * 0.8 + 2.0, tw + 24.0, fs + 10.0)
		var whole := plate_rect.merge(rect) if pin_alpha > 0.01 else plate_rect
		if not screen.intersects(whole) or _overlaps(whole, taken):
			continue
		taken.append(whole)
		if KDUi.has(&"plate"):
			var plate := KDUi.style(&"plate", Vector4(8, 3, 8, 3))
			plate.modulate_color = Color(1, 1, 1, alpha)
			draw_style_box(plate, plate_rect)
		if pin_alpha > 0.01:
			if pin:
				draw_texture_rect(pin, rect, false, Color(1, 1, 1, pin_alpha))
			else:
				_draw_seat_mark(rect, pin_alpha)   # the painted kit is missing: a drawn seat, never nothing
			var k := world.kingdom(s.kingdom)
			if k:
				# a dot of the realm's colour on the pin: who holds the place is read at a glance
				draw_circle(rect.get_center() - Vector2(0.0, h * 0.06), h * 0.115, Color(k.color, pin_alpha * 0.95))
		draw_string(font, Vector2(p.x - tw * 0.5, plate_rect.position.y + fs + 2.5), s.name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.96, 0.91, 0.78, alpha))
		drawn_count += 1


## A seat drawn by hand for when the painted pins are not there: a gold-rimmed tower on a disc.
func _draw_seat_mark(rect: Rect2, alpha: float) -> void:
	var c := rect.get_center()
	var r := rect.size.y * 0.42
	draw_circle(c, r + 2.0, Color(0.18, 0.12, 0.06, 0.85 * alpha))
	draw_circle(c, r, Color(0.93, 0.86, 0.66, alpha))
	var t := Rect2(c.x - r * 0.35, c.y - r * 0.55, r * 0.7, r * 1.0)
	draw_rect(t, Color(0.35, 0.26, 0.16, alpha))
	for i in 3:
		draw_rect(Rect2(t.position.x + i * t.size.x / 2.5, t.position.y - r * 0.18, t.size.x / 5.0, r * 0.2), Color(0.35, 0.26, 0.16, alpha))
	draw_arc(c, r, 0.0, TAU, 28, Color(GOLD, alpha), 2.0, true)


static var _radius_cache: Dictionary = {}   # settlement id -> [buildings_version, metres]


## How far the buildings of a place reach from its centre (metres): where the pin and the name go.
static func built_radius(world: WorldState, s: SettlementState) -> float:
	var cached: Array = _radius_cache.get(s.id, [])
	if not cached.is_empty() and int(cached[0]) == world.buildings_version and int(cached[2]) == world.get_instance_id():
		return float(cached[1])
	var dists: Array[float] = []
	for b in world.buildings_of(s.id):
		if not b.is_road():
			dists.append(b.pos.distance_to(s.center) + maxf(b.def().footprint.x, b.def().footprint.y) * 0.5)
	# the bulk of the place, not the one farm that wandered off: the distance that holds nine buildings in ten
	dists.sort()
	var r := dists[int(dists.size() * 0.9) - 1] if dists.size() >= 2 else (dists[0] if not dists.is_empty() else 0.0)
	_radius_cache[s.id] = [world.buildings_version, r, world.get_instance_id()]
	return r


## Which pin a place deserves, by the people who live there.
static func _pin_for(people: int) -> StringName:
	if people >= 20000:
		return &"pin_capital"
	if people >= 8000:
		return &"pin_city"
	if people >= 1200:
		return &"pin_town"
	return &"pin_village"



func _draw_realm(k: KingdomState, layout: Dictionary, mpp: float, screen: Rect2, taken: Array[Rect2]) -> bool:
	var is_kingdom := k.rank == KingdomState.Rank.KINGDOM
	var alpha := _band(mpp, 5.0, 8.0, 900.0, 1000.0) if is_kingdom else _band(mpp, 3.0, 5.0, 60.0, 90.0)
	if k.is_player:
		alpha = _band(mpp, 1.2, 2.2, 900.0, 1000.0)
	if alpha <= 0.01:
		return false
	var font := KDFonts.title()
	var text := k.short_name().to_upper()
	var p := _camera.world_to_screen(layout["anchor"])
	var angle := float(layout["angle"]) if is_kingdom else 0.0
	var fs: int
	var tracking: float
	if is_kingdom:
		# sized to the realm: the name spans most of the realm's length, within readable limits
		var span_px := float(layout["extent_m"]) / mpp * 0.8
		fs = int(clampf(span_px / maxf(text.length() * 1.05, 1.0), 17.0, 40.0))
		tracking = fs * 0.32
	else:
		fs = 15 if k.is_player else 13
		tracking = fs * 0.14
	var widths := PackedFloat32Array()
	var total := 0.0
	for i in text.length():
		var w := font.get_char_size(text.unicode_at(i), fs).x
		widths.append(w)
		total += w + (tracking if i < text.length() - 1 else 0.0)
	var shield_h := 34.0 if is_kingdom else (26.0 if k.is_player else 20.0)
	var half := Vector2(maxf(total, shield_h) * 0.5 + 6.0, 0.0)
	var axis := Vector2.from_angle(angle)
	var ends := [p - axis * half.x, p + axis * half.x]
	var rect := Rect2(Vector2(minf(ends[0].x, ends[1].x), minf(ends[0].y, ends[1].y) - shield_h - fs * 0.5),
		Vector2(absf(ends[1].x - ends[0].x), absf(ends[1].y - ends[0].y) + shield_h + fs * 1.6))
	if not screen.intersects(rect) or _overlaps(rect, taken):
		return false
	taken.append(rect)

	# shield above the name
	var srect := Rect2(p.x - shield_h * 0.44, p.y - shield_h - fs * 0.35, shield_h * 0.88, shield_h)
	if k.is_player:
		draw_circle(srect.get_center(), shield_h * 0.72, Color(GOLD, 0.28 * alpha))
	k.coat_of_arms.draw_on(self, srect, Color(0.10, 0.07, 0.04), 1.6 if is_kingdom else 1.2, alpha)

	# name: characters along the axis with a gentle arch
	var ink := INK.lerp(k.color.darkened(0.55), 0.35) if is_kingdom else INK
	var halo := Color(GOLD, 0.55 * alpha) if k.is_player else Color(PAPER, 0.5 * alpha)
	var arch := fs * 0.18 if is_kingdom and text.length() > 5 else 0.0
	var x := -total * 0.5
	var baseline_off := fs * 0.9
	for i in text.length():
		var w := widths[i]
		var t := (x + w * 0.5) / maxf(total * 0.5, 1.0)   # -1..1 along the name
		var local := Vector2(x, baseline_off + arch * t * t)
		var char_angle := angle + atan(2.0 * arch * t / maxf(total * 0.5, 1.0))
		draw_set_transform(p + local.rotated(angle), char_angle, Vector2.ONE)
		var ch := text.unicode_at(i)
		draw_char_outline(font, Vector2.ZERO, text.substr(i, 1), fs, maxi(int(fs * 0.3), 4), Color(PAPER, 0.28 * alpha))
		draw_char_outline(font, Vector2.ZERO, text.substr(i, 1), fs, 2 if not k.is_player else 3, halo)
		draw_char(font, Vector2.ZERO, text.substr(i, 1), fs, Color(ink, 0.96 * alpha))
		x += w + tracking
		if ch == 32:
			x += tracking * 0.5
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


static func _overlaps(r: Rect2, taken: Array[Rect2]) -> bool:
	for t in taken:
		if t.intersects(r):
			return true
	return false

