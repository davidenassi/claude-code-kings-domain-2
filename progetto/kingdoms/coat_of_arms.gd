class_name CoatOfArms
extends RefCounted
## Procedural coat of arms (legacy "Araldica": deterministic from the house name).
## Heraldic rule of tincture: a metal is always set against a colour, so shields stay readable when small.
## Drawn with plain polygons on any CanvasItem (map labels, inspector, later banners).

const METALS := {&"or": Color("#D4A93A"), &"argent": Color("#E9E3D2")}
const COLOURS := {&"gules": Color("#A8322D"), &"azure": Color("#2E5B9A"), &"vert": Color("#3D7A45"),
	&"purpure": Color("#6E3F7E"), &"sable": Color("#2A2522")}
const DIVISIONS: Array[StringName] = [&"plain", &"per_pale", &"per_fess", &"per_bend", &"quarterly", &"chevron", &"chief", &"bordure"]
const CHARGES: Array[StringName] = [&"cross", &"star", &"crescent", &"roundel", &"lozenge", &"tower", &"fleur", &"crown"]
const SHAPE_BY_CULTURE := {&"germanic": &"heater", &"latin": &"heater", &"slavic": &"rounded", &"hellenic": &"rounded",
	&"arab": &"ogival", &"asian": &"ogival"}

var shape: StringName = &"heater"
var division: StringName = &"plain"
var field: Color = COLOURS[&"gules"]
var second: Color = METALS[&"or"]
var charge: StringName = &"star"
var charge_color: Color = METALS[&"or"]

var _unit_shield: PackedVector2Array = PackedVector2Array()


## `field_color` (optional) lets a realm's map colour be the field, so map and shield match.
static func generate(seed_text: String, culture: StringName, field_color: Variant = null) -> CoatOfArms:
	var a := CoatOfArms.new()
	var h := seed_text.hash()
	var r := func(salt: int) -> float: return KDRng.hash01(h & 0xFFFF, (h >> 16) & 0xFFFF, salt)
	a.shape = SHAPE_BY_CULTURE.get(culture, &"heater")
	var metal: Color = METALS.values()[int(r.call(1) * METALS.size()) % METALS.size()]
	var colour: Color = COLOURS.values()[int(r.call(2) * COLOURS.size()) % COLOURS.size()]
	if field_color is Color:
		colour = field_color
	if r.call(3) < 0.72:
		a.field = colour
		a.second = metal
	else:
		a.field = metal
		a.second = colour
	a.division = DIVISIONS[int(r.call(4) * DIVISIONS.size()) % DIVISIONS.size()]
	a.charge = CHARGES[int(r.call(5) * CHARGES.size()) % CHARGES.size()]
	# the charge sits on the field: it takes the opposite tincture class
	a.charge_color = a.second
	return a


func to_dict() -> Dictionary:
	return {"shape": String(shape), "division": String(division), "field": field.to_html(false),
		"second": second.to_html(false), "charge": String(charge), "charge_color": charge_color.to_html(false)}


static func from_dict(d: Dictionary) -> CoatOfArms:
	var a := CoatOfArms.new()
	a.shape = StringName(d.get("shape", "heater"))
	a.division = StringName(d.get("division", "plain"))
	a.field = Color.html(String(d.get("field", "A8322D")))
	a.second = Color.html(String(d.get("second", "D4A93A")))
	a.charge = StringName(d.get("charge", "star"))
	a.charge_color = Color.html(String(d.get("charge_color", "D4A93A")))
	return a


