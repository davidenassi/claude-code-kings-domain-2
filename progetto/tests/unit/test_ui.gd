extends KDTestCase
## Phase 12: the interface. Every system of the game has its own sheet, every sheet builds and refreshes on a
## real game without a single error, and the numbers it shows are the numbers of the world.


func _session() -> GameSession:
	var s := Session.start_new({"campaign_seed": 1501})
	SettlementPlanner.place_starter_village(s, s.world.settlements[0].id)
	crown_player(s)   # the sheets of the realm are tested on a realm; the community has its own tests (test_founders)
	s.world.player().treasury = 640.0
	s.advance_days(40)
	return s


## Builds a panel inside the tree (so _ready runs) and gives it back ready to be asked questions.
func _open(panel: Control) -> Control:
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(panel)
	panel.visible = true
	if panel.has_method("refresh"):
		panel.call("refresh")
	return panel


func _drop(panel: Control) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.remove_child(panel)
	panel.free()   # a test cleans up at once: nothing of its own is left running


func after_each() -> void:
	Session.end()


func test_every_system_of_the_game_has_its_sheet() -> void:
	_session()
	var host := _open(PanelHost.new()) as PanelHost
	var pages: Array[StringName] = [&"realm", &"court", &"government", &"economy", &"knowledge",
		&"diplomacy", &"army", &"chronicle"]
	host.add_page(&"realm", "Regno", RealmPanel.new(), KEY_R)
	host.add_page(&"court", "Corte", CourtPanel.new(), KEY_Q)
	host.add_page(&"government", "Governo", GovernmentPanel.new(), KEY_G)
	host.add_page(&"economy", "Economia", EconomyPanel.new(), KEY_F)
	host.add_page(&"knowledge", "Sapere", KnowledgePanel.new(), KEY_K)
	host.add_page(&"diplomacy", "Diplomazia", DiplomacyPanel.new(), KEY_D)
	host.add_page(&"army", "Esercito", ArmyPanel.new(), KEY_E)
	host.add_page(&"chronicle", "Cronaca", ChroniclePanel.new(), KEY_C)
	for page_id in pages:
		host.open(page_id)
		assert_eq(host.current(), page_id, "%s can be opened" % page_id)
	# one page at a time: opening one closes the others
	host.open(&"court")
	var visible_pages := 0
	for child in host.get_children():
		if child is KDSheet or child is PanelContainer:
			visible_pages += 1 if child.visible else 0
	assert_true(visible_pages <= 2, "only the tab bar and one sheet are on screen (%d)" % visible_pages)
	assert_true(host.handle_key(KEY_ESCAPE), "escape is understood")
	assert_false(host.is_open(), "and closes the sheet")
	assert_true(host.handle_key(KEY_R), "a letter opens its own sheet")
	assert_eq(host.current(), &"realm", "the right one")
	_drop(host)


func test_the_sheets_show_the_numbers_of_the_world() -> void:
	var s := _session()
	var k := s.world.player()
	# the economy sheet says what the treasury holds
	var economy := _open(EconomyPanel.new()) as EconomyPanel
	var text := _all_text(economy)
	assert_true(text.contains("%d oro" % roundi(k.treasury)), "the economy sheet shows the treasury (%d)" % roundi(k.treasury))
	assert_true(text.contains("DEPOSITI") and text.contains("PREZZI DEL REGNO"), "with stores and prices")
	_drop(economy)
	# the court sheet names the king and his traits
	var ruler := s.world.ruler_of(k.id)
	var court := _open(CourtPanel.new()) as CourtPanel
	var court_text := _all_text(court)
	assert_true(court_text.contains(ruler.name), "the court sheet names the ruler (%s)" % ruler.name)
	assert_true(court_text.contains("Legittimità"), "with the legitimacy of the house")
	assert_false(court_text.contains("Nobiltà"), "and not the powers of the realm, which are on the Ceti sheet")
	_drop(court)
	# the realm sheet carries identity, goals and the formula
	var realm := _open(RealmPanel.new()) as RealmPanel
	var realm_text := _all_text(realm)
	assert_true(realm_text.contains(k.name), "the realm sheet names the realm")
	assert_true(realm_text.contains("OBIETTIVI") and realm_text.contains("LA FORMULA DEL REGNO"),
		"with the goals and the formula")
	assert_true(realm_text.contains("CRISI IN CORSO"), "and the crises passing over the realm")
	_drop(realm)


