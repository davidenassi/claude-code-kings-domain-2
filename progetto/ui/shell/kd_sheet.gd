class_name KDSheet
extends PanelContainer
## The common frame of every sheet of the realm: wood and gold, one scrolling column, one width.
## Pages fill `column`; the tabs and the closing are the PanelHost's business, not theirs.

const WIDTH := 520
const HEIGHT := 620
const MIN_HEIGHT := 140

var column: VBoxContainer
var _scroll: ScrollContainer
var _refresh_timer := 0.0
## Seconds between two automatic refreshes while the page is open (0 = only when asked).
var refresh_every := 1.0


func _ready() -> void:
	add_theme_stylebox_override("panel", KDTheme.wood_panel())
	custom_minimum_size = Vector2(WIDTH, 0)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(WIDTH, MIN_HEIGHT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(column)
	var gap := Control.new()   # the first row starts under the inner line of the frame, not on it
	gap.custom_minimum_size = Vector2(0, 22)
	column.add_child(gap)
	build()
	refresh()
	_fit()
	call_deferred("_fit")   # the containers measure what was just added only at the end of the frame


## A short sheet is short: the frame follows what is written on it, up to the height of the screen.
func _fit() -> void:
	if _scroll == null or column == null:
		return
	_scroll.custom_minimum_size.y = clampf(column.get_combined_minimum_size().y, MIN_HEIGHT, HEIGHT)


## Pages build their contents here.
func build() -> void:
	pass


func refresh() -> void:
	pass


func _process(delta: float) -> void:
	if not visible or refresh_every <= 0.0:
		return
	_refresh_timer += delta
	if _refresh_timer >= refresh_every:
		_refresh_timer = 0.0
		refresh()
		_fit()
		call_deferred("_fit")


# --- small helpers every page uses ------------------------------------------------------------------

## A section title in gold, on the painted section bar (sheet 3) when the kit has it: the fleur on the left,
## the name after it. It used to be a bare line of gold text, which is what made the sheets look like forms.
func section(text: String) -> Label:
	return section_in(column, text)


## The same painted section bar in any container (the sheets that are not KDSheets use it too, Phase 18).
static func section_in(parent: Control, text: String) -> Label:
	if not KDUi.has(&"section_bar"):
		var plain := SettlementHud._label(parent, 16, KDTheme.GOLD, true)
		plain.text = text
		return plain
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", KDUi.style(&"section_bar", Vector4(50, 7, 18, 7)))
	parent.add_child(bar)
	var l := SettlementHud._label(bar, 16, KDTheme.GOLD, true)
	l.text = text
	return l


## An empty box under the current section, where rows are rebuilt.
func box(separation: int = 4) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	column.add_child(b)
	return b


static func clear(parent: Control) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


## A line of parchment for the prose.
func parchment(min_height: int = 0) -> Label:
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", KDTheme.parchment_panel())
	column.add_child(sheet)
	var l := Label.new()
	l.add_theme_font_override("font", KDFonts.serif())
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", KDTheme.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 60, min_height)
	sheet.add_child(l)
	return l


## A named row with a bar and a number: measures, favour, anything from 0 to a maximum.
static func meter(parent: Control, label_text: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var name_label := SettlementHud._label(row, 13, KDTheme.TEXT_LIGHT, false)
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(130, 0)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(200, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = KDTheme.GOLD
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var value_label := SettlementHud._label(row, 13, KDTheme.TEXT_LIGHT, true)
	value_label.custom_minimum_size = Vector2(40, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return [value_label, bar, name_label]


static func set_meter(row: Array, value: float, maximum: float = 100.0) -> void:
	var bar := row[1] as ProgressBar
	bar.max_value = maximum
	bar.value = clampf(value, 0.0, maximum)
	var share := value / maxf(maximum, 0.001)
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = Color("#B4553F").lerp(Color("#C9A24A"), clampf(share * 1.6, 0.0, 1.0)).lerp(
		Color("#8FB86A"), clampf((share - 0.6) * 2.0, 0.0, 1.0))
	(row[0] as Label).text = "%d" % roundi(value)


## A row "name .... value", the bread and butter of every sheet.
static func line(parent: Control, name_text: String, value_text: String, tip: String = "",
		value_color: Color = KDTheme.TEXT_LIGHT) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var name_label := SettlementHud._label(row, 15, Color(KDTheme.TEXT_LIGHT, 0.92), false)
	name_label.text = name_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var value_label := SettlementHud._label(row, 15, value_color, true)
	value_label.text = value_text
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if tip != "":
		row.tooltip_text = tip
		name_label.tooltip_text = tip
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		value_label.tooltip_text = tip
		value_label.mouse_filter = Control.MOUSE_FILTER_PASS
	return [name_label, value_label]


## A condition or a goal: the painted checkbox, ticked when it is met, then the row (Phase 18: the ticks
## were the glyphs "✓" and "✗", drawn by whatever font had them).
static func check_line(parent: Control, ok: bool, name_text: String, value_text: String, tip: String = "",
		value_color: Color = KDTheme.TEXT_LIGHT) -> Array:
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	parent.add_child(holder)
	var mark := TextureRect.new()
	mark.texture = KDUi.piece(&"check_on" if ok else &"check_off")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(16, 16)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.modulate = Color(1, 1, 1, 1) if ok else Color(1, 1, 1, 0.7)
	holder.add_child(mark)
	var row := line(holder, name_text, value_text, tip, value_color)
	(row[0] as Label).get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


## A button that carries a command: disabled with the reason when the command refuses.
func command_button(parent: Control, text: String, command: Command, tip: String, danger: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	KDTheme.button_styles(btn)
	var reason := command.validate(Session.current) if Session.has_game() else "Nessuna partita."
	btn.disabled = reason != ""
	btn.tooltip_text = tip if reason == "" else "%s\n%s" % [tip, reason]
	if danger:
		btn.add_theme_color_override("font_color", Color("#E2896F"))
	btn.pressed.connect(func() -> void:
		var result := Session.current.submit(command)
		if result.success and result.data.has("accepted") and not bool(result.data["accepted"]):
			EventBus.notify("Rifiuto", String(result.data.get("reason", "")), &"diplomacy")
		elif not result.success and result.reason != "":
			EventBus.notify("Impossibile", result.reason, &"warning")
		refresh())
	parent.add_child(btn)
	return btn

