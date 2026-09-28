class_name MakePeaceCommand
extends Command
## One of the two asks for peace, with or without conditions: provinces held by arms can be asked for and kept.
## The other answers with its own head — how tired it is and how badly it is losing. A peace leaves a truce behind.

var from_kingdom: int = -1
var to_kingdom: int = -1
## Provinces of `to_kingdom`, held today by `from_kingdom`, that the peace hands over for good.
var cede: PackedInt32Array = PackedInt32Array()


static func create(p_from: int, p_to: int, p_cede: PackedInt32Array = PackedInt32Array()) -> MakePeaceCommand:
	var c := MakePeaceCommand.new()
	c.from_kingdom = p_from
	c.to_kingdom = p_to
	c.cede = p_cede
	return c


func get_type() -> StringName:
	return &"make_peace"


func validate(session: GameSession) -> String:
	var world := session.world
	var a := world.kingdom(from_kingdom)
	var b := world.kingdom(to_kingdom)
	if a == null or b == null:
		return "Regno inesistente."
	var r := Diplomacy.relation(world, a.id, b.id)
	if not r.at_war:
		return "Non siete in guerra."
	var min_days := int((Diplomacy.bal().get("war", {}) as Dictionary).get("min_days_before_peace", 180))
	if world.day - r.war_since < min_days:
		return "È troppo presto: la guerra dura da %d giorni." % (world.day - r.war_since)
	for pid in cede:
		var p := world.province(pid)
		if p == null or p.owner != b.id:
			return "Si può chiedere solo terra loro."
		if p.controller != a.id:
			return "Si tiene al tavolo solo ciò che si tiene in campo."
		if War.is_player_seat(world, pid):
			return "La sede della corona non si cede a un tavolo di pace."
	return ""


## How tired of this war a realm is (years of war, empty treasury, unhappy powers).
static func weariness(session: GameSession, kingdom_id: int, other_id: int) -> float:
	var world := session.world
	var r := Diplomacy.relation(world, kingdom_id, other_id)
	var k := world.kingdom(kingdom_id)
	if r == null or k == null or not r.at_war:
		return 0.0
	var years := float(world.day - r.war_since) / float(PersonState.DAYS_PER_YEAR)
	var value := years * float((Diplomacy.bal().get("war", {}) as Dictionary).get("weariness_per_year", 8.0))
	if k.treasury < 0.0:
		value += 15.0
	value += maxf(60.0 - k.stability, 0.0) * 0.4
	value += maxf(-War.score_for(world, kingdom_id, other_id), 0.0) * 0.6   # losing wars tire fastest
	# whoever is winning, and whoever loves war, holds out longer
	value -= clampf((Diplomacy.power_ratio(world, kingdom_id, other_id) - 1.0) * 6.0, -6.0, 12.0)
	value -= float(DiplomacyAi.personality(world, kingdom_id).get("aggression", 0.25)) * 15.0
	return value


## Does `target` swallow these terms? Returns {accept, reason}.
static func judge(session: GameSession, asker: int, target: int, cede: PackedInt32Array) -> Dictionary:
	var world := session.world
	var kt := world.kingdom(target)
	var tired := weariness(session, target, asker)
	var losing := -War.score_for(world, target, asker)   # how badly the target is losing
	var cfg: Dictionary = War.bal().get("war_score", {})
	var price := float(cfg.get("cede_province_cost", 35.0)) * cede.size()
	if cede.is_empty():
		if tired < 10.0:
			return {"accept": false, "reason": "%s non ne ha ancora abbastanza." % kt.name}
		return {"accept": true, "reason": "%s accetta la pace." % kt.name}
	var needed := maxf(price, float(cfg.get("accept_threshold", 55.0)) * 0.5)
	if losing < needed:
		return {"accept": false, "reason": "%s non ha ancora perso abbastanza per cedere terra (%d su %d)."
			% [kt.name, roundi(maxf(losing, 0.0)), roundi(needed)]}
	if tired < 5.0:
		return {"accept": false, "reason": "%s preferisce continuare la guerra." % kt.name}
	return {"accept": true, "reason": "%s cede %d province pur di finirla." % [kt.name, cede.size()]}


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var a := world.kingdom(from_kingdom)
	var b := world.kingdom(to_kingdom)
	if b.is_player:
		# the provinces by name: the ruler must know what he gives away before he answers
		var names := PackedStringArray()
		for pid in cede:
			var g := WorldData.get_instance().province_geo(pid)
			names.append(g.name if g else "una provincia")
		var offer := {"id": world.new_id(), "from": a.id, "kind": "peace", "pact": "",
			"day": world.day, "expires": world.day + 30, "cede": Array(cede),
			"text": "%s chiede la pace%s." % [a.name, "" if cede.is_empty() else " e pretende %s" % ", ".join(names)]}
		world.offers.append(offer)
		EventBus.notify("Un'ambasciata", offer["text"], &"diplomacy")
		return CommandResult.ok({"pending": true, "offer": offer["id"]})
	var verdict := judge(session, a.id, b.id, cede)
	if not bool(verdict["accept"]):
		if a.is_player:
			EventBus.notify("Pace rifiutata", String(verdict["reason"]), &"diplomacy")
		return CommandResult.ok({"accepted": false, "reason": String(verdict["reason"])})
	for pid in cede:
		War.cede(session, pid, a.id)
	Diplomacy.end_war(world, a.id, b.id)
	var text := "%s e %s fanno la pace%s." % [a.name, b.name,
		"" if cede.is_empty() else ": %d province passano a %s" % [cede.size(), a.name]]
	EventBus.chronicle_written.emit({"day": world.day, "kingdom": a.id, "other": b.id, "kind": "peace", "text": text})
	if a.is_player or b.is_player:
		EventBus.notify("Pace", text, &"diplomacy")
	return CommandResult.ok({"accepted": true, "reason": text})