func test_the_government_sheet_offers_every_law_and_says_no_with_a_reason() -> void:
	var s := _session()
	var k := s.world.player()
	k.treasury = 5.0
	var panel := _open(GovernmentPanel.new()) as GovernmentPanel
	var buttons := _buttons(panel)
	assert_true(buttons.size() >= 8, "every law and every edict has its button (%d)" % buttons.size())
	var disabled := 0
	var with_reason := 0
	for b: Button in buttons:
		if b.disabled:
			disabled += 1
			if b.tooltip_text.contains("ori") or b.tooltip_text.contains("vigore") or b.tooltip_text.length() > 20:
				with_reason += 1
	assert_true(disabled > 0, "with an empty treasury most of them are closed (%d)" % disabled)
	assert_eq(with_reason, disabled, "and every closed one says why")
	_drop(panel)


## Consolidation: the crises passing over the realm are its state, not its knowledge — they moved to Il mio regno.
func test_the_knowledge_sheet_shows_the_branches_and_the_realm_sheet_the_crises() -> void:
	var s := _session()
	var k := s.world.player()
	k.research = 5000.0
	Events.apply(s, k, {"crisis": {"id": "prova", "name": "Carestia di prova", "days": 30,
		"modifiers": [{"key": "trade.income", "op": "mul", "value": 0.9}]}})
	var panel := _open(KnowledgePanel.new()) as KnowledgePanel
	var text := _all_text(panel)
	assert_true(text.contains("Rotazione dei campi") and text.contains("Mura di pietra"),
		"the four branches are on the page")
	assert_false(text.contains("Carestia di prova"), "the crisis is not on the sheet of knowledge")
	var realm := _open(RealmPanel.new()) as RealmPanel
	assert_true(_all_text(realm).contains("Carestia di prova"), "it is on Il mio regno, with the state of the realm")
	_drop(realm)
	var adopted := false
	for b: Button in _buttons(panel):
		if b.text == "Rotazione dei campi" and not b.disabled:
			b.pressed.emit()
			adopted = true
			break
	assert_true(adopted, "a road can be taken from the sheet")
	assert_true(k.technologies.has(&"rotazione"), "and the realm really learns it")
	_drop(panel)


func test_notifications_pile_up_and_do_not_overflow() -> void:
	_session()
	var stack := _open(NotificationStack.new()) as NotificationStack
	for i in 12:
		EventBus.notify("Prova %d" % i, "Qualcosa è successo.", &"event")
	assert_true(stack.get_child_count() <= NotificationStack.MAX_CARDS,
		"the stack keeps at most %d cards (%d)" % [NotificationStack.MAX_CARDS, stack.get_child_count()])
	assert_true(stack.get_child_count() > 0, "and shows the last ones")
	_drop(stack)


func test_the_sheets_fit_the_screen() -> void:
	_session()
	var panels: Array[Control] = [RealmPanel.new(), CourtPanel.new(), GovernmentPanel.new(),
		EconomyPanel.new(), KnowledgePanel.new(), EstatesPanel.new(), PeoplePanel.new()]
	for panel in panels:
		_open(panel)
		var size := panel.get_combined_minimum_size()
		assert_true(size.x <= 700.0, "%s is no wider than the room it has (%.0f)" % [panel.get_class(), size.x])
		assert_true(size.y <= 860.0, "%s fits under the bars at 1080p (%.0f)" % [panel.get_class(), size.y])
		_drop(panel)



# --- Phase 12.5: the new layout ----------------------------------------------------------------------

