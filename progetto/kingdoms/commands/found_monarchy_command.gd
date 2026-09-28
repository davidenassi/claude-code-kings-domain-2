class_name FoundMonarchyCommand
extends Command
## The great decision of the years before the crown (Phase 15): the community chooses one of its families as the
## royal house, and one of its members is crowned as the first sovereign. The choice belongs to the player; the
## game never makes it on its own.

var kingdom_id: int = -1
var family_id: int = -1
var person_id: int = -1


static func create(p_kingdom: int, p_family: int, p_person: int) -> FoundMonarchyCommand:
	var c := FoundMonarchyCommand.new()
	c.kingdom_id = p_kingdom
	c.family_id = p_family
	c.person_id = p_person
	return c


func get_type() -> StringName:
	return &"found_monarchy"


func validate(session: GameSession) -> String:
	var world := session.world
	var k := world.kingdom(kingdom_id)
	var blocker := CourtSystem.monarchy_blocker(session, k)
	if blocker != "":
		return blocker
	var f := world.family(family_id)
	if f == null or world.members_of(f.id).is_empty():
		return "Questa famiglia non vive più nella comunità."
	var p := world.person(person_id)
	if p == null or p.family != f.id:
		return "Questa persona non è della famiglia scelta."
	if not CourtSystem.eligible_rulers(world, f).has(p):
		return "%s non può essere incoronato: serve un adulto della famiglia che viva nella comunità." % p.name
	return ""


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var k := world.kingdom(kingdom_id)
	var ruler := CourtSystem.found_monarchy(session, k, world.family(family_id), world.person(person_id))
	return CommandResult.ok({"ruler": ruler.id})

