class_name BuildColumn
extends VBoxContainer
## The building panel of the right column. It opens with Costruzioni (left column) or B, and closes by itself
## when it is not needed, so the map is not covered by a menu nobody is using. Underneath, always, whatever is
## selected on the map: the inspectors of a building or a province.
##
## Phase 18 HUD review: a framed panel titled COSTRUZIONI with a menu of the categories ("Tutte le categorie"
## first); each building a plate with its painted picture, name, what it is for, its cost with the icons of the
## goods (in red what is missing), the hours of work, and the hammer. The list scrolls inside a limited height.

signal open_changed(open: bool)

## The categories of the list: the data has six groups, the storage buildings go with the infrastructure.
const CATEGORIES: Array = [
	[&"population", "Abitazioni", &"beds"],
	[&"raw", "Risorse", &"wood"],
	[&"processing", "Produzione", &"smith"],
	[&"infrastructure", "Infrastrutture", &"road"],
	[&"military", "Militari", &"war"],
]
const DATA_TO_TAB := {&"storage": &"infrastructure"}
const LIST_MAX_HEIGHT := 430.0
const WIDTH := 370.0

var context: VBoxContainer          ## where the inspectors live
var _build: BuildController
var _panel: PanelContainer
var _choice: OptionButton
var _scroll: ScrollContainer
var _list: VBoxContainer
var _category: StringName = &""     ## &"" = every category
var _buttons: Dictionary = {}       ## building id -> Button
var _costs: Dictionary = {}         ## building id -> {res: Label}
var _refresh_timer := 0.0
var _open := false
static var _atlas: Texture2D = null
static var _sprites: Dictionary = {}


func setup(build: BuildController) -> void:
	_build = build
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", KDTheme.dark_panel())
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.visible = false
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(KDUi.icon_node(&"build", 24.0))
	var title := SettlementHud._label(head, 17, KDTheme.GOLD, true)
	title.text = "COSTRUZIONI"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_choice = OptionButton.new()
	_choice.focus_mode = Control.FOCUS_NONE
	_choice.add_theme_font_size_override("font_size", 14)
	# the painted icons are large: without a cap the menu grew as tall as the icon of a category
	_choice.add_theme_constant_override("icon_max_width", 18)
	_choice.get_popup().add_theme_constant_override("icon_max_width", 20)
	_choice.get_popup().add_theme_font_size_override("font_size", 15)
	_choice.fit_to_longest_item = false
	_choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	KDTheme.button_styles(_choice)
	_choice.add_item("Tutte le categorie")
	_choice.set_item_metadata(0, &"")
	var by_cat := _by_category()
	for entry: Array in CATEGORIES:
		if not by_cat.has(entry[0]):
			continue   # a category with nothing to build is not offered: no empty promises
		_choice.add_icon_item(KDUi.icon(entry[2]), String(entry[1]))
		_choice.set_item_metadata(_choice.item_count - 1, entry[0])
	_choice.item_selected.connect(func(i: int) -> void: show_category(StringName(_choice.get_item_metadata(i))))
	head.add_child(_choice)
	var close := KDTheme.close_button()
	close.tooltip_text = "Chiudi (B o Esc)"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	context = VBoxContainer.new()
	context.add_theme_constant_override("separation", 6)
	add_child(context)
	show_category(&"")
	if _build:
		_build.mode_changed.connect(func(_d: StringName) -> void: refresh())


## Opens or closes the building list (build mode). Closing it also drops a building still held by the mouse.
func set_open(on: bool) -> void:
	if on == _open:
		return
	_open = on
	_panel.visible = on
	if not on and _build and _build.active():
		_build.stop()
	if on:
		refresh()
		call_deferred("_fit")
	open_changed.emit(on)


func is_open() -> bool:
	return _open


func toggle() -> void:
	set_open(not _open)


