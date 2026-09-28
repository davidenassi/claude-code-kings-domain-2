class_name CancelSiteCommand
extends Command
## Abandons a construction site: delivered materials go back to the stores, felled trees stay felled.

var building_id: int = -1


static func create(p_building: int) -> CancelSiteCommand:
	var c := CancelSiteCommand.new()
	c.building_id = p_building
	return c


func get_type() -> StringName:
	return &"cancel_site"


func validate(session: GameSession) -> String:
	var b := session.world.building(building_id)
	if b == null:
		return "Edificio inesistente."
	if b.is_active():
		return "L'edificio è già finito."
	return ""


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var b := world.building(building_id)
	var s := world.settlement(b.settlement)
	for res: StringName in b.delivered.keys():
		s.add(res, int(b.delivered[res]), &"build")
	for p: PersonState in world.people.values():
		if p.workplace == b.id:
			p.workplace = -1
			p.job = &"idle"
		if not p.carrying.is_empty() and int(p.carrying.get("for_site", -1)) == b.id:
			p.carrying["for_site"] = -1
		if int(p.pending.get("site", -1)) == b.id:
			p.pending.erase("site")
	world.buildings.erase(b.id)
	world.buildings_changed()
	SettlementSim.mark_assignment_dirty(session, s.id)
	EventBus.building_removed.emit(b.id)
	EventBus.terrain_changed.emit(b.pos)
	EventBus.settlement_changed.emit(s.id)
	return CommandResult.ok()

