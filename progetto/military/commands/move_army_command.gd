class_name MoveArmyCommand
extends Command
## Sends a host to a province. The route follows the ground: plains and coasts are quick, hills and woods slow,
## rivers and passes cost days. An army with no food left refuses to march away from its own land.

var army_id: int = -1
var province_id: int = -1
## The route found by validate(), kept for execute() when nothing moved in between (Phase 19: every order searched
## the whole continent twice — 5 to 12 ms each time).
var _route := PackedInt32Array()
var _route_key := ""


static func create(p_army: int, p_province: int) -> MoveArmyCommand:
	var c := MoveArmyCommand.new()
	c.army_id = p_army
	c.province_id = p_province
	return c


func get_type() -> StringName:
	return &"move_army"


func validate(session: GameSession) -> String:
	var world := session.world
	var a := world.army(army_id)
	if a == null:
		return "Esercito inesistente."
	var p := world.province(province_id)
	if p == null:
		return "Provincia inesistente."
	if a.province == province_id:
		return "L'esercito è già lì."
	if a.is_empty():
		return "Non è rimasto nessuno."
	if _route_for(world, a).is_empty():
		return "Non c'è una strada via terra fin là."
	return ""


func _route_for(world: WorldState, a: ArmyState) -> PackedInt32Array:
	var key := "%d:%d:%d:%d" % [world.get_instance_id(), world.tick, a.province, province_id]
	if key != _route_key:
		_route = Military.route(world, a.province, province_id)
		_route_key = key
	return _route


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var a := world.army(army_id)
	a.path = _route_for(world, a)
	var k := world.kingdom(a.kingdom)
	var target := world.province(province_id)
	if k and k.is_player:
		var days := roundi(_days_of(world, a))
		var geo := WorldData.get_instance().province_geo(province_id)
		EventBus.notify("In marcia", "%s muove verso %s: circa %d giorni." % [a.name, geo.name if geo else "?", days], &"army")
	if target and target.owner >= 0 and target.owner != a.kingdom and Diplomacy.at_war(world, target.owner, a.kingdom):
		EventBus.chronicle_written.emit({"day": world.day, "kingdom": a.kingdom, "other": target.owner, "kind": "march",
			"text": "%s varca il confine." % a.name})
	EventBus.army_changed.emit(a.id)
	return CommandResult.ok({"provinces": a.path.size()})


static func _days_of(world: WorldState, a: ArmyState) -> float:
	var wd := WorldData.get_instance()
	var km := 0.0
	var last := a.pos
	for pid in a.path:
		var g := wd.province_geo(pid)
		if g:
			km += last.distance_to(g.center) / 1000.0
			last = g.center
	return km / maxf(Military.day_march_km(world, a), 0.1)

