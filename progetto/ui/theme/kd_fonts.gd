class_name KDFonts
extends RefCounted
## Fonts of the illustrated map and UI.
## Engraved capitals for realm names, a book serif for text, its italic for province names.
## System fonts with fallbacks for now: a bundled, redistributable medieval font arrives with the UI phase (Phase 12).

static var _cache: Dictionary = {}


static func _system(key: String, names: PackedStringArray, weight: int = 400, italic: bool = false) -> Font:
	if not _cache.has(key):
		var f := SystemFont.new()
		f.font_names = names
		f.font_weight = weight
		f.font_italic = italic
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		# light hinting keeps the serifs of the small sizes on the pixel grid without flattening the letters
		# (the default full hinting made them look jagged once the layout is scaled to the window)
		f.hinting = TextServer.HINTING_LIGHT
		f.force_autohinter = false
		_cache[key] = f
	return _cache[key]


## Engraved titling capitals (realm names on the map).
static func title() -> Font:
	return _system("title", PackedStringArray(["Perpetua Titling MT", "Castellar", "Trajan Pro", "Cinzel",
		"Book Antiqua", "Palatino Linotype", "Georgia", "serif"]), 700)


static func serif() -> Font:
	return _system("serif", PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "Times New Roman", "serif"]))


static func serif_bold() -> Font:
	return _system("serif_bold", PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "Times New Roman", "serif"]), 700)


static func serif_italic() -> Font:
	return _system("serif_italic", PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "serif"]), 400, true)

