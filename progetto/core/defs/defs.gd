extends Node
## Definitions registry (autoload "Defs").
## Loads every table in res://data/defs/ into typed KDDef resources and every file in
## res://data/defs/balance/ as a plain Dictionary. Validation problems are collected in `errors`.

const DEFS_DIR := "res://data/defs"
const BALANCE_DIR := "res://data/defs/balance"

## table name -> script of the KDDef subclass used for its items
var table_types: Dictionary = {
	"resources": ResourceDef,
	"terrain_types": TerrainTypeDef,
	"cultures": CultureDef,
	"religions": ReligionDef,
	"biomes": BiomeDef,
	"buildings": BuildingDef,
	"national_spirits": NationalSpiritDef,
	"traits": TraitDef,
	"factions": FactionDef,
	"units": UnitDef,
}

var errors: PackedStringArray = PackedStringArray()
var _tables: Dictionary = {}   # String -> Dictionary(StringName id -> KDDef)
var _order: Dictionary = {}    # String -> Array[StringName] (file order)
var _balance: Dictionary = {}  # String -> Dictionary
var _table_extra: Dictionary = {}  # String -> the table file's top-level fields other than "items"
var loaded: bool = false


func _ready() -> void:
	load_all()


func load_all() -> void:
	errors.clear()
	_tables.clear()
	_order.clear()
	_balance.clear()
	for table_name: String in table_types.keys():
		_load_table(table_name)
	_load_balance()
	_cross_validate()
	loaded = true
	if errors.is_empty():
		KDLog.info("defs", "loaded %d tables, %d balance files" % [_tables.size(), _balance.size()])
	else:
		for e in errors:
			KDLog.error("defs", e)


func _load_table(table_name: String) -> void:
	var path := "%s/%s.json" % [DEFS_DIR, table_name]
	var data: Variant = read_json(path)
	var table := {}
	var order: Array[StringName] = []
	_tables[table_name] = table
	_order[table_name] = order
	if not (data is Dictionary):
		errors.append("%s: missing or not an object" % path)
		return
	var items: Array = (data as Dictionary).get("items", [])
	var extra := (data as Dictionary).duplicate()
	extra.erase("items")
	_table_extra[table_name] = extra
	var script: GDScript = table_types[table_name]
	for raw in items:
		if not (raw is Dictionary):
			errors.append("%s: item is not an object" % path)
			continue
		var def: KDDef = script.new()
		def.load_from(raw, errors)
		if def.id == &"":
			continue
		if table.has(def.id):
			errors.append("%s: duplicate id %s" % [path, def.id])
			continue
		table[def.id] = def
		order.append(def.id)


func _load_balance() -> void:
	var dir := DirAccess.open(BALANCE_DIR)
	if dir == null:
		errors.append("%s: directory missing" % BALANCE_DIR)
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var data: Variant = read_json("%s/%s" % [BALANCE_DIR, file])
		if data is Dictionary:
			_balance[file.get_basename()] = data
		else:
			errors.append("balance/%s: not an object" % file)


func _cross_validate() -> void:
	var seen_index := {}
	for b: BiomeDef in all("biomes"):
		if not has_def("terrain_types", b.local_terrain):
			errors.append("biome %s: unknown local_terrain %s" % [b.id, b.local_terrain])
		if seen_index.has(b.index):
			errors.append("biome %s: duplicate index %d" % [b.id, b.index])
		seen_index[b.index] = true
	for bd: BuildingDef in all("buildings"):
		for res: StringName in bd.cost.keys():
			if not has_def("resources", res):
				errors.append("building %s: unknown cost resource %s" % [bd.id, res])
		for key in ["yield", "input", "output"]:
			for res: String in (bd.work.get(key, {}) as Dictionary).keys():
				if not has_def("resources", StringName(res)):
					errors.append("building %s: unknown %s resource %s" % [bd.id, key, res])


func table_extra(table_name: String) -> Dictionary:
	return _table_extra.get(table_name, {})


func biome_by_index(index: int) -> BiomeDef:
	for b: BiomeDef in all("biomes"):
		if b.index == index:
			return b
	return null


static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JSON parse error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


# --- queries ---------------------------------------------------------------

func get_def(table_name: String, def_id: StringName) -> KDDef:
	var table: Dictionary = _tables.get(table_name, {})
	return table.get(def_id)


func has_def(table_name: String, def_id: StringName) -> bool:
	return (_tables.get(table_name, {}) as Dictionary).has(def_id)


func ids(table_name: String) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_order.get(table_name, []))
	return out


func all(table_name: String) -> Array[KDDef]:
	var out: Array[KDDef] = []
	var table: Dictionary = _tables.get(table_name, {})
	for def_id in _order.get(table_name, []):
		out.append(table[def_id])
	return out


func balance(file_name: String) -> Dictionary:
	return _balance.get(file_name, {})


func resource(def_id: StringName) -> ResourceDef:
	return get_def("resources", def_id) as ResourceDef


func building(def_id: StringName) -> BuildingDef:
	return get_def("buildings", def_id) as BuildingDef


func culture(def_id: StringName) -> CultureDef:
	return get_def("cultures", def_id) as CultureDef


func religion(def_id: StringName) -> ReligionDef:
	return get_def("religions", def_id) as ReligionDef

