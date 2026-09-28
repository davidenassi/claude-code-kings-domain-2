class_name SetWorkersCommand
extends Command
## How many people should work in a building (0 .. the building's places).

var building_id: int = -1
var count: int = 0


static func create(p_building: int, p_count: int) -> SetWorkersCommand:
	var c := SetWorkersCommand.new()
	c.building_id = p_building
	c.count = p_count
	return c


func get_type() -> StringName:
	return &"set_workers"


func validate(session: GameSession) -> String:
	var b := session.world.building(building_id)
	if b == null:
		return "Edificio inesistente."
	if b.def().workers <= 0:
		return "In questo edificio non lavora nessuno."
	if count < 0 or count > b.def().workers:
		return "Posti disponibili: da 0 a %d." % b.def().workers
	return ""


func execute(session: GameSession) -> CommandResult:
	var b := session.world.building(building_id)
	b.workers_wanted = count
	SettlementSim.mark_assignment_dirty(session, b.settlement)
	EventBus.building_state_changed.emit(b.id)
	return CommandResult.ok()

