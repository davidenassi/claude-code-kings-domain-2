class_name SimClock
extends RefCounted
## Accumulates real time and converts it into simulation ticks.
## One day is split into `ticks_per_day` ticks; speeds are expressed in real seconds per day.

signal speed_changed(index: int)

var ticks_per_day: int = 24
## seconds_per_day for each speed index; index 0 is always pause (0.0).
var speeds: PackedFloat32Array = PackedFloat32Array([0.0, 4.0, 1.5, 0.5, 0.15, 0.05])
var speed_names: PackedStringArray = PackedStringArray()
## Hard cap of ticks processed per real frame, to avoid the spiral of death.
var max_ticks_per_frame: int = 240

var speed_index: int = 1
var _paused_speed: int = 1
var _accumulator: float = 0.0
## Optional ceiling on speed (e.g. observation speed while watching a battle). -1 = none.
var speed_cap_seconds_per_day: float = -1.0


static func from_config(cfg: Dictionary) -> SimClock:
	var c := SimClock.new()
	c.ticks_per_day = int(cfg.get("ticks_per_day", 24))
	c.max_ticks_per_frame = int(cfg.get("max_ticks_per_frame", 240))
	var list: Array = cfg.get("speeds", [])
	if not list.is_empty():
		c.speeds = PackedFloat32Array()
		c.speed_names = PackedStringArray()
		for s in list:
			c.speeds.append(float(s.get("seconds_per_day", 0.0)))
			c.speed_names.append(String(s.get("name", "")))
	c.speed_index = clampi(int(cfg.get("default_speed", 1)), 0, c.speeds.size() - 1)
	return c


func is_paused() -> bool:
	return speed_index == 0


func set_speed(index: int) -> void:
	index = clampi(index, 0, speeds.size() - 1)
	if index == speed_index:
		return
	if index != 0:
		_paused_speed = index
	speed_index = index
	_accumulator = 0.0
	speed_changed.emit(speed_index)


func toggle_pause() -> void:
	if is_paused():
		set_speed(_paused_speed)
	else:
		set_speed(0)


func effective_seconds_per_day() -> float:
	var spd := speeds[speed_index]
	if spd <= 0.0:
		return 0.0
	if speed_cap_seconds_per_day > 0.0:
		spd = maxf(spd, speed_cap_seconds_per_day)
	return spd


func seconds_per_tick() -> float:
	var spd := effective_seconds_per_day()
	if spd <= 0.0:
		return 0.0
	return spd / float(ticks_per_day)


## Consumes real delta time and returns how many ticks must be simulated now.
func consume(real_delta: float) -> int:
	var spt := seconds_per_tick()
	if spt <= 0.0:
		return 0
	_accumulator += real_delta
	var ticks := int(floor(_accumulator / spt))
	if ticks > max_ticks_per_frame:
		ticks = max_ticks_per_frame
		_accumulator = 0.0
	else:
		_accumulator -= ticks * spt
	return ticks


## Fraction (0..1) of the next tick already elapsed, for visual interpolation.
func tick_alpha() -> float:
	var spt := seconds_per_tick()
	if spt <= 0.0:
		return 0.0
	return clampf(_accumulator / spt, 0.0, 1.0)

