class_name AdoptTechnologyCommand
extends Command
## The crown spends what its scribes and masters have put together on one road of knowledge. Every branch has
## two roads and only one can be taken: what is learned in one way is not learned in the other.

var kingdom_id: int = -1
var tech_id: StringName = &""


static func create(p_kingdom: int, p_tech: StringName) -> AdoptTechnologyCommand:
	var c := AdoptTechnologyCommand.new()
	c.kingdom_id = p_kingdom
	c.tech_id = p_tech
	return c


func get_type() -> StringName:
	return &"adopt_technology"


func validate(session: GameSession) -> String:
	var k := session.world.kingdom(kingdom_id)
	var tech := Technologies.item(tech_id)
	if k == null or tech.is_empty():
		return "Sapere sconosciuto."
	if k.technologies.has(tech_id):
		return "Il regno lo conosce già."
	if Technologies.branch_taken(k, tech_id):
		var b := Technologies.branch_of(tech_id)
		return "In %s il regno ha già scelto la sua strada." % String(b.get("name", "questo ramo")).to_lower()
	if k.research < float(tech.get("cost", 0)):
		return "Servono %d punti di sapere, il regno ne ha %d." % [int(tech.get("cost", 0)), int(k.research)]
	return ""


func execute(session: GameSession) -> CommandResult:
	var world := session.world
	var k := world.kingdom(kingdom_id)
	var tech := Technologies.item(tech_id)
	k.research -= float(tech.get("cost", 0))
	k.technologies.append(tech_id)
	k.identity_changed()
	KingdomModifiers.record(world, k.id, &"technologies", 1.0)
	EventBus.chronicle_written.emit({"day": world.day, "kingdom": k.id, "kind": "technology",
		"text": "%s adotta %s." % [k.name, String(tech.get("name", tech_id)).to_lower()]})
	if k.is_player:
		EventBus.notify("Nuovo sapere", String(tech.get("name", tech_id)), &"realm")
	return CommandResult.ok()

