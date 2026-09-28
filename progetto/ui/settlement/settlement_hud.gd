class_name SettlementHud
extends CanvasLayer
## The frame of the whole realm (Phase 12.5). This file no longer draws anything of its own: it assembles the
## five blocks of the layout and hands each one what it needs.
##
##   A  top_bar.gd      — the band: arms, goods with their monthly change, the great measures of the crown;
##                        under its right end the clock (date, speed, map, menu)
##   B  nav_block.gd    — the left column: four big plates (Il mio regno, Corte, Governo, Costruzioni)
##   C  news_panel.gd + build_column.gd — the right column: the news with the way to the chronicle, then
##                        the building panel (only when Costruzioni is open), then the inspectors
##   D  nav_block.gd    — the bar at the foot: Esercito, Ceti, Ricerca, Economia, Diplomazia, Religione
##   E                  — the event card in the middle, the placement hint; bottom left the guide and the map
##
## The centre of the screen belongs to the map: the sheets open centre-left, beside the left column.
## Phase 18 HUD review: the layout follows the reference drawing given by the player (positions, room, weight).

## The game shell (scenes/main.gd): the two maps, and the way from one to the other (Rebirth, Phase 1).
@export var shell_path: NodePath

const TOP_MARGIN := 76     ## under the band of block A (the clock hangs under its right end only)
const BOTTOM_MARGIN := 98  ## over block D

## Block B: what the crown governs, few and big; the first is the main one. "build" is not a sheet: it opens the
## building panel on the right. [page, label as a kingdom, icon, key, label as a community, icon as a community]
const LEFT_ENTRIES: Array = [
	[&"realm", "Il mio regno", &"crown", KEY_R, "La mia comunità", &"village"],
	[&"court", "Corte", &"lily", KEY_Q, "Corte", &"lily"],   # hidden until somebody reigns
	[&"government", "Governo", &"law", KEY_G, "Consuetudini", &"law"],
	[&"build", "Costruzioni", &"build", KEY_B, "Costruzioni", &"build"],
]
## Block D: the great sections of the realm. Every sheet is in one place only: the chronicle opens from the
## news ("Vedi tutto", C), the inhabitants from Il mio regno (P), the families from Ceti (T).
const BOTTOM_ENTRIES: Array = [
	[&"army", "Esercito", &"war", KEY_E],
	[&"estates", "Ceti", &"house_arms", KEY_T],
	[&"knowledge", "Ricerca", &"book", KEY_K],
	[&"economy", "Economia", &"treasury", KEY_F],
	[&"diplomacy", "Diplomazia", &"diplomacy", KEY_L],   # D and A move the camera
	[&"religion", "Religione", &"clergy", KEY_V],
]

var _shell: Node
## The map of the valley: building, its clicks, its camera.
var _build: BuildController
var _local: LocalInteraction
var _camera: WorldCamera
## The map of the world: provinces and hosts, map modes.
var _interaction: MapInteraction
var _controller: MapModeController
var _top: TopBar
var _left: NavBlock
var _bottom: NavBlock
var _column: BuildColumn
var _host: PanelHost
var _notifications: NotificationStack
var _news: NewsPanel
var _event_card: EventCard
var _hint: Label
var _inspector: PanelContainer
var _insp_title: Label
var _insp_body: Label
var _insp_workers: HBoxContainer
var _insp_cancel: Button
var _province: ProvinceInspector
var _building_id := -1
var _minimap: Minimap
var _modes_menu: MapModeMenu
## The map on the table (MapSpace.LOCAL or GLOBAL).
var view: StringName = MapSpace.LOCAL
var _guide: GuidePanel
var _pause: PauseMenu
var _coronation: CoronationCard
var _crown_state := -1   # -1 unknown, 0 a community, 1 a kingdom
var _end_shown := false   # the end of the community is told once per session
const INTRO_SEEN := &"intro_seen"
var _refresh_timer := 0.0
var _dirty := false


