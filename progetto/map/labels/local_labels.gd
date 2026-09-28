class_name LocalLabels
extends Control
## The names of the valley on the local map (Rebirth, Phase 2): the river written along its course, the lake on
## its water, the ranges of the rim in spaced capitals, the passes where the ways leave the valley, the great woods,
## and the name of the community on a plate under its houses. They are read from far (the whole valley) and step
## aside when the camera comes down among the fields. Screen space, greedy placement like MapLabels.

const INK := Color(0.16, 0.10, 0.05)
const PAPER := Color(0.96, 0.91, 0.78)
const WATER_INK := Color(0.10, 0.24, 0.40)
const GOLD := Color(0.93, 0.76, 0.33)

@export var camera_path: NodePath

var _camera: WorldCamera
var drawn_count := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_camera = get_node_or_null(camera_path) as WorldCamera


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


## 0 below in_a, 1 between in_b and out_a, 0 above out_b.
static func _band(mpp: float, in_a: float, in_b: float, out_a: float, out_b: float) -> float:
	return smoothstep(in_a, in_b, mpp) * (1.0 - smoothstep(out_a, out_b, mpp))


func _draw() -> void:
	drawn_count = 0
	if _camera == null or not Session.has_game():
		return
	var world := Session.current.world
	var dd := DomainData.of(world)
	if dd == null:
		return
	var mpp := _camera.meters_per_pixel()
	var screen := get_viewport_rect()
	var taken: Array[Rect2] = []
	var names: Dictionary = dd.meta.get("names", {})
	var far_a := _band(mpp, 1.7, 2.8, 50.0, 60.0)
	# the community first: its plate under the houses (from the zoom where the houses become blocks)
	for s in world.settlements:
		var a := _band(mpp, 0.55, 0.85, 50.0, 60.0)
		if a > 0.01:
			_plate(_camera.world_to_screen(s.center) + Vector2(0, 26.0), s.name, a, screen, taken)
	if far_a <= 0.01:
		return
	# the lake, on its water
	for lk: Dictionary in dd.meta.get("lakes", []):
		var c: Array = lk["center"]
		_text(_camera.world_to_screen(Vector2(float(c[0]), float(c[1]))), String(lk["name"]), KDFonts.serif_italic(), 16,
			WATER_INK, Color(0.85, 0.93, 0.97, 0.7), 0.0, far_a, screen, taken, 1.5)
	# the rivers, along their course where it runs straightest
	for r in dd.rivers:
		var rname := String(r.get("name", ""))
		if rname == "":
			continue
		# the best stretch that is free: a name never sits on another
		for at: Dictionary in _river_anchors(r):
			if _text(_camera.world_to_screen(at["pos"]), rname, KDFonts.serif_italic(), 15, WATER_INK,
					Color(0.88, 0.94, 0.95, 0.75), float(at["angle"]), far_a, screen, taken, 1.0):
				break
	# the ranges of the rim, in spaced capitals
	for rg: Dictionary in names.get("ranges", []):
		var p: Array = rg["at"]
		_text(_camera.world_to_screen(Vector2(float(p[0]), float(p[1]))), _spaced(String(rg["name"]).to_upper()),
			KDFonts.title(), 15, INK, Color(PAPER, 0.8), 0.0, far_a, screen, taken, 2.5)
	# the passes, where the ways leave the valley for the unknown
	for ps: Dictionary in dd.meta.get("passes", []):
		var i: Array = ps["inner"]
		var e: Array = ps["edge"]
		var inner := Vector2(float(i[0]), float(i[1]))
		var edge := Vector2(float(e[0]), float(e[1]))
		var p := _camera.world_to_screen(inner.lerp(edge, 0.55))
		var label := String(ps["name"])
		var sub := "verso l'ignoto"
		if _text(p, label, KDFonts.serif_bold(), 14, INK, Color(PAPER, 0.85), 0.0, far_a, screen, taken, 1.2):
			_text(p + Vector2(0, 17), sub, KDFonts.serif_italic(), 12, Color(INK, 0.8), Color(PAPER, 0.7), 0.0,
				far_a * 0.9, screen, [], 1.0)
	# the great woods
	for pl: Dictionary in names.get("places", []):
		var p: Array = pl["at"]
		_text(_camera.world_to_screen(Vector2(float(p[0]), float(p[1]))), String(pl["name"]), KDFonts.serif_italic(), 14,
			Color(0.12, 0.20, 0.08), Color(0.90, 0.93, 0.80, 0.75), 0.0, far_a, screen, taken, 1.0)


