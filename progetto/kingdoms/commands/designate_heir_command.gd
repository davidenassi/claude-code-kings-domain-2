class_name DesignateHeirCommand
extends Command
## The ruler names his successor. The law still decides when nobody has been named (heir_designate = -1).

var kingdom_id: int = -1
var character_id: int = -1


static func create(p_kingdom: int, p_character: int) -> DesignateHeirCommand:
	var c := DesignateHeirCommand.new()
	c.kingdom_id = p_kingdom
	c.character_id = p_character
	return c


func get_type() -> StringName:
	return &"designate_heir"


func validate(session: GameSession) -> String:
	var k := session.world.kingdom(kingdom_id)
	if k == null:
		return "Regno inesistente."
	if not k.monarchy_founded:
		return "Non c'è ancora una corona: le leggi, gli editti e gli eredi arrivano con la monarchia."
	if character_id < 0:
		return ""  # back to the law
	var c := session.world.character(character_id)
	if c == null or not c.alive():
		return "Questa persona non può ereditare."
	if c.kingdom != k.id or c.id == k.ruler:
		return "L'erede deve essere un altro membro della corte."
	if StringName(k.laws.get(&"succession", &"")) == &"elective":
		return "Con la successione elettiva l'erede non si nomina: lo scelgono i grandi del regno."
	return ""


func execute(session: GameSession) -> CommandResult:
	var k := session.world.kingdom(kingdom_id)
	k.heir_designate = character_id
	var c := session.world.character(character_id)
	if k.is_player:
		EventBus.notify("Erede designato", "%s è indicato come successore." % c.name if c else "L'erede torna a essere quello di legge.", &"court")
	return CommandResult.ok()

