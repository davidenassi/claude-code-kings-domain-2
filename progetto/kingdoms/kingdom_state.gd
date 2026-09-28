class_name KingdomState
extends RefCounted
## A political entity on the map: the player's nascent realm, a formed kingdom or a minor lordship.
## The rank is a derived label that later phases promote (lordship -> kingdom) from real conditions.

enum Rank { SETTLEMENT, LORDSHIP, KINGDOM }

const RANK_IDS := {Rank.SETTLEMENT: &"settlement", Rank.LORDSHIP: &"lordship", Rank.KINGDOM: &"kingdom"}

var id: int = -1
## Stable key from start_setup.json ("" for generated lordships).
var key: StringName = &""
var name: String = ""
var house: String = ""
var rank: Rank = Rank.LORDSHIP
var culture: StringName = &""
var religion: StringName = &""
var color: Color = Color.GRAY
var capital: int = -1
var is_player: bool = false
var coat_of_arms: CoatOfArms
var alive: bool = true
## Crown treasury in gold (negative means debt).
var treasury: float = 0.0
## Last monthly balance for the UI: {"taxes", "provinces", "wages", "total"}.
var last_balance: Dictionary = {}
## Why the crown's measures stand where they do, for the tooltips of the top bar (Phase 18):
## {"legitimacy": {label: points, "_target": t}, "stability": {...}, "prestige": {...}}. Recomputed with the
## measures, never saved.
var measure_parts: Dictionary = {}
## Market prices of the realm (resource -> gold per unit), from scarcity against population.
var prices: Dictionary = {}
## National spirits in force (ids of data/defs/national_spirits.json).
var spirits: Array[StringName] = []
## spirit id -> day it was gained.
var spirit_since: Dictionary = {}
## Spirits the realm has left behind (they never come back on their own).
var spirits_past: Array[StringName] = []
## The person who reigns (CharacterState id) and the heir chosen by the crown (-1 = by law).
var ruler: int = -1
var heir_designate: int = -1
## Crown measures. `stability` is the realm's internal hold (public order, institutions, risk of crisis): it was
## called «Ordine» until the consolidation, and «Stabilità» is now its only name.
var legitimacy: float = 65.0
var stability: float = 80.0
var prestige: float = 10.0
## Shocks that push order down and fade day by day.
var turbulence: float = 0.0
## faction id -> favour 0..100
var favour: Dictionary = {}
## law group -> option id
var laws: Dictionary = {}
## edict id -> day it expires
var edicts: Dictionary = {}
## True while an heir is a child or nobody has been crowned yet.
var regency: bool = false
## False while the realm is still a community of families with nobody crowned (the player's start, Phase 15).
## Everything of the crown — ruler, succession, legitimacy, court, estates, laws — waits for it.
var monarchy_founded: bool = true
## Where the royal house comes from (data/defs/house_origins.json), and when the community began and was crowned.
var house_origin: StringName = &""
var founded_day: int = 0
var crowned_day: int = -1
## The family of the community that became the royal house (-1 before the crown, and in saves from before the
## consolidation until CourtSystem.royal_family_of finds it again).
var royal_family: int = -1
## Before the crown: the community's capacity to decide together (0..100). It becomes the first legitimacy of
## the royal house at the coronation.
var authority: float = 20.0
## Shocks that last: [{id, name, until, modifiers}] — plagues, quarantines, fairs, anything an event leaves behind.
var crises: Array[Dictionary] = []
## Knowledge the realm has adopted, and the points it has put aside.
var technologies: Array[StringName] = []
var research: float = 0.0

## Bumped whenever culture, religion or spirits change, so the modifier stack can be cached.
var identity_version: int = 0


func identity_changed() -> void:
	identity_version += 1
## Registers of what the realm has really done (wood cut, grain harvested, roads built, famine days...).
var records: Dictionary = {}
## Owned province ids, kept in sync by WorldState.set_province_owner (not saved: rebuilt on load).
var provinces: PackedInt32Array = PackedInt32Array()


func rank_id() -> StringName:
	return RANK_IDS[rank]


## Name without the rank prefix ("Regno di Waldmark" -> "Waldmark"), used for large map labels.
func short_name() -> String:
	for prefix in ["Regno di ", "Signoria di ", "Dominio di ", "Principato di ", "Ducato di "]:
		if name.begins_with(prefix):
			return name.substr(prefix.length())
	return name


func rank_label() -> String:
	match rank:
		Rank.SETTLEMENT:
			return "Insediamento"
		Rank.LORDSHIP:
			return "Signoria"
		_:
			return "Regno"


