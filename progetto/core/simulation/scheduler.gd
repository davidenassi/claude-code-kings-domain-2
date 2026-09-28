class_name Scheduler
extends RefCounted
## Runs registered SimSystems at their declared frequency.

var _systems: Array[SimSystem] = []
var profiling: bool = true


func register(system: SimSystem) -> void:
	for s in _systems:
		if s.id == system.id:
			push_error("Scheduler: duplicate system id %s" % system.id)
			return
	_systems.append(system)
	_systems.sort_custom(func(a: SimSystem, b: SimSystem) -> bool: return a.order < b.order)


func get_system(system_id: StringName) -> SimSystem:
	for s in _systems:
		if s.id == system_id:
			return s
	return null


func systems() -> Array[SimSystem]:
	return _systems


## Execute every system due at this step.
func run_step(session: GameSession, step: SimStep) -> void:
	for s in _systems:
		if not s.enabled:
			continue
		match s.frequency:
			SimSystem.Frequency.TICK:
				_run(s, session, step, 0, 1)
			SimSystem.Frequency.DAY:
				if step.is_new_day:
					_run(s, session, step, 0, 1)
			SimSystem.Frequency.DAY_ROTATING:
				if step.is_new_day:
					var sp := maxi(s.spread, 1)
					_run(s, session, step, step.day % sp, sp)
			SimSystem.Frequency.MONTH:
				if step.is_new_month:
					_run(s, session, step, 0, 1)
			SimSystem.Frequency.YEAR:
				if step.is_new_year:
					_run(s, session, step, 0, 1)


func _run(s: SimSystem, session: GameSession, step: SimStep, bucket: int, spread: int) -> void:
	step.bucket = bucket
	step.spread = spread
	if profiling:
		var t0 := Time.get_ticks_usec()
		s.run(session, step)
		s.profile_usec += Time.get_ticks_usec() - t0
		s.profile_runs += 1
	else:
		s.run(session, step)


func profile_report() -> String:
	var lines: PackedStringArray = []
	for s in _systems:
		if s.profile_runs == 0:
			continue
		lines.append("%s: %d runs, %.3f ms avg" % [s.id, s.profile_runs, s.profile_usec / 1000.0 / s.profile_runs])
	return "\n".join(lines)

