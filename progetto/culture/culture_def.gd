class_name CultureDef
extends KDDef
## A culture: FIXED statistics that never change with the ruler.

@export var color: Color = Color.WHITE
@export var name_pool: StringName = &""
var modifiers: Array[Modifier] = []


func load_from(d: Dictionary, errors: PackedStringArray) -> void:
	super.load_from(d, errors)
	color = KDDef.read_color(d.get("color", "#ffffff"))
	name_pool = StringName(d.get("name_pool", String(id)))
	modifiers = Modifier.list_from_array(d.get("modifiers", []))
	for m in modifiers:
		if m.key == &"":
			errors.append("culture %s: modifier without key" % id)