func _ready() -> void:
	layer = 11
	KDTheme.dress(self)
	_shell = get_node_or_null(shell_path)
	# the two maps are the shell's children before this one: they are ready, the shell itself is not yet
	var lv := _shell.get_node_or_null("LocalView") as LocalView if _shell else null
	var gv := _shell.get_node_or_null("GlobalView") as GlobalView if _shell else null
	if lv:
		_build = lv.build
		_local = lv.interaction
		_camera = lv.camera
	if gv:
		_interaction = gv.interaction
		_controller = gv.modes
	_make_host()          # the sheets exist first: the columns only point at them
	_make_top()
	_make_left_column()
	_make_build_column()
	_make_bottom_bar()
	_make_inspector()
	_make_province_inspector()
	_make_event_card()
	_make_hint()
	_make_minimap()
	_make_guide()
	_make_coronation_card()
	_make_pause_menu()
	if String(BootArgs.parse().get("panel", "")) == "build":
		_column.call_deferred("set_open", true)   # screenshots of the build list
	# the clock's own buttons: the other map (valley / world) and the menu of the game
	_top.map_requested.connect(func() -> void:
		if _shell:
			_shell.toggle_map())
	_top.menu_requested.connect(func() -> void:
		if _pause:
			_pause.open())
	if _build:
		_build.hint_changed.connect(_on_hint)
	if _local:
		_local.building_selected.connect(show_building)
	if _camera:
		# the valley is the whole of the local map: asking for more distance says where the world is
		_camera.zoom_out_blocked.connect(_on_zoom_out_blocked)
	# a settlement changes many times inside one simulated day (every building that works says so): the HUD
	# takes note and refreshes once, on the next frame — refreshing on each signal cost a town of three hundred
	# souls a fifth of a second every day of the game (found by the world art pass benchmark)
	EventBus.settlement_changed.connect(func(_id: int) -> void: _dirty = true)
	EventBus.building_state_changed.connect(func(id: int) -> void:
		if id == _building_id:
			_refresh_inspector())
	EventBus.day_passed.connect(func(_d: int) -> void: _dirty = true)
	refresh()
	_sync_crown()   # the right words from the first frame, not half a second later
	# what had to be said across a rebuild of the scene (a quick load): said now that the news can show it
	for notice: Array in Session.pending_notices:
		EventBus.notify.call_deferred(String(notice[0]), String(notice[1]), StringName(notice[2]))
	Session.pending_notices.clear()


func settlement() -> SettlementState:
	return _build.player_settlement() if _build else player_settlement()


## The map on the table changed (called by the shell): what the HUD offers follows it. On the map of the world
## there is nothing to build and no building to inspect; on the map of the valley there are no provinces to
## pick and no map modes.
func set_view(space: StringName, camera: WorldCamera) -> void:
	view = space
	var local := MapSpace.is_local(space)
	if _minimap:
		_minimap.set_map(space, camera)
	if _modes_menu:
		_modes_menu.visible = not local
	if not local:
		if _build and _build.active():
			_build.stop()
		if _column and _column.is_open():
			_column.set_open(false)
		show_building(-1)
	elif _province and _province.visible and _interaction:
		_interaction.select(-1)
	_hint.visible = false


var _edge_hint: Label = null
var _edge_hint_left := 0.0


## Shown when the wheel asks the valley for more than the valley: the world is another map, not a farther zoom.
func _on_zoom_out_blocked() -> void:
	if _edge_hint == null:
		var anchor := _anchor(Control.PRESET_CENTER_BOTTOM, Vector4(0, 0, 0, BOTTOM_MARGIN + 18))
		_edge_hint = _label(anchor, 17, KDTheme.GOLD, true)
		_edge_hint.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
		_edge_hint.add_theme_constant_override("outline_size", 6)
		_edge_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_edge_hint.text = "Questa è tutta la valle. Oltre le nebbie: la mappa del mondo (Tab)"
	_edge_hint.visible = true
	_edge_hint.modulate.a = 1.0
	_edge_hint_left = 2.8


