class_name TransferProvinceCommand
extends Command
## Transfers a province to another realm (or frees it with new_owner = -1).
## Used today by development tools and tests; conquest, treaties and inheritance use it in later phases.

var province_id: int = -1
var new_owner: int = ProvinceState.NO_OWNER
var reason: StringName = &"transfer"


static func create(p_province: int, p_owner: int, p_reason: StringName = &"transfer") -> TransferProvinceCommand:
	var c := TransferProvinceCommand.new()
	c.province_id = p_province
	c.new_owner = p_owner
	c.reason = p_reason
	return c


func get_type() -> StringName:
	return &"transfer_province"


func validate(session: GameSession) -> String:
	var p := session.world.province(province_id)
	if p == null:
		return "Provincia inesistente."
	if new_owner != ProvinceState.NO_OWNER and session.world.kingdom(new_owner) == null:
		return "Regno inesistente."
	if p.owner == new_owner:
		return "La provincia appartiene già a questo regno."
	return ""


func execute(session: GameSession) -> CommandResult:
	var old := session.world.set_province_owner(province_id, new_owner)
	EventBus.province_owner_changed.emit(province_id, old, new_owner, reason)
	return CommandResult.ok({"old_owner": old})


func describe() -> String:
	return "Trasferisci provincia %d a %d" % [province_id, new_owner]

