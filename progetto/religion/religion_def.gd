class_name ReligionDef
extends KDDef
## A religion: FIXED statistics, independent from culture.

@export var color: Color = Color.WHITE
var modifiers: Array[Modifier] = []


func load_from(d: Dictionary, errors: PackedStringArray) -> void:
	super.load_from(d, errors)
	color = KDDef.read_color(d.get("color", "#ffffff"))
	modifiers = Modifier.list_from_array(d.get("modifiers", []))
	for m in modifiers:
		if m.key == &"":
			errors.append("religion %s: modifier without key" % id)

