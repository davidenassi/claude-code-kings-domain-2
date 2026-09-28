class_name RecruitUnitCommand
extends Command
## Raises a regiment in a settlement. The men are inhabitants who leave their work, the weapons come out of
## the store and the gold out of the treasury. Training takes days, and only then does the host exist.

var settlement_id: int = -1
var unit_id: StringName = &""


static func create(p_settlement: int, p_unit: StringName) -> RecruitUnitCommand:
	var c := RecruitUnitCommand.new()
	c.settlement_id = p_settlement
	c.unit_id = p_unit
	return c


func get_type() -> StringName:
	return &"recruit_unit"


func validate(session: GameSession) -> String:
	var world := session.world
	var s := world.settlement(settlement_id)
	var u := Military.unit(unit_id)
	if s == null or u == null:
		return "Reparto sconosciuto."
	var k := world.kingdom(s.kingdom)
	if k == null:
		return "Insediamento senza corona."
	var req: Dictionary = u.requires
	if req.has("building"):
		var found := false
		for b in world.buildings_of(s.id):
			if b.def().id == StringName(req["building"]) and b.is_active():
				found = true
				break
		if not found:
			var bd := Defs.building(StringName(req["building"]))
			return "Serve %s." % (bd.display_name.to_lower() if bd else String(req["building"]))
	if req.has("weapons_made") and float(k.records.get(&"weapons", 0.0)) < float(req["weapons_made"]):
		return "Il regno ha forgiato %d armi su %d." % [int(k.records.get(&"weapons", 0.0)), int(req["weapons_made"])]
	if req.has("favour"):
		for fid: String in (req["favour"] as Dictionary).keys():
			if float(k.favour.get(StringName(fid), 55.0)) < float(req["favour"][fid]):
				var fd: FactionDef = Defs.get_def("factions", StringName(fid))
				return "%s non vi segue abbastanza (%d su %d)." % [fd.display_name if fd else fid,
					roundi(float(k.favour.get(StringName(fid), 55.0))), int(req["favour"][fid])]
	if s.amount(&"weapons") < u.weapons:
		return "Servono %d armi, nei depositi ce ne sono %d." % [u.weapons, s.amount(&"weapons")]
	if k.treasury < u.gold:
		return "Servono %d ori, la corona ne ha %d." % [int(u.gold), int(k.treasury)]
	var keep := int((Military.bal().get("recruitment", {}) as Dictionary).get("keep_workers", 2))
	var free := Military.eligible_people(world, s.id).size()
	if free - u.men < keep:
		return "Servono %d uomini validi e ne restano %d (il villaggio non può svuotarsi)." % [u.men, maxi(free - keep, 0)]
	return ""


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var s := world.settlement(settlement_id)
	var u := Military.unit(unit_id)
	var k := world.kingdom(s.kingdom)
	s.take(&"weapons", u.weapons, &"army")
	k.treasury -= u.gold
	var chosen := PackedInt32Array()
	for p in Military.eligible_people(world, s.id):
		if chosen.size() >= u.men:
			break
		p.job = &"recruit"
		p.workplace = -1
		p.action = &"idle"
		p.pending = {}
		chosen.append(p.id)
	s.training.append({"unit": unit_id, "days_left": float(u.train_days), "people": chosen})
	SettlementSim.mark_assignment_dirty(session, s.id)
	EventBus.settlement_changed.emit(s.id)
	if k.is_player:
		EventBus.notify("Leva", "%d uomini lasciano il lavoro per addestrarsi come %s." % [chosen.size(), u.display_name.to_lower()], &"army")
	return CommandResult.ok({"people": chosen.size()})


func describe() -> String:
	return "Arruola %s" % unit_id

