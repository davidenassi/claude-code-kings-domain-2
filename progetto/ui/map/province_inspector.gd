class_name ProvinceInspector
extends PanelContainer
## Right-side panel with the facts of the selected province: owner, identity, geography, people, resources.
## Everything shown is read from the real state (ProvinceGeo + ProvinceState + KingdomState).

signal closed

var province_id := -1
var _arms: ArmsView
var _realm: Label
var _title: Label
var _subtitle: Label
var _grid: GridContainer
var _notes: Label
## What the crown can do here (Phase 16): improve its own land, take a free one beside it.
var _actions: VBoxContainer
var _wd: WorldData


func _ready() -> void:
	_wd = WorldData.get_instance()
	add_theme_stylebox_override("panel", KDTheme.card_panel())
	custom_minimum_size = Vector2(286, 0)   # it lives in the right column now: it keeps its width
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	_arms = ArmsView.new()
	_arms.custom_minimum_size = Vector2(44, 50)
	head.add_child(_arms)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	_title = _label(names, 19, KDTheme.GOLD, true)
	_subtitle = _label(names, 14, KDTheme.TEXT_LIGHT, false)
	var close := KDTheme.close_button()   # the painted cross, not a glyph
	close.tooltip_text = "Chiudi (Esc)"
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(func() -> void: closed.emit())
	head.add_child(close)

	_realm = _label(col, 15, KDTheme.TEXT_LIGHT, true)
	_realm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_realm.custom_minimum_size = Vector2(236, 40)
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", KDTheme.parchment_panel())
	col.add_child(sheet)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 3)
	sheet.add_child(_grid)
	_notes = _label(col, 13, Color(KDTheme.TEXT_LIGHT, 0.85), false)
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes.custom_minimum_size = Vector2(236, 62)   # three short lines: an autowrap Label does not ask for the room it needs
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 4)
	col.add_child(_actions)
	EventBus.province_owner_changed.connect(func(p: int, _o: int, _n: int, _r: StringName) -> void:
		if p == province_id:
			refresh())
	EventBus.month_passed.connect(func(_d: int) -> void: refresh())