## Every page of the realm must be reachable, each button must open its own, and no sheet sits in two places.
## The lists are the HUD's own. Since the HUD review (Phase 18) the left column has four big plates — the last,
## Costruzioni, opens the building panel — the bar at the foot the six great sections, the chronicle opens from
## the news ("Vedi tutto") and the inhabitants from the sheet of the realm.
func test_the_columns_reach_every_sheet_of_the_realm() -> void:
	_session()
	var host := _open(PanelHost.new()) as PanelHost
	var realm := RealmPanel.new()
	for entry: Array in [[&"realm", realm], [&"court", CourtPanel.new()],
			[&"government", GovernmentPanel.new()], [&"religion", ReligionPanel.new()], [&"people", PeoplePanel.new()],
			[&"diplomacy", DiplomacyPanel.new()], [&"estates", EstatesPanel.new()],
			[&"economy", EconomyPanel.new()], [&"knowledge", KnowledgePanel.new()],
			[&"army", ArmyPanel.new()], [&"chronicle", ChroniclePanel.new()]]:
		host.add_page(entry[0], String(entry[0]), entry[1])
	var built := [0]
	var left_entries: Array = []
	for e: Array in SettlementHud.LEFT_ENTRIES:
		left_entries.append([e[0], e[1], e[2], e[3], func() -> void: built[0] += 1] if e[0] == &"build" else [e[0], e[1], e[2], e[3]])
	var left := _open(NavBlock.new()) as NavBlock
	left.setup(host, left_entries, true)
	var bottom := _open(NavBlock.new()) as NavBlock
	bottom.setup(host, SettlementHud.BOTTOM_ENTRIES, false)
	assert_eq(SettlementHud.LEFT_ENTRIES.size(), 4, "the left column is four big plates")
	assert_eq(SettlementHud.BOTTOM_ENTRIES.size(), 6, "the bar at the foot the six great sections")
	var seen := {}
	var pressed := 0
	for b: Button in _buttons(left) + _buttons(bottom):
		if b.text == "Costruzioni":
			b.pressed.emit()
			assert_eq(built[0], 1, "Costruzioni opens the building panel, not a sheet")
			continue
		var page := StringName("")
		for e: Array in SettlementHud.LEFT_ENTRIES + SettlementHud.BOTTOM_ENTRIES:
			if String(e[1]) == b.text:
				page = e[0]
		if page == &"":
			continue
		assert_false(seen.has(page), "%s is in one place only" % page)
		seen[page] = true
		b.pressed.emit()
		assert_eq(host.current(), page, "%s opens its own sheet" % b.text)
		pressed += 1
	assert_eq(pressed, 9, "every sheet of the two blocks has its button (%d)" % pressed)
	for wanted in ["Il mio regno", "Corte", "Governo", "Costruzioni"]:
		assert_true(_all_text(left).contains(wanted), "the left column carries %s" % wanted)
	for wanted in ["Esercito", "Ceti", "Ricerca", "Economia", "Diplomazia", "Religione"]:
		assert_true(_all_text(bottom).contains(wanted), "the bar at the foot carries %s" % wanted)
	# the chronicle, from the news
	var news := _open(NewsPanel.new()) as NewsPanel
	news.setup(Callable())
	news.chronicle_requested.connect(func() -> void: host.open(&"chronicle"))
	for b: Button in _buttons(news):
		if b.text == "Vedi tutto":
			b.pressed.emit()
	assert_eq(host.current(), &"chronicle", "the whole chronicle opens from the news")
	# the inhabitants and families, from the sheet of the realm
	host.open(&"realm")
	for b: Button in _buttons(realm):
		if b.text == "Abitanti":
			b.pressed.emit()
	assert_eq(host.current(), &"people", "the inhabitants open from the sheet of the realm")
	_drop(news)
	_drop(left)
	_drop(bottom)
	_drop(host)


## The religion sheet (Phase 18) tells the faith, the clergy, the law of faith and the faiths of the lands.
func test_the_religion_sheet_tells_the_faith_of_the_crown_and_of_the_lands() -> void:
	var s := _session()
	var k := s.world.player()
	var panel := _open(ReligionPanel.new()) as ReligionPanel
	panel.refresh()
	var text := _all_text(panel)
	var faith: ReligionDef = Defs.get_def("religions", k.religion)
	assert_true(text.contains(faith.display_name), "the sheet names the faith of the crown (%s)" % faith.display_name)
	assert_true(text.contains("Peso sulla legittimità"), "it shows what the favour of the clergy does to the crown")
	assert_false(text.contains("Favore del clero"), "without a second meter of the favour, which is on the Ceti sheet")
	assert_true(text.contains("scheda Ceti"), "and it says where the clergy is")
	assert_true(text.contains("Decima regia") and text.contains("Tolleranza"), "it offers the laws of faith")
	# a land of another faith appears with its conversion
	var other := &""
	for r: ReligionDef in Defs.all("religions"):
		if r.id != k.religion:
			other = r.id
			break
	s.world.province(k.provinces[0]).religion = other
	panel._signature = ""
	panel.refresh()
	text = _all_text(panel)
	assert_true(text.contains("TERRE DI UN'ALTRA FEDE") and text.contains("conversione"),
		"a province of another faith is listed with its conversion")
	_drop(panel)


