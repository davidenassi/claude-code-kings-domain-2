class_name PlaceRoadCommand
extends Command
## Traces a dirt road between two points: builders fell the trees on the way and beat the ground.

var settlement_id: int = -1
var a: Vector2 = Vector2.ZERO
var b: Vector2 = Vector2.ZERO


static func create(p_settlement: int, p_a: Vector2, p_b: Vector2) -> PlaceRoadCommand:
	var c := PlaceRoadCommand.new()
	c.settlement_id = p_settlement
	c.a = p_a.snapped(Vector2.ONE)
	c.b = p_b.snapped(Vector2.ONE)
	return c


func get_type() -> StringName:
	return &"place_road"


func validate(session: GameSession) -> String:
	var res := Placement.check_road(session.world, session.world.settlement(settlement_id), a, b)
	return "" if bool(res["ok"]) else String(res["reason"])


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var road := BuildingState.new()
	road.id = world.new_id()
	road.def_id = &"road"
	road.settlement = settlement_id
	road.a = a
	road.b = b
	road.pos = (a + b) * 0.5
	road.status = BuildingState.Status.SITE
	road.placed_day = world.day
	var hours := maxf(a.distance_to(b) / 10.0 * float(Defs.balance("settlement").get("road_hours_per_10m", 1.5)), 0.5)
	road.work_required = KingdomModifiers.value(session, world.settlement(settlement_id).kingdom, &"construction.road_cost", hours)
	KingdomModifiers.record(world, world.settlement(settlement_id).kingdom, &"road_m", a.distance_to(b))
	world.buildings[road.id] = road
	world.buildings_changed()
	SettlementSim.mark_assignment_dirty(session, settlement_id)
	EventBus.building_placed.emit(road.id)
	EventBus.terrain_changed.emit(road.pos)
	return CommandResult.ok({"building": road.id})