func to_dict() -> Dictionary:
	return {"id": id, "key": String(key), "name": name, "house": house, "rank": String(rank_id()),
		"culture": String(culture), "religion": String(religion), "color": color.to_html(false),
		"capital": capital, "is_player": is_player, "alive": alive, "arms": coat_of_arms.to_dict(),
		"treasury": treasury, "last_balance": last_balance.duplicate(), "prices": _prices_dict(),
		"spirits": spirits.map(func(s: StringName) -> String: return String(s)),
		"spirit_since": _string_keys(spirit_since), "records": _string_keys(records),
		"spirits_past": spirits_past.map(func(s: StringName) -> String: return String(s)),
		"ruler": ruler, "heir_designate": heir_designate, "legitimacy": legitimacy, "stability": stability,
		"prestige": prestige, "turbulence": turbulence, "regency": regency,
		"favour": _string_keys(favour), "laws": _string_keys(laws), "edicts": _string_keys(edicts),
		"crises": crises.duplicate(true), "research": research,
		"technologies": technologies.map(func(t: StringName) -> String: return String(t)),
		"monarchy_founded": monarchy_founded, "house_origin": String(house_origin), "founded_day": founded_day,
		"crowned_day": crowned_day, "authority": authority, "royal_family": royal_family}


static func _string_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[String(k)] = d[k]
	return out


func _prices_dict() -> Dictionary:
	var out := {}
	for res: StringName in prices.keys():
		out[String(res)] = prices[res]
	return out


static func from_dict(d: Dictionary) -> KingdomState:
	var k := KingdomState.new()
	k.id = int(d.get("id", -1))
	k.key = StringName(d.get("key", ""))
	k.name = String(d.get("name", ""))
	k.house = String(d.get("house", ""))
	k.rank = rank_from_id(StringName(d.get("rank", "lordship")))
	k.culture = StringName(d.get("culture", ""))
	k.religion = StringName(d.get("religion", ""))
	k.color = Color.html(String(d.get("color", "808080")))
	k.capital = int(d.get("capital", -1))
	k.is_player = bool(d.get("is_player", false))
	k.alive = bool(d.get("alive", true))
	k.treasury = float(d.get("treasury", 0.0))
	k.last_balance = (d.get("last_balance", {}) as Dictionary).duplicate()
	for res: String in (d.get("prices", {}) as Dictionary).keys():
		k.prices[StringName(res)] = float(d["prices"][res])
	for sid: String in d.get("spirits", []):
		k.spirits.append(StringName(sid))
	for sid: String in (d.get("spirit_since", {}) as Dictionary).keys():
		k.spirit_since[StringName(sid)] = int(d["spirit_since"][sid])
	for key: String in (d.get("records", {}) as Dictionary).keys():
		k.records[StringName(key)] = float(d["records"][key])
	for sid: String in d.get("spirits_past", []):
		k.spirits_past.append(StringName(sid))
	k.ruler = int(d.get("ruler", -1))
	k.heir_designate = int(d.get("heir_designate", -1))
	k.legitimacy = float(d.get("legitimacy", 65.0))
	k.stability = float(d.get("stability", 80.0))
	k.prestige = float(d.get("prestige", 10.0))
	k.turbulence = float(d.get("turbulence", 0.0))
	k.regency = bool(d.get("regency", false))
	for f: String in (d.get("favour", {}) as Dictionary).keys():
		k.favour[StringName(f)] = float(d["favour"][f])
	for g: String in (d.get("laws", {}) as Dictionary).keys():
		k.laws[StringName(g)] = StringName(d["laws"][g])
	for e: String in (d.get("edicts", {}) as Dictionary).keys():
		k.edicts[StringName(e)] = int(d["edicts"][e])
	for c: Dictionary in d.get("crises", []):
		k.crises.append({"id": String(c.get("id", "")), "name": String(c.get("name", "")),
			"until": int(c.get("until", 0)), "modifiers": c.get("modifiers", [])})
	for t: String in d.get("technologies", []):
		k.technologies.append(StringName(t))
	k.research = float(d.get("research", 0.0))
	# saves from before Phase 15 always had a crown: they load as founded monarchies
	k.monarchy_founded = bool(d.get("monarchy_founded", true))
	k.house_origin = StringName(d.get("house_origin", ""))
	k.founded_day = int(d.get("founded_day", 0))
	k.crowned_day = int(d.get("crowned_day", -1))
	k.authority = float(d.get("authority", 50.0))
	k.royal_family = int(d.get("royal_family", -1))
	var arms: Variant = d.get("arms", null)
	k.coat_of_arms = CoatOfArms.from_dict(arms) if arms is Dictionary else CoatOfArms.generate(k.house, k.culture)
	return k


static func rank_from_id(rank_key: StringName) -> Rank:
	for r: Rank in RANK_IDS.keys():
		if RANK_IDS[r] == rank_key:
			return r
	return Rank.LORDSHIP