static func _by_category() -> Dictionary:
	var out := {}
	for d: BuildingDef in Defs.all("buildings"):
		if not d.buildable:
			continue
		var tab: StringName = DATA_TO_TAB.get(d.category, d.category)
		if not out.has(tab):
			out[tab] = []
		(out[tab] as Array).append(d)
	return out


## Shows one category, or all of them with &"" (in the order of CATEGORIES).
func show_category(cat: StringName) -> void:
	_category = cat
	for i in _choice.item_count:
		if StringName(_choice.get_item_metadata(i)) == cat:
			_choice.select(i)
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_buttons.clear()
	_costs.clear()
	var by_cat := _by_category()
	for entry: Array in CATEGORIES:
		if cat != &"" and entry[0] != cat:
			continue
		for d: BuildingDef in by_cat.get(entry[0], []):
			_list.add_child(_entry(d))
	refresh()
	call_deferred("_fit")


## The list is as tall as what it holds, up to LIST_MAX_HEIGHT (less when an inspector is open under it).
func _fit() -> void:
	if _scroll == null:
		return
	var room := LIST_MAX_HEIGHT - (180.0 if context.get_children().any(func(c: Node) -> bool: return c is Control and (c as Control).visible) else 0.0)
	_scroll.custom_minimum_size = Vector2(WIDTH - 24.0, clampf(_list.get_combined_minimum_size().y, 60.0, room))


