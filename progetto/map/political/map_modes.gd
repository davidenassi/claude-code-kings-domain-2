class_name MapModes
extends RefCounted
## Map modes are overlays of the same map (never separate scenes): one colour per province, uploaded as a small
## lookup texture read by the terrain shader together with the province raster. Rules in data/defs/map_modes.json.

const CONFIG_PATH := "res://data/defs/map_modes.json"
const LOOKUP_WIDTH := 1024

static var _cfg: Dictionary = {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var d: Variant = Defs.read_json(CONFIG_PATH)
		_cfg = d if d is Dictionary else {"modes": []}
	return _cfg


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for m: Dictionary in config()["modes"]:
		out.append(StringName(m["id"]))
	return out


static func mode_info(mode: StringName) -> Dictionary:
	for m: Dictionary in config()["modes"]:
		if StringName(m["id"]) == mode:
			return m
	return {}


static func strength(mode: StringName) -> float:
	return float(mode_info(mode).get("strength", 0.0))


## Colour of one province in a mode; alpha 0 = no overlay.
static func province_color(mode: StringName, world: WorldState, province_id: int) -> Color:
	var wd := WorldData.get_instance()
	var g := wd.province_geo(province_id)
	var p := world.province(province_id)
	if g == null or p == null:
		return Color(0, 0, 0, 0)
	var cfg := config()
	match mode:
		&"political":
			var k := world.kingdom(p.owner)
			return k.color if k else Color(0, 0, 0, 0)
		&"culture":
			var c: CultureDef = Defs.get_def("cultures", g.culture)
			return c.color if c else Color(0, 0, 0, 0)
		&"religion":
			var r: ReligionDef = Defs.get_def("religions", g.religion)
			return r.color if r else Color(0, 0, 0, 0)
		&"resources":
			var present := {}
			for dep in g.deposits:
				present[String(dep["type"])] = true
			for t: String in cfg.get("deposit_priority", []):
				if present.has(t):
					return Color.html(String(cfg["deposit_colors"][t]))
			return Color(0, 0, 0, 0)
		&"development":
			return _gradient(float(p.development) / float(cfg.get("development_max", 6)))
		&"diplomacy":
			var colors: Dictionary = cfg.get("diplomacy_colors", {})
			var me := world.player()
			if me == null or p.owner < 0:
				return Color(0, 0, 0, 0)
			if p.owner == me.id:
				return Color.html(String(colors.get("self", "#C9A24A")))
			var rel := Diplomacy.relation(world, me.id, p.owner)
			if rel.at_war:
				return Color.html(String(colors.get("war", "#9E3125")))
			if rel.has_pact(&"vassalage"):
				return Color.html(String(colors.get("vassal" if rel.payer == p.owner else "liege", "#7FA86B")))
			if rel.has_pact(&"alliance"):
				return Color.html(String(colors.get("ally", "#4E8F5B")))
			if not rel.pacts.is_empty():
				return Color.html(String(colors.get("pact", "#6E8FA8")))
			if rel.truce_until > world.day:
				return Color.html(String(colors.get("truce", "#C0873F")))
			# nothing signed: the shade says only how they look at us
			return Color.html(String(colors.get("neutral_low", "#A8492F"))).lerp(
				Color.html(String(colors.get("neutral_high", "#6E8F5B"))), clampf((rel.opinion + 60.0) / 120.0, 0.0, 1.0))
		&"population":
			return _gradient(float(p.population) / maxf(g.area_km2, 0.1) / float(cfg.get("population_density_max", 40.0)))
	return Color(0, 0, 0, 0)


static func _gradient(t: float) -> Color:
	var cfg := config()
	return Color.html(String(cfg.get("gradient_low", "#EFE3C0"))).lerp(Color.html(String(cfg.get("gradient_high", "#8E2A1E"))), clampf(t, 0.0, 1.0))


static func build_image(mode: StringName, world: WorldState) -> Image:
	var img := Image.create(LOOKUP_WIDTH, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for p in world.provinces:
		if p.id < LOOKUP_WIDTH:
			img.set_pixel(p.id, 0, province_color(mode, world, p.id))
	return img