## Shield outline in unit space: x 0..1, y 0..1.15.
func unit_shield() -> PackedVector2Array:
	if not _unit_shield.is_empty():
		return _unit_shield
	var pts := PackedVector2Array()
	match shape:
		&"rounded":
			pts.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.6)])
			for i in range(1, 17):
				var t := PI * float(i) / 16.0
				pts.append(Vector2(0.5 + 0.5 * cos(t), 0.6 + 0.55 * sin(t)))
		&"ogival":
			pts.append_array([Vector2(0.08, 0), Vector2(0.92, 0), Vector2(1, 0.12), Vector2(1, 0.55)])
			for i in range(1, 9):
				var t := float(i) / 9.0
				pts.append(Vector2(1.0 - 0.5 * t, 0.55 + 0.6 * sin(t * PI * 0.5)))
			for i in range(0, 9):
				var t := 1.0 - float(i) / 9.0
				pts.append(Vector2(0.5 * t, 0.55 + 0.6 * sin(t * PI * 0.5)))
			pts.append_array([Vector2(0, 0.55), Vector2(0, 0.12)])
		_:
			pts.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.5)])
			for i in range(1, 12):
				var t := float(i) / 12.0
				pts.append(Vector2(1.0 - 0.5 * t + 0.0 * t, 0.5 + 0.65 * sin(t * PI * 0.5)))
			for i in range(0, 12):
				var t := 1.0 - float(i) / 12.0
				pts.append(Vector2(0.5 * t, 0.5 + 0.65 * sin(t * PI * 0.5)))
			pts.append(Vector2(0, 0.5))
	_unit_shield = pts
	return pts


## Draws the shield inside `rect` (keeps the aspect ratio, centred).
func draw_on(ci: CanvasItem, rect: Rect2, outline_color: Color = Color(0.12, 0.09, 0.06), outline_px: float = 1.5, alpha: float = 1.0) -> void:
	var s := minf(rect.size.x, rect.size.y / 1.15)
	var origin := rect.position + Vector2((rect.size.x - s) * 0.5, (rect.size.y - s * 1.15) * 0.5)
	var xf := Transform2D(Vector2(s, 0), Vector2(0, s), origin)
	var shield := unit_shield()
	if division == &"bordure":
		ci.draw_colored_polygon(xf * shield, Color(second, alpha))
		var inner := Geometry2D.offset_polygon(shield, -0.09)
		if not inner.is_empty():
			ci.draw_colored_polygon(xf * inner[0], Color(field, alpha))
	else:
		ci.draw_colored_polygon(xf * shield, Color(field, alpha))
	for poly in _division_polys():
		for clipped in Geometry2D.intersect_polygons(shield, poly):
			ci.draw_colored_polygon(xf * clipped, Color(second, alpha))
	var cc := charge_color if division == &"plain" or division == &"bordure" else _charge_contrast()
	for poly in _charge_polys():
		ci.draw_colored_polygon(xf * poly, Color(cc, alpha))
	var ring := xf * shield
	ring.append(ring[0])
	ci.draw_polyline(ring, Color(outline_color, outline_color.a * alpha), outline_px, true)


func _charge_contrast() -> Color:
	# on divided fields the charge is drawn in argent or sable so it reads over both halves
	return METALS[&"argent"] if field.get_luminance() < 0.55 else COLOURS[&"sable"]


func _division_polys() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	match division:
		&"per_pale":
			out.append(PackedVector2Array([Vector2(0.5, -0.1), Vector2(1.1, -0.1), Vector2(1.1, 1.3), Vector2(0.5, 1.3)]))
		&"per_fess":
			out.append(PackedVector2Array([Vector2(-0.1, 0.55), Vector2(1.1, 0.55), Vector2(1.1, 1.3), Vector2(-0.1, 1.3)]))
		&"per_bend":
			out.append(PackedVector2Array([Vector2(-0.1, -0.1), Vector2(1.1, 1.3), Vector2(-0.1, 1.3)]))
		&"quarterly":
			out.append(PackedVector2Array([Vector2(0.5, -0.1), Vector2(1.1, -0.1), Vector2(1.1, 0.55), Vector2(0.5, 0.55)]))
			out.append(PackedVector2Array([Vector2(-0.1, 0.55), Vector2(0.5, 0.55), Vector2(0.5, 1.3), Vector2(-0.1, 1.3)]))
		&"chevron":
			out.append(PackedVector2Array([Vector2(-0.1, 0.95), Vector2(0.5, 0.35), Vector2(1.1, 0.95), Vector2(1.1, 1.2), Vector2(0.5, 0.6), Vector2(-0.1, 1.2)]))
		&"chief":
			out.append(PackedVector2Array([Vector2(-0.1, -0.1), Vector2(1.1, -0.1), Vector2(1.1, 0.28), Vector2(-0.1, 0.28)]))
	return out


