class_name ArrangeMarriageCommand
extends Command
## A child of one house marries a child of the other. Blood holds where ink does not.

var from_kingdom: int = -1
var to_kingdom: int = -1


static func create(p_from: int, p_to: int) -> ArrangeMarriageCommand:
	var c := ArrangeMarriageCommand.new()
	c.from_kingdom = p_from
	c.to_kingdom = p_to
	return c


func get_type() -> StringName:
	return &"arrange_marriage"


func validate(session: GameSession) -> String:
	var world := session.world
	var a := world.kingdom(from_kingdom)
	var b := world.kingdom(to_kingdom)
	if a == null or b == null or a.id == b.id:
		return "Regno inesistente."
	if not a.monarchy_founded or not b.monarchy_founded:
		return "Un matrimonio fra corone chiede due corone: la comunità non ne ha ancora una."
	var m: Dictionary = Diplomacy.data().get("marriage", {})
	if a.treasury < float(m.get("cost", 0)):
		return "Servono %d ori per le nozze, la corona ne ha %d." % [int(m.get("cost", 0)), int(a.treasury)]
	var r := Diplomacy.relation(world, a.id, b.id)
	if r.married:
		return "Le due case sono già imparentate."
	if r.at_war:
		return "Non si celebrano nozze fra regni in guerra."
	if CourtSystem.marriageable(world, a.id) < 0 or CourtSystem.marriageable(world, b.id) < 0:
		return "Manca un figlio in età da nozze in una delle due case."
	return ""


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var a := world.kingdom(from_kingdom)
	var b := world.kingdom(to_kingdom)
	var m: Dictionary = Diplomacy.data().get("marriage", {})
	if b.is_player:
		var offer := {"id": world.new_id(), "from": a.id, "kind": "marriage", "pact": "",
			"day": world.day, "expires": world.day + 30,
			"text": "%s propone un matrimonio fra le due case." % a.name}
		world.offers.append(offer)
		EventBus.notify("Un'ambasciata", offer["text"], &"diplomacy")
		return CommandResult.ok({"pending": true, "offer": offer["id"]})
	var verdict := DiplomacyAi.judge_marriage(session, a.id, b.id)
	if not bool(verdict["accept"]):
		return CommandResult.ok({"accepted": false, "reason": String(verdict["reason"])})
	a.treasury -= float(m.get("cost", 0))
	CourtSystem.marry_houses(session, a.id, b.id)
	var r := Diplomacy.relation(world, a.id, b.id)
	r.married = true
	r.remember(&"marriage", world.day)
	Diplomacy._touch(world, a.id, b.id)
	var text := "Le case di %s e %s si legano con un matrimonio." % [a.name, b.name]
	EventBus.chronicle_written.emit({"day": world.day, "kingdom": a.id, "other": b.id, "kind": "marriage", "text": text})
	if a.is_player or b.is_player:
		EventBus.notify("Nozze fra corone", text, &"diplomacy")
	return CommandResult.ok({"accepted": true, "reason": String(verdict["reason"])})

