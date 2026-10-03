extends RefCounted
## Catalogue of pre-rendered sprites (buildings, props, trees) with anchors and shadows.

const SHADOW_SHADER := preload("res://valley/buildings/shadow_sprite.gdshader")
const BDIR := "res://assets/sprites/buildings/"

var buildings: Dictionary = {}
var veg: Dictionary = {}
var veg_atlas: Texture2D
var veg_shadow_atlas: Texture2D
var _tex_cache: Dictionary = {}
var _shadow_mat_red: ShaderMaterial
var _shadow_mat_alpha: ShaderMaterial


func _init() -> void:
	buildings = _json("res://assets/sprites/buildings/buildings.json")
	veg = _json("res://data/valley/vegetation.json")
	if not veg.is_empty():
		veg_atlas = load("res://assets/vegetation/" + String(veg["atlas"]))
		veg_shadow_atlas = load("res://assets/vegetation/" + String(veg["shadow_atlas"]))
	_shadow_mat_red = ShaderMaterial.new()
	_shadow_mat_red.shader = SHADOW_SHADER
	_shadow_mat_red.set_shader_parameter("use_red", true)
	_shadow_mat_alpha = ShaderMaterial.new()
	_shadow_mat_alpha.shader = SHADOW_SHADER
	_shadow_mat_alpha.set_shader_parameter("use_red", false)


static func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func has(type: String) -> bool:
	return buildings.has(type) or (veg.has("sprites") and veg["sprites"].has(type))


func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]


func make(type: String, x: float, y: float, z: float, scale := 1.0) -> Dictionary:
	## Returns {"body": Node2D (put in the y-sorted layer), "shadow": Sprite2D (shadow layer)}.
	var body_tex: Texture2D
	var shadow_tex: Texture2D
	var anchor: Vector2
	var red := true
	if buildings.has(type):
		var m: Dictionary = buildings[type]
		body_tex = _tex(BDIR + type + ".png")
		shadow_tex = _tex(BDIR + type + "_sh.png")
		anchor = Vector2(m["anchor"][0], m["anchor"][1])
	elif veg.has("sprites") and veg["sprites"].has(type):
		var m: Dictionary = veg["sprites"][type]
		var r: Array = m["rect"]
		var rect := Rect2(r[0], r[1], r[2], r[3])
		var at := AtlasTexture.new()
		at.atlas = veg_atlas
		at.region = rect
		body_tex = at
		var st := AtlasTexture.new()
		st.atlas = veg_shadow_atlas
		st.region = rect
		shadow_tex = st
		anchor = Vector2(m["anchor"][0], m["anchor"][1])
		red = false
	else:
		return {}
	var root := Node2D.new()
	root.name = type
	root.position = Proj.ground_px(x, y)
	var spr := Sprite2D.new()
	spr.texture = body_tex
	spr.centered = false
	spr.scale = Vector2(scale, scale)
	spr.position = Vector2(-anchor.x * scale, Proj.altitude_offset(z) - anchor.y * scale)
	root.add_child(spr)
	var sh := Sprite2D.new()
	sh.texture = shadow_tex
	sh.centered = false
	sh.scale = spr.scale
	sh.position = root.position + spr.position
	sh.material = _shadow_mat_red if red else _shadow_mat_alpha
	return {"body": root, "shadow": sh, "sprite": spr}
