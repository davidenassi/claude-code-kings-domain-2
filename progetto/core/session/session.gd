extends Node
## Holder of the current GameSession (autoload "Session").

var current: GameSession = null
## Notices for the ruler that must outlive a rebuild of the game scene (a quick load): [[title, text, kind]].
## The HUD says them once it is up again.
var pending_notices: Array = []


func has_game() -> bool:
	return current != null


func start_new(options: Dictionary = {}) -> GameSession:
	end()
	current = GameSession.create_new(options)
	current.clock.speed_changed.connect(_on_speed_changed)
	EventBus.session_started.emit(current)
	return current


func adopt_loaded(session: GameSession) -> void:
	end()
	current = session
	current.clock.speed_changed.connect(_on_speed_changed)
	EventBus.session_loaded.emit(current)


func end() -> void:
	if current != null:
		# everything this node hung on the session comes off before the session goes: a signal that points
		# at a freed autoload is a crash at the end of the program
		if current.clock.speed_changed.is_connected(_on_speed_changed):
			current.clock.speed_changed.disconnect(_on_speed_changed)
		current.dispose()
		current = null
		EventBus.session_ended.emit()


func _on_speed_changed(speed_index: int) -> void:
	EventBus.speed_changed.emit(speed_index)

