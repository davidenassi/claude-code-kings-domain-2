class_name LocalView
extends Node2D
## THE LOCAL DOMAIN MAP (Rebirth, Phase 1): the valley of the homeland, where the community is founded, built
## and lived in. It has its own ground (DomainData, in the valley's metres), its own camera — from the people up
## to the whole valley, never the continent — and its own layers: terrain, water, woods, buildings, people, the
## hosts that stand in the valley, and the mists at its edges.
##
## While this map is on the table the settlements of the valley are simulated inhabitant by inhabitant.

## Closest zoom: a man is about forty pixels tall.
const MIN_MPP := 0.05
## The farthest this map ever goes: the whole valley and its misty rim (computed from the valley and the screen,
## never more than this).
const MAX_MPP_CAP := 7.0
## How far past the valley's edge the camera may look (the mists are drawn there).
const EDGE_MARGIN_M := 260.0
## The zoom the game opens on: the founders' fire and the ground around it.
const HOME_MPP := 0.35

@onready var world_view: WorldView = $WorldView
@onready var camera: WorldCamera = $WorldCamera
@onready var interaction: LocalInteraction = $LocalInteraction
@onready var build: BuildController = $WorldView/BuildController

var active := false


func _ready() -> void:
	camera.world_view = world_view
	camera.keep_view_inside = true
	camera.edge_margin_m = EDGE_MARGIN_M
	configure()
	EventBus.session_started.connect(func(_s: GameSession) -> void: configure())
	EventBus.session_loaded.connect(func(_s: GameSession) -> void: configure())


## Fits the camera to the valley of the running campaign.
func configure() -> void:
	var d := domain()
	if d == null:
		return
	camera.world_bounds = d.rect()
	camera.set_limits(MIN_MPP, max_mpp())


## The zoom that shows the whole valley on this screen (its rim of mist included).
func max_mpp() -> float:
	var d := domain()
	if d == null:
		return MAX_MPP_CAP
	var screen := get_viewport_rect().size
	var fit := maxf((d.size_m.x + EDGE_MARGIN_M * 2.0) / screen.x, (d.size_m.y + EDGE_MARGIN_M * 2.0) / screen.y)
	return minf(fit, MAX_MPP_CAP)


static func domain() -> DomainState:
	return Session.current.world.domain if Session.has_game() else null


func activate() -> void:
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	camera.enabled = true
	camera.make_current()
	_watch()


func deactivate() -> void:
	active = false
	visible = false
	if build and build.active():
		build.stop()
	process_mode = Node.PROCESS_MODE_DISABLED
	camera.enabled = false


## The first fire of the community (or the heart of the town it became), in the valley's metres.
func home_point() -> Vector2:
	var s := SettlementHud.player_settlement()
	if s:
		return s.center
	var d := domain()
	return d.center() if d else Vector2.ZERO


func focus_home(mpp: float = HOME_MPP, instant: bool = true) -> void:
	camera.focus_on(home_point(), mpp, instant)


func _process(_delta: float) -> void:
	if active:
		_watch()


## The valley on the table is watched: its settlements run hour by hour.
func _watch() -> void:
	if not Session.has_game():
		return
	var observed := {}
	for s in Session.current.world.settlements:
		observed[s.id] = true
	SettlementSim.set_observed(Session.current, observed)
