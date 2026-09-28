class_name BorderMesh
extends RefCounted
## Accumulates constant-screen-width ribbons along polylines (see shaders/border.gdshader) into one ArrayMesh.

var verts := PackedVector2Array()
var uvs := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()


static func vertex_normals(pts: PackedVector2Array) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var d0 := (pts[i] - pts[maxi(i - 1, 0)]).normalized()
		var d1 := (pts[mini(i + 1, n - 1)] - pts[i]).normalized()
		if d0 == Vector2.ZERO:
			d0 = d1
		if d1 == Vector2.ZERO:
			d1 = d0
		var n0 := Vector2(-d0.y, d0.x)
		var n1 := Vector2(-d1.y, d1.x)
		var m := (n0 + n1).normalized()
		if m == Vector2.ZERO:
			m = n1
		# miter, limited so sharp corners do not spike
		out[i] = m / maxf(m.dot(n1), 0.5)
	return out


## Centred line `width_px` wide.
func add_line(pts: PackedVector2Array, normals: PackedVector2Array, color: Color, width_px: float) -> void:
	_strip(pts, normals, width_px * 0.5, color, -width_px * 0.5, color)


## Colour band on one side (side = +1 left normal, -1 right), opaque at the line, fading outwards.
func add_band(pts: PackedVector2Array, normals: PackedVector2Array, side: float, color: Color, width_px: float) -> void:
	var outer := Color(color, 0.0)
	_strip(pts, normals, 0.0, color, side * width_px, outer)


## Band with an ease-out falloff (two strips: fast fade near the line, long soft tail).
func add_soft_band(pts: PackedVector2Array, normals: PackedVector2Array, side: float, color: Color, width_px: float) -> void:
	var mid := Color(color, color.a * 0.45)
	_strip(pts, normals, 0.0, color, side * width_px * 0.35, mid)
	_strip(pts, normals, side * width_px * 0.35, mid, side * width_px, Color(color, 0.0))


func _strip(pts: PackedVector2Array, normals: PackedVector2Array, off_a: float, col_a: Color, off_b: float, col_b: Color) -> void:
	var base := verts.size()
	for i in pts.size():
		verts.append(pts[i])
		uvs.append(normals[i] * off_a)
		colors.append(col_a)
		verts.append(pts[i])
		uvs.append(normals[i] * off_b)
		colors.append(col_b)
	for i in pts.size() - 1:
		var a := base + i * 2
		indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])


func is_empty() -> bool:
	return verts.is_empty()


func commit() -> ArrayMesh:
	var m := ArrayMesh.new()
	if verts.is_empty():
		return m
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

