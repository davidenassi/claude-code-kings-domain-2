class_name GlobalView
extends Node2D
## THE GLOBAL STRATEGIC MAP (Rebirth, Phase 1): the continent — provinces, realms, borders, rivers, mountains,
## great woods, hosts, battles and sieges, the names of the realms. It never shows a house, a field or a person:
## the homeland is a seat on this map, and it is entered with a double click (or Tab, or the button).
##
## While this map is on the table nobody is watched in the valley: its day is resolved in closed form
## (SettlementAggregate, same rules and same physical changes).

## Closest zoom: provinces and their villages as symbols — above the zoom where buildings could be drawn.
const MIN_MPP := 6.0
const MAX_MPP := 80.0
## The zoom the map opens on around the homeland: the province and its neighbours.
const HOME_MPP := 14.0

@onready var world_view: WorldView = $WorldView
@onready var camera: WorldCamera = $WorldCamera
@onready var interaction: MapInteraction = $MapInteraction
@onready var modes: MapModeController = $MapModeController
@onready var map_hud: MapHud = $MapHud

var active := false


func _ready() -> void:
	camera.world_view = world_view
	camera.world_bounds = Rect2(Vector2.ZERO, WorldConstants.world_size())
	camera.set_limits(MIN_MPP, MAX_MPP)


func activate() -> void:
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	map_hud.visible = true
	camera.enabled = true
	camera.make_current()
	if Session.has_game():
		SettlementSim.set_observed(Session.current, {})   # the valley goes on by the day


func deactivate() -> void:
	active = false
	visible = false
	map_hud.visible = false
	interaction.army_order = -1
	process_mode = Node.PROCESS_MODE_DISABLED
	camera.enabled = false


## Where the homeland stands on the continent: the player's first settlement, else the home province.
func home_point() -> Vector2:
	if not Session.has_game():
		return WorldConstants.world_size() * 0.5
	var world := Session.current.world
	var s := SettlementHud.player_settlement()
	if s:
		return world.settlement_global_pos(s)
	if world.domain:
		return world.domain.anchor_global
	var k := world.player()
	if k and k.capital >= 0:
		return WorldData.get_instance().province_geo(k.capital).center
	return WorldConstants.world_size() * 0.5


func focus_home(mpp: float = HOME_MPP, instant: bool = true) -> void:
	camera.focus_on(home_point(), mpp, instant)
