class_name ModifierStack
extends RefCounted
## Modifiers grouped by named source ("culture", "religion", "law:catasto", ...).
## Effective values are cached per key and invalidated whenever a source changes.
## breakdown() explains a value source by source, for UI tooltips.

signal changed

var _sources: Dictionary = {}      # String source_id -> Array[Modifier]
var _source_labels: Dictionary = {} # String source_id -> human label
var _add_cache: Dictionary = {}    # StringName key -> float
var _mul_cache: Dictionary = {}    # StringName key -> float
var _dirty: bool = true


func set_source(source_id: String, modifiers: Array[Modifier], label: String = "") -> void:
	_sources[source_id] = modifiers
	if label != "":
		_source_labels[source_id] = label
	_invalidate()


func remove_source(source_id: String) -> void:
	if _sources.erase(source_id):
		_source_labels.erase(source_id)
		_invalidate()


func has_source(source_id: String) -> bool:
	return _sources.has(source_id)


func source_ids() -> Array:
	return _sources.keys()


func clear() -> void:
	_sources.clear()
	_source_labels.clear()
	_invalidate()


func _invalidate() -> void:
	_dirty = true
	changed.emit()


func _rebuild() -> void:
	_add_cache.clear()
	_mul_cache.clear()
	for sid in _sources.keys():
		for m: Modifier in _sources[sid]:
			if m.op == Modifier.Op.MUL:
				_mul_cache[m.key] = float(_mul_cache.get(m.key, 1.0)) * m.value
			else:
				_add_cache[m.key] = float(_add_cache.get(m.key, 0.0)) + m.value
	_dirty = false


func additive(key: StringName) -> float:
	if _dirty:
		_rebuild()
	return float(_add_cache.get(key, 0.0))


func multiplier(key: StringName) -> float:
	if _dirty:
		_rebuild()
	return float(_mul_cache.get(key, 1.0))


## (base + additive) * multiplier
func apply(key: StringName, base: float) -> float:
	return (base + additive(key)) * multiplier(key)


## Returns [{source, label, op, value}] for every modifier touching `key`.
func breakdown(key: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sid in _sources.keys():
		for m: Modifier in _sources[sid]:
			if m.key == key:
				out.append({
					"source": sid,
					"label": String(_source_labels.get(sid, sid)),
					"op": m.op,
					"value": m.value,
				})
	return out

