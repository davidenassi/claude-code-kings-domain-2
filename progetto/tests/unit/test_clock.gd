extends KDTestCase

var clock: SimClock


func before_each() -> void:
	clock = SimClock.from_config(Defs.balance("time"))


func test_pause_produces_no_ticks() -> void:
	clock.set_speed(0)
	assert_eq(clock.consume(10.0), 0)
	assert_true(clock.is_paused())


func test_speed_one_rate() -> void:
	clock.set_speed(1)
	var spd := clock.effective_seconds_per_day()
	assert_near(spd, 4.0, 0.001)
	# one whole day of real time -> ticks_per_day ticks (allowing float rounding)
	var n := 0
	for i in 400:
		n += clock.consume(spd / 400.0)
	assert_true(absi(n - clock.ticks_per_day) <= 1, "expected ~%d ticks got %d" % [clock.ticks_per_day, n])


func test_max_ticks_cap() -> void:
	clock.set_speed(clock.speeds.size() - 1)
	var n := clock.consume(1000.0)
	assert_eq(n, clock.max_ticks_per_frame)


func test_toggle_pause_restores_speed() -> void:
	clock.set_speed(3)
	clock.toggle_pause()
	assert_eq(clock.speed_index, 0)
	clock.toggle_pause()
	assert_eq(clock.speed_index, 3)


func test_observation_cap_slows_time() -> void:
	clock.set_speed(5)
	clock.speed_cap_seconds_per_day = 120.0
	assert_near(clock.effective_seconds_per_day(), 120.0, 0.001)