static func _label(parent: Control, font_size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", KDFonts.serif_bold() if bold else KDFonts.serif())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func show_province(pid: int) -> void:
	province_id = pid
	visible = pid >= 0
	refresh()


func refresh() -> void:
	if province_id < 0 or not Session.has_game() or not visible:
		return
	var world := Session.current.world
	var g := _wd.province_geo(province_id)
	var p := world.province(province_id)
	if g == null or p == null:
		return
	var names: Dictionary = MapModes.config().get("names", {})
	var owner := world.kingdom(p.owner)
	_title.text = g.name
	_subtitle.text = "%s · %.1f km²" % [String((names.get("terrain", {}) as Dictionary).get(String(g.terrain), g.terrain)), g.area_km2]
	if owner:
		_arms.arms = owner.coat_of_arms
		_arms.visible = true
		_realm.text = "%s (%s) — %s%s" % [owner.name, owner.rank_label(), owner.house, "\nIl tuo dominio" if owner.is_player else ""]
	else:
		_arms.arms = null
		_arms.visible = false
		_realm.text = "Terre libere — villaggi senza corona"

	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var culture: CultureDef = Defs.get_def("cultures", g.culture)
	var religion: ReligionDef = Defs.get_def("religions", g.religion)
	_row("Cultura", culture.display_name if culture else String(g.culture))
	_row("Religione", religion.display_name if religion else String(g.religion))
	if p.is_occupied():
		var ctrl := world.kingdom(p.controller)
		_row("Occupata da", ctrl.name if ctrl else "nessuno")
	_row("Popolazione", "%s (%.0f/km²)" % [thousands(p.population), float(p.population) / maxf(g.area_km2, 0.1)])
	_row("Sviluppo", "%d / %d" % [p.development, int((Diplomacy.bal().get("ai", {}) as Dictionary).get("develop_province_max", 8))])
	_row("Fertilità", "%d%%" % roundi(g.fertility * 100.0))
	_row("Boschi", "%d%%" % roundi(g.forest * 100.0))
	_row("Altitudine", "%d m (max %d m)" % [roundi(g.elevation_mean), roundi(g.elevation_max)])
	var biomes := PackedStringArray()
	var shares: Array = g.biomes.keys()
	shares.sort_custom(func(a: String, b: String) -> bool: return float(g.biomes[a]) > float(g.biomes[b]))
	for b: String in shares.slice(0, 2):
		var bd: BiomeDef = Defs.get_def("biomes", StringName(b))
		biomes.append("%s %d%%" % [bd.display_name if bd else b, roundi(float(g.biomes[b]) * 100.0)])
	_row("Paesaggio", ", ".join(biomes))
	var water := PackedStringArray()
	if g.has_river:
		water.append("fiume")
	if g.has_lake:
		water.append("lago")
	if g.coastal:
		water.append("costa")
	_row("Acque", ", ".join(water) if not water.is_empty() else "—")
	var dep_count := {}
	var dep_names: Dictionary = names.get("deposits", {})
	for d in g.deposits:
		var key := String(d["type"])
		dep_count[key] = int(dep_count.get(key, 0)) + 1
	var deps := PackedStringArray()
	for key: String in dep_count.keys():
		var label := String(dep_names.get(key, key))
		deps.append("%s ×%d" % [label, dep_count[key]] if int(dep_count[key]) > 1 else label)
	_row("Giacimenti", ", ".join(deps) if not deps.is_empty() else "—")

	var border_names: Dictionary = names.get("borders", {})
	var special := PackedStringArray()
	var neighbour_realms := {}
	for n in g.neighbors:
		if n["type"] != &"land":
			special.append("%s con %s" % [border_names.get(String(n["type"]), n["type"]), _wd.provinces[int(n["id"])].name])
		var nk := world.owner_of(int(n["id"]))
		if nk and nk.id != p.owner:
			neighbour_realms[nk.name] = true
	var notes := PackedStringArray(["Confina con %d province." % g.neighbors.size()])
	if not special.is_empty():
		notes.append("Confini naturali: " + ", ".join(special) + ".")
	if not neighbour_realms.is_empty():
		notes.append("Domini confinanti: " + ", ".join(PackedStringArray(neighbour_realms.keys())) + ".")
	_notes.text = "\n".join(notes)
	_refresh_actions(world, p)


## One button per thing the player's crown could do with this land, disabled with the reason when it cannot.
func _refresh_actions(world: WorldState, p: ProvinceState) -> void:
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	var me := world.player()
	if me == null:
		return
	if p.owner == me.id:
		var price := DevelopProvinceCommand.cost(Session.current, p.id)
		_action("Migliora le terre (%d ori)" % roundi(price), DevelopProvinceCommand.create(me.id, p.id),
			"Campi dissodati, un mulino, un ponte: lo sviluppo alza le rendite e la gente che la terra può nutrire.")
	elif p.is_free() and ClaimProvinceCommand.borders(world, me.id, p.id):
		var price := ClaimProvinceCommand.cost(world, me.id, p.id)
		_action("Annetti al regno (%d ori)" % roundi(price), ClaimProvinceCommand.create(me.id, p.id),
			"I villaggi liberi accettano la protezione della corona: la terra entra nel regno senza guerra.")


func _action(text: String, command: Command, tip: String) -> void:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	KDTheme.button_styles(btn)
	var reason := command.validate(Session.current)
	btn.disabled = reason != ""
	btn.tooltip_text = tip if reason == "" else "%s\n%s" % [tip, reason]
	btn.pressed.connect(func() -> void:
		var result := Session.current.submit(command)
		if not result.success and result.reason != "":
			EventBus.notify("Impossibile", result.reason, &"warning")
		refresh())
	_actions.add_child(btn)
	if reason != "":
		var why := _label(_actions, 12, Color(KDTheme.TEXT_LIGHT, 0.7), false)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size = Vector2(236, 0)
		why.text = reason


func _row(key: String, value: String) -> void:
	var k := Label.new()
	k.text = key
	k.add_theme_font_override("font", KDFonts.serif_bold())
	k.add_theme_font_size_override("font_size", 13)
	k.add_theme_color_override("font_color", Color("#5A3E22"))
	_grid.add_child(k)
	var v := Label.new()
	v.text = value
	v.add_theme_font_override("font", KDFonts.serif())
	v.add_theme_font_size_override("font_size", 13)
	v.add_theme_color_override("font_color", KDTheme.INK)
	_grid.add_child(v)


## Italian thousands separator: 12345 -> "12.345".
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

