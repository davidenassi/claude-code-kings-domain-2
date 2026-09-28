class_name KDTheme
extends RefCounted
## The colours of the realm and the styles everything is dressed with. The shapes come from the painted kit
## (`KDUi`); when a piece is missing the old drawn-by-hand boxes are used, so the interface never goes blank.

const WOOD := Color("#2A1D12")
const WOOD_LIGHT := Color("#4A3322")
const GOLD := Color("#C9A24A")
const PARCHMENT := Color("#EADFBF")
const INK := Color("#2B1E12")
const TEXT_LIGHT := Color("#F0E6CC")


## The frame of a sheet or a window: carved corners, a painted band at the top for the title.
## The content margins clear the painted border, or the text would be written over the carving.
static func wood_panel(alpha: float = 0.94) -> StyleBox:
	if KDUi.has(&"window"):
		return KDUi.style(&"window", Vector4(42, 40, 42, 34))
	var s := StyleBoxFlat.new()
	s.bg_color = Color(WOOD, alpha)
	s.border_color = GOLD
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(10)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	return s


## The same carved frame without the title band: cards, inspectors, anything that starts straight with text.
static func card_panel() -> StyleBox:
	if KDUi.has(&"panel"):
		return KDUi.style(&"panel", Vector4(34, 24, 34, 30))
	return wood_panel(0.92)


## A plain dark box: bars, groups, rows.
static func dark_panel() -> StyleBox:
	if KDUi.has(&"panel_dark"):
		return KDUi.style(&"panel_dark", Vector4(16, 11, 16, 11))
	return wood_panel(0.92)


static func parchment_panel() -> StyleBox:
	var s := StyleBoxFlat.new()
	s.bg_color = PARCHMENT
	s.border_color = Color("#7A5A34")
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(10)
	return s


## Dresses a button with the painted states. `tone` picks a coloured variant: "", "green", "red", "blue".
static func button_styles(button: Button, tone: String = "") -> void:
	if KDUi.has(&"button"):
		var normal_name := StringName("button_%s" % tone) if tone != "" and KDUi.has(StringName("button_%s" % tone)) else &"button"
		var content := Vector4(14, 8, 14, 8)
		button.add_theme_stylebox_override("normal", KDUi.style(normal_name, content))
		button.add_theme_stylebox_override("hover", KDUi.style(&"button_hover", content))
		button.add_theme_stylebox_override("pressed", KDUi.style(&"button_pressed", content))
		button.add_theme_stylebox_override("hover_pressed", KDUi.style(&"button_pressed", content))
		button.add_theme_stylebox_override("disabled", KDUi.style(&"button_disabled", content))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	else:
		var normal := StyleBoxFlat.new()
		normal.bg_color = WOOD_LIGHT
		normal.border_color = Color(GOLD, 0.6)
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(3)
		normal.content_margin_left = 10
		normal.content_margin_right = 10
		normal.content_margin_top = 4
		normal.content_margin_bottom = 4
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = WOOD_LIGHT.lightened(0.15)
		var pressed := normal.duplicate() as StyleBoxFlat
		pressed.bg_color = Color("#7A5A2A")
		pressed.border_color = GOLD
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("hover_pressed", pressed)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", TEXT_LIGHT)
	button.add_theme_color_override("font_pressed_color", Color("#3A2A12"))
	button.add_theme_color_override("font_hover_color", Color("#FFF3D0"))
	button.add_theme_color_override("font_disabled_color", Color(TEXT_LIGHT, 0.45))
	button.add_theme_font_override("font", KDFonts.serif())
	button.add_theme_font_size_override("font_size", 15)


## The little ✕ that closes a sheet.
static func close_button() -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	if KDUi.has(&"close"):
		btn.add_theme_stylebox_override("normal", KDUi.style(&"close"))
		btn.add_theme_stylebox_override("hover", KDUi.style(&"close_hover"))
		btn.add_theme_stylebox_override("pressed", KDUi.style(&"close_pressed"))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.custom_minimum_size = Vector2(26, 26)
	else:
		btn.text = "x"
		button_styles(btn)
	return btn


## The dress of everything the code does not vest by hand: tooltips, scrollbars, boxes, bars, menus.
## Without it Godot's own grey theme shows through in every corner the painted kit has not reached, and the
## interface looks like two games glued together. Built once and hung on the root of the tree.
static var _project_theme: Theme = null


