class_name ProposePactCommand
extends Command
## One crown offers a pact to another. An AI crown answers at once, and always says why; an offer to the
## player waits on his table (WorldState.offers) until he answers it.

var from_kingdom: int = -1
var to_kingdom: int = -1
var pact_id: StringName = &""


static func create(p_from: int, p_to: int, p_pact: StringName) -> ProposePactCommand:
	var c := ProposePactCommand.new()
	c.from_kingdom = p_from
	c.to_kingdom = p_to
	c.pact_id = p_pact
	return c


func get_type() -> StringName:
	return &"propose_pact"


func validate(session: GameSession) -> String:
	var world := session.world
	var a := world.kingdom(from_kingdom)
	var b := world.kingdom(to_kingdom)
	if a == null or b == null or a.id == b.id:
		return "Regno inesistente."
	if not a.alive or not b.alive:
		return "Quel regno non esiste più."
	var def := Diplomacy.pact(pact_id)
	if def.is_empty():
		return "Patto sconosciuto."
	var r := Diplomacy.relation(world, a.id, b.id)
	if r.has_pact(pact_id):
		return "%s è già in vigore." % def.get("name", pact_id)
	if r.at_war:
		return "Prima si fa la pace."
	var requires := StringName(def.get("requires", &""))
	if requires != &"" and not r.has_pact(requires):
		return "Serve prima %s." % Diplomacy.pact(requires).get("name", requires)
	if a.treasury < float(def.get("cost", 0)):
		return "Servono %d ori, la corona ne ha %d." % [int(def.get("cost", 0)), int(a.treasury)]
	if bool(def.get("asymmetric", false)) and Diplomacy.power_ratio(world, a.id, b.id) < float(def.get("power_ratio", 2.0)):
		return "Non siete abbastanza più forti per chiederlo."
	if a.regency:
		return "Una reggenza non firma patti."
	return Diplomacy.pact_blocker(world, a, b, pact_id)


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var a := world.kingdom(from_kingdom)
	var b := world.kingdom(to_kingdom)
	var def := Diplomacy.pact(pact_id)
	if b.is_player:
		var offer := {"id": world.new_id(), "from": a.id, "kind": "pact", "pact": String(pact_id),
			"day": world.day, "expires": world.day + 30,
			"text": "%s propone %s." % [a.name, String(def.get("name", pact_id)).to_lower()]}
		world.offers.append(offer)
		EventBus.notify("Un'ambasciata", offer["text"], &"diplomacy")
		return CommandResult.ok({"pending": true, "offer": offer["id"]})
	var verdict := DiplomacyAi.judge_pact(session, a.id, b.id, pact_id)
	if not bool(verdict["accept"]):
		return CommandResult.ok({"accepted": false, "reason": String(verdict["reason"])})
	a.treasury -= float(def.get("cost", 0))
	Diplomacy.sign(world, a.id, b.id, pact_id)
	if Diplomacy.CHRONICLE_PACTS.has(pact_id):
		EventBus.chronicle_written.emit({"day": world.day, "kingdom": a.id, "other": b.id, "kind": "pact",
			"text": "%s e %s firmano %s." % [a.name, b.name, String(def.get("name", pact_id)).to_lower()]})
	if a.is_player or b.is_player:
		EventBus.notify(String(def.get("name", pact_id)), String(verdict["reason"]), &"diplomacy")
	return CommandResult.ok({"accepted": true, "reason": String(verdict["reason"])})


func describe() -> String:
	return "Proponi %s" % pact_id

