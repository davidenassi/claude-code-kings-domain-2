extends Node2D
## Library galleries for Phase 1 screenshots: buildings (with shadows) and citizens (4 animations).
## Run:  godot --path game res://gallery/gallery.tscn -- --capture=res://data/capture/gallery.json --out=DIR

const SpriteDB := preload("res://valley/buildings/sprite_db.gd")
const Capture := preload("res://tools/capture.gd")

const NAMES := {
	"house_a": "Casa A (paglia)", "house_b": "Casa B (coppi)", "house_c": "Casa C (legno)",
	"house_d": "Casa D (intonaco)", "house_e": "Casa E (pietra)", "house_rich_a": "Casa ricca A",
	"house_rich_b": "Casa ricca B", "house_rich_c": "Casa ricca C", "house_a_e": "Casa A (verso est)",
	"house_b_w": "Casa B (verso ovest)", "house_d_e": "Casa D (verso est)", "house_rich_a_e": "Casa ricca A (est)",
	"house_rich_c_w": "Casa ricca C (ovest)", "farm": "Fattoria", "granary": "Granaio",
	"sawmill": "Segheria", "quarry": "Cava", "mine": "Miniera", "windmill": "Mulino", "market": "Mercato",
	"blacksmith": "Fabbro", "barracks": "Caserma", "stable": "Stalla", "tower": "Torre di guardia",
	"wall_000": "Mura", "wall_045": "Mura (diagonale)", "wall_tower": "Torre delle mura",
	"gatehouse": "Porta fortificata", "gatehouse_ns": "Porta (est-ovest)",
	"townhall": "Palazzo comunale", "church": "Chiesa", "castle": "Castello iniziale", "bridge_argento": "Ponte in pietra",
	"bridge_bianco": "Ponte in legno", "well": "Pozzo", "stall_a": "Bancarella", "stall_c": "Bancarella",
	"prop_cart_hay": "Carro di fieno", "prop_haystack": "Covone", "prop_logs": "Cataste", "prop_barrels": "Botti",
	"prop_crates": "Casse", "prop_scarecrow": "Spaventapasseri", "fence_0000": "Recinto", "fence_0450": "Recinto",
}
const ROWS := [
	["house_a", "house_b", "house_c", "house_d", "house_e", "house_rich_a", "house_rich_b", "house_rich_c"],
	["house_a_e", "house_b_w", "house_d_e", "house_rich_a_e", "house_rich_c_w", "well", "stall_a", "stall_c"],
	["farm", "granary", "sawmill", "windmill", "blacksmith", "stable"],
	["quarry", "mine", "market", "tower", "barracks"],
	["townhall", "church", "wall_000", "wall_045", "wall_tower", "gatehouse", "gatehouse_ns"],
	["castle", "bridge_argento", "bridge_bianco"],
	["prop_cart_hay", "prop_haystack", "prop_logs", "prop_barrels", "prop_crates", "prop_scarecrow", "fence_0000",
		"fence_0450"],
]
const ROLES := ["farmer", "woodcutter", "miner", "builder", "merchant", "soldier", "citizen"]
const ROLE_NAMES := {"farmer": "Contadino", "woodcutter": "Boscaiolo", "miner": "Minatore", "builder": "Costruttore",
	"merchant": "Mercante", "soldier": "Soldato", "citizen": "Cittadino"}

var db: SpriteDB
var anims: Array = []
var citizens_y := 187.5
var _labels: Array = []
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
	# buildings: x in metres; each row is spaced by its tallest part above / below the anchor
	var k := 32.0 * 0.766            # sprite px per ground metre (vertical)
	var y := 0.0
	for row in ROWS:
		var up := 0.0
		var down := 0.0
		for t in row:
			if db.buildings.has(t):
				var mm: Dictionary = db.buildings[t]
				up = maxf(up, float(mm["anchor"][1]) / k)
				down = maxf(down, (float(mm["size"][1]) - float(mm["anchor"][1])) / k)
		y += up + 2.0
		var x := 0.0
		for t in row:
			if not db.buildings.has(t):
				continue
			var m: Dictionary = db.buildings[t]
			var fw: float = m["footprint"][0]
			var w_px: float = m["size"][0]
			var ax: float = m["anchor"][0]
			x += maxf(maxf(fw * 0.5 + 3.0, ax / 32.0 + 2.0), 7.0)
			var parts := db.make(t, x, y, 0.0)
			objects.add_child(parts["body"])
			shadows.add_child(parts["shadow"])
			_label(labels, NAMES.get(t, t), Proj.ground_px(x, y + down + 1.0))
			x += maxf(maxf(fw * 0.5 + 3.0, (w_px - ax) / 32.0 + 2.0), 7.0)
		y += down + 8.0
	citizens_y = y + 12.0
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
			_label(labels, ROLE_NAMES[role], Proj.ground_px(-6.0, citizens_y + cy) + Vector2(-40, -20))
			for anim in ["idle", "walk", "carry", "work"]:
				for d in ["SE", "E"]:
					var s := Sprite2D.new()
					s.texture = tex
					s.region_enabled = true
					s.centered = false
					s.position = Proj.ground_px(cx, citizens_y + cy) - Vector2(meta[role]["anchor"][0], meta[role]["anchor"][1])
					objects.add_child(s)
					anims.append({"s": s, "m": meta[role], "anim": anim, "dir": d})
					cx += 2.4
				cx += 1.6
			cy += 3.2
		var lx := 0.0
		for anim in ["idle", "walk", "carry", "work"]:
			_label(labels, {"idle": "fermo", "walk": "cammina", "carry": "trasporta", "work": "lavora"}[anim],
				Proj.ground_px(lx + 1.2, citizens_y - 2.4))
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
	l.position = pos - Vector2(110, 0)
	l.size = Vector2(220, 30)
	_labels.append([l, pos])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
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
	# labels keep a readable size on screen at any zoom
	if cam:
		var sc := clampf(0.62 / cam.zoom.x, 1.0, 6.0)
		for e in _labels:
			var l: Label = e[0]
			l.scale = Vector2(sc, sc)
			l.position = e[1] - Vector2(110, 0) * sc
