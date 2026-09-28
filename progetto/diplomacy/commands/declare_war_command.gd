class_name DeclareWarCommand
extends Command
## A crown declares war on another. Until armies march (Phase 9) a war is a political and economic fact:
## pacts fall, allies are called, the powers of the realm take sides and the opinion of the world changes.

var attacker: int = -1
var defender: int = -1
var motive: String = ""


static func create(p_attacker: int, p_defender: int, p_motive: String = "") -> DeclareWarCommand:
	var c := DeclareWarCommand.new()
	c.attacker = p_attacker
	c.defender = p_defender
	c.motive = p_motive
	return c


func get_type() -> StringName:
	return &"declare_war"


func validate(session: GameSession) -> String:
	var world := session.world
	var a := world.kingdom(attacker)
	var b := world.kingdom(defender)
	if a == null or b == null or a.id == b.id:
		return "Regno inesistente."
	if not a.alive or not b.alive:
		return "Quel regno non esiste più."
	var r := Diplomacy.relation(world, a.id, b.id)
	if r.at_war:
		return "Siete già in guerra."
	if r.truce_until > world.day:
		return "La tregua dura ancora %d giorni." % (r.truce_until - world.day)
	for pact_id: StringName in r.pacts.keys():
		if bool(Diplomacy.pact(pact_id).get("blocks_war", false)):
			return "%s lo impedisce: prima va rotto." % Diplomacy.pact(pact_id).get("name", pact_id)
	if a.regency:
		return "Una reggenza non dichiara guerre."
	if Diplomacy.liege_of(world, a.id) == b.id:
		return "Non si dichiara guerra al proprio signore."
	return ""


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var a := world.kingdom(attacker)
	var b := world.kingdom(defender)
	Diplomacy.start_war(world, a.id, b.id)
	var joined := PackedInt32Array()
	for ally in Diplomacy.allies_of(world, b.id):
		var ally_k := world.kingdom(ally)
		if ally_k == null or not ally_k.alive or ally == a.id:
			continue
		if ally_k.is_player:
			# the player is called, not dragged: he answers with his own declaration
			EventBus.notify("Chiamata alle armi", "%s ci chiama contro %s." % [b.name, a.name], &"war")
			continue
		var r_ally := Diplomacy.relation(world, ally, b.id)
		var bound := r_ally.has_pact(&"vassalage") and r_ally.payer == ally
		var mind := DiplomacyAi.personality(world, ally)
		var comes := bound or float(mind.get("aggression", 0.25)) + Diplomacy.opinion(world, ally, b.id) * 0.006 > 0.3
		if comes and not Diplomacy.at_war(world, ally, a.id):
			Diplomacy.start_war(world, ally, a.id)
			Diplomacy.relation(world, ally, b.id).remember(&"called_and_came", world.day)
			joined.append(ally)
		elif not comes:
			Diplomacy.relation(world, ally, b.id).remember(&"called_and_stayed", world.day)
			Diplomacy.break_pact(world, ally, b.id, &"alliance")
	var text := "%s dichiara guerra a %s%s." % [a.name, b.name, (" — %s" % motive) if motive != "" else ""]
	EventBus.chronicle_written.emit({"day": world.day, "kingdom": a.id, "kind": "war", "text": text})
	if a.is_player or b.is_player or joined.size() > 0:
		EventBus.notify("Guerra", text, &"war")
	return CommandResult.ok({"joined": joined})


func describe() -> String:
	return "Dichiara guerra a %d" % defender

