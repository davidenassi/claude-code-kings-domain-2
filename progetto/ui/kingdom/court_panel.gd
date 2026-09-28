class_name CourtPanel
extends KDSheet
## The CORTE sheet: the people around the sovereign — who reigns and with what head, how firmly the house holds
## the crown, who of the house could follow — and nothing else. The powers of the realm and their families are in
## the Ceti sheet, the realm's own measures in the bar at the top (consolidation: the court repeated the favour of
## the five powers, and before the crown this same place was the Famiglie sheet — the families now live in the
## estates, and the conditions of the kingdom in La mia comunità).

var _ruler: Label
var _legitimacy: Array
var _heirs: VBoxContainer
var _heirs_signature := ""
var _note: Label
var _court_parts: Array[Control] = []


func build() -> void:
	# before the crown there is no court: the page says where things are, if it is opened by its key
	_note = parchment()
	_court_parts.append(_part(section("IL SOVRANO")))
	_ruler = parchment()
	_court_parts.append(_ruler.get_parent())
	var measures := box(3)
	_court_parts.append(measures)
	_legitimacy = meter(measures, "Legittimità")
	_court_parts.append(_part(section("LA CASATA")))
	_heirs = box(3)
	_court_parts.append(_heirs)


## The whole bar of a section title (or the title itself when the kit has no painted bar).
func _part(title: Label) -> Control:
	return title if title.get_parent() == column else title.get_parent()


func refresh() -> void:
	if not Session.has_game() or column == null:
		return
	var k := Session.current.world.player()
	if k == null:
		return
	_note.get_parent().visible = not k.monarchy_founded
	for c in _court_parts:
		c.visible = k.monarchy_founded
	if not k.monarchy_founded:
		_note.text = ("Non c'è ancora una corte: nessuno regna. Le condizioni del Regno sono nella scheda La mia comunità; " +
			"la casa reale si sceglie fra le famiglie, nella scheda Ceti.")
		return
	_note.text = ""
	_refresh_court()


# --- the court ---------------------------------------------------------------------------------------------

func _refresh_court() -> void:
	if not Session.has_game() or column == null:
		return
	var session := Session.current
	var world := session.world
	var k := world.player()
	if k == null:
		return
	var ruler := world.ruler_of(k.id)
	if ruler == null:
		_ruler.text = "Il trono è vacante: i grandi del regno si contendono la corona."
	else:
		var lines := PackedStringArray()
		lines.append("%s %s di %s, %d anni%s" % ["Regina" if ruler.female else "Re", ruler.name, ruler.house,
			ruler.age_years(world.day), "  ·  reggenza" if k.regency else ""])
		var skills := PackedStringArray()
		for key: StringName in [&"governo", &"guerra", &"diplomazia", &"intrigo"]:
			skills.append("%s %d" % [String(key).capitalize(), ruler.skill(key)])
		lines.append(" · ".join(skills))
		for td in ruler.trait_defs():
			lines.append("%s — %s" % [td.display_name, td.description])
		var heir := CourtSystem.heir_of(world, k)
		lines.append("Erede: %s" % ("%s, %d anni" % [heir.name, heir.age_years(world.day)] if heir
			else "nessuno — la casata è a rischio"))
		_ruler.text = "\n".join(lines)
	set_meter(_legitimacy, k.legitimacy)
	_refresh_heirs(session, k, ruler)


func _refresh_heirs(session: GameSession, k: KingdomState, ruler: CharacterState) -> void:
	var world := session.world
	var ids := PackedInt32Array(ruler.children) if ruler else PackedInt32Array()
	var signature := "%d|%d|%s" % [k.ruler, k.heir_designate,
		",".join(PackedStringArray(Array(ids).map(func(i: int) -> String: return str(i))))]
	if signature == _heirs_signature:
		return
	_heirs_signature = signature
	clear(_heirs)
	var shown := 0
	for child_id in ids:
		var c := world.character(child_id)
		if c == null or not c.alive():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_heirs.add_child(row)
		var name_label := SettlementHud._label(row, 14, Color(KDTheme.TEXT_LIGHT, 0.9), false)
		name_label.text = "%s, %d anni · governo %d, guerra %d" % [c.name, c.age_years(world.day),
			c.skill(&"governo"), c.skill(&"guerra")]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var designated := k.heir_designate == c.id
		command_button(row, "erede designato" if designated else "designa erede",
			DesignateHeirCommand.create(k.id, -1 if designated else c.id),
			"L'erede scelto dalla corona viene prima di quello di legge")
		shown += 1
	if shown == 0:
		var none := SettlementHud._label(_heirs, 14, Color(KDTheme.TEXT_LIGHT, 0.8), false)
		none.text = "Nessun figlio a corte."