## One building: its picture, its name, what it is for, its cost and hours of work, and the hammer.
func _entry(d: BuildingDef) -> Button:
	var btn := KDTipButton.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(WIDTH - 36.0, 76)
	KDTheme.button_styles(btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.offset_top = 4
	row.offset_bottom = -4
	btn.add_child(row)
	var picture := TextureRect.new()
	picture.texture = building_picture(d)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(58, 58)
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(picture)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var name_label := SettlementHud._label(text, 16, KDTheme.TEXT_LIGHT, true)
	name_label.text = d.display_name
	name_label.name = "Name"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var what := SettlementHud._label(text, 13, Color(KDTheme.TEXT_LIGHT, 0.7), false)
	what.text = _first_sentence(d.description)
	what.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	what.clip_text = true
	what.custom_minimum_size = Vector2(200, 0)
	what.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var costs := HBoxContainer.new()
	costs.add_theme_constant_override("separation", 4)
	costs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(costs)
	var labels := {}
	if d.cost.is_empty():
		var free := SettlementHud._label(costs, 13, Color(KDTheme.TEXT_LIGHT, 0.8), false)
		free.text = "nessun materiale"
	for res: StringName in d.cost.keys():
		if KDUi.has(StringName("icon_%s" % res)):
			var ic := KDUi.icon_node(res, 17.0)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			costs.add_child(ic)
		var amount := SettlementHud._label(costs, 14, KDTheme.TEXT_LIGHT, true)
		amount.text = "%d" % int(d.cost[res])
		amount.custom_minimum_size = Vector2(24, 0)
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels[res] = amount
	if d.build_hours > 0.0 and not d.is_line:
		var hours := SettlementHud._label(costs, 13, Color(KDTheme.TEXT_LIGHT, 0.65), false)
		hours.text = "  %d ore di lavoro" % roundi(d.build_hours)
		hours.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hammer := KDUi.icon_node(&"build", 26.0)
	hammer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hammer.name = "Hammer"
	row.add_child(hammer)
	var def_id := d.id
	btn.pressed.connect(func() -> void:
		if _build:
			if _build.def_id == def_id:
				_build.stop()
			else:
				_build.start(def_id))
	_buttons[d.id] = btn
	_costs[d.id] = labels
	return btn


static func _first_sentence(text: String) -> String:
	var cut := text.find(". ")
	return text.substr(0, cut + 1) if cut > 0 else text


## The painted picture of a building from the atlas of the map (the road has the road icon).
static func building_picture(d: BuildingDef) -> Texture2D:
	if _atlas == null:
		var meta: Dictionary = Defs.read_json(SettlementLayer.ATLAS_DIR + "/building_atlas.json")
		_atlas = load(SettlementLayer.ATLAS_DIR + "/" + String(meta["atlas"]))
		_sprites = meta["sprites"]
	var key := String(d.sprite) if d.sprite != &"" else String(d.id)
	if d.id == &"farm":
		key = "farm_green"   # a field in leaf reads better than bare earth at the size of a button
	if not _sprites.has(key) or _atlas == null:
		return KDUi.icon(&"road" if d.id == &"road" else &"build")
	var r: Array = _sprites[key]["rect"]
	var tex := AtlasTexture.new()
	tex.atlas = _atlas
	tex.region = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	return tex


func _process(delta: float) -> void:
	if not _open:
		return
	_refresh_timer += delta
	if _refresh_timer > 0.5:
		_refresh_timer = 0.0
		refresh()


func refresh() -> void:
	if not Session.has_game():
		return
	var s := _settlement()
	if s == null:
		return
	var committed := Placement.committed_materials(Session.current.world, s.id)
	for id: StringName in _buttons.keys():
		var d := Defs.building(id)
		var missing := PackedStringArray()
		for res: StringName in d.cost.keys():
			var have := s.amount(res) - int(committed.get(res, 0))
			var short := have < int(d.cost[res])
			if short:
				missing.append("%s %d" % [Defs.resource(res).display_name.to_lower(), int(d.cost[res]) - maxi(have, 0)])
			var label: Label = (_costs[id] as Dictionary).get(res)
			if label:
				label.add_theme_color_override("font_color", Color("#FF9A8A") if short else KDTheme.TEXT_LIGHT)
		var btn: Button = _buttons[id]
		var chosen := _build != null and _build.def_id == id
		btn.modulate = Color(1, 1, 1, 1) if missing.is_empty() else Color(0.85, 0.8, 0.76, 0.85)
		# the hammer is lit when the building can be raised now, dim when something is missing
		(btn.find_child("Hammer", true, false) as Control).modulate = Color(1, 1, 1, 1) if missing.is_empty() else Color(1, 1, 1, 0.35)
		(btn.find_child("Name", true, false) as Label).add_theme_color_override("font_color",
			Color("#FFE9A8") if chosen else KDTheme.TEXT_LIGHT)
		btn.tooltip_text = tooltip_for(d, missing)


## What a building does, what it costs and where it can stand, in the rich tooltip.
static func tooltip_for(d: BuildingDef, missing: PackedStringArray) -> String:
	var out := KDTip.head(d.display_name)
	if d.description != "":
		out += d.description + "\n"
	var facts: Array = []
	if d.beds > 0:
		facts.append(["Letti", "%d" % d.beds])
	if d.workers > 0:
		facts.append(["Lavoratori", "%d" % d.workers])
	if d.is_storage and d.storage > 0:
		facts.append(["Deposito", "%d" % d.storage])
	for res: StringName in d.cost.keys():
		facts.append([Defs.resource(res).display_name, "%d" % int(d.cost[res])])
	out += KDTip.rows(facts)
	var needs: Dictionary = d.requires
	if needs.has("rocks_within_m"):
		out += KDTip.note("Va costruita entro %d m da rocce affioranti%s." % [int(needs["rocks_within_m"]),
			" con una vena di ferro" if String(needs.get("deposit", "")) == "iron" else ""])
	if not missing.is_empty():
		out += KDTip.colored("Manca: %s" % ", ".join(missing), KDTip.BAD) + "\n"
	else:
		out += KDTip.note("Clic per scegliere il posto; tasto destro per annullare.")
	return out


## The settlement the column speaks of: the one the build controller works on, or the crown's own.
func _settlement() -> SettlementState:
	return _build.player_settlement() if _build else SettlementHud.player_settlement()