## Costruzioni: building is done in the valley — from the map of the world the button takes the player there.
func _toggle_build() -> void:
	if not MapSpace.is_local(view) and _shell:
		_shell.show_local()
		_column.set_open(true)
		return
	_column.toggle()


## The settlement of the crown, for everything that has no BuildController at hand.
static func player_settlement() -> SettlementState:
	if not Session.has_game():
		return null
	var world := Session.current.world
	var k := world.player()
	if k == null:
		return null
	for s in world.settlements:
		if s.kingdom == k.id:
			return s
	return null


static func _label(parent: Control, size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", KDFonts.serif_bold() if bold else KDFonts.serif())
	# nothing smaller than 14: the layout is drawn at 1080p and scaled to the window, and 12 became 10
	l.add_theme_font_size_override("font_size", maxi(size, 14))
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


## A corner of the screen that does not eat the clicks meant for the map.
func _anchor(preset: int, margins: Vector4) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(preset)
	if preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT]:
		m.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if preset in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER]:
		m.grow_horizontal = Control.GROW_DIRECTION_BOTH
	if preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM, Control.PRESET_BOTTOM_WIDE]:
		m.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if preset == Control.PRESET_CENTER:
		m.grow_vertical = Control.GROW_DIRECTION_BOTH
	m.add_theme_constant_override("margin_left", int(margins.x))
	m.add_theme_constant_override("margin_top", int(margins.y))
	m.add_theme_constant_override("margin_right", int(margins.z))
	m.add_theme_constant_override("margin_bottom", int(margins.w))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	return m


# --- A: the top band ---------------------------------------------------------------------------------

func _make_top() -> void:
	_top = TopBar.new()
	_top.name = "TopBar"
	add_child(_top)


# --- B: the left column, what the king governs -------------------------------------------------------

func _make_left_column() -> void:
	var anchor := _anchor(Control.PRESET_TOP_LEFT, Vector4(10, TOP_MARGIN, 0, 0))
	_left = NavBlock.new()
	_left.name = "RealmColumn"
	anchor.add_child(_left)
	var entries: Array = []
	for e: Array in LEFT_ENTRIES:
		if e[0] == &"build":
			entries.append([e[0], e[1], e[2], e[3], func() -> void: _toggle_build()])
		else:
			entries.append([e[0], e[1], e[2], e[3]])
	_left.setup(_host, entries, true)


# --- C: the right column, what is built --------------------------------------------------------------

## One column under the clock: the news, then the building panel, then the inspectors — stacked, so nothing on
## the right ever covers anything else (they used to be two blocks side by side that had to step aside).
func _make_build_column() -> void:
	var anchor := _anchor(Control.PRESET_TOP_RIGHT, Vector4(0, TopBar.bottom_edge() + 8.0, 10, 0))
	var right := VBoxContainer.new()
	right.name = "RightColumn"
	right.add_theme_constant_override("separation", 8)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(right)
	_news = NewsPanel.new()
	_news.name = "News"
	right.add_child(_news)
	_news.setup(func(pos: Vector2, space: StringName) -> void:
		if _shell:
			_shell.go_to(pos, space))
	_news.chronicle_requested.connect(func() -> void: _host.open(&"chronicle"))
	_notifications = _news.stack
	_column = BuildColumn.new()
	_column.name = "BuildColumn"
	right.add_child(_column)
	_column.setup(_build)
	_column.open_changed.connect(func(on: bool) -> void:
		if _left:
			_left.set_active(&"build", on))


# --- D: the bottom bar, the great sections -----------------------------------------------------------

func _make_bottom_bar() -> void:
	# a band across the whole foot of the screen, the six sections spread along it
	var anchor := _anchor(Control.PRESET_BOTTOM_WIDE, Vector4(10, 0, 10, 8))
	_bottom = NavBlock.new()
	_bottom.name = "MainBar"
	anchor.add_child(_bottom)
	_bottom.setup(_host, BOTTOM_ENTRIES, false)


