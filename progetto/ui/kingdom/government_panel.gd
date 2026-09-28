class_name GovernmentPanel
extends KDSheet
## The GOVERNO sheet: the permanent laws of the realm, one per group, and the edicts that last a season.
## Every button says what the choice does, who gains, who loses, and — when it cannot be done — why.

var _laws: VBoxContainer
var _edicts: VBoxContainer
var _signature := ""
## Before the crown (Phase 15) the sheet says how the community decides, and the laws wait.
var _community: Label
var _heads: Array[Control] = []


func build() -> void:
	_community = parchment()
	_heads.append(_bar_of(section("LEGGI")))
	_laws = box(6)
	_heads.append(_bar_of(section("EDITTI")))
	_edicts = box(4)


static func _bar_of(title: Label) -> Control:
	return title.get_parent() as Control if title.get_parent() is PanelContainer else title


func refresh() -> void:
	if not Session.has_game() or column == null:
		return
	var session := Session.current
	var k := session.world.player()
	if k == null:
		return
	(_community.get_parent() as Control).visible = not k.monarchy_founded
	for head in _heads:
		head.visible = k.monarchy_founded
	_laws.visible = k.monarchy_founded
	_edicts.visible = k.monarchy_founded
	if not k.monarchy_founded:
		_community.text = ("Non c'è ancora una corona, e dunque nessuna legge scritta né editto.\n\n" +
			"La comunità decide insieme, per consuetudine: le famiglie si parlano attorno al fuoco e ciò che si fa lo " +
			"decide il bisogno. Con la fondazione del Regno arriveranno le leggi — tasse, successione, fede, " +
			"gilde — e gli editti di una stagione.")
		_signature = ""
		return
	var signature := "%s|%s|%d" % [str(k.laws), str(k.edicts), roundi(k.treasury / 20.0)]
	if signature == _signature:
		return
	_signature = signature
	clear(_laws)
	for g: Dictionary in Laws.groups():
		var group_id := StringName(g["id"])
		var head := SettlementHud._label(_laws, 14, Color("#E9D8A6"), true)
		head.text = String(g.get("name", group_id)).to_upper()
		# which one is in force, in words: the gold of a pressed button alone was easy to miss (Phase 18)
		for o: Dictionary in g.get("options", []):
			if StringName(k.laws.get(group_id, &"")) == StringName(o["id"]):
				head.text += "  ·  in vigore: %s" % String(o.get("name", o["id"]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_laws.add_child(row)
		for o: Dictionary in g.get("options", []):
			var option_id := StringName(o["id"])
			var in_force := StringName(k.laws.get(group_id, &"")) == option_id
			var btn := command_button(row, String(o.get("name", option_id)),
				EnactLawCommand.create(k.id, group_id, option_id), _tip(o, in_force, -1))
			if in_force:
				btn.add_theme_color_override("font_disabled_color", KDTheme.GOLD)
	clear(_edicts)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	_edicts.add_child(grid)
	for e: Dictionary in Laws.edicts():
		var edict_id := StringName(e["id"])
		var in_force := k.edicts.has(edict_id)
		var days := int(k.edicts.get(edict_id, session.world.day)) - session.world.day
		var btn := command_button(grid, String(e.get("name", edict_id)),
			IssueEdictCommand.create(k.id, edict_id, in_force), _tip(e, in_force, days))
		if in_force:
			btn.add_theme_color_override("font_color", KDTheme.GOLD)


## What a law or an edict does, in the words of the data.
static func _tip(def: Dictionary, in_force: bool, days_left: int) -> String:
	var tips := PackedStringArray([String(def.get("description", ""))])
	for m: Modifier in Modifier.list_from_array(def.get("modifiers", [])):
		tips.append("%s %s" % [Modifier.label_for(m.key), m.describe()])
	var favour: Dictionary = def.get("favour", {})
	for fid: String in favour.keys():
		var fd: FactionDef = Defs.get_def("factions", StringName(fid))
		tips.append("%s %+d" % [fd.display_name if fd else fid, int(favour[fid])])
	if float(def.get("turbulence", 0.0)) > 0.0:
		tips.append("Turbolenza +%d" % int(def["turbulence"]))
	if in_force:
		tips.append("In vigore" + ("  ·  scade fra %d giorni" % days_left if days_left > 0 else ""))
	elif int(def.get("cost", 0)) > 0:
		tips.append("Costo: %d oro" % int(def["cost"]))
	return "\n".join(tips)

