class_name FieldPainter
extends RefCounted
## The fields of a farm, drawn the way a farmer lays them out instead of as one rectangle (world art pass).
##
## The farm keeps its logical footprint (26 x 30 m: placement, collisions, work, harvest do not change). Under
## the farmstead the picture shows two to four strips — the open fields of the middle ages — each with its own
## width, its furrows along its length, grass balks between them, slightly irregular edges, the whole field
## turned by a few degrees; now and then a strip left fallow. Everything comes from the id of the building,
## so a field looks the same after a reload.
##
## Stages (only the picture: the simulation keeps its crop and its months): ploughed before sowing, sown in
## the month of sowing, growing, ripening in the month before the harvest, ripe while the crop is standing,
## stubble once it is in.

const FARMSTEAD_DEPTH := 9.2      ## metres at the top of the footprint taken by the farmstead
const BALK := 0.55                ## half the grass balk between two strips
const EDGE_STEP := 3.0            ## metres between two points of a strip's edge
const EDGE_WOBBLE := 0.55         ## how far an edge wanders from the straight line
const FURROW_GAP := 0.9

const COL_SOIL := Color(0.45, 0.34, 0.21)
const COL_SOIL_DARK := Color(0.33, 0.24, 0.15)
const COL_SOWN := Color(0.49, 0.39, 0.24)
const COL_GREEN := Color(0.40, 0.53, 0.22)
const COL_GREEN_DARK := Color(0.30, 0.42, 0.16)
const COL_RIPENING := Color(0.66, 0.62, 0.30)
const COL_RIPE := Color(0.80, 0.66, 0.30)
const COL_RIPE_DARK := Color(0.60, 0.47, 0.20)
const COL_STUBBLE := Color(0.70, 0.61, 0.40)
const COL_FALLOW := Color(0.45, 0.52, 0.28)
const COL_BALK := Color(0.40, 0.48, 0.25, 0.9)
## Not every strip grows the same thing: wheat, barley a little paler and earlier, beans darker (only the picture).
const CROP_TINTS: Array[Color] = [Color(1.0, 1.0, 1.0), Color(1.10, 1.08, 0.92), Color(0.82, 0.90, 0.80)]

static var _cache: Dictionary = {}   # building id -> layout


static func _h(b: BuildingState, k: int) -> float:
	return KDRng.hash01(b.id, k, 7717)


## The layout of a farm's field: {"center": Vector2, "angle": float, "strips": [{"rect", "poly", "along_x",
## "fallow", "tint"}]} in the local frame of the field (centre at 0, turned by angle).
static func layout(b: BuildingState) -> Dictionary:
	if _cache.has(b.id):
		return _cache[b.id]
	var r := b.rect()
	var field := Rect2(r.position.x + 0.8, r.position.y + FARMSTEAD_DEPTH, r.size.x - 1.6, r.size.y - FARMSTEAD_DEPTH - 0.6)
	var half := field.size * 0.5
	var n := 2 + int(_h(b, 1) * 3.0)                # 2..4 strips
	var side_by_side := _h(b, 2) < 0.55             # strips next to each other, or one above the other
	var span := field.size.x if side_by_side else field.size.y
	var weights: Array[float] = []
	var total := 0.0
	for i in n:
		var w := 0.7 + 0.6 * _h(b, 10 + i)
		weights.append(w)
		total += w
	var strips: Array = []
	var at := -span * 0.5
	for i in n:
		var w := span * weights[i] / total
		var rect: Rect2
		if side_by_side:
			rect = Rect2(at, -half.y, w, field.size.y)
		else:
			rect = Rect2(-half.x, at, field.size.x, w)
		at += w
		# the balk between two strips: each strip gives up a little on its inner sides
		var inner := rect
		if side_by_side:
			inner = inner.grow_individual(-BALK if i > 0 else 0.0, 0.0, -BALK if i < n - 1 else 0.0, 0.0)
		else:
			inner = inner.grow_individual(0.0, -BALK if i > 0 else 0.0, 0.0, -BALK if i < n - 1 else 0.0)
		var along_x := inner.size.x >= inner.size.y   # furrows along the longer side
		if _h(b, 30 + i) < 0.2:
			along_x = not along_x                      # now and then ploughed the other way
		strips.append({"rect": inner, "poly": _wobbly(b, inner, 100 + i * 40), "along_x": along_x,
			"fallow": n >= 3 and _h(b, 20 + i) < 0.28, "tint": 0.88 + 0.22 * _h(b, 50 + i),
			"crop": int(_h(b, 70 + i) * CROP_TINTS.size()) % CROP_TINTS.size()})
	var out := {"center": field.get_center(), "angle": (_h(b, 3) - 0.5) * deg_to_rad(7.0), "strips": strips,
		"size": field.size}
	_cache[b.id] = out
	return out


