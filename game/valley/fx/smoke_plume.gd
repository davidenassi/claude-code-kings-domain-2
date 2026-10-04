extends Node2D
## Chimney smoke: a handful of soft puffs that rise, drift downwind, swell and fade, in a loop.
## Deterministic and cheap (a few Sprite2D per chimney, updated only when visible). Replaces the
## CPUParticles2D emitters, which were created but never drawn by the compatibility renderer here.

const N := 7

var life := 6.5            # seconds for a puff to rise and vanish
var rise := 88.0           # px risen over a life
var drift := 34.0          # px pushed downwind (east) over a life
var size := 0.48           # puff scale at birth (texture is 64 px)
var grow := 1.1            # extra scale at the end of the life
var alpha := 0.62
var tint := Color(0.94, 0.94, 0.92)
var _puffs: Array[Sprite2D] = []
var _seed := 0.0

static var _tex: Texture2D


static func puff_texture() -> Texture2D:
	if _tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.55, Color(1, 1, 1, 0.55))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_tex = t
	return _tex


func _ready() -> void:
	_seed = fposmod(position.x * 0.0137 + position.y * 0.0071, 1.0) * life
	for i in N:
		var s := Sprite2D.new()
		s.texture = puff_texture()
		add_child(s)
		_puffs.append(s)
	_update()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_update()


func _update() -> void:
	var t := Time.get_ticks_msec() / 1000.0 + _seed
	for i in N:
		var a := fposmod(t / life + float(i) / N, 1.0)          # age 0..1
		var s := _puffs[i]
		var wob := sin(t * 0.9 + i * 1.7) * 3.0 * a
		s.position = Vector2(drift * a * a + wob, -rise * a)
		s.scale = Vector2.ONE * (size + grow * a)
		var k := smoothstep(0.0, 0.12, a) * (1.0 - a) * (1.0 - a)
		s.modulate = Color(tint.r, tint.g, tint.b, alpha * k * 1.6)
