extends RefCounted
## Builds the terrain-following ground meshes of the settlement: fields, roads, plazas, yards.
## Every vertex is projected with the terrain altitude, so decals follow hills and banks.

const FIELD_SHADER := preload("res://valley/ground/field.gdshader")
const ROAD_SHADER := preload("res://valley/ground/road.gdshader")
const DECAL_SHADER := preload("res://valley/ground/decal.gdshader")
const PLAZA_SHADER := preload("res://valley/ground/plaza.gdshader")
const EARTH_SHADER := preload("res://valley/ground/earth.gdshader")
const CROPS := {"wheat": 0, "barley": 1, "plowed": 2, "green": 3, "hay": 4, "flax": 5}


static func _mesh(verts: PackedVector2Array, uvs: PackedVector2Array, cols: PackedColorArray,
		idx: PackedInt32Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _node(mesh: ArrayMesh, shader: Shader, name: String) -> MeshInstance2D:
	var mi := MeshInstance2D.new()
	mi.name = name
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mi.material = mat
	return mi


static func _quad_grid(poly: Array, step: float, verts: PackedVector2Array, uvs: PackedVector2Array,
		cols: PackedColorArray, idx: PackedInt32Array, col: Color, dir_deg: float) -> void:
	## Bilinear grid over a quad, each vertex projected on the terrain. UV in metres along/across `dir`.
	var p0: Vector2 = poly[0]
	var p1: Vector2 = poly[1]
	var p2: Vector2 = poly[2]
	var p3: Vector2 = poly[3]
	var nu := maxi(2, int(ceil(maxf(p0.distance_to(p1), p3.distance_to(p2)) / step)))
	var nv := maxi(2, int(ceil(maxf(p0.distance_to(p3), p1.distance_to(p2)) / step)))
	var a := deg_to_rad(dir_deg)
	var ax := Vector2(cos(a), sin(a))
	var ay := Vector2(-sin(a), cos(a))
	var base := verts.size()
	for j in nv + 1:
		var t := float(j) / nv
		for i in nu + 1:
			var s := float(i) / nu
			var top := p0.lerp(p1, s)
			var bot := p3.lerp(p2, s)
			var q := top.lerp(bot, t)
			verts.append(Proj.project(q.x, q.y))
			uvs.append(Vector2(q.dot(ax), q.dot(ay)))
			# distance to the quad border (approximate, in metres)
			var de: float = minf(minf(s, 1.0 - s) * p0.distance_to(p1), minf(t, 1.0 - t) * p0.distance_to(p3))
			cols.append(Color(col.r, col.g, clampf(de / 8.0, 0.0, 1.0), Proj.light_at(q.x, q.y) / 1.5))
	for j in nv:
		for i in nu:
			var k := base + j * (nu + 1) + i
			idx.append_array([k, k + 1, k + nu + 2, k, k + nu + 2, k + nu + 1])


static func _poly_grid(poly: PackedVector2Array, step: float, verts: PackedVector2Array, uvs: PackedVector2Array,
		cols: PackedColorArray, idx: PackedInt32Array) -> void:
	## Regular grid over any simple polygon; COLOR.b = distance to the border (m / 8), 0 outside.
	var bb := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		bb = bb.expand(q)
	bb = bb.grow(step)
	var nx := int(ceil(bb.size.x / step)) + 1
	var ny := int(ceil(bb.size.y / step)) + 1
	var base := verts.size()
	var inside := PackedByteArray()
	inside.resize(nx * ny)
	for j in ny:
		for i in nx:
			var q := bb.position + Vector2(i, j) * step
			var de := INF
			for k in poly.size():
				var cp := Geometry2D.get_closest_point_to_segment(q, poly[k], poly[(k + 1) % poly.size()])
				de = minf(de, q.distance_to(cp))
			var ins := Geometry2D.is_point_in_polygon(q, poly)
			verts.append(Proj.project(q.x, q.y))
			uvs.append(q)
			cols.append(Color(0, 0, clampf(de / 8.0, 0.0, 1.0) if ins else 0.0, Proj.light_at(q.x, q.y) / 1.5))
			inside[j * nx + i] = 1 if (ins or de < step) else 0
	for j in ny - 1:
		for i in nx - 1:
			var k := j * nx + i
			if inside[k] + inside[k + 1] + inside[k + nx] + inside[k + nx + 1] == 0:
				continue
			var b := base + k
			idx.append_array([b, b + 1, b + nx + 1, b, b + nx + 1, b + nx])


static func build_fields(fields: Array) -> MeshInstance2D:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for f in fields:
		var poly := []
		for p in f["polygon"]:
			poly.append(Vector2(p[0], p[1]))
		var crop: int = CROPS.get(f["crop"], 0)
		_quad_grid(poly, 4.0, verts, uvs, cols, idx, Color(crop / 8.0, rng.randf(), 0, 1), float(f["dir"]))
	return _node(_mesh(verts, uvs, cols, idx), FIELD_SHADER, "Fields")


static func smooth_polyline(pts: Array, step: float) -> PackedVector2Array:
	## Centripetal-ish Catmull-Rom through the points, resampled every `step` metres.
	var p := PackedVector2Array()
	for q in pts:
		p.append(Vector2(q[0], q[1]))
	if p.size() < 2:
		return p
	var dense := PackedVector2Array()
	for i in p.size() - 1:
		var a := p[maxi(i - 1, 0)]
		var b := p[i]
		var c := p[i + 1]
		var d := p[mini(i + 2, p.size() - 1)]
		var n := maxi(2, int(b.distance_to(c) / 1.0))
		for k in n:
			var t := float(k) / n
			var t2 := t * t
			var t3 := t2 * t
			dense.append(0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2
				+ (-a + 3.0 * b - 3.0 * c + d) * t3))
	dense.append(p[p.size() - 1])
	var out := PackedVector2Array([dense[0]])
	var acc := 0.0
	for i in range(1, dense.size()):
		acc += dense[i].distance_to(dense[i - 1])
		if acc >= step:
			out.append(dense[i])
			acc = 0.0
	if out[out.size() - 1] != dense[dense.size() - 1]:
		out.append(dense[dense.size() - 1])
	return out