# --- the sheets --------------------------------------------------------------------------------------

func _make_host() -> void:
	# centre-left, beside the column of the realm: the map stays in the middle and on the right
	var anchor := _anchor(Control.PRESET_TOP_LEFT, Vector4(308, TOP_MARGIN, 0, BOTTOM_MARGIN))
	_host = PanelHost.new()
	_host.name = "PanelHost"
	_host.compact = true   # the columns are the navigation: the bar keeps only the name and the cross
	anchor.add_child(_host)
	_host.add_page(&"realm", "Regno", RealmPanel.new(), KEY_R)
	_host.add_page(&"court", "Corte", CourtPanel.new(), KEY_Q)
	_host.add_page(&"government", "Governo", GovernmentPanel.new(), KEY_G)
	_host.add_page(&"religion", "Religione", ReligionPanel.new(), KEY_V)
	_host.add_page(&"people", "Abitanti", PeoplePanel.new(), KEY_P)
	_host.add_page(&"diplomacy", "Diplomazia", DiplomacyPanel.new(), KEY_L)
	_host.add_page(&"estates", "Ceti", EstatesPanel.new(), KEY_T)
	_host.add_page(&"economy", "Economia", EconomyPanel.new(), KEY_F)
	_host.add_page(&"knowledge", "Ricerca", KnowledgePanel.new(), KEY_K)
	var army := ArmyPanel.new()
	army.set_interaction(_interaction)
	# the orders of the hosts are given on the map of the world
	army.destination_wanted.connect(func(_id: int) -> void:
		if _shell:
			_shell.show_global())
	_host.add_page(&"army", "Esercito", army, KEY_E)
	_host.add_page(&"chronicle", "Cronaca", ChroniclePanel.new(), KEY_C)
	if _interaction:
		_interaction.army_selected.connect(func(_army_id: int) -> void: _host.open(&"army"))
	if _local:
		_local.army_selected.connect(func(_army_id: int) -> void: _host.open(&"army"))
	var wanted := String(BootArgs.parse().get("panel", ""))
	if wanted != "" and wanted != "build":
		_host.call_deferred("open", StringName(wanted))   # screenshots of one sheet


# --- E: notifications, event card, placement hint ----------------------------------------------------

func _make_event_card() -> void:
	var anchor := _anchor(Control.PRESET_CENTER, Vector4(0, 0, 0, 0))
	_event_card = EventCard.new()
	_event_card.name = "EventCard"
	anchor.add_child(_event_card)


func _make_hint() -> void:
	_hint = Label.new()
	_hint.add_theme_font_override("font", KDFonts.serif_bold())
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.visible = false
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)


func _on_hint(text: String, ok: bool, screen_pos: Vector2) -> void:
	_hint.visible = text != ""
	_hint.text = text
	_hint.add_theme_color_override("font_color", Color("#CFF2A8") if ok else Color("#FFB09A"))
	_hint.position = screen_pos + Vector2(18, 16)


# --- the contextual zone: building and province ------------------------------------------------------

func _make_inspector() -> void:
	_inspector = PanelContainer.new()
	_inspector.add_theme_stylebox_override("panel", KDTheme.card_panel())
	_inspector.visible = false
	_column.context.add_child(_inspector)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_inspector.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_insp_title = _label(head, 19, KDTheme.GOLD, true)
	_insp_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_insp_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var close := KDTheme.close_button()
	close.tooltip_text = "Chiudi"
	close.pressed.connect(func() -> void:
		if _local:
			_local.select_building(-1)
		else:
			show_building(-1))
	head.add_child(close)
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", KDTheme.parchment_panel())
	col.add_child(sheet)
	_insp_body = Label.new()
	_insp_body.add_theme_font_override("font", KDFonts.serif())
	_insp_body.add_theme_font_size_override("font_size", 13)
	_insp_body.add_theme_color_override("font_color", KDTheme.INK)
	_insp_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_insp_body.custom_minimum_size = Vector2(226, 0)
	sheet.add_child(_insp_body)
	_insp_workers = HBoxContainer.new()
	_insp_workers.add_theme_constant_override("separation", 6)
	col.add_child(_insp_workers)
	_insp_cancel = Button.new()
	_insp_cancel.text = "Annulla cantiere"
	_insp_cancel.focus_mode = Control.FOCUS_NONE
	KDTheme.button_styles(_insp_cancel, "red")
	_insp_cancel.pressed.connect(func() -> void:
		var res := Session.current.submit(CancelSiteCommand.create(_building_id))
		if not res.success:
			EventBus.notify("Impossibile", res.reason, &"warning"))
	col.add_child(_insp_cancel)


