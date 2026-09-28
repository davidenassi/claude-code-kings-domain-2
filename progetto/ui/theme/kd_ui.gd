class_name KDUi
extends RefCounted
## The painted skin of the interface: the pieces cut from the asset sheets (assets/ui/kit.json) turned into
## nine-patch styles and icons, built once and handed out to everybody.
##
## Nine patch = the four corners never stretch, the four sides stretch one way, the middle stretches both.
## The margins come from the kit, so a frame keeps its carved corners at any size.

const KIT_PATH := "res://assets/ui/kit.json"
const DIR := "res://assets/ui"

static var _kit: Dictionary = {}
static var _styles: Dictionary = {}
static var _icons: Dictionary = {}


static func kit() -> Dictionary:
	if _kit.is_empty():
		var d: Variant = Defs.read_json(KIT_PATH)
		_kit = (d as Dictionary).get("pieces", {}) if d is Dictionary else {}
	return _kit


static func has(piece: StringName) -> bool:
	return kit().has(String(piece))


## A nine-patch style from a piece of the kit. `content` overrides the inner padding (the room for text).
static func style(piece: StringName, content: Vector4 = Vector4.ZERO) -> StyleBoxTexture:
	var key := "%s|%v" % [piece, content]
	if _styles.has(key):
		return _styles[key]
	var entry: Dictionary = kit().get(String(piece), {})
	var box := StyleBoxTexture.new()
	if entry.is_empty():
		_styles[key] = box
		return box
	var texture: Texture2D = load(DIR.path_join(String(entry["file"])))
	box.texture = texture
	var m: Array = entry.get("margins", [12, 12, 12, 12])
	box.texture_margin_left = float(m[0])
	box.texture_margin_top = float(m[1])
	box.texture_margin_right = float(m[2])
	box.texture_margin_bottom = float(m[3])
	box.content_margin_left = content.x if content.x > 0.0 else float(m[0]) * 0.6 + 6.0
	box.content_margin_top = content.y if content.y > 0.0 else float(m[1]) * 0.6 + 4.0
	box.content_margin_right = content.z if content.z > 0.0 else float(m[2]) * 0.6 + 6.0
	box.content_margin_bottom = content.w if content.w > 0.0 else float(m[3]) * 0.6 + 4.0
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	_styles[key] = box
	return box


## One of the painted icons (icon_gold, icon_people, icon_wood…), or null when it does not exist.
static func icon(name: StringName) -> Texture2D:
	var key := String(name)
	if _icons.has(key):
		return _icons[key]
	var entry: Dictionary = kit().get(key if key.begins_with("icon_") else "icon_" + key, {})
	var texture: Texture2D = null
	if not entry.is_empty():
		texture = load(DIR.path_join(String(entry["file"])))
	_icons[key] = texture
	return texture


## The texture of any piece of the kit (the checkboxes, the close button…), or null.
static func piece(name: StringName) -> Texture2D:
	var entry: Dictionary = kit().get(String(name), {})
	return load(DIR.path_join(String(entry["file"]))) if not entry.is_empty() else null


## A TextureRect with an icon, sized in pixels of height (the width follows the drawing).
static func icon_node(name: StringName, height: float = 22.0) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = icon(name)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(height * 1.15, height)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

