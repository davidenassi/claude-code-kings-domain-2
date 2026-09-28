class_name IssueEdictCommand
extends Command
## Issue (or revoke) a temporary edict. Edicts cost little, last thirty days and can be stacked.

var kingdom_id: int = -1
var edict_id: StringName = &""
var revoke: bool = false


static func create(p_kingdom: int, p_edict: StringName, p_revoke: bool = false) -> IssueEdictCommand:
	var c := IssueEdictCommand.new()
	c.kingdom_id = p_kingdom
	c.edict_id = p_edict
	c.revoke = p_revoke
	return c


func get_type() -> StringName:
	return &"issue_edict"


func validate(session: GameSession) -> String:
	var k := session.world.kingdom(kingdom_id)
	if k == null:
		return "Regno inesistente."
	if not k.monarchy_founded:
		return "Non c'è ancora una corona: le leggi, gli editti e gli eredi arrivano con la monarchia."
	var ed := Laws.edict(edict_id)
	if ed.is_empty():
		return "Editto sconosciuto."
	if revoke:
		return "" if k.edicts.has(edict_id) else "Questo editto non è in vigore."
	if k.edicts.has(edict_id):
		return "%s è già in vigore." % ed.get("name", edict_id)
	# a season of it, then a rest: the same edict every month is no longer an edict, it is the rule
	var rest := int(Laws.data().get("edict_rest_days", 180))
	var ended := int(k.records.get(StringName("edict_ended:%s" % edict_id), -999999.0))
	if session.world.day - ended < rest:
		return "Il regno ha appena finito %s: si potrà riproclamare fra %d giorni." % [
			String(ed.get("name", edict_id)).to_lower(), rest - (session.world.day - ended)]
	var cost := float(ed.get("cost", 0))
	if k.treasury < cost:
		return "Servono %d ori, la corona ne ha %d." % [int(cost), int(k.treasury)]
	return ""


func execute(session: GameSession) -> CommandResult:
	var k := session.world.kingdom(kingdom_id)
	var ed := Laws.edict(edict_id)
	if revoke:
		k.edicts.erase(edict_id)
		k.identity_changed()
		if k.is_player:   # the courts of the world are news for the chronicle, not for the player
			EventBus.notify("Editto revocato", "%s non è più in vigore." % ed.get("name", edict_id), &"law")
		return CommandResult.ok()
	k.treasury -= float(ed.get("cost", 0))
	k.edicts[edict_id] = session.world.day + int(ed.get("days", 30))
	CrownEffects.apply_political(k, ed, false)
	k.records[StringName("edict_ended:%s" % edict_id)] = float(k.edicts[edict_id])
	k.identity_changed()
	if k.is_player:   # the courts of the world are news for the chronicle, not for the player
		EventBus.notify("Editto", "%s, per %d giorni." % [ed.get("name", edict_id), int(ed.get("days", 30))], &"law")
	return CommandResult.ok()

