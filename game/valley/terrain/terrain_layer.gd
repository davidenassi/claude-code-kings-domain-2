extends Node2D
## Draws the pre-rendered valley terrain as chunk sprites (culled automatically by Godot when off
## screen). Each chunk uses the terrain shader: baked colour + detail textures + animated water.

const SHADER := preload("res://valley/terrain/terrain.gdshader")
const DIR := "res://assets/terrain/"
const DETAIL := "res://assets/textures/detail/"

var chunk_sprites: Array[Sprite2D] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var meta: Dictionary = Proj.terrain
	var k: float = Proj.terrain_scale
	var pad: float = meta.get("pad_px", 0)
	var v_off: float = meta["v_offset_px"]
	var shared := {
		"d_grass": load(DETAIL + "grass.png"),
		"d_forest": load(DETAIL + "forest.png"),
		"d_soil": load(DETAIL + "soil.png"),
		"d_rock": load(DETAIL + "rock.png"),
		"d_snow": load(DETAIL + "snow.png"),
		"water_normal": load(DETAIL + "water_normal.png"),
		"foam_tex": load(DETAIL + "foam.png"),
	}
	for c in meta["chunks"]:
		var tag: String = c["tag"]
		var spr := Sprite2D.new()
		spr.name = "Chunk_" + tag
		spr.texture = load(DIR + "color_%s.webp" % tag)
		spr.centered = false
		spr.region_enabled = true
		spr.region_rect = Rect2(pad, pad, float(c["w"]), float(c["h"]))
		spr.position = Vector2(float(c["x"]) * k, (float(c["y"]) + v_off) * k)
		spr.scale = Vector2(k, k)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("mat_tex", load(DIR + "mat_%s.png" % tag))
		mat.set_shader_parameter("light_tex", load(DIR + "light_%s.webp" % tag))
		if c["water"]:
			mat.set_shader_parameter("water_tex", load(DIR + "water_%s.png" % tag))
			mat.set_shader_parameter("has_water", true)
		for key in shared:
			mat.set_shader_parameter(key, shared[key])
		mat.set_shader_parameter("sin_el", Proj.sin_el)
		mat.set_shader_parameter("px_per_m", Proj.px_per_m)
		spr.material = mat
		add_child(spr)
		chunk_sprites.append(spr)
