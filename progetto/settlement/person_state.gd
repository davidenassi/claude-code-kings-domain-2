class_name PersonState
extends RefCounted
## One inhabitant. The player never commands individuals: jobs come from buildings and priorities, tasks from the
## settlement simulation. `seg_*` describe what the person is doing right now (for the renderer to interpolate).

const DAYS_PER_YEAR := 360

var id: int = -1
var name: String = ""
var female: bool = false
var birth_day: int = 0
var culture: StringName = &""
var religion: StringName = &""
var settlement: int = -1
var is_king: bool = false
## The family this person belongs to (FamilyState id), and the one she or he was born into (for a wife they differ).
var family: int = -1
var born_family: int = -1
## Spouse, mother and father (PersonState ids, -1 when there is none or they are unknown).
var spouse: int = -1
var mother: int = -1
var father: int = -1
var home: int = -1
var job: StringName = &"idle"
## Building where the person works (site for builders).
var workplace: int = -1
## Accumulated food shortage in days of rations (0 = well fed).
var hunger: float = 0.0

# --- current activity (simulation time in hours = ticks) ---
var action: StringName = &"idle"     ## walk, chop, quarry, build, farm, bake, carry, sleep, idle
var busy_until: float = 0.0
## What happens when the current action ends: {"do": StringName, ...}
var pending: Dictionary = {}
var seg_from: Vector2 = Vector2.ZERO
var seg_to: Vector2 = Vector2.ZERO
var seg_t0: float = 0.0
var seg_t1: float = 0.0
## Goods in hand: {"res": StringName, "amount": int, "for_site": int}
var carrying: Dictionary = {}


func age_years(day: int) -> int:
	return int(floor(float(day - birth_day) / float(DAYS_PER_YEAR)))


func position_at(hours: float) -> Vector2:
	if seg_t1 <= seg_t0 or hours >= seg_t1:
		return seg_to
	if hours <= seg_t0:
		return seg_from
	return seg_from.lerp(seg_to, (hours - seg_t0) / (seg_t1 - seg_t0))


func to_dict() -> Dictionary:
	var carry := {}
	if not carrying.is_empty():
		carry = {"res": String(carrying["res"]), "amount": int(carrying["amount"]), "for_site": int(carrying.get("for_site", -1)),
			"for_bake": int(carrying.get("for_bake", -1))}
	return {"id": id, "name": name, "female": female, "birth_day": birth_day, "culture": String(culture),
		"religion": String(religion), "settlement": settlement, "is_king": is_king, "home": home, "job": String(job),
		"family": family, "born_family": born_family, "spouse": spouse, "mother": mother, "father": father,
		"workplace": workplace, "hunger": hunger, "action": String(action), "busy_until": busy_until,
		"pending": JSON.stringify(pending), "seg": [seg_from.x, seg_from.y, seg_to.x, seg_to.y, seg_t0, seg_t1],
		"carrying": carry}


static func from_dict(d: Dictionary) -> PersonState:
	var p := PersonState.new()
	p.id = int(d.get("id", -1))
	p.name = String(d.get("name", ""))
	p.female = bool(d.get("female", false))
	p.birth_day = int(d.get("birth_day", 0))
	p.culture = StringName(d.get("culture", ""))
	p.religion = StringName(d.get("religion", ""))
	p.settlement = int(d.get("settlement", -1))
	p.is_king = bool(d.get("is_king", false))
	p.family = int(d.get("family", -1))
	p.born_family = int(d.get("born_family", -1))
	p.spouse = int(d.get("spouse", -1))
	p.mother = int(d.get("mother", -1))
	p.father = int(d.get("father", -1))
	p.home = int(d.get("home", -1))
	p.job = StringName(d.get("job", "idle"))
	p.workplace = int(d.get("workplace", -1))
	p.hunger = float(d.get("hunger", 0.0))
	p.action = StringName(d.get("action", "idle"))
	p.busy_until = float(d.get("busy_until", 0.0))
	var pend: Variant = JSON.parse_string(String(d.get("pending", "{}")))
	p.pending = _restore_pending(pend if pend is Dictionary else {})
	var seg: Array = d.get("seg", [0, 0, 0, 0, 0, 0])
	p.seg_from = Vector2(float(seg[0]), float(seg[1]))
	p.seg_to = Vector2(float(seg[2]), float(seg[3]))
	p.seg_t0 = float(seg[4])
	p.seg_t1 = float(seg[5])
	var c: Dictionary = d.get("carrying", {})
	if not c.is_empty():
		p.carrying = {"res": StringName(c["res"]), "amount": int(c["amount"]), "for_site": int(c.get("for_site", -1)),
			"for_bake": int(c.get("for_bake", -1))}
	return p


## JSON turns every number into a float and StringNames into strings: normalise the fields tasks use.
static func _restore_pending(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	if out.has("do"):
		out["do"] = StringName(out["do"])
	for k in ["building", "site", "amount", "bake", "used"]:
		if out.has(k):
			out[k] = int(out[k])
	if out.has("res"):
		out["res"] = StringName(out["res"])
	if out.has("x") and out.has("y"):
		out["x"] = float(out["x"])
		out["y"] = float(out["y"])
	return out

