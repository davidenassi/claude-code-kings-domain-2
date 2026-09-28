class_name ClaimProvinceCommand
extends Command
## A crown takes a free land beside its own without a war (Phase 16): the villages without a lord accept its
## protection and its taxes. It costs gold — more for a populous land and for a realm already wide — it wants a
## crown that is believed, and it takes time for the new lands to settle before the next ones are asked.
## Until now the free lands of the world could only be looked at: nobody, player or AI, could ever hold them.

var kingdom_id: int = -1
var province_id: int = -1


static func create(p_kingdom: int, p_province: int) -> ClaimProvinceCommand:
	var c := ClaimProvinceCommand.new()
	c.kingdom_id = p_kingdom
	c.province_id = p_province
	return c


func get_type() -> StringName:
	return &"claim_province"


static func cfg() -> Dictionary:
	return Diplomacy.bal().get("claim", {})


## What the villages want to accept the crown: a base, a part for every soul, more for every land already held.
static func cost(world: WorldState, kingdom_id: int, province_id: int) -> float:
	var c := cfg()
	var k := world.kingdom(kingdom_id)
	var p := world.province(province_id)
	if k == null or p == null:
		return 0.0
	var price := float(c.get("base_gold", 150.0)) + float(c.get("gold_per_person", 0.2)) * float(p.population)
	return price * (1.0 + float(c.get("per_province_held", 0.12)) * float(maxi(k.provinces.size() - 1, 0)))


## True when the land touches one of the realm's own (by land, river, pass or mountain — never across the sea).
static func borders(world: WorldState, kingdom_id: int, province_id: int) -> bool:
	var g := WorldData.get_instance().province_geo(province_id)
	if g == null:
		return false
	for n: Dictionary in g.neighbors:
		var q := world.province(int(n["id"]))
		if q and q.owner == kingdom_id:
			return true
	return false


## Days before the realm can ask again (0 when it can).
static func days_to_wait(world: WorldState, k: KingdomState) -> int:
	var last := int(k.records.get(&"claim_day", -999999.0))
	return maxi(int(cfg().get("cooldown_days", 720)) - (world.day - last), 0)


func validate(session: GameSession) -> String:
	var world := session.world
	var k := world.kingdom(kingdom_id)
	var p := world.province(province_id)
	if k == null or p == null or not k.alive:
		return "Regno o provincia inesistente."
	if not k.monarchy_founded:
		return "Una comunità non annette terre: servono una corona e un regno."
	if not p.is_free():
		return "Quella terra ha già un signore: si prende solo con le armi o con un trattato."
	if not borders(world, k.id, province_id):
		return "Quella terra non confina con il regno."
	var wait := days_to_wait(world, k)
	if wait > 0:
		return "Le ultime terre annesse non sono ancora quiete: ancora %d giorni." % wait
	var min_legitimacy := float(cfg().get("min_legitimacy", 40.0))
	if k.legitimacy < min_legitimacy:
		return "Una corona poco creduta (legittimità %d su %d) non convince i villaggi liberi." % [roundi(k.legitimacy), roundi(min_legitimacy)]
	if not Diplomacy.enemies_of(world, k.id).is_empty():
		return "In guerra nessun villaggio chiede la protezione di una corona."
	var price := cost(world, k.id, province_id)
	if k.treasury < price:
		return "Servono %d ori, la corona ne ha %d." % [roundi(price), roundi(k.treasury)]
	return ""


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var k := world.kingdom(kingdom_id)
	var p := world.province(province_id)
	var price := cost(world, k.id, province_id)
	k.treasury -= price
	var old := world.set_province_owner(province_id, k.id)
	EventBus.province_owner_changed.emit(province_id, old, k.id, &"claim")
	# a land of another tongue or faith does not love its new crown at once
	p.unrest = clampf(p.unrest + float(cfg().get("unrest_foreign", 0.25)) * CultureSystem.friction(session, province_id), 0.0, 1.0)
	CourtSystem.add_prestige(k, float(cfg().get("prestige", 3.0)))
	k.records[&"claim_day"] = float(world.day)
	KingdomModifiers.record(world, k.id, &"provinces_claimed", 1.0)
	var name := WorldData.get_instance().province_geo(province_id).name
	EventBus.chronicle_written.emit({"day": world.day, "kingdom": k.id, "kind": "claim",
		"text": "I villaggi di %s accettano la protezione di %s." % [name, k.name]})
	if k.is_player:
		EventBus.notify("Nuove terre", "%s entra nel regno per %d ori." % [name, roundi(price)], &"realm")
	return CommandResult.ok({"cost": price})


func describe() -> String:
	return "Annetti la terra libera %d al regno %d" % [province_id, kingdom_id]