## The build list is there only in build mode, and closing it drops the building in hand.
func test_the_build_list_opens_only_in_build_mode() -> void:
	_session()
	var column := _open(BuildColumn.new()) as BuildColumn
	column.setup(null)
	assert_false(column.is_open(), "the list starts closed: the map comes first")
	column.toggle()
	assert_true(column.is_open(), "the build button opens it")
	var text := _all_text(column)
	assert_true(text.contains("COSTRUZIONI") and text.contains("Casa") and text.contains("Fattoria"),
		"with its title and, under every category, all the buildings")
	column.toggle()
	assert_false(column.is_open(), "and closes it again")
	_drop(column)


## The date and the speed of time used to live in the debug overlay: now they are part of the game.
func test_the_top_bar_carries_the_day_the_stores_and_the_crown() -> void:
	var s := _session()
	var bar := _open(TopBar.new()) as TopBar
	bar.refresh()
	var text := _all_text(bar)
	assert_true(text.contains(s.date_text()), "the top bar says what day it is (%s)" % s.date_text())
	assert_true(text.contains("%d" % roundi(s.world.player().treasury)), "and how much gold the crown has")
	assert_true(text.contains("%d" % roundi(s.world.player().legitimacy)), "and how firm it stands")
	var speed_buttons := 0
	for b: Button in _buttons(bar):
		if b.text in ["1", "2", "3", "4", "5"] or b.tooltip_text.begins_with("Pausa"):
			speed_buttons += 1
	assert_eq(speed_buttons, 6, "pause and the five speeds are on the bar")
	for b: Button in _buttons(bar):
		if b.text == "3":
			b.pressed.emit()
	assert_eq(s.clock.speed_index, 3, "and pressing one really changes the speed of the world")
	_drop(bar)


## Phase 18: every number of the bar says where it comes from. The goods keep a register of what came in and
## what went out and why; the tooltip reads it, and it survives a save.
func test_the_top_bar_tells_where_the_goods_come_from_and_go() -> void:
	var s := _session()
	var settlement := SettlementHud.player_settlement()
	settlement.flow.clear()   # the forty days of the fixture have their own movements
	settlement.last_flow.clear()
	settlement.add(&"wood", 30, &"work")
	settlement.take(&"wood", 12, &"build")
	settlement.take(&"wood", 3, &"trade")
	var bar := _open(TopBar.new()) as TopBar
	bar.refresh()
	bar.write_tooltips(s, settlement)
	var tip := bar.tip_of(&"wood")
	assert_true(tip.contains("Lavoro") and tip.contains("Cantieri") and tip.contains("Mercanti"),
		"the wood tooltip names why the wood came and went: %s" % tip)
	assert_true(tip.contains("+15"), "and the balance of the month (+30 -12 -3 = +15): %s" % tip)
	settlement.close_month()
	assert_true(settlement.flow.is_empty() and int(settlement.last_flow[&"wood"][&"work"]) == 30,
		"a new month opens a new register and keeps the last one")
	var back := SettlementState.from_dict(settlement.to_dict())
	assert_eq(int(back.last_flow[&"wood"][&"build"]), -12, "the register survives a save")
	bar.write_tooltips(s, settlement)
	assert_true(bar.tip_of(&"wood").contains("Il mese scorso"), "and the tooltip then tells the month that closed")
	assert_true(bar.tip_of(&"food").contains("giorni"), "the food tells how long it lasts")
	assert_true(bar.tip_of(&"gold").contains("Oro della corona"), "the gold has its own tooltip")
	# a month of the world: the treasury balance and the reasons of the measures are there to be read
	for i in 31:
		s.advance_days(1)
	bar.write_tooltips(s, settlement)
	assert_true(bar.tip_of(&"gold").contains("Saldo"), "after a month the gold tells the balance: %s" % bar.tip_of(&"gold"))
	var k := s.world.player()
	if k.monarchy_founded:
		assert_true(bar.tip_of(&"crown").contains("Verso"), "the legitimacy tells where it is heading")
	else:
		assert_true(bar.tip_of(&"justice").contains("Verso"), "the authority tells where it is heading")
	assert_true(bar.tip_of(&"consent").contains("Verso"), "and so does the consent")
	_drop(bar)


