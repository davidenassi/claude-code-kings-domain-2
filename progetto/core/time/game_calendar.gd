class_name GameCalendar
extends RefCounted
## Converts the absolute simulation day (0 = campaign start) into a calendar date.
## All calendar parameters come from data/defs/balance/time.json.

var start_year: int = 1230
var start_month: int = 3
var start_day: int = 1
var days_per_month: int = 30
var months_per_year: int = 12
var month_names: PackedStringArray = PackedStringArray()
var season_names: PackedStringArray = PackedStringArray()
## month (1-based) -> season index
var month_to_season: PackedInt32Array = PackedInt32Array()


static func from_config(cfg: Dictionary) -> GameCalendar:
	var c := GameCalendar.new()
	c.start_year = int(cfg.get("start_year", 1230))
	c.start_month = int(cfg.get("start_month", 3))
	c.start_day = int(cfg.get("start_day", 1))
	c.days_per_month = int(cfg.get("days_per_month", 30))
	c.months_per_year = int(cfg.get("months_per_year", 12))
	c.month_names = PackedStringArray(cfg.get("month_names", []))
	c.month_to_season.resize(c.months_per_year + 1)
	c.month_to_season.fill(0)
	var seasons: Array = cfg.get("seasons", [])
	for i in seasons.size():
		var s: Dictionary = seasons[i]
		c.season_names.append(String(s.get("name", "")))
		for m in s.get("months", []):
			var month := int(m)
			if month >= 1 and month <= c.months_per_year:
				c.month_to_season[month] = i
	return c


func days_per_year() -> int:
	return days_per_month * months_per_year


## Days elapsed from 1st day of start_year to the campaign start date.
func _start_offset() -> int:
	return (start_month - 1) * days_per_month + (start_day - 1)


## Returns {year, month (1-based), day (1-based), season, day_of_year (0-based)}.
func date_of(abs_day: int) -> Dictionary:
	var total := _start_offset() + maxi(abs_day, 0)
	var dpy := days_per_year()
	var year := start_year + total / dpy
	var doy := total % dpy
	var month := doy / days_per_month + 1
	var day := doy % days_per_month + 1
	return {
		"year": year,
		"month": month,
		"day": day,
		"season": month_to_season[month],
		"day_of_year": doy,
	}


func year_of(abs_day: int) -> int:
	return int(date_of(abs_day)["year"])


func season_of(abs_day: int) -> int:
	return int(date_of(abs_day)["season"])


func month_name(month: int) -> String:
	if month >= 1 and month <= month_names.size():
		return month_names[month - 1]
	return str(month)


func season_name(season: int) -> String:
	if season >= 0 and season < season_names.size():
		return season_names[season]
	return ""


func format_date(abs_day: int) -> String:
	var d := date_of(abs_day)
	return "%d %s %d" % [d["day"], month_name(d["month"]), d["year"]]


## True when abs_day is the first day of a month / year.
func is_month_start(abs_day: int) -> bool:
	return int(date_of(abs_day)["day"]) == 1


func is_year_start(abs_day: int) -> bool:
	var d := date_of(abs_day)
	return int(d["day_of_year"]) == 0


## Absolute day of the given calendar date (may be negative if before campaign start).
func day_from_date(year: int, month: int, day: int) -> int:
	var total := (year - start_year) * days_per_year() + (month - 1) * days_per_month + (day - 1)
	return total - _start_offset()

