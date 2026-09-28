class_name PeoplePanel
extends KDSheet
## The ABITANTI sheet: who lives in the settlement, what work they do, how many days of food are left and how
## many hands the crown sends to the building sites. It used to be a box hanging under the old bar.

var _quota_buttons: Dictionary = {}
var _summary: Label
var _list: Label


func build() -> void:
	section("GLI ABITANTI")
	_summary = parchment()
	section("MANI AI CANTIERI")
	var quota_row := HBoxContainer.new()
	quota_row.add_theme_constant_override("separation", 4)
	column.add_child(quota_row)
	var group := ButtonGroup.new()
	for q: Dictionary in Defs.balance("settlement").get("builder_quotas", []):
		var b := Button.new()
		b.text = String(q["name"])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%d%% degli abitanti ai cantieri" % roundi(float(q["share"]) * 100.0)
		KDTheme.button_styles(b)
		var qid := StringName(q["id"])
		b.pressed.connect(func() -> void:
			var s := SettlementHud.player_settlement()
			if s:
				Session.current.submit(SetBuilderQuotaCommand.create(s.id, qid)))
		quota_row.add_child(b)
		_quota_buttons[qid] = b
	section("NOME PER NOME")
	_list = parchment()


func refresh() -> void:
	if not Session.has_game() or column == null:
		return
	var s := SettlementHud.player_settlement()
	if s == null:
		return
	var world := Session.current.world
	var people := world.people_of(s.id)
	var beds := 0
	for b in world.buildings_of(s.id):
		if b.is_active():
			beds += b.beds()
	_summary.text = "%s — %s\n%d abitanti · %d letti · fiducia %d%% · cibo per %d giorni" % [
		s.name, s.tier_name(people.size()), people.size(), beds, roundi(s.trust),
		roundi(PopulationSystem.food_days(world, s))]
	var jobs: Dictionary = Defs.balance("settlement").get("job_names", {})
	var lines := PackedStringArray()
	for p in people:
		var where := ""
		var wp := world.building(p.workplace)
		if wp:
			where = " (%s)" % wp.def().display_name.to_lower()
		var hunger := "" if p.hunger < 1.0 else "  · fame %d g" % roundi(p.hunger)
		lines.append("%s, %d anni — %s%s%s" % [p.name, p.age_years(world.day),
			jobs.get(String(p.job), p.job), where, hunger])
	if lines.is_empty():
		lines.append("Nessuno abita ancora qui.")
	_list.text = "\n".join(lines)
	if _quota_buttons.has(s.builder_quota):
		(_quota_buttons[s.builder_quota] as Button).set_pressed_no_signal(true)

