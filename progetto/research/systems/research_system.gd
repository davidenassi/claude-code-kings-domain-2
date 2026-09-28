class_name ResearchSystem
extends SimSystem
## Every month the realm puts aside what its lands, its workshops and the head of whoever reigns can spare for
## knowing things. The AI adopts what it can as soon as it can; the player chooses. Rules in balance/events.json.


func _init() -> void:
	id = &"research"
	frequency = Frequency.MONTH
	order = 36


static func bal() -> Dictionary:
	return (Defs.balance("events").get("research", {}) as Dictionary)


func run(session: GameSession, _step: SimStep) -> void:
	var world := session.world
	for k in world.kingdoms:
		if not k.alive or k.provinces.is_empty():
			continue
		k.research += points_per_month(session, k)
		if not k.is_player:
			ai_adopt(session, k)


## What the realm learns in a month, and why.
static func points_per_month(session: GameSession, k: KingdomState) -> float:
	var world := session.world
	var cfg := bal()
	var value := float(cfg.get("base_per_month", 6.0))
	for pid in k.provinces:
		var p := world.province(pid)
		if p:
			value += float(cfg.get("per_development", 1.1)) * p.development
	for s in world.settlements:
		if s.kingdom == k.id:
			value += float(cfg.get("per_building", 0.5)) * world.buildings_of(s.id).size()
	var ruler := world.ruler_of(k.id)
	if ruler:
		value += float(cfg.get("per_governo_skill", 0.8)) * (ruler.skill(&"governo") - 5)
		if ruler.traits.has(&"saggio"):
			value *= float(cfg.get("saggio_bonus", 1.25))
	return maxf(value, 0.0) * KingdomModifiers.value(session, k.id, &"research.speed", 1.0)


## The AI takes the knowledge that fits its ruler as soon as it can pay for it (public: the campaign pilot uses it).
static func ai_adopt(session: GameSession, k: KingdomState) -> void:
	var mind := DiplomacyAi.personality(session.world, k.id)
	var best: Dictionary = {}
	var best_value := -INF
	for tech: Dictionary in Technologies.available(k):
		if k.research < float(tech.get("cost", 0)):
			continue
		var value := 0.5
		match StringName(tech["id"]):
			&"rotazione", &"bonifica":
				value += 0.4
			&"mulini", &"altoforno":
				value += float(mind.get("trade", 0.3))
			&"cancelleria", &"curia_regia":
				value += float(mind.get("authority", 0.3))
			&"mura_di_pietra", &"leva_regia":
				value += float(mind.get("aggression", 0.25))
		if value > best_value:
			best_value = value
			best = tech
	if not best.is_empty():
		session.submit(AdoptTechnologyCommand.create(k.id, StringName(best["id"])))

