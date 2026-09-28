class_name ResourceDef
extends KDDef
## A tradeable / storable good (wood, stone, iron, grain, bread, weapons, gold...).

@export var category: StringName = &"material"
@export var base_price: float = 1.0
@export var color: Color = Color.WHITE
@export var is_food: bool = false
## Food value relative to bread (bread = 1.0, raw grain less).
@export var food_value: float = 0.0
## Treasury goods (gold) do not occupy storage.
@export var uses_storage: bool = true
@export var icon: String = ""
## Which store holds it ("material", "food", "treasury"); capacity is shared inside a group.
@export var storage_group: StringName = &"material"


func load_from(d: Dictionary, errors: PackedStringArray) -> void:
	super.load_from(d, errors)
	category = StringName(d.get("category", "material"))
	base_price = float(d.get("base_price", 1.0))
	color = KDDef.read_color(d.get("color", "#ffffff"))
	is_food = bool(d.get("is_food", false))
	food_value = float(d.get("food_value", 0.0))
	uses_storage = bool(d.get("uses_storage", true))
	icon = String(d.get("icon", ""))
	storage_group = StringName(d.get("storage_group", "treasury" if not uses_storage else "material"))
	if base_price < 0.0:
		errors.append("resource %s: negative base_price" % id)
	if is_food and food_value <= 0.0:
		errors.append("resource %s: food without food_value" % id)

