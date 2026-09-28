class_name BiomeDef
extends KDDef
## A macro biome of the official map (value stored in data/world/biome.bin).

@export var index: int = 0
@export var color: Color = Color.GREEN
@export var fertility: float = 0.5
@export var forest: float = 0.0
@export var move_cost: float = 1.0
@export var local_terrain: StringName = &"grass"


func load_from(d: Dictionary, errors: PackedStringArray) -> void:
	super.load_from(d, errors)
	index = int(d.get("index", -1))
	color = KDDef.read_color(d.get("color", "#00ff00"))
	fertility = float(d.get("fertility", 0.5))
	forest = float(d.get("forest", 0.0))
	move_cost = float(d.get("move_cost", 1.0))
	local_terrain = StringName(d.get("local_terrain", "grass"))
	if index < 0 or index > 255:
		errors.append("biome %s: index out of range" % id)

