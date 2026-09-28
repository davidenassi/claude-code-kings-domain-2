class_name BreakPactCommand
extends Command
## Tearing up a signed pact. It is free of gold and expensive of everything else: the other crown remembers
## it for a generation, and the world reads it as the word of a king that is worth nothing.

var from_kingdom: int = -1
var to_kingdom: int = -1
var pact_id: StringName = &""


static func create(p_from: int, p_to: int, p_pact: StringName) -> BreakPactCommand:
	var c := BreakPactCommand.new()
	c.from_kingdom = p_from
	c.to_kingdom = p_to
	c.pact_id = p_pact
	return c


func get_type() -> StringName:
	return &"break_pact"


func validate(session: GameSession) -> String:
	var world := session.world
	if world.kingdom(from_kingdom) == null or world.kingdom(to_kingdom) == null:
		return "Regno inesistente."
	if not Diplomacy.has_pact(world, from_kingdom, to_kingdom, pact_id):
		return "Quel patto non esiste."
	return ""


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var a := world.kingdom(from_kingdom)
	var b := world.kingdom(to_kingdom)
	var def := Diplomacy.pact(pact_id)
	Diplomacy.break_pact(world, a.id, b.id, pact_id)
	var text := "%s rompe %s con %s." % [a.name, String(def.get("name", pact_id)).to_lower(), b.name]
	EventBus.chronicle_written.emit({"day": world.day, "kingdom": a.id, "other": b.id, "kind": "pact_broken", "text": text})
	if a.is_player or b.is_player:
		EventBus.notify("Patto rotto", text, &"diplomacy")
	return CommandResult.ok()