func _make_province_inspector() -> void:
	_province = ProvinceInspector.new()
	_province.name = "ProvinceInspector"
	_province.visible = false
	_column.context.add_child(_province)
	if _interaction:
		_interaction.province_selected.connect(_province.show_province)
		_province.closed.connect(func() -> void: _interaction.select(-1))


func show_building(building_id: int) -> void:
	_building_id = building_id
	_inspector.visible = building_id >= 0 and Session.has_game() and Session.current.world.building(building_id) != null
	_column.call_deferred("_fit")   # the list gives room to the inspector under it
	_refresh_inspector()


func _refresh_inspector() -> void:
	if not _inspector.visible or not Session.has_game():
		return
	var world := Session.current.world
	var b := world.building(_building_id)
	if b == null:
		_inspector.visible = false
		return
	var def := b.def()
	_insp_title.text = def.display_name
	var lines := PackedStringArray()
	if not b.is_active():
		lines.append("Cantiere: %d%%" % roundi(b.progress() * 100.0))
		var mats := PackedStringArray()
		for res: StringName in def.cost.keys():
			mats.append("%s %d/%d" % [Defs.resource(res).display_name.to_lower(), int(b.delivered.get(res, 0)), int(def.cost[res])])
		if not mats.is_empty():
			lines.append("Materiali: " + ", ".join(mats))
		var trees := 0
		for t in b.trees_on_ground(SettlementSim.ground(world)):
			if not world.terrain.is_felled(t["key"]):
				trees += 1
		if trees > 0:
			lines.append("Alberi ancora da abbattere: %d" % trees)
		var builders := world.people_of(b.settlement).filter(func(p: PersonState) -> bool: return p.job == &"builder" and p.workplace == b.id)
		lines.append("Costruttori al lavoro: %d" % builders.size())
	else:
		lines.append(def.description)
		if def.beds > 0:
			var sleepers := world.people_of(b.settlement).filter(func(p: PersonState) -> bool: return p.home == b.id)
			lines.append("Letti: %d/%d" % [sleepers.size(), def.beds])
		match def.work_type():
			&"farm":
				lines.append("Grano nei campi: %d" % int(b.crop))
			&"fell_trees":
				lines.append("Raggio di taglio: %d m" % int(def.work.get("radius_m", 0)))
				var standing := 0
				var rad := float(def.work.get("radius_m", 110.0))
				for t in LocalFeatures.trees_in_rect(SettlementSim.ground(world), Rect2(b.pos - Vector2(rad, rad), Vector2(rad, rad) * 2.0), false):
					if not world.terrain.is_felled(t["key"]) and t["pos"].distance_to(b.pos) <= rad:
						standing += 1
				lines.append("Alberi ancora in piedi nel raggio: %d" % standing)
			&"quarry_rock":
				var rocks := 0
				var r := float(def.work.get("radius_m", 90.0))
				for rock in LocalFeatures.outcrops_in_rect(SettlementSim.ground(world), Rect2(b.pos - Vector2(r, r), Vector2(r, r) * 2.0)):
					if world.terrain.rock_charges_left(rock) > 0 and rock["pos"].distance_to(b.pos) <= r:
						rocks += 1
				lines.append("Rocce lavorabili vicine: %d" % rocks)
	if def.workers > 0 and b.is_active():
		var names := PackedStringArray()
		for p in world.people_of(b.settlement):
			if p.workplace == b.id and p.job == def.job:
				names.append(p.name)
		lines.append("Lavoratori: %s" % (", ".join(names) if not names.is_empty() else "nessuno"))
	if b.def_id == Nucleus.HEARTH:
		# the historic point of the community (Rebirth, Phase 3): who lit it, and who sits there now
		var founders := PackedStringArray()
		for f: FamilyState in world.families.values():
			if f.founding and f.settlement == b.settlement:
				for pid: int in f.founders:
					var p := world.person(pid)
					if p:
						founders.append(SettlementSetup.full_name(world, p))
		if not founders.is_empty():
			lines.append("Lo accesero: %s." % ", ".join(founders))
		var around := world.people_of(b.settlement).filter(func(p: PersonState) -> bool:
			return (p.action == &"sit" or p.action == &"warm") and p.seg_to.distance_to(b.pos) < 8.0)
		if not around.is_empty():
			lines.append("Attorno al fuoco ora: %d." % around.size())
	_insp_body.text = "\n".join(lines)
	for c in _insp_workers.get_children():
		_insp_workers.remove_child(c)
		c.queue_free()
	_insp_workers.visible = def.workers > 0 and b.is_active()
	if _insp_workers.visible:
		var l := _label(_insp_workers, 14, KDTheme.TEXT_LIGHT, false)
		l.text = "Posti: %d/%d" % [b.workers_wanted, def.workers]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for delta: int in [-1, 1]:
			var btn := Button.new()
			btn.text = "-" if delta < 0 else "+"
			btn.focus_mode = Control.FOCUS_NONE
			btn.custom_minimum_size = Vector2(34, 0)
			KDTheme.button_styles(btn)
			btn.pressed.connect(func() -> void:
				Session.current.submit(SetWorkersCommand.create(b.id, b.workers_wanted + delta))
				_refresh_inspector())
			_insp_workers.add_child(btn)
	_insp_cancel.visible = not b.is_active()


