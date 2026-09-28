class_name NavBlock
extends PanelContainer
## A block of buttons that open the sheets of the realm: a column on the left (what you govern) or a bar at
## the bottom (the great sections). It knows nothing of what the sheets do — it only asks the PanelHost.
##
## Phase 18 (HUD layout): the column is a few big framed plates with an icon and a chevron, the first one the
## most visible; the bar is wide, with large icons, and spans the foot of the screen.

var _host: PanelHost
var _buttons: Dictionary = {}   # page id -> Button
var _actions: Dictionary = {}   # ids of the buttons that are actions, not sheets
var _box: BoxContainer
var _head: Label
var _vertical := true


## `entries` = [[page id, label, icon, key, action?], …]; `vertical` picks a column or a bar. An entry with an
## action (a Callable) is not a sheet: the button calls it (Costruzioni opens the build list this way).
func setup(host: PanelHost, entries: Array, vertical: bool, title: String = "") -> void:
	_host = host
	_vertical = vertical
	# the column is made of its plates, with nothing around them; the bar has its band of dark wood
	add_theme_stylebox_override("panel", StyleBoxEmpty.new() if vertical else KDTheme.dark_panel())
	mouse_filter = Control.MOUSE_FILTER_IGNORE if vertical else Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	if title != "":
		_head = SettlementHud._label(col, 14, KDTheme.GOLD, true)
		_head.text = title
		_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box = VBoxContainer.new() if vertical else HBoxContainer.new()
	_box.add_theme_constant_override("separation", 6 if vertical else 8)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not vertical:
		(_box as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
		_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_box)
	for i in entries.size():
		var entry: Array = entries[i]
		var page: StringName = entry[0]
		var primary := vertical and i == 0
		var btn := _make_button(entry, primary)
		if entry.size() > 4 and entry[4] is Callable:
			btn.pressed.connect(entry[4] as Callable)
			_actions[page] = true
		else:
			btn.pressed.connect(func() -> void: _host.toggle(page))
		_box.add_child(btn)
		_buttons[page] = btn
	if _host:
		_host.page_changed.connect(_sync)


func _make_button(entry: Array, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = String(entry[1])
	btn.focus_mode = Control.FOCUS_NONE
	if primary:
		KDTheme.primary_button_styles(btn)   # the plate with the fleurs: the first thing the eye finds
	else:
		KDTheme.button_styles(btn)
	var icon_px := 46 if not _vertical else (46 if primary else 28)
	if _vertical:
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(290, 74 if primary else 46)
		btn.add_theme_font_size_override("font_size", 20 if primary else 17)
		btn.add_theme_font_override("font", KDFonts.serif_bold())
		if primary:
			btn.add_theme_color_override("font_color", Color("#F3D98B"))
		else:
			# the chevron that says «this opens something», drawn, not a glyph of the font (the main plate
			# has its fleurs instead)
			var chevron := TextureRect.new()
			chevron.texture = KDTheme.chevron_texture()
			chevron.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chevron.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
			chevron.offset_left = -26
			chevron.offset_right = -12
			chevron.offset_top = -8
			chevron.offset_bottom = 8
			chevron.modulate = Color(KDTheme.GOLD, 0.9)
			btn.add_child(chevron)
	else:
		# the great sections fill the bar: no empty brown band on the sides
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.custom_minimum_size = Vector2(200, 64)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_font_override("font", KDFonts.serif_bold())
	if entry.size() > 2 and String(entry[2]) != "":
		btn.icon = KDUi.icon(StringName(entry[2]))
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", icon_px)
		btn.add_theme_constant_override("h_separation", 12)
	if entry.size() > 3 and int(entry[3]) > 0:
		btn.tooltip_text = "%s  (%s)" % [entry[1], char(int(entry[3]))]
	return btn


func _sync(page_id: StringName) -> void:
	for id: StringName in _buttons.keys():
		if _actions.has(id):
			continue   # a button that is not a sheet keeps its own state (set_active)
		var primary: bool = _vertical and _box.get_child(0) == _buttons[id]
		(_buttons[id] as Button).add_theme_color_override("font_color",
			KDTheme.GOLD if id == page_id else (Color("#F3D98B") if primary else KDTheme.TEXT_LIGHT))


## Lights a button that is not a sheet (the build list open).
func set_active(id: StringName, on: bool) -> void:
	var btn: Button = _buttons.get(id)
	if btn:
		btn.add_theme_color_override("font_color", KDTheme.GOLD if on else KDTheme.TEXT_LIGHT)


## Adds something that is not a sheet under the buttons.
func add_extra(control: Control) -> void:
	_box.get_parent().add_child(control)


## Renames a button (and changes its icon): the same page reads differently before and after the crown —
## "La mia comunità" becomes "Il mio regno", "Consuetudini" becomes "Governo".
func set_entry(page: StringName, text: String, icon: StringName = &"") -> void:
	var btn: Button = _buttons.get(page)
	if btn == null:
		return
	btn.text = text
	if icon != &"" and KDUi.icon(icon):
		btn.icon = KDUi.icon(icon)


## Shows or hides a button: the Corte exists only once somebody reigns (consolidation — before the crown that
## button was "Famiglie"; the families now live in the Ceti sheet).
func set_entry_visible(page: StringName, on: bool) -> void:
	var btn: Button = _buttons.get(page)
	if btn:
		btn.visible = on


## The tooltip of one button (the bar writes the points of knowledge on Ricerca, for instance).
func set_tip(page: StringName, text: String) -> void:
	var btn: Button = _buttons.get(page)
	if btn:
		btn.tooltip_text = text


func set_title(text: String) -> void:
	if _head:
		_head.text = text