func _charge_polys() -> Array[PackedVector2Array]:
	var c := Vector2(0.5, 0.62 if division != &"chief" else 0.7)
	var out: Array[PackedVector2Array] = []
	match charge:
		&"cross":
			out.append(_rect(c, Vector2(0.12, 0.56)))
			out.append(_rect(c + Vector2(0, -0.06), Vector2(0.46, 0.12)))
		&"star":
			var p := PackedVector2Array()
			for i in 10:
				var ang := -PI * 0.5 + TAU * float(i) / 10.0
				var rad := 0.24 if i % 2 == 0 else 0.1
				p.append(c + Vector2(cos(ang), sin(ang)) * rad)
			out.append(p)
		&"crescent":
			var outer := _circle(c, 0.2, 20)
			var bite := _circle(c + Vector2(0, -0.09), 0.17, 20)
			for ring in Geometry2D.clip_polygons(outer, bite):
				out.append(ring)
		&"roundel":
			out.append(_circle(c, 0.17, 20))
		&"lozenge":
			out.append(PackedVector2Array([c + Vector2(0, -0.26), c + Vector2(0.17, 0), c + Vector2(0, 0.26), c + Vector2(-0.17, 0)]))
		&"tower":
			var b := c + Vector2(0, 0.2)
			out.append(PackedVector2Array([b + Vector2(-0.16, 0), b + Vector2(-0.16, -0.34), b + Vector2(-0.1, -0.34),
				b + Vector2(-0.1, -0.29), b + Vector2(-0.03, -0.29), b + Vector2(-0.03, -0.34), b + Vector2(0.03, -0.34),
				b + Vector2(0.03, -0.29), b + Vector2(0.1, -0.29), b + Vector2(0.1, -0.34), b + Vector2(0.16, -0.34), b + Vector2(0.16, 0)]))
		&"fleur":
			out.append(PackedVector2Array([c + Vector2(0, -0.27), c + Vector2(0.07, -0.12), c + Vector2(0.03, 0.05), c + Vector2(-0.03, 0.05), c + Vector2(-0.07, -0.12)]))
			out.append(PackedVector2Array([c + Vector2(0.03, -0.02), c + Vector2(0.2, -0.16), c + Vector2(0.22, 0.02), c + Vector2(0.06, 0.08)]))
			out.append(PackedVector2Array([c + Vector2(-0.03, -0.02), c + Vector2(-0.06, 0.08), c + Vector2(-0.22, 0.02), c + Vector2(-0.2, -0.16)]))
			out.append(_rect(c + Vector2(0, 0.08), Vector2(0.3, 0.06)))
			out.append(PackedVector2Array([c + Vector2(-0.04, 0.1), c + Vector2(0.04, 0.1), c + Vector2(0.07, 0.24), c + Vector2(-0.07, 0.24)]))
		&"crown":
			var b := c + Vector2(0, 0.12)
			out.append(PackedVector2Array([b + Vector2(-0.22, 0), b + Vector2(-0.24, -0.26), b + Vector2(-0.12, -0.12),
				b + Vector2(0, -0.3), b + Vector2(0.12, -0.12), b + Vector2(0.24, -0.26), b + Vector2(0.22, 0)]))
	return out


static func _rect(center: Vector2, size: Vector2) -> PackedVector2Array:
	var h := size * 0.5
	return PackedVector2Array([center - h, center + Vector2(h.x, -h.y), center + h, center + Vector2(-h.x, h.y)])


static func _circle(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		p.append(center + Vector2(cos(a), sin(a)) * radius)
	return p

