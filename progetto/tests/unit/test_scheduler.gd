extends KDTestCase


class CountingSystem extends SimSystem:
	var runs: int = 0
	var seen_ids: Dictionary = {}
	var entity_count: int = 0

	func _init(p_id: StringName, p_freq: int, p_spread: int = 1, p_entities: int = 0) -> void:
		id = p_id
		frequency = p_freq
		spread = p_spread
		entity_count = p_entities

	func run(_session: GameSession, step: SimStep) -> void:
		runs += 1
		for e in entity_count:
			if SimSystem.in_bucket(e, step):
				seen_ids[e] = int(seen_ids.get(e, 0)) + 1


func test_frequencies_over_two_years() -> void:
	var session := GameSession.create_new({"campaign_seed": 42})
	var tick_sys := CountingSystem.new(&"t_tick", SimSystem.Frequency.TICK)
	var day_sys := CountingSystem.new(&"t_day", SimSystem.Frequency.DAY)
	var month_sys := CountingSystem.new(&"t_month", SimSystem.Frequency.MONTH)
	var year_sys := CountingSystem.new(&"t_year", SimSystem.Frequency.YEAR)
	for s in [tick_sys, day_sys, month_sys, year_sys]:
		session.scheduler.register(s)
	var days := 720
	session.advance_days(days)
	assert_eq(tick_sys.runs, days * session.world.ticks_per_day, "tick runs")
	assert_eq(day_sys.runs, days, "day runs")
	assert_eq(month_sys.runs, 24, "month runs in 720 days")
	# campaign starts 1 March 1230: 1 Jan 1231 (day 300) is inside, 1 Jan 1232 (day 660) too
	assert_eq(year_sys.runs, 2, "year runs")
	assert_eq(session.world.day, days)


func test_rotating_covers_every_entity_once_per_cycle() -> void:
	var session := GameSession.create_new({"campaign_seed": 7})
	var rot := CountingSystem.new(&"t_rot", SimSystem.Frequency.DAY_ROTATING, 7, 50)
	session.scheduler.register(rot)
	session.advance_days(70)
	assert_eq(rot.runs, 70)
	for e in 50:
		assert_eq(int(rot.seen_ids.get(e, 0)), 10, "entity %d processed once per week" % e)


func test_duplicate_system_rejected() -> void:
	var sch := Scheduler.new()
	sch.register(CountingSystem.new(&"dup", SimSystem.Frequency.DAY))
	sch.register(CountingSystem.new(&"dup", SimSystem.Frequency.DAY))
	assert_eq(sch.systems().size(), 1)

