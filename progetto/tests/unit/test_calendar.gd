extends KDTestCase

var cal: GameCalendar


func before_each() -> void:
	cal = GameCalendar.from_config(Defs.balance("time"))


func test_start_date() -> void:
	assert_eq(cal.format_date(0), "1 Marzo 1230")
	var d := cal.date_of(0)
	assert_eq(int(d["season"]), 0, "March is spring")


func test_month_and_year_rollover() -> void:
	assert_eq(cal.format_date(30), "1 Aprile 1230")
	assert_eq(cal.format_date(299), "30 Dicembre 1230")
	assert_eq(cal.format_date(300), "1 Gennaio 1231")
	assert_true(cal.is_year_start(300))
	assert_false(cal.is_year_start(299))
	assert_true(cal.is_month_start(330))
	assert_eq(cal.season_of(300), 3, "January is winter")
	assert_eq(cal.season_of(120), 1, "July is summer")


func test_day_from_date_inverse() -> void:
	for day in [0, 1, 29, 30, 299, 300, 1000, 57599]:
		var d := cal.date_of(day)
		assert_eq(cal.day_from_date(int(d["year"]), int(d["month"]), int(d["day"])), day, "roundtrip day %d" % day)


func test_days_per_year() -> void:
	assert_eq(cal.days_per_year(), 360)

