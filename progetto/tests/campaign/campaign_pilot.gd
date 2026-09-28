class_name CampaignPilot
extends RefCounted
## A careful player for whole campaigns (Phase 16). It never cheats: every move is a command the player could
## give from the interface, and it is refused for the same reasons.
##
## - the villages: one month of a careful lord each (`SettlementPlanner.lord_month`);
## - before the crown: when the six conditions hold, the family with the best name is chosen and its eldest
##   adult crowned;
## - after the crown: the same head the AI crowns use (`RealmAiSystem.take_turn`) for laws, lands, pacts, war and
##   peace — a reasonable ruler, not a genius;
## - knowledge is taken as the AI crowns take it;
## - events are answered as the reigning character would, embassies judged as an AI crown would judge them — but
##   a player never puts his own crown under tribute or vassalage because an embassy asked.


## Returns the choice of the crown this month ({} when it did nothing or there is no crown yet).
static func month(session: GameSession) -> Dictionary:
	var world := session.world
	var k := world.player()
	if k == null or not k.alive:
		return {}
	_answer_events(session, k)
	_answer_offers(session, k)
	for s in world.settlements:
		if s.kingdom == k.id:
			SettlementPlanner.lord_month(session, s.id, 1000)
	if not k.monarchy_founded:
		_crown_when_ready(session, k)
		return {}
	ResearchSystem.ai_adopt(session, k)   # the knowledge that fits the one who reigns, as the AI crowns do
	return RealmAiSystem.take_turn(session, k)


static func _answer_events(session: GameSession, k: KingdomState) -> void:
	var world := session.world
	for pending: Dictionary in world.pending_events.duplicate():
		var e := Events.event(StringName(pending["event"]))
		if e.is_empty():
			continue
		session.submit(ChooseEventOptionCommand.create(int(pending["id"]), Events.ai_choice(world, k, e)))


static func _answer_offers(session: GameSession, k: KingdomState) -> void:
	var world := session.world
	for o: Dictionary in world.offers.duplicate():
		var accept := true
		match String(o.get("kind", "")):
			"pact":
				accept = bool(DiplomacyAi.judge_pact(session, int(o["from"]), k.id, StringName(o["pact"])).get("accept", false))
				# a player does not put his own crown under tribute because an embassy asked nicely
				if bool(Diplomacy.pact(StringName(o["pact"])).get("asymmetric", false)):
					accept = false
			"marriage":
				accept = k.monarchy_founded and bool(DiplomacyAi.judge_marriage(session, int(o["from"]), k.id).get("accept", false))
			"peace":
				accept = true   # a careful ruler takes the peace that is offered
		var cmd := AnswerOfferCommand.create(int(o["id"]), accept)
		if cmd.validate(session) != "":
			cmd = AnswerOfferCommand.create(int(o["id"]), false)
		session.submit(cmd)


static func _crown_when_ready(session: GameSession, k: KingdomState) -> void:
	var world := session.world
	if CourtSystem.monarchy_blocker(session, k) != "":
		return
	var home: SettlementState = null
	for s in world.settlements:
		if s.kingdom == k.id:
			home = s
			break
	if home == null:
		return
	var best: FamilyState = null
	for f in FamilySystem.consolidated_families(world, home):
		if CourtSystem.eligible_rulers(world, f).is_empty():
			continue
		if best == null or FamilySystem.influence(world, f) > FamilySystem.influence(world, best):
			best = f
	if best:
		session.submit(FoundMonarchyCommand.create(k.id, best.id, CourtSystem.eligible_rulers(world, best)[0].id))

