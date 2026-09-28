extends KDTestCase
## Phase 16: the free lands of the world can finally be held — taken with gold by a believed crown, never by a
## community, never across the sea, never in the middle of a war — and the crowns of the world take them too.


func after_each() -> void:
	Session.end()


static func _free_border(world: WorldState, k: KingdomState) -> int:
	for p in world.provinces:
		if p.is_free() and ClaimProvinceCommand.borders(world, k.id, p.id):
			return p.id
	return -1


func test_a_crown_takes_a_free_land_beside_it() -> void:
	var s := GameSession.create_new({"campaign_seed": 1601})
	var w := s.world
	var k := w.player()
	var land := _free_border(w, k)
	assert_true(land >= 0, "the start valley has free lands around it")
	if land < 0:
		return
	var community := ClaimProvinceCommand.create(k.id, land).validate(s)
	assert_true(community.contains("comunità"), "a community takes no lands: %s" % community)
	crown_player(s)
	k.legitimacy = 70.0
	k.treasury = 5000.0
	var other := -1
	for q in w.provinces:
		if q.id != land and q.is_free() and ClaimProvinceCommand.borders(w, k.id, q.id):
			other = q.id
			break
	var other_before := ClaimProvinceCommand.cost(w, k.id, other) if other >= 0 else 0.0
	var price := ClaimProvinceCommand.cost(w, k.id, land)
	assert_true(price > 100.0, "the villages want gold (%d)" % roundi(price))
	var res := s.submit(ClaimProvinceCommand.create(k.id, land))
	assert_true(res.success, "the land is taken: %s" % res.reason)
	assert_eq(w.province(land).owner, k.id, "it belongs to the realm")
	assert_true(k.provinces.has(land), "and the realm knows it")
	assert_near(k.treasury, 5000.0 - price, 0.01, "the gold is paid")
	assert_true(w.chronicle.any(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "claim"), "the chronicle says so")
	var next := _free_border(w, k)
	if next >= 0:
		var wait := ClaimProvinceCommand.create(k.id, next).validate(s)
		assert_true(wait.contains("giorni"), "the new lands must settle before the next: %s" % wait)
	if other >= 0 and w.province(other).is_free():
		assert_true(ClaimProvinceCommand.cost(w, k.id, other) > other_before, "a wider realm pays more for the same land")


func test_no_land_is_taken_from_a_lord_across_the_sea_or_in_war() -> void:
	var s := GameSession.create_new({"campaign_seed": 1602})
	var w := s.world
	var k := crown_player(s)
	k.legitimacy = 70.0
	k.treasury = 5000.0
	var owned := -1
	var far := -1
	for p in w.provinces:
		if owned < 0 and p.owner >= 0 and p.owner != k.id:
			owned = p.id
		if far < 0 and p.is_free() and not ClaimProvinceCommand.borders(w, k.id, p.id):
			far = p.id
	assert_true(ClaimProvinceCommand.create(k.id, owned).validate(s).contains("signore"), "a lord's land is not for sale")
	assert_true(ClaimProvinceCommand.create(k.id, far).validate(s).contains("confina"), "nor a land that does not touch the realm")
	var enemy := w.kingdoms[1] if w.kingdoms[0] == k else w.kingdoms[0]
	Diplomacy.start_war(w, enemy.id, k.id)
	var land := _free_border(w, k)
	if land >= 0:
		assert_true(ClaimProvinceCommand.create(k.id, land).validate(s).contains("guerra"), "and nothing is asked in war")
	k.legitimacy = 20.0
	Diplomacy.end_war(w, enemy.id, k.id)
	if land >= 0:
		assert_true(ClaimProvinceCommand.create(k.id, land).validate(s).contains("legittimità"), "a crown nobody believes is refused")


func test_the_crowns_of_the_world_take_free_lands() -> void:
	var s := GameSession.create_new({"campaign_seed": 1603})
	s.set_system_enabled(&"events", false)
	var w := s.world
	var free_before := 0
	for p in w.provinces:
		if p.is_free():
			free_before += 1
	s.advance_days(360 * 12)
	var claimed := 0
	for k in w.kingdoms:
		claimed += int(k.records.get(&"provinces_claimed", 0.0))
	var free_after := 0
	for p in w.provinces:
		if p.is_free():
			free_after += 1
	assert_true(claimed > 0, "in twelve years the crowns took free lands (%d)" % claimed)
	assert_true(free_after < free_before, "the free lands shrink (%d → %d)" % [free_before, free_after])
	assert_true(free_after > free_before / 3, "but slowly: the world is not swallowed in a decade (%d left)" % free_after)


func test_the_province_card_offers_what_the_crown_can_do() -> void:
	var s := Session.start_new({"campaign_seed": 1604})
	var w := s.world
	var k := crown_player(s)
	k.legitimacy = 70.0
	k.treasury = 5000.0
	var card := ProvinceInspector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(card)
	card.show_province(k.capital)
	var text := _texts(card)
	assert_true(text.contains("Migliora le terre"), "one's own land can be improved")
	var land := _free_border(w, k)
	if land >= 0:
		card.show_province(land)
		text = _texts(card)
		assert_true(text.contains("Annetti al regno"), "a free land beside the realm can be taken")
	(Engine.get_main_loop() as SceneTree).root.remove_child(card)
	card.free()


static func _texts(node: Node) -> String:
	var parts := PackedStringArray()
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	for c in node.get_children():
		parts.append(_texts(c))
	return "\n".join(parts)

