class_name KDDef
extends Resource
## Base class for data definitions loaded from res://data/defs/*.json.

@export var id: StringName
@export var display_name: String = ""
@export var description: String = ""


## Subclasses override to read their fields. Must append problems to `errors`.
func load_from(d: Dictionary, errors: PackedStringArray) -> void:
	id = StringName(d.get("id", ""))
	display_name = String(d.get("name", ""))
	description = String(d.get("description", ""))
	if id == &"":
		errors.append("%s: missing id" % get_script().resource_path.get_file())


static func read_color(value: Variant, fallback: Color = Color.MAGENTA) -> Color:
	if value is String and String(value).begins_with("#"):
		return Color.html(String(value))
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	return fallback

