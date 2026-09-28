class_name GiftFactionCommand
extends Command
## The crown opens its coffers for one of the powers of the realm (Phase 16): feasts for the nobility, candles
## and land for the clergy, privileges for the merchants, pay for the army, bread for the people. It costs more
## in a wider realm, a power cannot be bought twice in a year, and it is remembered like a law — gold that buys
## peace at home. The whole-campaign runs showed crowns sitting on tens of thousands of gold with nothing to
## spend them on, and powers sliding to hostility for want of any way to win them back.

var kingdom_id: int = -1
var faction_id: StringName = &""


static func create(p_kingdom: int, p_faction: StringName) -> GiftFactionCommand:
	var c := GiftFactionCommand.new()
	c.kingdom_id = p_kingdom
	c.faction_id = p_faction
	return c


func get_type() -> StringName:
	return &"gift_faction"


static func cfg() -> Dictionary:
	return CourtSystem.bal().get("gifts", {})


static func cost(k: KingdomState) -> float:
	var c := cfg()
	return float(c.get("base_gold", 60.0)) + float(c.get("gold_per_province", 25.0)) * float(k.provinces.size())


static func days_to_wait(world: WorldState, k: KingdomState, faction: StringName) -> int:
	var last := int(k.records.get(StringName("gift:%s" % faction), -999999.0))
	return maxi(int(cfg().get("cooldown_days", 360)) - (world.day - last), 0)


func validate(session: GameSession) -> String:
	var world := session.world
	var k := world.kingdom(kingdom_id)
	var fd := Defs.get_def("factions", faction_id) as FactionDef
	if k == null or fd == null:
		return "Regno o ceto inesistente."
	if not k.monarchy_founded:
		return "Non ci sono ancora ceti da ingraziarsi: prima la corona."
	var wait := days_to_wait(world, k, faction_id)
	if wait > 0:
		return "%s ha già avuto il suo dono quest'anno: ancora %d giorni." % [fd.display_name, wait]
	var price := cost(k)
	if k.treasury < price:
		return "Servono %d ori, la corona ne ha %d." % [roundi(price), roundi(k.treasury)]
	return ""


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var k := world.kingdom(kingdom_id)
	var fd := Defs.get_def("factions", faction_id) as FactionDef
	var price := cost(k)
	k.treasury -= price
	CrownEffects.apply_political(k, {"favour": {String(faction_id): float(cfg().get("favour", 10.0))}})
	k.records[StringName("gift:%s" % faction_id)] = float(world.day)
	KingdomModifiers.record(world, k.id, &"gifts_given", 1.0)
	if k.is_player:
		EventBus.notify("Un dono della corona", "%s ricevono %d ori in feste e privilegi." % [fd.display_name, roundi(price)], &"law")
	return CommandResult.ok({"cost": price})


func describe() -> String:
	return "Dono della corona %d al ceto %s" % [kingdom_id, faction_id]

