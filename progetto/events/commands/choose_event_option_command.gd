class_name ChooseEventOptionCommand
extends Command
## The king answers what the world has put in front of him.

var pending_id: int = -1
var option: int = 0


static func create(p_pending: int, p_option: int) -> ChooseEventOptionCommand:
	var c := ChooseEventOptionCommand.new()
	c.pending_id = p_pending
	c.option = p_option
	return c


func get_type() -> StringName:
	return &"choose_event_option"


static func find(world: WorldState, pending_id: int) -> Dictionary:
	for p: Dictionary in world.pending_events:
		if int(p["id"]) == pending_id:
			return p
	return {}


func validate(session: GameSession) -> String:
	var pending := find(session.world, pending_id)
	if pending.is_empty():
		return "Quel fatto è già passato."
	var e := Events.event(StringName(pending["event"]))
	if e.is_empty():
		return "Fatto sconosciuto."
	var options: Array = e.get("options", [])
	if option < 0 or option >= options.size():
		return "Scelta inesistente."
	var effects: Dictionary = (options[option] as Dictionary).get("effects", {})
	var k := session.world.player()
	var cost := float(effects.get("treasury", 0.0))
	if cost < 0.0 and k and k.treasury + cost < 0.0:
		return "Servono %d ori, la corona ne ha %d." % [int(-cost), int(k.treasury)]
	return ""


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var pending := find(world, pending_id)
	var e := Events.event(StringName(pending["event"]))
	world.pending_events.erase(pending)
	EventSystem.choose(session, world.player(), e, option, world.day)
	return CommandResult.ok()

