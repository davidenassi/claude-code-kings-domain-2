class_name KnowledgePanel
extends KDSheet
## The SAPERE sheet: what the realm has learned and what it could learn next (one road per branch). The crises
## passing over the realm moved to Il mio regno (consolidation: they are the state of the realm, not its knowledge).

var _points: Label
var _branches: VBoxContainer
var _signature := ""


func build() -> void:
	section("IL SAPERE DEL REGNO")
	_points = parchment()
	_branches = box(6)


func refresh() -> void:
	if not Session.has_game() or column == null:
		return
	var session := Session.current
	var k := session.world.player()
	if k == null:
		return
	_points.text = "Punti di sapere: %d  (+%d al mese)\nUn ramo si percorre una volta sola: la strada che non prendi resta chiusa." % [
		roundi(k.research), roundi(ResearchSystem.points_per_month(session, k))]
	var signature := "%d|%d" % [k.technologies.size(), int(k.research / 25.0)]
	if signature != _signature:
		_signature = signature
		clear(_branches)
		for b: Dictionary in Technologies.branches():
			var head := SettlementHud._label(_branches, 14, Color("#E9D8A6"), true)
			head.text = String(b.get("name", b["id"])).to_upper()
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			_branches.add_child(row)
			for it: Dictionary in b.get("items", []):
				var tech_id := StringName(it["id"])
				var known := k.technologies.has(tech_id)
				var tips := PackedStringArray([String(it.get("description", ""))])
				for m: Modifier in Modifier.list_from_array(it.get("modifiers", [])):
					tips.append("%s %s" % [Modifier.label_for(m.key), m.describe()])
				tips.append("Costo: %d punti" % int(it.get("cost", 0)))
				var btn := command_button(row, String(it.get("name", tech_id)),
					AdoptTechnologyCommand.create(k.id, tech_id), "\n".join(tips))
				if known:
					btn.add_theme_color_override("font_disabled_color", KDTheme.GOLD)

