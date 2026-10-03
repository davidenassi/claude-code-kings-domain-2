extends Node
## Projection, scale and terrain queries shared by every valley system (autoload "Proj").
##
## World (gameplay) units are metres: x east, y south, z up.
## Godot world pixels:  X = x * px_per_m,  Y = (y * sin_el - z * cos_el) * px_per_m.
## Node positions of objects use ground_px() (no altitude) so that y-sorting follows real depth;
## the altitude is applied as a sprite offset (see altitude_offset()).

var sin_el := 0.766
var cos_el := 0.643
var px_per_m := 32.0
var terrain: Dictionary = {}
var terrain_scale := 16.0          # Godot px per terrain texel

var _hg := PackedFloat32Array()
var _wl := PackedFloat32Array()
var _hg_nx := 0
var _hg_ny := 0
var _hg_x0 := 0.0
var _hg_y0 := 0.0
var _hg_cell := 2.0


func _ready() -> void:
	var p: Dictionary = _load_json("res://data/projection.json")
	sin_el = p.get("sin_el", sin_el)
	cos_el = p.get("cos_el", cos_el)
	px_per_m = p.get("px_per_m", px_per_m)
	terrain = _load_json("res://data/valley/terrain.json")
	if terrain.is_empty():
		push_error("terrain.json missing: run pipeline/terrain/build_terrain.py")
		return
	terrain_scale = px_per_m / float(terrain["px_per_m"])
	_load_heightgrid()


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _load_heightgrid() -> void:
	var hg: Dictionary = terrain["heightgrid"]
	_hg_nx = int(hg["nx"])
	_hg_ny = int(hg["ny"])
	_hg_x0 = float(hg["x0"])
	_hg_y0 = float(hg["y0"])
	_hg_cell = float(hg["cell_m"])
	var scale: float = hg["scale"]
	_hg = _decode16("res://assets/terrain/" + String(hg["file"]), scale)
	_wl = _decode16("res://assets/terrain/" + String(hg["water_file"]), scale)


func _decode16(path: String, scale: float) -> PackedFloat32Array:
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	var data := img.get_data()
	var n := _hg_nx * _hg_ny
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = float(data[i * 3] * 256 + data[i * 3 + 1]) * scale
	return out


# --- projection ------------------------------------------------------------------------------
func ground_px(x: float, y: float) -> Vector2:
	return Vector2(x * px_per_m, y * sin_el * px_per_m)


func world_px(x: float, y: float, z: float) -> Vector2:
	return Vector2(x * px_per_m, (y * sin_el - z * cos_el) * px_per_m)


func altitude_offset(z: float) -> float:
	return -z * cos_el * px_per_m


func project(x: float, y: float) -> Vector2:
	return world_px(x, y, height_at(x, y))


func screen_to_ground(p: Vector2) -> Vector2:
	## Inverse projection of a Godot world point onto the terrain (fixed-point iteration).
	var x := p.x / px_per_m
	var y := p.y / (sin_el * px_per_m)
	for i in 8:
		var z := height_at(x, y)
		y = (p.y / px_per_m + z * cos_el) / sin_el
	return Vector2(x, y)


# --- terrain queries -------------------------------------------------------------------------
func _sample(grid: PackedFloat32Array, x: float, y: float) -> float:
	if grid.is_empty():
		return 100.0
	var fx := clampf((x - _hg_x0) / _hg_cell, 0.0, _hg_nx - 1.001)
	var fy := clampf((y - _hg_y0) / _hg_cell, 0.0, _hg_ny - 1.001)
	var i := int(fx)
	var j := int(fy)
	var ax := fx - i
	var ay := fy - j
	var k := j * _hg_nx + i
	var a := lerpf(grid[k], grid[k + 1], ax)
	var b := lerpf(grid[k + _hg_nx], grid[k + _hg_nx + 1], ax)
	return lerpf(a, b, ay)


func height_at(x: float, y: float) -> float:
	return _sample(_hg, x, y)


func water_level_at(x: float, y: float) -> float:
	## Water surface altitude (0 where dry).
	return _sample(_wl, x, y)


func is_water(x: float, y: float) -> bool:
	return water_level_at(x, y) > height_at(x, y) + 0.05


func terrain_rect() -> Rect2:
	## Godot-pixel rectangle covered by the projected terrain.
	var k := terrain_scale
	return Rect2(0.0, float(terrain["v_offset_px"]) * k, float(terrain["width_px"]) * k,
		float(terrain["height_px"]) * k)
