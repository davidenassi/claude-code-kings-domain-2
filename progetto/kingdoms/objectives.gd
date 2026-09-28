class_name Objectives
extends RefCounted
## What a campaign is for. Not a score: things a crown can point at and say "this I have done".
## Thresholds in data/defs/balance/events.json.


static func cfg() -> Dictionary:
	return (Defs.balance("events").get("objectives", {}) as Dictionary)


## [{id, category, name, description, value, target, done}] for the realm, in the order they are shown.
## Phase 17: eleven aims in different fields, so that conquering everything is not the only sensible way to play.
static func progress(session: GameSession, k: KingdomState) -> Array:
	var world := session.world
	var c := cfg()
	var people := 0
	var capital_people := 0
	for s in world.settlements:
		if s.kingdom == k.id:
			var n := world.people_of(s.id).size()
			people += n
			capital_people = maxi(capital_people, n)
	var pacts := 0
	for r: RelationState in world.relations.values():
		if (r.a == k.id or r.b == k.id) and not r.at_war:
			pacts += r.pacts.size()
	var identity := 0
	for spirit_id in k.spirits:
		var sp: NationalSpiritDef = Defs.get_def("national_spirits", spirit_id)
		if sp and not sp.initial:
			identity += 1   # earned by deeds or grown out of the land's first spirits
	var out: Array = []
	out.append(_row("village", "capitale", "Un villaggio vivo", "Abitanti che lavorano nelle tue terre",
		people, int(c.get("village_people", 25))))
	out.append(_row("realm", "territorio", "Un dominio", "Province sotto la tua corona",
		k.provinces.size(), int(c.get("provinces", 8))))
	out.append(_row("dynasty", "dinastia", "Una dinastia", "Sovrani della tua casata che hanno regnato",
		int(k.records.get(&"rulers_crowned", 0.0)), int(c.get("dynasty_rulers", 4))))
	out.append(_row("treasury", "ricchezza", "Un tesoro", "Oro nelle casse della corona",
		int(k.treasury), int(c.get("treasury", 1500))))
	out.append(_row("knowledge", "sapere", "Il sapere", "Rami di conoscenza portati a compimento",
		k.technologies.size(), int(c.get("technologies", 3))))
	out.append(_row("capital", "capitale", "Una capitale", "Abitanti del più grande insediamento del regno",
		capital_people, int(c.get("capital_people", 150))))
	out.append(_row("trade", "commercio", "Un regno di mercanti", "Oro guadagnato vendendo ciò che avanza",
		int(k.records.get(&"trade_gold", 0.0)), int(c.get("trade_gold", 5000))))
	out.append(_row("victories", "guerra", "Vittorie", "Battaglie vinte dalle tue schiere",
		int(k.records.get(&"battles_won", 0.0)), int(c.get("battles_won", 5))))
	out.append(_row("pacts", "diplomazia", "Amici e alleati", "Patti in vigore con altri regni",
		pacts, int(c.get("pacts", 3))))
	out.append(_row("identity", "cultura", "Un'identità", "Spiriti del regno nati da ciò che ha fatto, non solo dalla terra",
		identity, int(c.get("identity_spirits", 2))))
	out.append(_row("stability", "stabilità", "Una pace lunga", "Il più lungo periodo di anni con stabilità e legittimità da 60 in su",
		int(k.records.get(&"stable_best", 0.0)), int(c.get("stable_years", 15))))
	return out


static func _row(id: String, category: String, name: String, description: String, value: int, target: int) -> Dictionary:
	return {"id": id, "category": category, "name": name, "description": description, "value": value, "target": target,
		"done": value >= target}


static func completed(session: GameSession, k: KingdomState) -> int:
	var count := 0
	for row: Dictionary in progress(session, k):
		if bool(row["done"]):
			count += 1
	return count

