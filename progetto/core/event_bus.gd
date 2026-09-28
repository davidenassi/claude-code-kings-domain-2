extends Node
## Global signal bus (autoload "EventBus"). Systems emit facts here; other systems
## (factions, national spirits, chronicle, AI memory, UI) react without direct references.
## Payloads are plain typed arguments, never scene nodes.

# --- session lifecycle ---
signal session_started(session: GameSession)
signal session_loaded(session: GameSession)
signal session_ended

# --- time ---
signal day_passed(day: int)
signal month_passed(day: int)
signal year_passed(day: int, year: int)
signal speed_changed(speed_index: int)

# --- notifications for the UI ---
signal notification(title: String, text: String, kind: StringName, world_pos: Vector2)

# --- world facts (extended in later phases) ---
signal province_owner_changed(province_id: int, old_owner: int, new_owner: int, reason: StringName)
signal building_placed(building_id: int)
signal building_state_changed(building_id: int)
signal settlement_changed(settlement_id: int)
signal building_completed(building_id: int)
signal building_removed(building_id: int)
## Something changed on the ground at this world position (tree felled or regrown, rock exhausted, building placed).
signal terrain_changed(world_pos: Vector2)
signal chronicle_written(entry: Dictionary)
## Something changed between two realms (pact, war, peace, marriage).
signal diplomacy_changed(kingdom_a: int, kingdom_b: int)
## An army was raised, moved, lost men or disbanded.
signal army_changed(army_id: int)
## A battle started, went on or was decided.
signal battle_changed(battle_id: int)
## Something happened to a realm and may be waiting for an answer.
signal event_raised(event_id: String)


func notify(title: String, text: String, kind: StringName = &"info", world_pos: Vector2 = Vector2.INF) -> void:
	notification.emit(title, text, kind, world_pos)

