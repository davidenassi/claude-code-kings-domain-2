class_name DevelopProvinceCommand
extends Command
## The crown spends gold on a province: fields cleared, a mill, a bridge, a market day. Development is the
## slow wealth of a land — it raises its rents and how many people it can hold.

var kingdom_id: int = -1
var province_id: int = -1


static func create(p_kingdom: int, p_province: int) -> DevelopProvinceCommand:
	var c := DevelopProvinceCommand.new()
	c.kingdom_id = p_kingdom
	c.province_id = p_province
	return c


func get_type() -> StringName:
	return &"develop_province"


static func cost(session: GameSession, province_id: int) -> float:
	var cfg: Dictionary = Diplomacy.bal().get("ai", {})
	var p := session.world.province(province_id)
	var base := float(cfg.get("develop_province_cost", 120.0))
	return base * (1.0 + 0.35 * float(p.development if p else 0))


func validate(session: GameSession) -> String:
	var world := session.world
	var k := world.kingdom(kingdom_id)
	var p := world.province(province_id)
	if k == null or p == null:
		return "Regno o provincia inesistente."
	if p.owner != k.id:
		return "Quella provincia non è vostra."
	var max_dev := int((Diplomacy.bal().get("ai", {}) as Dictionary).get("develop_province_max", 8))
	if p.development >= max_dev:
		return "La provincia è già sviluppata quanto può."
	if p.is_occupied():
		return "La provincia è occupata."
	var price := cost(session, province_id)
	if k.treasury < price:
		return "Servono %d ori, la corona ne ha %d." % [int(price), int(k.treasury)]
	return ""


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var k := world.kingdom(kingdom_id)
	var p := world.province(province_id)
	k.treasury -= cost(session, province_id)
	p.development += 1
	world.political_version += 1
	KingdomModifiers.record(world, k.id, &"development", 1.0)
	EventBus.province_owner_changed.emit(p.id, p.owner, p.owner, &"development")
	if k.is_player:
		EventBus.notify("Terre migliorate", "Lo sviluppo della provincia sale a %d." % p.development, &"realm")
	return CommandResult.ok({"development": p.development})

