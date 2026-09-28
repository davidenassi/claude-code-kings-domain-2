class_name EnactLawCommand
extends Command
## Promulgate a permanent law: one option per group, paid in gold, with winners and losers among the powers.

var kingdom_id: int = -1
var group: StringName = &""
var option: StringName = &""


static func create(p_kingdom: int, p_group: StringName, p_option: StringName) -> EnactLawCommand:
	var c := EnactLawCommand.new()
	c.kingdom_id = p_kingdom
	c.group = p_group
	c.option = p_option
	return c


func get_type() -> StringName:
	return &"enact_law"


func validate(session: GameSession) -> String:
	var k := session.world.kingdom(kingdom_id)
	if k == null:
		return "Regno inesistente."
	if not k.monarchy_founded:
		return "Non c'è ancora una corona: le leggi, gli editti e gli eredi arrivano con la monarchia."
	var law := Laws.option(group, option)
	if law.is_empty():
		return "Legge sconosciuta."
	if StringName(k.laws.get(group, &"")) == option:
		return "%s è già in vigore." % law.get("name", option)
	var cost := float(law.get("cost", 0))
	if k.treasury < cost:
		return "Servono %d ori, la corona ne ha %d." % [int(cost), int(k.treasury)]
	var req: Dictionary = law.get("requires", {})
	if k.legitimacy < float(req.get("legitimacy", 0.0)):
		return "Serve una legittimità di almeno %d." % int(req["legitimacy"])
	if k.regency:
		return "Una reggenza non può cambiare le leggi del regno."
	return ""


func execute(session: GameSession) -> CommandResult:
	var k := session.world.kingdom(kingdom_id)
	var law := Laws.option(group, option)
	k.treasury -= float(law.get("cost", 0))
	k.records[&"laws_changed"] = float(k.records.get(&"laws_changed", 0.0)) + 1.0   # the guide and the spirits read it
	k.laws[group] = option
	CrownEffects.apply_political(k, law)
	k.identity_changed()
	if k.is_player:   # the courts of the world are news for the chronicle, not for the player
		EventBus.notify("Nuova legge", "%s: %s." % [Laws.group(group).get("name", group), law.get("name", option)], &"law")
	EventBus.chronicle_written.emit({"day": session.world.day, "kingdom": k.id, "kind": "law",
		"text": "Il regno adotta %s." % String(law.get("name", option)).to_lower()})
	return CommandResult.ok()

