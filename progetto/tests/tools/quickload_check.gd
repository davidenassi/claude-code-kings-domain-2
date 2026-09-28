extends Node
## Phase 19: the quick save and the quick load (F5 / F9) played on the real game scene. Run with:
##   godot --headless --path <ROOT> res://tests/tools/quickload_check.tscn
## Opens scenes/main.tscn as the game does, presses F5, lets the world go on, presses F9 and checks that the
## whole scene was rebuilt around the saved world (not the old map and HUD left on screen with a new world
## under them) and that the notice "Partita caricata" reached the news of the new HUD.
## Keeps to its own shelf (user://tests/quickload_shelf): the saves of whoever runs it are never touched.
## Prints "[KD:quickload] PASSED" or the failed checks, exit code 0 / 1.

const SHELF := "user://tests/quickload_shelf"

var _failures: PackedStringArray = []


func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.save_dir = SHELF
	for entry in SaveCatalogue.list():
		SaveCatalogue.remove(String(entry["path"]))
	var tree := get_tree()
	Session.start_new({"campaign_seed": 1906})
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	tree.current_scene = main   # F9 rebuilds the current scene: the game one, not this checker
	for i in 5:
		await tree.process_frame
	Session.current.advance_days(3)
	var saved_day := Session.current.world.day
	_press(&"kd_quick_save")
	await tree.process_frame
	_check(FileAccess.file_exists(SaveSystem.slot_path("quicksave")), "F5 writes the quick save")
	Session.current.advance_days(20)
	var old_session := Session.current
	var old_hud := main.find_child("SettlementHud", true, false)
	_press(&"kd_quick_load")
	for i in 6:
		await tree.process_frame
	_check(Session.current != old_session, "F9 puts the saved world in place of the running one")
	_check(Session.current.world.day == saved_day, "on the day of the quick save (%d, expected %d)" % [Session.current.world.day, saved_day])
	_check(not is_instance_valid(main), "the old game scene is gone")
	_check(old_hud == null or not is_instance_valid(old_hud), "and its HUD with it")
	var now := tree.current_scene
	_check(now != null and now.scene_file_path == "res://scenes/main.tscn", "a new game scene stands in its place")
	_check(Session.pending_notices.is_empty(), "the notice waiting for the new HUD was delivered")
	var told := false
	if now:
		for n in now.find_children("*", "", true, false):
			if (n is Label and (n as Label).text.contains("Partita caricata")) \
					or (n is RichTextLabel and (n as RichTextLabel).get_parsed_text().contains("Partita caricata")):
				told = true
				break
	_check(told, "and the news of the new HUD say «Partita caricata»")
	for entry in SaveCatalogue.list():
		SaveCatalogue.remove(String(entry["path"]))
	SaveSystem.save_dir = SaveSystem.SAVE_DIR
	if _failures.is_empty():
		print("[KD:quickload] PASSED")
	else:
		for f in _failures:
			print("[KD:quickload] FAILED: " + f)
	Session.end()
	tree.quit(0 if _failures.is_empty() else 1)


func _press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)