# --- keeping it true ---------------------------------------------------------------------------------

func refresh() -> void:
	if _top:
		_top.refresh()
	if _bottom and Session.has_game() and Session.current.world.player():
		# the points of knowledge left the top band: they are written on Ricerca
		_bottom.set_tip(&"knowledge", "Ricerca (K) — %d punti di sapere" % roundi(Session.current.world.player().research))
	if _column:
		_column.refresh()
	if _inspector and _inspector.visible:
		_refresh_inspector()


func _process(delta: float) -> void:
	if _dirty:
		_dirty = false
		refresh()
	if _edge_hint and _edge_hint.visible:
		_edge_hint_left -= delta
		_edge_hint.modulate.a = clampf(_edge_hint_left / 0.6, 0.0, 1.0)
		_edge_hint.visible = _edge_hint_left > 0.0
	if _crown_state < 0:
		_sync_crown()   # until the game exists the state is unknown: learn it on the first frame, not after half a second
	_refresh_timer += delta
	if _refresh_timer > 0.5:
		_refresh_timer = 0.0
		_sync_crown()
		if _inspector and _inspector.visible:
			_refresh_inspector()


# --- before and after the crown (Phase 15) ------------------------------------------------------------------

func _make_coronation_card() -> void:
	_coronation = CoronationCard.new()
	_coronation.name = "CoronationCard"
	add_child(_coronation)


