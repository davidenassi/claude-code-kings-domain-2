extends KDTestCase


func test_apply_add_then_mul() -> void:
	var st := ModifierStack.new()
	var culture: Array[Modifier] = [Modifier.new(&"production.wood", Modifier.Op.MUL, 1.10)]
	var law: Array[Modifier] = [
		Modifier.new(&"production.wood", Modifier.Op.ADD, 2.0),
		Modifier.new(&"production.wood", Modifier.Op.MUL, 0.5),
	]
	st.set_source("culture", culture, "Cultura")
	st.set_source("law:test", law, "Legge di prova")
	assert_near(st.apply(&"production.wood", 10.0), (10.0 + 2.0) * 1.10 * 0.5)
	assert_near(st.apply(&"production.stone", 10.0), 10.0, 0.0001, "untouched key")


func test_breakdown_lists_sources() -> void:
	var st := ModifierStack.new()
	var a: Array[Modifier] = [Modifier.new(&"k", Modifier.Op.ADD, 1.0)]
	var b: Array[Modifier] = [Modifier.new(&"k", Modifier.Op.MUL, 2.0)]
	st.set_source("religion", a, "Religione")
	st.set_source("spirit:x", b, "Spirito")
	var br := st.breakdown(&"k")
	assert_eq(br.size(), 2)
	var labels := []
	for e in br:
		labels.append(e["label"])
	assert_true(labels.has("Religione") and labels.has("Spirito"))


func test_remove_source_invalidates_cache() -> void:
	var st := ModifierStack.new()
	var a: Array[Modifier] = [Modifier.new(&"k", Modifier.Op.MUL, 3.0)]
	st.set_source("tmp", a)
	assert_near(st.apply(&"k", 1.0), 3.0)
	st.remove_source("tmp")
	assert_near(st.apply(&"k", 1.0), 1.0)


func test_culture_def_feeds_stack() -> void:
	var latin := Defs.culture(&"latin")
	assert_not_null(latin)
	var st := ModifierStack.new()
	st.set_source("culture", latin.modifiers, latin.display_name)
	assert_near(st.multiplier(&"construction.road_cost"), 0.85)

