class_name SimulationRunner
extends Node
## Drives the current session from real frame time. Keyboard speed controls live here.

var last_ticks_per_second: float = 0.0
var _tick_counter: int = 0
var _tick_timer: float = 0.0
## The year (of game time) of the last automatic save, -1 until the first frame has seen the world.
var _last_autosave_year: int = -1
## Screenshots and benchmarks do not write into the ruler's shelf (Phase 19: they had left three
## "Salvataggio automatico" of test worlds in the list of the menu).
var _autosave_enabled := true

## A year of game time between one automatic save and the next.
const AUTOSAVE_EVERY_DAYS := 360


func _ready() -> void:
	var args := BootArgs.parse()
	_autosave_enabled = not (args.has("screenshot") or args.has("benchmark") or args.has("no-autosave"))


func _process(delta: float) -> void:
	if not Session.has_game():
		return
	var n := Session.current.advance_real(delta)
	_autosave_if_due(Session.current.world.day)
	_tick_counter += n
	_tick_timer += delta
	if _tick_timer >= 1.0:
		last_ticks_per_second = _tick_counter / _tick_timer
		_tick_counter = 0
		_tick_timer = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not Session.has_game() or not event.is_pressed() or event.is_echo():
		return
	var clock := Session.current.clock
	if event.is_action(&"kd_pause"):
		clock.toggle_pause()
	elif event.is_action(&"kd_speed_1"):
		clock.set_speed(1)
	elif event.is_action(&"kd_speed_2"):
		clock.set_speed(2)
	elif event.is_action(&"kd_speed_3"):
		clock.set_speed(3)
	elif event.is_action(&"kd_speed_4"):
		clock.set_speed(4)
	elif event.is_action(&"kd_speed_5"):
		clock.set_speed(5)
	elif event.is_action(&"kd_quick_save"):
		var err := SaveSystem.save_to_file(Session.current, SaveSystem.slot_path("quicksave"), "Salvataggio rapido")
		if err == OK:
			EventBus.notify("Partita salvata", Session.current.date_text(), &"good")
		else:
			EventBus.notify("Salvataggio fallito", error_string(err), &"bad")
	elif event.is_action(&"kd_quick_load"):
		var loaded := SaveSystem.load_from_file(SaveSystem.slot_path("quicksave"))
		if loaded != null:
			# the whole scene is rebuilt around the loaded world, as the pause menu does: the map, the HUD, the
			# news and the minimap of the previous game must not stay on screen (Phase 19: the coronation card
			# of the loaded kingdom, old news and the old minimap were shown after F9)
			Session.adopt_loaded(loaded)
			Session.pending_notices.append(["Partita caricata", loaded.date_text(), &"good"])
			get_tree().reload_current_scene()
		else:
			EventBus.notify("Caricamento fallito", "Nessun salvataggio rapido valido", &"bad")


## The crown writes its own memoirs: once a year of game time the campaign goes to the shelf by itself, so a
## window closed by mistake never costs a reign. Rotating, so the shelf does not grow for ever.
## Once the year has turned since the last look, not on one exact day: at high speed, or after a long frame,
## several days pass in one frame and the one day that divided by 360 could be skipped (Phase 19).
func _autosave_if_due(day: int) -> void:
	var year := day / AUTOSAVE_EVERY_DAYS
	if _last_autosave_year < 0:
		_last_autosave_year = year   # a game just started or loaded is not saved again at once
		return
	if year <= _last_autosave_year:
		return
	_last_autosave_year = year
	if not _autosave_enabled:
		return
	if SaveCatalogue.autosave(Session.current) != "":
		EventBus.notify("Cronaca messa al sicuro", Session.current.date_text(), &"realm")

