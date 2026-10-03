extends Node2D
## Library galleries for Phase 1 screenshots: buildings (with shadows) and citizens (4 animations).
## Run:  godot --path game res://gallery/gallery.tscn -- --capture=res://data/capture/gallery.json --out=DIR

const SpriteDB := preload("res://valley/buildings/sprite_db.gd")
const Capture := preload("res://tools/capture.gd")

const NAMES := {
	"house_a": "Casa semplice A", "house_b": "Casa semplice B", "house_c": "Casa semplice C",
	"house_d": "Casa semplice D", "house_e": "Casa semplice E", "house_rich_a": "Casa ricca A",
	"house_rich_b": "Casa ricca B", "house_rich_c": "Casa ricca C", "farm": "Fattoria", "granary": "Granaio",
	"sawmill": "Segheria", "quarry": "Cava", "mine": "Miniera", "windmill": "Mulino", "market": "Mercato",
	"blacksmith": "Fabbro", "barracks": "Caserma", "stable": "Stalla", "tower": "Torre di guardia",
	"wall_000": "Mura", "wall_tower": "Torre delle mura", "gatehouse": "Porta fortificata",
	"townhall": "Palazzo comunale", "castle": "Castello iniziale", "bridge_argento": "Ponte in pietra",
	"bridge_bianco": "Ponte in legno", "well": "Pozzo",
}
const ROWS := [
	["house_a", "house_b", "house_c", "house_d", "house_e", "house_rich_a", "house_rich_b", "house_rich_c"],
	["farm", "granary", "sawmill", "windmill", "blacksmith", "stable"],
	["quarry", "mine", "market", "well", "tower", "barracks"],
	["townhall", "wall_000", "wall_tower", "gatehouse", "castle"],
	["bridge_argento", "bridge_bianco"],
]
const ROLES := ["farmer", "woodcutter", "miner", "builder", "merchant", "soldier", "citizen"]
const ROLE_NAMES := {"farmer": "Contadino", "woodcutter": "Boscaiolo", "miner": "Minatore", "builder": "Costruttore",
	"merchant": "Mercante", "soldier": "Soldato", "citizen": "Cittadino"}

var db: SpriteDB
var anims: Array = []
var cam: Camera2D


class GalleryCam:
	extends Camera2D
	func jump_to(p: Vector2, z: float) -> void:
		position = p
		zoom = Vector2.ONE * z
		RenderingServer.global_shader_parameter_set("cam_zoom", z)


func _ready() -> void:
	db = SpriteDB.new()
	var bg := Polygon2D.new()
	bg.polygon = PackedVector2Array([Vector2(-4000, -4000), Vector2(14000, -4000), Vector2(14000, 9000), Vector2(-4000, 9000)])
	var mat := ShaderMaterial.new()
	mat.shader = load("res://gallery/meadow.gdshader")
	mat.set_shader_parameter("d_grass", load("res://assets/textures/detail/grass.png"))
	bg.material = mat
	add_child(bg)
	var shadows := Node2D.new()
	add_child(shadows)
	var objects := Node2D.new()
	objects.y_sort_enabled = true
	add_child(objects)
	var labels := Node2D.new()
	add_child(labels)
	# buildings: x in metres, rows spaced by the tallest sprite
	var y := 0.0
	for row in ROWS:
		var x := 0.0
		var row_h := 0.0
		for t in row:
			if not db.buildings.has(t):
				continue
			var m: Dictionary = db.buildings[t]
			var fw: float = m["footprint"][0]
			var w_px: float = m["size"][0]
			var h_px: float = m["size"][1]
			var ax: float = m["anchor"][0]
			x += maxf(fw * 0.5 + 4.0, ax / 32.0 + 2.0)
			var parts := db.make(t, x, y, 0.0)
			objects.add_child(parts["body"])
			shadows.add_child(parts["shadow"])
			_label(labels, NAMES.get(t, t), Proj.ground_px(x, y) + Vector2(0, 40))
			x += maxf(fw * 0.5 + 4.0, (w_px - ax) / 32.0 * 0.6 + 2.0)
			row_h = maxf(row_h, h_px / 32.0 / 0.766)
		y += maxf(row_h * 0.75, 24.0) + 10.0
	# citizens: one row per role, the four animations, facing south-east and east
	var f := FileAccess.open("res://assets/sprites/citizens/citizens.json", FileAccess.READ)
	if f:
		var meta: Dictionary = JSON.parse_string(f.get_as_text())
		var cy := 0.0
		for role in ROLES:
			if not meta.has(role):
				continue
			var cx := 0.0
			var tex: Texture2D = load("res://assets/sprites/citizens/" + role + ".png")
			_label(labels, ROLE_NAMES[role], Proj.ground_px(-6.0, 6000.0 / 32.0 + cy) + Vector2(-40, -20))
			for anim in ["idle", "walk", "carry", "work"]:
				for d in ["SE", "E"]:
					var s := Sprite2D.new()
					s.texture = tex
					s.region_enabled = true
					s.centered = false
					s.position = Proj.ground_px(cx, 6000.0 / 32.0 + cy) - Vector2(meta[role]["anchor"][0], meta[role]["anchor"][1])
					objects.add_child(s)
					anims.append({"s": s, "m": meta[role], "anim": anim, "dir": d})
					cx += 2.4
				cx += 1.6
			cy += 3.2
		var lx := 0.0
		for anim in ["idle", "walk", "carry", "work"]:
			_label(labels, {"idle": "fermo", "walk": "cammina", "carry": "trasporta", "work": "lavora"}[anim],
				Proj.ground_px(lx + 1.2, 6000.0 / 32.0 - 2.4))
			lx += 4.8 + 1.6
	cam = GalleryCam.new()
	cam.add_to_group("valley_camera")
	add_child(cam)
	cam.make_current()
	cam.jump_to(Vector2(1500, 800), 0.25)
	var cap := Capture.new()
	add_child(cap)


func _label(parent: Node, text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos - Vector2(80, 0)
	l.size = Vector2(160, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.98, 0.95, 0.85))
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)


var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	for a in anims:
		var m: Dictionary = a["m"]
		var n: int = m["frames"][a["anim"]]
		var fps := 3.0 if a["anim"] == "idle" else 8.0
		var frame := int(_t * fps) % n
		var key: String = a["anim"] + "_" + a["dir"]
		var rows: Dictionary = m["rows"]
		var row: int = rows[key] if rows.has(key) else rows.get(a["anim"] + "_S", 0)
		a["s"].region_rect = Rect2(frame * m["cell"][0], row * m["cell"][1], m["cell"][0], m["cell"][1])
