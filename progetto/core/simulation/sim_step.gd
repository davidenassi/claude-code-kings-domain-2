class_name SimStep
extends RefCounted
## Describes the tick being simulated. Created by the Simulation and passed to every system.

var tick: int = 0            ## absolute tick counter
var tick_in_day: int = 0     ## 0 .. ticks_per_day-1
var ticks_per_day: int = 24
var day: int = 0             ## absolute day (0 = campaign start)
var is_new_day: bool = false
var is_new_month: bool = false
var is_new_year: bool = false
## For rotating systems: which bucket (0..spread-1) is processed this day.
var bucket: int = 0
var spread: int = 1


func day_fraction() -> float:
	return 1.0 / float(ticks_per_day)