## Where a river's name can go, best first: the middles of its straightest long stretches.
static func _river_anchors(r: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pts: PackedVector2Array = r["points"]
	if pts.size() < 12:
		return out
	var step := 6
	var scored: Array = []
	for i in range(step, pts.size() - step, step):
		var a := pts[i - step]
		var b := pts[i + step]
		var chord := a.distance_to(b)
		var arc := 0.0
		for k in range(i - step, i + step):
			arc += pts[k].distance_to(pts[k + 1])
		# straight and far from both ends
		var middle := 1.0 - absf(float(i) / float(pts.size()) - 0.5) * 1.2
		scored.append([chord / maxf(arc, 0.001) + middle * 0.3, i])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
	for entry: Array in scored.slice(0, 6):
		var i := int(entry[1])
		var d := pts[i + step] - pts[i - step]
		var angle := atan2(d.y, d.x)
		if angle > PI * 0.5:
			angle -= PI
		elif angle < -PI * 0.5:
			angle += PI
		out.append({"pos": pts[i], "angle": angle})
	return out


static func _spaced(text: String) -> String:
	var out := PackedStringArray()
	for i in text.length():
		out.append(text[i])
	return " ".join(out).replace("   ", "     ")


## One name, centred on p, turned by angle; skipped when it would sit on another. True when drawn.
func _text(p: Vector2, text: String, font: Font, fs: int, ink: Color, halo: Color, angle: float, alpha: float,
		screen: Rect2, taken: Array[Rect2], pad: float) -> bool:
	if alpha <= 0.01 or text == "":
		return false
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ext := Vector2(absf(cos(angle)) * w + absf(sin(angle)) * fs, absf(sin(angle)) * w + absf(cos(angle)) * fs)
	var rect := Rect2(p - ext * 0.5, ext).grow(4.0 * pad)
	if not screen.intersects(rect):
		return false
	for t in taken:
		if t.intersects(rect):
			return false
	taken.append(rect)
	draw_set_transform(p, angle, Vector2.ONE)
	var base := Vector2(-w * 0.5, fs * 0.35)
	draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(halo, halo.a * alpha))
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ink, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	drawn_count += 1
	return true


## The name of a place on a painted plate (drawn by hand when the kit is missing).
func _plate(p: Vector2, text: String, alpha: float, screen: Rect2, taken: Array[Rect2]) -> void:
	var font := KDFonts.serif_bold()
	var fs := 15
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rect := Rect2(p.x - tw * 0.5 - 14.0, p.y - fs * 0.5 - 6.0, tw + 28.0, fs + 12.0)
	if not screen.intersects(rect):
		return
	for t in taken:
		if t.intersects(rect):
			return
	taken.append(rect)
	if KDUi.has(&"plate"):
		var plate := KDUi.style(&"plate", Vector4(8, 3, 8, 3))
		plate.modulate_color = Color(1, 1, 1, alpha)
		draw_style_box(plate, rect)
	else:
		draw_rect(rect, Color(0.20, 0.13, 0.07, 0.85 * alpha))
		draw_rect(rect, Color(GOLD, alpha), false, 1.5)
	draw_string(font, Vector2(rect.position.x + 14.0, rect.position.y + fs + 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(0.96, 0.91, 0.78, alpha))
	drawn_count += 1