## The build menu left the foot of the screen: the column keeps every building and now says what is missing.
func test_the_build_column_lists_the_buildings_and_says_what_is_missing() -> void:
	var s := _session()
	var column := _open(BuildColumn.new()) as BuildColumn
	column.setup(null)
	var settlement := SettlementHud.player_settlement()
	for res in [&"wood", &"stone"]:
		settlement.stock[res] = 0
	column.show_category(&"population")
	var names := _all_text(column)
	assert_true(names.contains("Casa"), "the houses are in the population category")
	var with_reason := 0
	for b: Button in _buttons(column):
		if b.tooltip_text.contains("Manca:"):
			with_reason += 1
	assert_true(with_reason > 0, "with empty stores the column says what is missing (%d)" % with_reason)
	column.show_category(&"raw")
	assert_true(_all_text(column).contains("Fattoria") or _all_text(column).contains("Taglialegna"),
		"and another category shows other buildings")
	_drop(column)


## The five powers left the foot of the Corte sheet and became a sheet of their own.
func test_the_estates_sheet_carries_the_five_powers() -> void:
	var s := _session()
	var k := s.world.player()
	k.favour[&"nobility"] = 20.0
	var panel := _open(EstatesPanel.new()) as EstatesPanel
	panel.refresh()
	var text := _all_text(panel)
	for name_text in ["Nobiltà", "Popolo", "Mercanti", "Esercito", "Clero"]:
		assert_true(text.contains(name_text), "%s is on the sheet" % name_text)
	assert_true(text.contains("ostile"), "a power under thirty is called hostile")
	assert_true(text.contains("Malcontento pesato"), "and the sheet says what it costs the crown")
	_drop(panel)


## The centre of the screen belongs to the map: the three columns must leave it free at 1080p.
func test_the_blocks_leave_the_middle_of_the_map_free() -> void:
	_session()
	var host := _open(PanelHost.new()) as PanelHost
	host.add_page(&"realm", "Regno", RealmPanel.new(), KEY_R)
	var left := _open(NavBlock.new()) as NavBlock
	left.setup(host, [[&"realm", "Il mio regno", &"crown", KEY_R]], true, "IL REGNO")
	var column := _open(BuildColumn.new()) as BuildColumn
	column.setup(null)
	var left_width := left.get_combined_minimum_size().x
	var right_width := column.get_combined_minimum_size().x
	var sheet_width := float(KDSheet.WIDTH)
	for width in [1280.0, 1920.0, 2560.0]:
		assert_true(left_width + sheet_width + right_width + 40.0 <= width,
			"at %.0f px the two columns and an open sheet still leave the map room (%.0f)" % [
				width, left_width + sheet_width + right_width])
	assert_true(column.get_combined_minimum_size().y <= 900.0,
		"the build column fits under the top band at 1080p (%.0f)" % column.get_combined_minimum_size().y)
	_drop(column)
	_drop(left)
	_drop(host)


## Everything written on a page, so a test can read it like a player would.
static func _all_text(node: Node) -> String:
	var parts := PackedStringArray()
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	for child in node.get_children():
		parts.append(_all_text(child))
	return "\n".join(parts)


static func _buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node is Button:
		out.append(node as Button)
	for child in node.get_children():
		out.append_array(_buttons(child))
	return out


## Consolidation: the four maps a ruler reads every day are in the list, the others folded under «Altre mappe».
func test_the_map_menu_keeps_the_daily_maps_in_sight() -> void:
	_session()
	var menu := MapModeMenu.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(menu)
	menu.setup(null)
	var in_sight: Array[String] = []
	var folded: Array[String] = []
	for b: Button in _buttons(menu):
		if b == menu._head or b == menu._more:
			continue
		if b.get_parent() == menu._more_list:
			folded.append(b.text)
		else:
			in_sight.append(b.text)
	assert_eq(in_sight, ["Politica", "Terreno", "Risorse", "Popolazione"], "the daily maps are in the list")
	assert_eq(folded.size(), 4, "the others are folded (%s)" % ", ".join(folded))
	assert_false(menu._more_list.visible, "and closed until asked for")
	(Engine.get_main_loop() as SceneTree).root.remove_child(menu)
	menu.free()

