class_name DiplomacySystem
extends SimSystem
## Every day the world moves between the crowns: opinions walk towards what the facts ask, pacts and truces
## run out, tributes are paid, and the ambassadors waiting on the player's table go home if he never answers.


func _init() -> void:
	id = &"diplomacy"
	frequency = Frequency.DAY
	order = 26


func run(session: GameSession, step: SimStep) -> void:
	var world := session.world
	var cfg: Dictionary = Diplomacy.bal().get("opinion", {})
	var week := int(cfg.get("opinion_spread_days", 7))
	var chase := clampf(float(cfg.get("chase_per_day", 0.1)) * week, 0.0, 1.0)
	var bucket := world.day % week
	# each pair is looked at once a week, spread over the days so no morning costs more than another
	for r: RelationState in world.relations.values():
		if (r.a * 31 + r.b) % week != bucket:
			continue
		var ka := world.kingdom(r.a)
		var kb := world.kingdom(r.b)
		if ka == null or kb == null or not ka.alive or not kb.alive:
			continue
		if not r.pacts.is_empty():
			_expire_pacts(world, r)
		r.opinion = lerpf(r.opinion, Diplomacy.opinion_target(world, r), chase)
	if step.is_new_month:
		for r: RelationState in world.relations.values():
			if r.payer >= 0:
				_pay_tribute(world, r)
	if step.is_new_year:
		for r: RelationState in world.relations.values():
			if not r.memories.is_empty():
				_forget(world, r)
	_expire_offers(world)


func _expire_pacts(world: WorldState, r: RelationState) -> void:
	for pact_id: StringName in r.pacts.keys():
		var until := int(r.pacts[pact_id])
		if until > 0 and world.day >= until:
			r.pacts.erase(pact_id)
			if r.pacts.is_empty():
				r.payer = -1
			Diplomacy._touch(world, r.a, r.b)
			var ka := world.kingdom(r.a)
			var kb := world.kingdom(r.b)
			if ka.is_player or kb.is_player:
				EventBus.notify("Patto scaduto", "%s con %s non è più in vigore." % [
					Diplomacy.pact(pact_id).get("name", pact_id), kb.name if ka.is_player else ka.name], &"diplomacy")


## The weaker crown pays, every month, a share of what its lands yield.
func _pay_tribute(world: WorldState, r: RelationState) -> void:
	if r.payer < 0:
		return
	var pact_id := &"vassalage" if r.has_pact(&"vassalage") else &"tribute"
	if not r.has_pact(pact_id):
		return
	var share := float(Diplomacy.pact(pact_id).get("share_of_income", 0.0))
	var payer := world.kingdom(r.payer)
	var receiver := world.kingdom(r.other(r.payer))
	if payer == null or receiver == null or share <= 0.0:
		return
	var due := maxf(float(payer.last_balance.get("taxes", 0.0)) + float(payer.last_balance.get("provinces", 0.0)), 0.0) * share
	due = minf(due, maxf(payer.treasury, 0.0))
	if due <= 0.0:
		return
	payer.treasury -= due
	receiver.treasury += due


func _forget(world: WorldState, r: RelationState) -> void:
	var kept: Array[Dictionary] = []
	for m: Dictionary in r.memories:
		var def := Diplomacy.memory_def(StringName(m["kind"]))
		var life := float(def.get("years", 20)) * float(PersonState.DAYS_PER_YEAR)
		if def.is_empty() or world.day - int(m["day"]) < life:
			kept.append(m)
	r.memories = kept


func _expire_offers(world: WorldState) -> void:
	var kept: Array[Dictionary] = []
	for o: Dictionary in world.offers:
		if world.day < int(o.get("expires", 0)):
			kept.append(o)
	world.offers = kept

