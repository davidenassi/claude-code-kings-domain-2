class_name AnswerOfferCommand
extends Command
## The player answers an offer left on his table by another crown.

var offer_id: int = -1
var accept: bool = true


static func create(p_offer: int, p_accept: bool) -> AnswerOfferCommand:
	var c := AnswerOfferCommand.new()
	c.offer_id = p_offer
	c.accept = p_accept
	return c


func get_type() -> StringName:
	return &"answer_offer"


static func find(world: WorldState, offer_id: int) -> Dictionary:
	for o: Dictionary in world.offers:
		if int(o["id"]) == offer_id:
			return o
	return {}


func validate(session: GameSession) -> String:
	var o := find(session.world, offer_id)
	if o.is_empty():
		return "L'ambasciata è già ripartita."
	var from_k := session.world.kingdom(int(o["from"]))
	if from_k == null or not from_k.alive:
		return "Quel regno non esiste più."
	if accept and String(o["kind"]) == "pact":
		var def := Diplomacy.pact(StringName(o["pact"]))
		var me := session.world.player()
		var blocker := Diplomacy.pact_blocker(session.world, from_k, me, StringName(o["pact"])) if me else ""
		if blocker != "":
			return blocker
		if me and me.treasury < float(def.get("cost", 0)):
			return "Servono %d ori, la corona ne ha %d." % [int(def.get("cost", 0)), int(me.treasury)]
	return ""


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var o := find(world, offer_id)
	var me := world.player()
	var them := world.kingdom(int(o["from"]))
	world.offers.erase(o)
	var r := Diplomacy.relation(world, me.id, them.id)
	if not accept:
		r.opinion = clampf(r.opinion - 6.0, -100.0, 100.0)
		EventBus.notify("Ambasciata respinta", "%s torna a mani vuote." % them.name, &"diplomacy")
		return CommandResult.ok({"accepted": false})
	if String(o["kind"]) == "peace":
		var cede := PackedInt32Array(o.get("cede", []))
		for pid in cede:
			if War.is_player_seat(world, pid):
				continue   # an offer written before Phase 19 may still ask for the seat: that stays
			War.cede(session, pid, them.id)   # what they held in arms, they keep by treaty
		Diplomacy.end_war(world, me.id, them.id)
		EventBus.chronicle_written.emit({"day": world.day, "kingdom": me.id, "kind": "peace",
			"text": "%s e %s fanno la pace%s." % [me.name, them.name,
				"" if cede.is_empty() else ": %d province passano a %s" % [cede.size(), them.name]]})
	elif String(o["kind"]) == "marriage":
		CourtSystem.marry_houses(session, them.id, me.id)
		r.married = true
		r.remember(&"marriage", world.day)
		EventBus.chronicle_written.emit({"day": world.day, "kingdom": me.id, "kind": "marriage",
			"text": "Le case di %s e %s si legano con un matrimonio." % [me.name, them.name]})
	else:
		var def := Diplomacy.pact(StringName(o["pact"]))
		me.treasury -= float(def.get("cost", 0))
		Diplomacy.sign(world, me.id, them.id, StringName(o["pact"]))
		if Diplomacy.CHRONICLE_PACTS.has(StringName(o["pact"])):
			EventBus.chronicle_written.emit({"day": world.day, "kingdom": me.id, "other": them.id, "kind": "pact",
				"text": "%s e %s firmano %s." % [me.name, them.name, String(def.get("name", o["pact"])).to_lower()]})
	return CommandResult.ok({"accepted": true})

