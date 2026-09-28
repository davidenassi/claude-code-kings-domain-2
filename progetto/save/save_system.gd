class_name SaveSystem
extends RefCounted
## Versioned save files: zstd-compressed JSON in user://saves/.

const SAVE_DIR := "user://saves"
## Where the shelf is. The tests point it elsewhere: running the suite must never touch the campaigns of whoever
## runs it (it did, until the menu tests learned to keep to their own folder).
static var save_dir := SAVE_DIR
## The moment of the last save, strictly increasing within the process: two saves written in the same
## millisecond must still have an order, or "Continue" can open the older one.
static var _last_stamp := 0.0
const EXTENSION := ".kds"


static func build_save_data(session: GameSession, save_name: String = "") -> Dictionary:
	return {
		"header": {
			"save_version": SaveMigrator.CURRENT_VERSION,
			"game_version": String(ProjectSettings.get_setting("application/config/version", "0.0.0")),
			"world_version": session.world.world_version,
			"saved_at": Time.get_datetime_string_from_system(false, true),
			"saved_unix": next_stamp(),
			"name": save_name,
			"date_text": session.date_text(),
			"realm": session.world.player().name if session.world.player() else "",
			"ruler": _ruler_name(session),
			"day": session.world.day,
		},
		"world": session.world.to_dict(),
	}


static func session_from_data(data: Dictionary) -> GameSession:
	var migrated := SaveMigrator.migrate(data)
	if migrated.is_empty():
		return null
	var world := WorldState.from_dict(migrated.get("world", {}))
	return GameSession.from_world(world)


## The save is written beside its slot and takes the place of the old one only once it is whole (Phase 19: it
## was written over the old file, so a game killed while saving, or a full disk, left the slot with half a save
## and without the previous one — the quick save and the saves by hand have no copy).
const TEMP_SUFFIX := ".tmp"


static func save_to_file(session: GameSession, path: String, save_name: String = "") -> Error:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var temp := path + TEMP_SUFFIX
	var f := FileAccess.open_compressed(temp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(build_save_data(session, save_name)))
	var err := f.get_error()
	f.close()
	if err != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return err
	SaveCatalogue.forget_header(path)
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path))


static func load_from_file(path: String) -> GameSession:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_error("SaveSystem: cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		push_error("SaveSystem: corrupted save %s" % path)
		return null
	return session_from_data(json.data)


static func slot_path(slot_name: String) -> String:
	return "%s/%s%s" % [save_dir, slot_name.validate_filename(), EXTENSION]


## Who reigns, for the line in the load menu ("Casa del Re — Rinaldo I").
static func _ruler_name(session: GameSession) -> String:
	var k := session.world.player()
	if k == null:
		return ""
	var ruler := session.world.ruler_of(k.id)
	return ruler.name if ruler else ""


## Unix time in seconds, never equal to the previous one returned in this process.
static func next_stamp() -> float:
	_last_stamp = maxf(Time.get_unix_time_from_system(), _last_stamp + 0.001)
	return _last_stamp

