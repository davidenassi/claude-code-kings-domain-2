class_name TimeSignalsSystem
extends SimSystem
## Publishes calendar boundaries on the EventBus so non-simulation code (UI, chronicle) can react.


func _init() -> void:
	id = &"time_signals"
	frequency = Frequency.DAY
	order = 0


func run(session: GameSession, step: SimStep) -> void:
	EventBus.day_passed.emit(step.day)
	if step.is_new_month:
		for s in session.world.settlements:
			s.close_month()
		EventBus.month_passed.emit(step.day)
	if step.is_new_year:
		EventBus.year_passed.emit(step.day, session.calendar.year_of(step.day))

