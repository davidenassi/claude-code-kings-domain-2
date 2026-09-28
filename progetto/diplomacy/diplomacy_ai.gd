class_name DiplomacyAi
extends RefCounted
## How a crown judges an offer, and what kind of person sits on it. The same code answers whether an AI realm
## accepts the player's proposal and whether it makes one of its own — and it always says why in words.


## The character of a realm today: its ruler's traits, tempered by the realm itself.
## Keys: aggression, greed, piety, caution, trade, authority, justice, cruelty.
static func personality(world: WorldState, kingdom_id: int) -> Dictionary:
	var cfg: Dictionary = Diplomacy.bal().get("ai", {})
	var out: Dictionary = (cfg.get("personality_base", {}) as Dictionary).duplicate()
	var ruler := world.ruler_of(kingdom_id)
	if ruler == null:
		out["caution"] = float(out.get("caution", 0.3)) + 0.3  # a regency dares nothing
		return out
	for td in ruler.trait_defs():
		for key: String in td.ai.keys():
			out[key] = float(out.get(key, 0.0)) + float(td.ai[key])
	var w := float(cfg.get("skill_weight", 0.04))
	out["aggression"] = float(out.get("aggression", 0.0)) + (ruler.skill(&"guerra") - 5) * w
	out["trade"] = float(out.get("trade", 0.0)) + (ruler.skill(&"diplomazia") - 5) * w
	out["authority"] = float(out.get("authority", 0.0)) + (ruler.skill(&"governo") - 5) * w
	var k := world.kingdom(kingdom_id)
	if k and k.regency:
		out["caution"] = float(out.get("caution", 0.3)) + 0.3
	for key: String in out.keys():
		out[key] = clampf(float(out[key]), -1.0, 1.5)
	return out


static func trait_line(world: WorldState, kingdom_id: int) -> String:
	var ruler := world.ruler_of(kingdom_id)
	if ruler == null:
		return "una reggenza"
	var names := ruler.trait_names()
	return "%s (%s)" % [ruler.name, ", ".join(names).to_lower() if names.size() > 0 else "senza fama"]


# --- judging an offer -------------------------------------------------------------------------------------

## Does `target` accept `pact_id` offered by `proposer`? Returns {accept, utility, reason}.
static func judge_pact(session: GameSession, proposer: int, target: int, pact_id: StringName) -> Dictionary:
	var world := session.world
	var cfg: Dictionary = Diplomacy.bal().get("acceptance", {})
	var def := Diplomacy.pact(pact_id)
	var r := Diplomacy.relation(world, proposer, target)
	var me := world.kingdom(target)
	var them := world.kingdom(proposer)
	if def.is_empty() or me == null or them == null:
		return {"accept": false, "utility": 0.0, "reason": "Non c'è nulla da trattare."}
	var mind := personality(world, target)
	var utility := 0.5 + r.opinion * float(cfg.get("opinion_weight", 0.012))
	var reasons := PackedStringArray()
	if r.opinion < float(def.get("min_opinion", 0)):
		return {"accept": false, "utility": 0.0,
			"reason": "%s non vi stima abbastanza (%d, ne servono %d)." % [me.name, roundi(r.opinion), int(def.get("min_opinion", 0))]}
	var ratio := Diplomacy.power_ratio(world, proposer, target)
	match pact_id:
		&"non_aggression":
			utility += float(mind.get("caution", 0.3)) * float(cfg.get("personality_weight", 0.35))
			utility -= float(mind.get("aggression", 0.25)) * float(cfg.get("personality_weight", 0.35))
			if ratio > 1.4:
				utility += float(cfg.get("power_weight", 0.25))
				reasons.append("siete più forti di loro")
		&"trade":
			utility += float(mind.get("trade", 0.3)) * float(cfg.get("personality_weight", 0.35))
			utility -= float(mind.get("greed", 0.3)) * 0.1
			if me.treasury < 0.0:
				utility += 0.15
				reasons.append("le loro casse sono vuote")
		&"alliance":
			if not r.has_pact(&"non_aggression"):
				return {"accept": false, "utility": 0.0,
					"reason": "Prima di un'alleanza %s vuole un patto di non aggressione." % me.name}
			utility += float(mind.get("caution", 0.3)) * 0.3
			utility += clampf((ratio - 1.0) * 0.3, -0.3, 0.45)
			for enemy in Diplomacy.enemies_of(world, target):
				if Diplomacy.has_pact(world, proposer, enemy, &"alliance"):
					utility += float(cfg.get("ally_of_my_enemy", -0.4))
					reasons.append("siete alleati di chi li combatte")
			if Diplomacy.enemies_of(world, target).size() > 0:
				utility += 0.25
				reasons.append("hanno una guerra aperta")
		&"tribute", &"vassalage":
			var needed := float(def.get("power_ratio", 2.0))
			if ratio < needed:
				return {"accept": false, "utility": 0.0,
					"reason": "%s non vi teme abbastanza (siete %.1f volte più forti, ne servono %.1f)." % [me.name, ratio, needed]}
			utility = 0.35 + clampf((ratio - needed) * 0.35, 0.0, 0.5)
			utility += float(mind.get("caution", 0.3)) * 0.4
			utility -= float(mind.get("authority", 0.3)) * 0.5
			if Diplomacy.enemies_of(world, target).size() > 0:
				utility += 0.2
				reasons.append("sono già in guerra con qualcun altro")
			reasons.append("la loro corona è debole")
		_:
			utility += 0.1
	if r.married:
		utility += 0.15
		reasons.append("le due case sono parenti")
	if me.regency:
		utility += 0.1
		reasons.append("il regno è retto da una reggenza prudente")
	var threshold := float(cfg.get("threshold", 0.5))
	var accept := utility >= threshold
	var reason := ""
	if accept:
		reason = "%s accetta: %s." % [me.name, ", ".join(reasons) if reasons.size() > 0 else "l'accordo conviene a entrambi"]
	else:
		reason = "%s rifiuta: %s." % [me.name, ", ".join(reasons) if reasons.size() > 0 else "l'accordo non conviene alla loro corona"]
	return {"accept": accept, "utility": utility, "reason": reason}


## Does `target` accept a dynastic marriage with `proposer`?
static func judge_marriage(session: GameSession, proposer: int, target: int) -> Dictionary:
	var world := session.world
	var m: Dictionary = Diplomacy.data().get("marriage", {})
	var r := Diplomacy.relation(world, proposer, target)
	var me := world.kingdom(target)
	if me == null:
		return {"accept": false, "reason": "Non c'è nessuno con cui imparentarsi."}
	if r.married:
		return {"accept": false, "reason": "Le due case sono già imparentate."}
	if r.opinion < float(m.get("min_opinion", 10)):
		return {"accept": false, "reason": "%s non vi stima abbastanza per darvi un figlio." % me.name}
	var ratio := Diplomacy.power_ratio(world, proposer, target)
	var mind := personality(world, target)
	var utility := 0.45 + r.opinion * 0.01 + clampf((ratio - 1.0) * 0.3, -0.2, 0.4) - float(mind.get("authority", 0.3)) * 0.2
	var accept := utility >= 0.5
	return {"accept": accept, "utility": utility,
		"reason": ("%s acconsente alle nozze." % me.name) if accept else ("%s preferisce cercare altrove." % me.name)}