## A rectangle whose edges wander a little: points every EDGE_STEP metres pushed along the normal.
static func _wobbly(b: BuildingState, r: Rect2, salt: int) -> PackedVector2Array:
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var pts := PackedVector2Array()
	var k := 0
	for e in 4:
		var a: Vector2 = corners[e]
		var c: Vector2 = corners[(e + 1) % 4]
		var normal := (c - a).normalized().orthogonal()
		var steps := maxi(int(a.distance_to(c) / EDGE_STEP), 1)
		for s in steps:
			var t := float(s) / float(steps)
			var wobble := (_h(b, salt + k) - 0.5) * 2.0 * EDGE_WOBBLE
			if s == 0:
				wobble *= 0.4   # the corners stay near the corners: the field keeps its footprint
			pts.append(a.lerp(c, t) + normal * wobble)
			k += 1
	return pts


## What the field looks like this month.
static func stage(b: BuildingState, month: int) -> StringName:
	var work := b.def().work
	var sow := int(work.get("sow_month", 3))
	var harvest := int(work.get("harvest_month", 8))
	if month < sow:
		return &"ploughed"
	if month == sow:
		return &"sown"
	if month < harvest - 1:
		return &"growing"
	if month < harvest:
		return &"ripening"
	return &"ripe" if b.crop >= 1.0 else &"stubble"


static func colours(stage_id: StringName) -> Array[Color]:
	match stage_id:
		&"ploughed":
			return [COL_SOIL, COL_SOIL_DARK]
		&"sown":
			return [COL_SOWN, COL_SOIL_DARK]
		&"growing":
			return [COL_GREEN, COL_GREEN_DARK]
		&"ripening":
			return [COL_RIPENING, COL_GREEN_DARK]
		&"ripe":
			return [COL_RIPE, COL_RIPE_DARK]
	return [COL_STUBBLE, COL_RIPE_DARK]


## Draws the field on a canvas item. `detail` adds the furrows (close zoom only); `min_line` is the thinnest
## line worth drawing in metres (the marks of the mid zoom pass a larger one).
static func draw(ci: CanvasItem, b: BuildingState, month: int, detail: bool, alpha: float = 1.0) -> void:
	var lay := layout(b)
	var st := stage(b, month)
	var cols := colours(st)
	ci.draw_set_transform(lay["center"], float(lay["angle"]), Vector2.ONE)
	# the grass under the whole field shows between the strips: the balks
	var size: Vector2 = lay["size"]
	ci.draw_rect(Rect2(-size * 0.5 - Vector2(0.3, 0.3), size + Vector2(0.6, 0.6)), Color(COL_BALK, COL_BALK.a * alpha))
	for strip: Dictionary in lay["strips"]:
		var tint := float(strip["tint"])
		var fallow := bool(strip["fallow"])
		var crop: Color = CROP_TINTS[int(strip.get("crop", 0))]
		var base := (COL_FALLOW if fallow else cols[0] * crop) * tint
		ci.draw_colored_polygon(strip["poly"], Color(base, alpha))
		if not detail:
			continue
		var line := Color((cols[1] if not fallow else COL_FALLOW.darkened(0.12)) * tint, 0.75 * alpha)
		var width := 0.36 if st in [&"growing", &"ripening", &"ripe"] else 0.26
		if fallow:
			continue   # a fallow strip is grazed grass: no rows
		# all the furrows of a strip in one command (a line each was thousands of commands replayed every frame)
		ci.draw_multiline(furrows(strip), line, width)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The flat picture of the mid zoom: the strips as plain rectangles in world coordinates, no transform, no
