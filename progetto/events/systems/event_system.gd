class_name EventSystem
extends SimSystem
## The world knocking at the door. Once a month every realm may meet something — a good harvest, a hard winter,
## the plague, bandits, a rebellious lord — chosen among the events whose conditions really hold. The AI answers
## with the head of whoever reigns; the player's crown waits for his word (and, if he never gives it, the
## first answer is taken for him). Rules in data/defs/events.json and balance/events.json.


func _init() -> void:
	id = &"events"
	frequency = Frequency.MONTH
	order = 38


static func cfg() -> Dictionary:
	return (Events.bal().get("events", {}) as Dictionary)


func run(session: GameSession, step: SimStep) -> void:
	var world := session.world
	_expire_crises(world, step.day)
	_expire_pending(session, step.day)
	var rng := world.rng.stream(&"events")
	for k in world.kingdoms:
		if not k.alive or k.provinces.is_empty():
			continue
		_fire_due_chains(session, k, step.day)
		var last := int(k.records.get(&"event_last_day", -999999.0))
		if step.day - last < int(cfg().get("min_days_between_events", 90)):
			continue
		var chance := float(cfg().get("chance_per_roll", 0.5)) if k.is_player else float(cfg().get("ai_chance_per_roll", 0.35))
		if rng.randf() > chance:
			continue
		var e := Events.pick(session, k, rng)
		if e.is_empty():
			continue
		fire(session, k, e, step.day)


## Puts one event in front of a realm: the AI decides at once, the player is asked.
static func fire(session: GameSession, k: KingdomState, e: Dictionary, day: int) -> void:
	var world := session.world
	k.records[StringName("event_day:%s" % String(e["id"]))] = float(day)
	k.records[&"event_last_day"] = float(day)
	if k.is_player:
		world.pending_events.append({"id": world.new_id(), "event": String(e["id"]), "day": day,
			"expires": day + int(cfg().get("answer_days", 45))})
		EventBus.notify(Events.words(k, String(e.get("title", "Un fatto"))), Events.words(k, String(e.get("text", ""))), &"event")
		EventBus.event_raised.emit(String(e["id"]))
	else:
		choose(session, k, e, Events.ai_choice(world, k, e), day)


## The categories of events whose choice is history even when it is not a crisis: the dynasty, the ruler, the
## crises of the realm (consolidation: every answer wrote a line, 127 in forty years, harvests and wolves included).
const CHRONICLE_CATEGORIES: Array[String] = ["dinastia", "sovrano", "crisi"]


## Applies one option, writes it in the chronicle when it is history, and follows the chain, if the option has one.
static func choose(session: GameSession, k: KingdomState, e: Dictionary, option_index: int, day: int) -> void:
	var options: Array = e.get("options", [])
	if options.is_empty():
		return
	var option: Dictionary = options[clampi(option_index, 0, options.size() - 1)]
	Events.apply(session, k, option.get("effects", {}))
	var own_line := (option.get("effects", {}) as Dictionary).has("chronicle")
	if not own_line and (String(e.get("kind", "")) == "crisis" or CHRONICLE_CATEGORIES.has(String(e.get("category", "")))):
		EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "event",
			"text": "%s — %s: %s" % [k.name, Events.words(k, String(e.get("title", "Un fatto"))), Events.words(k, String(option.get("text", "")))]})
	var chain := StringName(option.get("effects", {}).get("chain", ""))
	if chain != &"":
		var next := Events.event(chain)
		var after := int(option.get("effects", {}).get("chain_days", next.get("after_days", 0)))
		if not next.is_empty() and after <= 0:
			fire(session, k, next, day)
		elif not next.is_empty():
			# the sequel comes when its time comes (Phase 17: the usurers asked back their gold the same day)
			k.records[StringName("chain_due:%s" % chain)] = float(day + after)
	EventBus.event_raised.emit(String(e["id"]))


static func _fire_due_chains(session: GameSession, k: KingdomState, day: int) -> void:
	for key: StringName in k.records.keys():
		var name := String(key)
		if not name.begins_with("chain_due:") or float(k.records[key]) > float(day):
			continue
		k.records.erase(key)
		var next := Events.event(StringName(name.substr(10)))
		if not next.is_empty():
			fire(session, k, next, day)
		return   # one sequel a month is enough


# --- what runs out -------------------------------------------------------------------------------------------

static func _expire_crises(world: WorldState, day: int) -> void:
	for k in world.kingdoms:
		if k.crises.is_empty():
			continue
		var kept: Array[Dictionary] = []
		for c in k.crises:
			if int(c["until"]) > day:
				kept.append(c)
			else:
				if k.is_player:
					EventBus.notify("Passata", "%s è finita." % c.get("name", "La crisi"), &"event")
		if kept.size() != k.crises.size():
			k.crises = kept
			k.identity_changed()


## An answer that never comes is an answer: the first option is what the court decided in the king's silence.
static func _expire_pending(session: GameSession, day: int) -> void:
	var world := session.world
	var k := world.player()
	if k == null:
		return
	var kept: Array[Dictionary] = []
	for pending in world.pending_events:
		if day < int(pending["expires"]):
			kept.append(pending)
			continue
		var e := Events.event(StringName(pending["event"]))
		if not e.is_empty():
			choose(session, k, e, 0, day)
	world.pending_events = kept

