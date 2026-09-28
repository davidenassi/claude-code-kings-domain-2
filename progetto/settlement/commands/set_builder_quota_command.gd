class_name SetBuilderQuotaCommand
extends Command
## Share of the inhabitants sent to construction sites (few, fair, many, all).

var settlement_id: int = -1
var quota: StringName = &"fair"


static func create(p_settlement: int, p_quota: StringName) -> SetBuilderQuotaCommand:
	var c := SetBuilderQuotaCommand.new()
	c.settlement_id = p_settlement
	c.quota = p_quota
	return c


func get_type() -> StringName:
	return &"set_builder_quota"


func validate(session: GameSession) -> String:
	if session.world.settlement(settlement_id) == null:
		return "Insediamento inesistente."
	for q: Dictionary in Defs.balance("settlement").get("builder_quotas", []):
		if StringName(q["id"]) == quota:
			return ""
	return "Quota sconosciuta."


func execute(session: GameSession) -> CommandResult:
	session.world.settlement(settlement_id).builder_quota = quota
	SettlementSim.mark_assignment_dirty(session, settlement_id)
	EventBus.settlement_changed.emit(settlement_id)
	return CommandResult.ok()

