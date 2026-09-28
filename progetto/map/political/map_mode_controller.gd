class_name MapModeController
extends Node
## Owns the active map mode and keeps the terrain overlay in sync with the political state.

signal mode_changed(mode: StringName)

@export var terrain_path: NodePath

var mode: StringName = &"political"
var _terrain: TerrainLayer
var _lookup: ImageTexture
var _dirty := true


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path) as TerrainLayer
	EventBus.province_owner_changed.connect(func(_p: int, _o: int, _n: int, _r: StringName) -> void: _dirty = true)
	EventBus.session_started.connect(func(_s: GameSession) -> void: _dirty = true)
	EventBus.session_loaded.connect(func(_s: GameSession) -> void: _dirty = true)
	EventBus.month_passed.connect(func(_d: int) -> void:
		if mode == &"population" or mode == &"development":
			_dirty = true)


func set_mode(new_mode: StringName) -> void:
	if not MapModes.ids().has(new_mode) or new_mode == mode:
		return
	mode = new_mode
	_dirty = true
	mode_changed.emit(mode)


func cycle(step: int = 1) -> void:
	var list := MapModes.ids()
	set_mode(list[posmod(list.find(mode) + step, list.size())])


func _process(_delta: float) -> void:
	if not _dirty or _terrain == null or not Session.has_game():
		return
	_dirty = false
	var img := MapModes.build_image(mode, Session.current.world)
	if _lookup == null:
		_lookup = ImageTexture.create_from_image(img)
	else:
		_lookup.update(img)
	var fade: Array = MapModes.mode_info(mode).get("close_fade_mpp", [0.0, 0.0])
	_terrain.set_overlay(_lookup, MapModes.strength(mode), Vector2(float(fade[0]), float(fade[1])))

