class_name TerrainTypeDef
extends KDDef
## Local terrain rules (2 m grid): walkability, buildability, movement cost.

@export var walkable: bool = true
@export var buildable: bool = true
@export var move_cost: float = 1.0
@export var color: Color = Color.GREEN
## What must be done before building here (e.g. "clear_trees", "quarry_rock"), empty if none.
@export var clearing: StringName = &""


func load_from(d: Dictionary, errors: PackedStringArray) -> void:
	super.load_from(d, errors)
	walkable = bool(d.get("walkable", true))
	buildable = bool(d.get("buildable", true))
	move_cost = float(d.get("move_cost", 1.0))
	color = KDDef.read_color(d.get("color", "#00ff00"))
	clearing = StringName(d.get("clearing", ""))
	if walkable and move_cost <= 0.0:
		errors.append("terrain %s: walkable with move_cost <= 0" % id)

