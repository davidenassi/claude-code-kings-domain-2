class_name DisbandArmyCommand
extends Command
## Sends the host home. In one of its own settlements the men go back to their houses and their work;
## anywhere else they simply scatter, and the village never sees them again.

var army_id: int = -1


static func create(p_army: int) -> DisbandArmyCommand:
	var c := DisbandArmyCommand.new()
	c.army_id = p_army
	return c


func get_type() -> StringName:
	return &"disband_army"


func validate(session: GameSession) -> String:
	var a := session.world.army(army_id)
	if a == null:
		return "Esercito inesistente."
	if Diplomacy.enemies_of(session.world, a.kingdom).size() > 0 and _home(session.world, a) == null:
		return "Con una guerra aperta un esercito si scioglie solo a casa."
	return ""


static func _home(world: WorldState, a: ArmyState) -> SettlementState:
	var radius := float((Military.bal().get("supply", {}) as Dictionary).get("food_from_settlement_radius_m", 900.0))
	for s in world.settlements:
		if s.kingdom == a.kingdom and s.center.distance_to(a.pos) < radius * 2.0:
			return s
	return null


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var a := world.army(army_id)
	var home := _home(world, a)
	var returned := 0
	for person_id in a.people():
		var p := world.person(person_id)
		if p == null:
			continue
		if home:
			world.move_person(p, home.id)
			p.job = &"idle"
			p.action = &"idle"
			p.seg_from = home.center
			p.seg_to = home.center
			returned += 1
		else:
			world.remove_person(person_id)   # they melt away along the roads
	world.armies.erase(a)
	if home:
		SettlementSim.mark_assignment_dirty(session, home.id)
		EventBus.settlement_changed.emit(home.id)
	var k := world.kingdom(a.kingdom)
	if k and k.is_player:
		EventBus.notify("Esercito sciolto", "%s: %d uomini tornano alle case." % [a.name, returned] if home
			else "%s si disperde lontano da casa." % a.name, &"army")
	EventBus.army_changed.emit(a.id)
	return CommandResult.ok({"returned": returned})

