extends KDTestCase


func test_defs_load_without_errors() -> void:
	assert_true(Defs.loaded, "Defs not loaded")
	assert_eq(Defs.errors.size(), 0, "definition errors: %s" % ", ".join(Defs.errors))


func test_resources() -> void:
	var wood := Defs.resource(&"wood")
	assert_not_null(wood, "wood missing")
	if wood:
		assert_eq(wood.display_name, "Legname")
		assert_true(wood.base_price > 0.0)
	var bread := Defs.resource(&"bread")
	assert_true(bread != null and bread.is_food, "bread must be food")
	var gold := Defs.resource(&"gold")
	assert_true(gold != null and not gold.uses_storage, "gold is treasury, no storage")


func test_cultures_and_religions_are_fixed_sets() -> void:
	var cultures := Defs.ids("cultures")
	for c in [&"germanic", &"hellenic", &"asian", &"latin", &"slavic", &"arab"]:
		assert_true(cultures.has(c), "missing culture %s" % c)
	assert_eq(cultures.size(), 6)
	var religions := Defs.ids("religions")
	for r in [&"catholic", &"orthodox", &"muslim", &"hindu"]:
		assert_true(religions.has(r), "missing religion %s" % r)
	assert_eq(religions.size(), 4)


func test_culture_modifiers_parsed() -> void:
	for c: CultureDef in Defs.all("cultures"):
		assert_true(c.modifiers.size() >= 2, "culture %s needs bonus and malus" % c.id)
		var has_bonus := false
		var has_malus := false
		for m in c.modifiers:
			if m.is_beneficial():
				has_bonus = true
			else:
				has_malus = true
		assert_true(has_bonus and has_malus, "culture %s must have both bonus and malus" % c.id)


func test_every_modifier_key_has_a_label() -> void:
	var labels: Dictionary = Defs.balance("modifier_keys").get("labels", {})
	for table in ["cultures", "religions"]:
		for def in Defs.all(table):
			for m: Modifier in def.get("modifiers"):
				assert_true(labels.has(String(m.key)), "%s %s: key %s has no label" % [table, def.id, m.key])


func test_balance_time_present() -> void:
	var t := Defs.balance("time")
	assert_true(t.has("speeds"), "time balance needs speeds")
	assert_eq(int(t.get("start_year", 0)), 1230)

