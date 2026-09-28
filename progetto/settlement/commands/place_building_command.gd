class_name PlaceBuildingCommand
extends Command
## Opens a construction site: the builders will clear the footprint, bring the materials and build.

var settlement_id: int = -1
var def_id: StringName = &""
var pos: Vector2 = Vector2.ZERO


static func create(p_settlement: int, p_def: StringName, p_pos: Vector2) -> PlaceBuildingCommand:
	var c := PlaceBuildingCommand.new()
	c.settlement_id = p_settlement
	c.def_id = p_def
	c.pos = p_pos.snapped(Vector2.ONE)
	return c


func get_type() -> StringName:
	return &"place_building"


func validate(session: GameSession) -> String:
	var def := Defs.building(def_id)
	if def == null:
		return "Edificio sconosciuto."
	var res := Placement.check(session.world, session.world.settlement(settlement_id), def, pos)
	return "" if bool(res["ok"]) else String(res["reason"])


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var b := BuildingState.new()
	b.id = world.new_id()
	b.def_id = def_id
	b.settlement = settlement_id
	b.pos = pos
	b.status = BuildingState.Status.SITE
	b.workers_wanted = b.def().workers
	b.placed_day = world.day
	world.buildings[b.id] = b
	world.buildings_changed()
	SettlementSim.mark_assignment_dirty(session, settlement_id)
	EventBus.building_placed.emit(b.id)
	EventBus.terrain_changed.emit(pos)
	return CommandResult.ok({"building": b.id})


func describe() -> String:
	return "Cantiere %s a %s" % [def_id, str(pos)]

