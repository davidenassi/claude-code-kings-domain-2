class_name UnitDef
extends KDDef
## A kind of regiment (data/defs/units.json). Men are real inhabitants; weapons are real weapons in store.

@export var category: StringName = &"infantry"
@export var men: int = 8
@export var gold: float = 30.0
@export var weapons: int = 4
@export var train_days: int = 20
@export var upkeep_gold_day: float = 0.3
@export var food_day: int = 8
@export var speed_kmh: float = 4.0
@export var attack: int = 6
@export var defense: int = 8
@export var morale: float = 55.0
## {"building": id, "weapons_made": n, "favour": {faction: value}}
var requires: Dictionary = {}


func load_from(d: Dictionary, errors: PackedStringArray) -> void:
	super.load_from(d, errors)
	category = StringName(d.get("category", "infantry"))
	men = int(d.get("men", 8))
	gold = float(d.get("gold", 30.0))
	weapons = int(d.get("weapons", 4))
	train_days = int(d.get("train_days", 20))
	upkeep_gold_day = float(d.get("upkeep_gold_day", 0.3))
	food_day = int(d.get("food_day", 8))
	speed_kmh = float(d.get("speed_kmh", 4.0))
	attack = int(d.get("attack", 6))
	defense = int(d.get("defense", 8))
	morale = float(d.get("morale", 55.0))
	requires = d.get("requires", {})
	if men <= 0:
		errors.append("unit %s: men must be positive" % id)

