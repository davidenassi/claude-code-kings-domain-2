class_name CoronationCard
extends Control
## The moment the community becomes a kingdom (Phase 15). It is shown once, when the player chooses the royal
## house: the new arms of the house, the name of the realm, the first sovereign and where the house comes from.
## Time stands still while it is on the screen — a realm is born only once.
##
## The same card tells the other end of the story: when nobody lives any more in the community, it says so and
## offers the way back to the menu (or lets the player keep looking at the empty valley).

var _arms: ArmsView
var _title: Label
var _text: Label
var _button: Button
var _speed_before := 1
var _second: Button
## True while the card tells the end of the community: its button leads to the menu.
var ending := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.03, 0.02, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", KDTheme.card_panel())
	frame.custom_minimum_size = Vector2(560, 0)
	centre.add_child(frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(col)
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 12)   # the carved corner of the frame: nothing is written on it
	col.add_child(top)
	_arms = ArmsView.new()
	_arms.custom_minimum_size = Vector2(96, 110)
	_arms.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_arms)
	_title = Label.new()
	_title.add_theme_font_override("font", KDFonts.title())
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", KDTheme.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	col.add_child(KDTheme.ornate_rule())
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", KDTheme.parchment_panel())
	col.add_child(sheet)
	_text = Label.new()
	_text.add_theme_font_override("font", KDFonts.serif())
	_text.add_theme_font_size_override("font_size", 15)
	_text.add_theme_color_override("font_color", KDTheme.INK)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.custom_minimum_size = Vector2(500, 0)
	sheet.add_child(_text)
	_button = Button.new()
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size = Vector2(300, 42)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	KDTheme.button_styles(_button)
	_button.add_theme_font_size_override("font_size", 17)
	_button.pressed.connect(_on_button)
	col.add_child(_button)
	_second = Button.new()
	_second.focus_mode = Control.FOCUS_NONE
	_second.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_second.flat = true
	_second.text = "Resta a guardare la valle"
	_second.add_theme_color_override("font_color", KDTheme.TEXT_LIGHT)
	_second.pressed.connect(close)
	_second.visible = false
	col.add_child(_second)


## Tells the story of the crowning just done and stops the clock.
func show_for(k: KingdomState) -> void:
	if not Session.has_game():
		return
	var world := Session.current.world
	var ruler := world.ruler_of(k.id)
	var origin := CourtSystem.origin_def(k.house_origin)
	_arms.arms = k.coat_of_arms
	_arms.visible = true
	_title.text = "Nasce il %s" % k.name
	var lines := PackedStringArray()
	if ruler:
		lines.append("%s della %s %s %s del Regno." % [ruler.name, k.house,
			"è incoronata prima" if ruler.female else "è incoronato primo", "Regina" if ruler.female else "Re"])
	lines.append("%s. %s" % [String(origin.get("name", k.house)), String(origin.get("text", ""))])
	var years := (world.day - k.founded_day) / PersonState.DAYS_PER_YEAR
	lines.append("Sei persone arrivarono qui %d anni fa. Da oggi c'è una corona, una casata e una successione." % maxi(years, 1))
	_text.text = "\n\n".join(lines)
	_button.text = "Lunga vita alla Regina!" if ruler and ruler.female else "Lunga vita al Re!"
	ending = false
	_second.visible = false
	_speed_before = Session.current.clock.speed_index
	Session.current.clock.set_speed(0)
	visible = true


## Tells the beginning: six people, no kingdom yet (Phase 15, brief §15.1).
func show_start(k: KingdomState) -> void:
	if not Session.has_game():
		return
	var world := Session.current.world
	var home: SettlementState = null
	for s in world.settlements:
		if s.kingdom == k.id:
			home = s
			break
	var names := PackedStringArray()
	if home:
		for p in world.people_of(home.id):
			names.append(SettlementSetup.full_name(world, p))
	_arms.visible = false
	_title.text = "Sei persone e una valle"
	var who := ", ".join(names.slice(0, names.size() - 1)) + " e " + names[names.size() - 1] if names.size() > 1 else "Sei persone"
	_text.text = ("Non possiedi ancora un Regno.\nHai soltanto sei persone e un territorio da trasformare.\n\n" +
		"%s sono arrivati a %s con un fuoco, una tettoia e le provviste per l'inverno. Il bosco, la roccia e il " +
		"fiume sono qui intorno: tutto il resto va costruito. Le famiglie che nasceranno qui, un giorno, " +
		"sceglieranno chi le guida.") % [who, home.name if home else "questa valle"]
	_button.text = "Cominciamo"
	ending = false
	_second.visible = false
	_speed_before = Session.current.clock.speed_index
	Session.current.clock.set_speed(0)
	visible = true


## Tells the end of the community: nobody is left.
func show_end(k: KingdomState) -> void:
	if not Session.has_game():
		return
	var world := Session.current.world
	_arms.arms = k.coat_of_arms
	_arms.visible = true
	_title.text = "Non resta nessuno"
	var years := (world.day - k.founded_day) / PersonState.DAYS_PER_YEAR
	var born := 0
	for f: FamilyState in world.families.values():
		born += roundi(float(f.records.get(&"children", 0.0)))
	_text.text = ("%s è finita: in %d anni vi sono nati %d bambini, ma oggi non vive più nessuno fra le sue case.\n\n" +
		"La cronaca resta: si può riprendere da un salvataggio o fondare un'altra comunità.") % [k.name, maxi(years, 1), born]
	_button.text = "Torna al menù"
	ending = true
	_second.visible = true
	_speed_before = Session.current.clock.speed_index
	Session.current.clock.set_speed(0)
	visible = true


func _on_button() -> void:
	if ending:
		Session.end()
		get_tree().change_scene_to_file(MainMenu.MENU_SCENE)
		return
	close()


func close() -> void:
	visible = false
	if Session.has_game():
		Session.current.clock.set_speed(maxi(_speed_before, 1))