## triangulation — a couple of pixels of wobble or a few degrees of turn do not show from that height, and this
## is redrawn while the camera zooms.
static func draw_flat(ci: CanvasItem, b: BuildingState, month: int, alpha: float = 1.0) -> void:
	var lay := layout(b)
	var cols := colours(stage(b, month))
	var c: Vector2 = lay["center"]
	var size: Vector2 = lay["size"]
	ci.draw_rect(Rect2(c - size * 0.5, size), Color(COL_BALK, COL_BALK.a * alpha))
	for strip: Dictionary in lay["strips"]:
		var crop: Color = CROP_TINTS[int(strip.get("crop", 0))]
		var base := (COL_FALLOW if bool(strip["fallow"]) else cols[0] * crop) * float(strip["tint"])
		var r: Rect2 = strip["rect"]
		ci.draw_rect(Rect2(c + r.position, r.size), Color(base, alpha))


## The furrows of a strip as pairs of points (for draw_multiline), cached with the layout.
static func furrows(strip: Dictionary) -> PackedVector2Array:
	if strip.has("furrows"):
		return strip["furrows"]
	var out := PackedVector2Array()
	var inset: Rect2 = (strip["rect"] as Rect2).grow(-EDGE_WOBBLE - 0.2)
	if inset.size.x > 0.5 and inset.size.y > 0.5:
		if bool(strip["along_x"]):
			var y := inset.position.y + FURROW_GAP * 0.5
			while y < inset.end.y:
				out.append(Vector2(inset.position.x, y))
				out.append(Vector2(inset.end.x, y))
				y += FURROW_GAP
		else:
			var x := inset.position.x + FURROW_GAP * 0.5
			while x < inset.end.x:
				out.append(Vector2(x, inset.position.y))
				out.append(Vector2(x, inset.end.y))
				x += FURROW_GAP
	strip["furrows"] = out
	return out


## Every field of these farms in one mesh (strips, balks and furrows, with vertex colours): drawn with a single
## command. `detail` adds the furrows. Built on the CPU once per change of buildings or month.
static func build_mesh(farms: Array, month: int, detail: bool) -> ArrayMesh:
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	for b: BuildingState in farms:
		var lay := layout(b)
		var xf := Transform2D(float(lay["angle"]), lay["center"])
		var st := stage(b, month)
		var cols := colours(st)
		var size: Vector2 = lay["size"]
		_quad(verts, colors, xf, Rect2(-size * 0.5 - Vector2(0.3, 0.3), size + Vector2(0.6, 0.6)), COL_BALK)
		for strip: Dictionary in lay["strips"]:
			var tint := float(strip["tint"])
			var fallow := bool(strip["fallow"])
			var crop: Color = CROP_TINTS[int(strip.get("crop", 0))]
			var base := (COL_FALLOW if fallow else cols[0] * crop) * tint
			base.a = 1.0
			var poly: PackedVector2Array = strip["poly"]
			if not strip.has("tris"):
				strip["tris"] = Geometry2D.triangulate_polygon(poly)
			var tris: PackedInt32Array = strip["tris"]
			for i in tris:
				verts.append(xf * poly[i])
				colors.append(base)
			if not detail or fallow:
				continue
			var line := Color((cols[1]) * tint, 0.75)
			var half := (0.36 if st in [&"growing", &"ripening", &"ripe"] else 0.26) * 0.5
			var f := furrows(strip)
			for k in range(0, f.size(), 2):
				var a := f[k]
				var c := f[k + 1]
				var n := (c - a).normalized().orthogonal() * half
				_tri(verts, colors, xf, a + n, c + n, c - n, line)
				_tri(verts, colors, xf, a + n, c - n, a - n, line)
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _quad(verts: PackedVector2Array, colors: PackedColorArray, xf: Transform2D, r: Rect2, col: Color) -> void:
	var p0 := r.position
	var p1 := Vector2(r.end.x, r.position.y)
	var p2 := r.end
	var p3 := Vector2(r.position.x, r.end.y)
	_tri(verts, colors, xf, p0, p1, p2, col)
	_tri(verts, colors, xf, p0, p2, p3, col)


static func _tri(verts: PackedVector2Array, colors: PackedColorArray, xf: Transform2D, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	verts.append(xf * a)
	verts.append(xf * b)
	verts.append(xf * c)
	colors.append(col)
	colors.append(col)
	colors.append(col)


## Forgets the layouts (the buildings changed: a farm was removed and its id could come back).
static func clear_cache() -> void:
	_cache.clear()