## The same interface reads as a community or as a kingdom. When the player crowns the first sovereign during
## this session, the moment is shown on its own card.
func _sync_crown() -> void:
	if not Session.has_game() or _left == null:
		return
	var k := Session.current.world.player()
	if k == null:
		return
	if k.records.has(FamilySystem.EXTINCT) and not _end_shown and _coronation:
		_end_shown = true
		_coronation.show_end(k)
	# a new game opens on the six founders, once: the record keeps it from coming back after a load
	if not k.monarchy_founded and not k.records.has(INTRO_SEEN) and Session.current.world.day == 0 and _coronation \
			and not BootArgs.parse().has("no-events"):
		k.records[INTRO_SEEN] = 1.0
		_coronation.show_start(k)
	var state := 1 if k.monarchy_founded else 0
	if state == _crown_state:
		return
	var was := _crown_state
	_crown_state = state
	# the same column reads as a community or as a kingdom: "Comunità" becomes "Regno", "Consuetudini" "Governo",
	# and the Corte appears (consolidation: before the crown it was the Famiglie sheet, now in Ceti)
	for e: Array in LEFT_ENTRIES:
		var label := String(e[1]) if k.monarchy_founded else String(e[4])
		_left.set_entry(e[0], label, e[2] if k.monarchy_founded else e[5])
		if e[0] != &"build":
			_host.set_title(e[0], "Regno" if e[0] == &"realm" and k.monarchy_founded
				else ("Comunità" if e[0] == &"realm" else label))
	_left.set_entry_visible(&"court", k.monarchy_founded)
	_host.set_title(&"religion", "Religione" if k.monarchy_founded else "Fede")
	if k.monarchy_founded and was == 0 and _coronation:
		_coronation.show_for(k)




func _make_minimap() -> void:
	# bottom left, over the map and under nothing: the corner the eye goes to when it wants the whole realm
	var anchor := _anchor(Control.PRESET_BOTTOM_LEFT, Vector4(10, 0, 0, BOTTOM_MARGIN + 6))
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	anchor.add_child(_minimap)
	_minimap.setup(_camera, _controller)
	_minimap.switch_requested.connect(func() -> void:
		if _shell:
			_shell.toggle_map())
	# the maps of the realm live with the map of the world (they closed the left column before the HUD review)
	_modes_menu = MapModeMenu.new()
	_modes_menu.name = "MapModes"
	_minimap.add_to_head(_modes_menu)
	_modes_menu.setup(_controller)




func _make_guide() -> void:
	# over the minimap, on the side where the eye already goes for what the crown must do next
	var anchor := _anchor(Control.PRESET_BOTTOM_LEFT, Vector4(10, 0, 0, BOTTOM_MARGIN + 262))
	_guide = GuidePanel.new()
	_guide.name = "Guide"
	anchor.add_child(_guide)
	if _host:
		# a sheet of the realm opens over the same corner: the note waits under it
		_host.page_changed.connect(func(page_id: StringName) -> void:
			_guide.covered = page_id != &""
			_guide.refresh())
		_guide.covered = _host.is_open()
		_guide.refresh()




func _make_pause_menu() -> void:
	_pause = PauseMenu.new()
	_pause.name = "PauseMenu"
	add_child(_pause)
	if BootArgs.parse().has("pause"):
		_pause.call_deferred("open")   # for the screenshots of the menu in game


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or _host == null:
		return
	if k.physical_keycode == KEY_ESCAPE and _pause and _pause.visible:
		_pause.close()
		get_viewport().set_input_as_handled()
		return
	if k.physical_keycode == KEY_B and _column:
		_toggle_build()
		get_viewport().set_input_as_handled()
		return
	# Esc first lets go of the building in hand, then closes the list, then the sheet, then opens the pause
	if k.physical_keycode == KEY_ESCAPE and _build and _build.active():
		_build.stop()
		get_viewport().set_input_as_handled()
		return
	if k.physical_keycode == KEY_ESCAPE and _column and _column.is_open():
		_column.set_open(false)
		get_viewport().set_input_as_handled()
		return
	if _host.handle_key(k.physical_keycode):
		get_viewport().set_input_as_handled()
		return
	if k.physical_keycode == KEY_ESCAPE and _pause:
		# no sheet in the way: ESC is the crown putting the quill down
		_pause.open()
		get_viewport().set_input_as_handled()