static func project_theme() -> Theme:
	if _project_theme != null:
		return _project_theme
	var t := Theme.new()
	t.default_font = KDFonts.serif()
	t.default_font_size = 16   # Phase 18 HUD review: 15 read small once the 1080p layout is scaled to the window

	# what the player reads most: the tooltip
	var tip := KDUi.style(&"panel", Vector4(30, 36, 30, 28)) if KDUi.has(&"panel") else parchment_panel()
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT_LIGHT)
	t.set_font("font", "TooltipLabel", KDFonts.serif())
	t.set_font_size("font_size", "TooltipLabel", 15)

	# the bars of the long sheets: a dark groove with a gold edge and a gold grabber, wide enough to be seen
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.0, 0.0, 0.0, 0.38)
	track.border_color = Color(GOLD, 0.25)
	track.set_border_width_all(1)
	track.set_corner_radius_all(4)
	track.content_margin_left = 4
	track.content_margin_right = 4
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(GOLD, 0.62)
	grabber.set_corner_radius_all(4)
	var grabber_hover := grabber.duplicate() as StyleBoxFlat
	grabber_hover.bg_color = Color(GOLD, 0.85)
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("grabber", bar, grabber)
		t.set_stylebox("grabber_highlight", bar, grabber_hover)
		t.set_stylebox("grabber_pressed", bar, grabber_hover)

	# boxes and ticks, with the painted marks when the kit has them
	if KDUi.has(&"check_on"):
		t.set_icon("checked", "CheckBox", KDUi.icon(&"check_on"))
		t.set_icon("unchecked", "CheckBox", KDUi.icon(&"check_off"))
	t.set_color("font_color", "CheckBox", TEXT_LIGHT)
	t.set_color("font_color", "Label", TEXT_LIGHT)
	t.set_font("font", "Label", KDFonts.serif())

	# the popups of the option menus
	var popup := KDUi.style(&"panel", Vector4(10, 8, 10, 10)) if KDUi.has(&"panel") else wood_panel()
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_color("font_color", "PopupMenu", TEXT_LIGHT)
	t.set_color("font_hover_color", "PopupMenu", Color("#FFF3D0"))

	# progress bars (the meters of the sheets set their own, this is for everything else)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(3)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)

	# separators: a thin gold rule instead of the grey line
	var rule := StyleBoxLine.new()
	rule.color = Color(GOLD, 0.35)
	rule.thickness = 1
	t.set_stylebox("separator", "HSeparator", rule)
	t.set_stylebox("separator", "VSeparator", rule)

	_project_theme = t
	return _project_theme


## The main button of a column: the painted plate with a fleur at each end (sheet 5), brighter on hover.
static func primary_button_styles(button: Button) -> void:
	button_styles(button)
	if not KDUi.has(&"plate"):
		return
	var tex := KDUi.piece(&"plate")
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var box := StyleBoxTexture.new()
		box.texture = tex
		box.texture_margin_left = 30
		box.texture_margin_right = 30
		box.texture_margin_top = 14
		box.texture_margin_bottom = 14
		box.content_margin_left = 40    # clear of the fleur at each end
		box.content_margin_right = 40
		box.content_margin_top = 8
		box.content_margin_bottom = 8
		match state:
			"hover":
				box.modulate_color = Color(1.18, 1.12, 1.0)
			"pressed", "hover_pressed":
				box.modulate_color = Color(0.82, 0.78, 0.72)
		button.add_theme_stylebox_override(state, box)
	button.add_theme_color_override("font_pressed_color", Color("#F3D98B"))


## Small drawn marks for the buttons, so no glyph of the font is needed (Phase 18).
static var _marks: Dictionary = {}


## A right-pointing chevron: «this opens something».
static func chevron_texture() -> Texture2D:
	if not _marks.has("chevron"):
		var img := Image.create(10, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in 16:
			var x := 7 - absi(y - 8) * 7 / 8
			for w in 3:
				if x - w >= 0:
					img.set_pixel(x - w, y, Color.WHITE)
		_marks["chevron"] = ImageTexture.create_from_image(img)
	return _marks["chevron"]


## The same chevron pointing down: «this is open, click to fold it».
static func chevron_down_texture() -> Texture2D:
	if not _marks.has("chevron_down"):
		var img := (chevron_texture() as ImageTexture).get_image()
		img.rotate_90(CLOCKWISE)
		_marks["chevron_down"] = ImageTexture.create_from_image(img)
	return _marks["chevron_down"]


## Three bars: the menu of the game.
static func menu_texture() -> Texture2D:
	if not _marks.has("menu"):
		var img := Image.create(16, 14, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y0: int in [1, 6, 11]:
			img.fill_rect(Rect2i(0, y0, 16, 2), Color.WHITE)
		_marks["menu"] = ImageTexture.create_from_image(img)
	return _marks["menu"]


## A thin vertical gold rule between two slots of a bar.
static func slot_rule(height: float) -> Control:
	var r := ColorRect.new()
	r.color = Color(GOLD, 0.35)
	r.custom_minimum_size = Vector2(1, height)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Hangs the dress on the root of the tree, so every window of the game wears it.
static func dress(node: Node) -> void:
	var root := node.get_tree().root if node.is_inside_tree() else null
	if root and root.theme != project_theme():
		root.theme = project_theme()


## The ornamental rule with the fleur in the middle (sheet 3), at its own size, centred: under a title, between
## what belongs together and what does not. A thin gold line when the kit is missing.
static func ornate_rule() -> Control:
	if KDUi.has(&"rule_ornate"):
		var tex := load(KDUi.DIR.path_join(String(KDUi.kit()["rule_ornate"]["file"]))) as Texture2D
		var r := TextureRect.new()
		r.texture = tex
		r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		r.custom_minimum_size = Vector2(0, tex.get_height()) if tex else Vector2(0, 8)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	var line := HSeparator.new()
	return line

