class_name ChroniclePanel
extends PanelContainer
## The chronicle of the realm: what has happened, in order, with the date. Everything the systems write down
## (reigns, laws, pacts, wars, battles, sieges, conquests, events) ends up on this page.

const KIND_COLORS := {
	"war": "#E2896F", "battle": "#E2896F", "battle_won": "#E2A06F", "siege": "#E2A06F",
	"conquest": "#E2A06F", "occupation": "#E2A06F", "peace": "#BFE39A", "pact": "#BFE39A",
	"marriage": "#E9D8A6", "succession": "#E9D8A6", "reign_begins": "#E9D8A6", "ruler_died": "#C9A24A",
	"event": "#DCCFAE", "technology": "#BFD9E3", "law": "#DCCFAE",
	# the story of the community before and at the crown (Phase 15): the great moments in gold
	"founding_arrival": "#EFC96F", "founding_family": "#E9D8A6", "founding_child": "#E9D8A6", "founding_first_house": "#DCCFAE",
	"founding_harvest": "#DCCFAE", "founding_village": "#E9D8A6", "founding_royal_house": "#EFC96F", "founding_crown": "#EFC96F",
	"founding_realm": "#EFC96F", "founding_extinct": "#C9A24A", "founding_seat": "#EFC96F",
	# Phase 16-17: great works, lands, crises, revolts, spirits
	"first_building": "#DCCFAE", "growth": "#E9D8A6", "claim": "#BFE39A", "crisis": "#E2A06F", "revolt": "#E2896F",
	"revolt_over": "#BFE39A", "spirit_gained": "#BFD9E3", "spirit_evolved": "#BFD9E3", "spirit_lost": "#C9A24A",
	"assimilation": "#BFD9E3", "conversion": "#BFD9E3", "succession_crisis": "#E2896F",
}

var _lines: VBoxContainer
var _filter_mine := true
var _count := -1


func _ready() -> void:
	add_theme_stylebox_override("panel", KDTheme.wood_panel())
	custom_minimum_size = Vector2(560, 0)
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	# the name of the sheet lives in the painted band now: keep the first row clear of the inner frame line
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)   # the filter button stands on this row: it needs more room
	col.add_child(gap)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	head.alignment = BoxContainer.ALIGNMENT_END   # the name is in the band of the frame (PanelHost)
	var mine := Button.new()
	mine.text = "Solo il mio regno"
	mine.toggle_mode = true
	mine.button_pressed = true
	mine.focus_mode = Control.FOCUS_NONE
	KDTheme.button_styles(mine)
	mine.toggled.connect(func(on: bool) -> void:
		_filter_mine = on
		_count = -1
		refresh())
	head.add_child(mine)
	# closing is the PanelHost's business
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 3)
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_lines)


func toggle() -> void:
	visible = not visible
	if visible:
		_count = -1
		refresh()


func _process(_delta: float) -> void:
	if visible and Session.has_game() and Session.current.world.chronicle.size() != _count:
		refresh()


func refresh() -> void:
	if not Session.has_game():
		return
	var session := Session.current
	var world := session.world
	_count = world.chronicle.size()
	for c in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	var me := world.player()
	var shown := 0
	for i in range(world.chronicle.size() - 1, -1, -1):
		var entry: Dictionary = world.chronicle[i]
		if _filter_mine and me and int(entry.get("kingdom", -1)) != me.id and int(entry.get("kingdom", -1)) >= 0 \
				and int(entry.get("other", -1)) != me.id:
			continue   # "mine": the player's deeds and what the others did to him
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_lines.add_child(row)
		var date := SettlementHud._label(row, 13, Color(KDTheme.TEXT_LIGHT, 0.6), false)
		date.text = session.calendar.format_date(int(entry.get("day", 0)))
		date.custom_minimum_size = Vector2(150, 0)
		var text := SettlementHud._label(row, 14, Color.html(String(KIND_COLORS.get(String(entry.get("kind", "")), "#DCCFAE"))), false)
		text.text = String(entry.get("text", ""))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(370, 0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shown += 1
		if shown >= 120:
			break
	if shown == 0:
		var none := SettlementHud._label(_lines, 14, Color(KDTheme.TEXT_LIGHT, 0.8), false)
		none.text = "La cronaca è ancora bianca."