static func build_roads(roads: Array, inside: Callable) -> MeshInstance2D:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	# draw paths first, main roads last (on top at junctions)
	var order := {"path": 0, "lane": 1, "main": 2}
	var sorted := roads.duplicate()
	sorted.sort_custom(func(a, b): return order[a["kind"]] < order[b["kind"]])
	for r in sorted:
		var pts := smooth_polyline(r["points"], 2.0)
		var w: float = r["width"]
		var kind: float = {"path": 0.0, "lane": 0.5, "main": 1.0}[r["kind"]]
		var dist := 0.0
		var base := verts.size()
		for i in pts.size():
			var a := pts[maxi(i - 1, 0)]
			var b := pts[mini(i + 1, pts.size() - 1)]
			var tdir := (b - a).normalized()
			var nrm := Vector2(-tdir.y, tdir.x)
			if i > 0:
				dist += pts[i].distance_to(pts[i - 1])
			# width breathes a little along the road
			var ww := w * (1.0 + 0.12 * sin(dist * 0.11) + 0.06 * sin(dist * 0.37))
			var cob := 1.0 if (r["kind"] != "path" and inside.call(pts[i].x, pts[i].y)) else 0.0
			for side in [-0.5, 0.5]:
				var q: Vector2 = pts[i] + nrm * ww * side
				verts.append(Proj.project(q.x, q.y))
				uvs.append(Vector2(side + 0.5, dist))
				cols.append(Color(kind, ww / 10.0, cob, Proj.light_at(q.x, q.y) / 1.5))
		for i in pts.size() - 1:
			var k := base + i * 2
			idx.append_array([k, k + 1, k + 3, k, k + 3, k + 2])
	return _node(_mesh(verts, uvs, cols, idx), ROAD_SHADER, "Roads")


static func build_plazas(plazas: Array, kind := "cobble") -> MeshInstance2D:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for p in plazas:
		if p.get("kind", "cobble") != kind:
			continue
		var poly := []
		for q in p["polygon"]:
			poly.append(Vector2(q[0], q[1]))
		if poly.size() == 4:
			_quad_grid(poly, 3.0, verts, uvs, cols, idx, Color(0, 0, 0, 1), 0.0)
		else:
			_poly_grid(PackedVector2Array(poly), 3.0, verts, uvs, cols, idx)
	if kind == "earth":
		# edge distance must be allowed to grow beyond 8 m for the wide soft border
		pass
	return _node(_mesh(verts, uvs, cols, idx), EARTH_SHADER if kind == "earth" else PLAZA_SHADER,
		"Earth" if kind == "earth" else "Plazas")


static func build_yards(yards: Array) -> MeshInstance2D:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in yards:
		var cx: float = y["x"]
		var cy: float = y["y"]
		var hw: float = y["w"] * 0.5
		var hd: float = y["d"] * 0.5
		var base := verts.size()
		var g := rng.randf()
		for j in 3:
			for i in 3:
				var u := float(i) / 2.0
				var v := float(j) / 2.0
				var q := Vector2(cx - hw + u * hw * 2.0, cy - hd + v * hd * 2.0)
				verts.append(Proj.project(q.x, q.y))
				uvs.append(Vector2(u, v))
				cols.append(Color(1, g, 0, Proj.light_at(q.x, q.y) / 1.5))
		for j in 2:
			for i in 2:
				var k := base + j * 3 + i
				idx.append_array([k, k + 1, k + 4, k, k + 4, k + 3])
	return _node(_mesh(verts, uvs, cols, idx), DECAL_SHADER, "Yards")
