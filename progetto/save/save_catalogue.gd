class_name SaveCatalogue
extends RefCounted
## What is on the shelf: the saved campaigns, newest first, with enough of each to choose without opening it.
## A save is a compressed JSON file; the header carries the day, the date in words and the name of the realm,
## so the menu never has to build a whole world just to draw a line of a list.

const AUTOSAVE_PREFIX := "auto"
const AUTOSAVE_KEEP := 3


## [{path, name, realm, date_text, day, saved_at, auto}], newest first.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(SaveSystem.save_dir)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(SaveSystem.EXTENSION):
			continue
		var path := "%s/%s" % [SaveSystem.save_dir, file]
		var header := read_header(path)
		if header.is_empty():
			continue
		out.append({
			"path": path,
			"slot": file.trim_suffix(SaveSystem.EXTENSION),
			"name": String(header.get("name", "")),
			"realm": String(header.get("realm", "")),
			"date_text": String(header.get("date_text", "")),
			"day": int(header.get("day", 0)),
			"saved_at": String(header.get("saved_at", "")),
			"saved_unix": float(header.get("saved_unix", 0.0)),
			"auto": file.begins_with(AUTOSAVE_PREFIX),
		})
	# newest first, down to the fraction of a second: two campaigns written in the same breath keep their order
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a["saved_unix"]) - float(b["saved_unix"])) > 0.0005:
			return float(a["saved_unix"]) > float(b["saved_unix"])
		return String(a["saved_at"]) > String(b["saved_at"]))
	return out


## The header alone. Reading it still opens the file — the world is parsed and thrown away — so the menu asks
## for it once and keeps the list.
static func read_header(path: String) -> Dictionary:
	# a file already read and not written since is not opened again (Phase 19: the list of the menu parsed
	# every whole world on the shelf each time — 70 ms for a town of two thousand, per save)
	var stamp := FileAccess.get_modified_time(path)
	var known: Array = _headers.get(path, [])
	if not known.is_empty() and int(known[0]) == stamp:
		return known[1]
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	var header: Dictionary = (json.data as Dictionary).get("header", {})
	if not (header is Dictionary):
		return {}
	_headers[path] = [stamp, header]
	return header


## path -> [modified time, header]: the headers already read. Forgotten when the file is written or removed
## (the modified time counts whole seconds: two quick saves in the same second must not show the older one).
static var _headers: Dictionary = {}


static func forget_header(path: String) -> void:
	_headers.erase(path)


## The last campaign touched, for "continue".
static func most_recent() -> Dictionary:
	var all := list()
	return all[0] if not all.is_empty() else {}


static func exists() -> bool:
	return not list().is_empty()


## Writes a save and gives back the path (empty on failure). `slot` is the file name without extension.
static func write(session: GameSession, slot: String, save_name: String = "") -> String:
	var path := SaveSystem.slot_path(slot)
	var err := SaveSystem.save_to_file(session, path, save_name)
	return path if err == OK else ""


## The crown writes its own memoirs: a rotating autosave, so a campaign is never lost to a closed window.
## The name carries the moment down to the millisecond, so two saves in the same second never overwrite.
static func autosave(session: GameSession) -> String:
	var stamp := "%d" % int(SaveSystem.next_stamp() * 1000.0)   # milliseconds, strictly increasing: the name orders them
	var path := write(session, "%s_%s" % [AUTOSAVE_PREFIX, stamp], "Salvataggio automatico")
	prune_autosaves()
	return path


## Only the last few automatic saves are kept: the shelf does not grow for ever. They are weighed by their
## own name, which carries the moment: two written in the same second still have an order. Only the names are
## read (Phase 19: the whole shelf was opened and parsed at every automatic save — half a second at the turn of
## each year in a large town).
static func prune_autosaves() -> void:
	var dir := DirAccess.open(SaveSystem.save_dir)
	if dir == null:
		return
	var autos: Array[String] = []
	for file in dir.get_files():
		if file.begins_with(AUTOSAVE_PREFIX) and file.ends_with(SaveSystem.EXTENSION):
			autos.append(file)
	autos.sort_custom(func(a: String, b: String) -> bool: return a > b)
	for i in range(AUTOSAVE_KEEP, autos.size()):
		remove("%s/%s" % [SaveSystem.save_dir, autos[i]])


static func remove(path: String) -> bool:
	forget_header(path)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK \
		or DirAccess.remove_absolute(path) == OK

