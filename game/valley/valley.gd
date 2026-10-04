extends Node2D
## The Valley scene: the city-builder half of King's Domain.
## Layers (bottom to top): terrain+water, ground decals (fields, roads), shadows, depth-sorted
## objects (trees, buildings, citizens), effects. Built in code so that every system stays data-driven.

const TerrainLayer := preload("res://valley/terrain/terrain_layer.gd")
const ValleyCamera := preload("res://valley/camera/valley_camera.gd")
const Capture := preload("res://tools/capture.gd")
const VegetationLayer := preload("res://valley/vegetation/vegetation_layer.gd")
const TownBuilder := preload("res://valley/demo/town_builder.gd")
const SliceBuilder := preload("res://valley/slice/slice_builder.gd")

var terrain: Node2D
var ground: Node2D       # fields, roads, plazas
var shadows: Node2D      # all object shadows, below every object
var objects: Node2D      # y-sorted trees, buildings, citizens, props
var camera: Camera2D
var vegetation: RefCounted
var town: RefCounted
var quarter: RefCounted
var fx: Node2D           # effects above the objects (smoke, splashes)
var bridges: Node2D     # bridges: above shadows, below every object (citizens walk on them)


func _ready() -> void:
	terrain = TerrainLayer.new()
	terrain.name = "Terrain"
	add_child(terrain)

	ground = Node2D.new()
	ground.name = "Ground"
	add_child(ground)

	shadows = Node2D.new()
	shadows.name = "Shadows"
	add_child(shadows)

	bridges = Node2D.new()
	bridges.name = "Bridges"
	add_child(bridges)

	objects = Node2D.new()
	objects.name = "Objects"
	objects.y_sort_enabled = true
	add_child(objects)

	vegetation = VegetationLayer.new()
	vegetation.build(objects, shadows)
	town = TownBuilder.new()
	town.build(ground, shadows, bridges, objects)
	fx = Node2D.new()
	fx.name = "FX"
	add_child(fx)
	quarter = SliceBuilder.new()
	quarter.build(ground, shadows, bridges, objects, fx)

	var clouds := preload("res://valley/fx/cloud_shadows.gd").new()
	clouds.name = "CloudShadows"
	add_child(clouds)
	var ring := preload("res://valley/fx/cloud_ring.gd").new()
	ring.name = "CloudRing"
	add_child(ring)
	# colour grade over the whole valley view (warm light, richer colour, light vignette)
	var grade_layer := CanvasLayer.new()
	grade_layer.name = "Grade"
	grade_layer.layer = 5
	var grade := ColorRect.new()
	grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://valley/fx/grade.gdshader")
	grade.material = gm
	grade_layer.add_child(grade)
	add_child(grade_layer)

	camera = ValleyCamera.new()
	camera.name = "Camera"
	camera.add_to_group("valley_camera")
	add_child(camera)
	camera.make_current()
	camera.jump_to_ground(1600.0, 1000.0, 0.12)
	camera.zoom_changed.connect(_on_zoom)

	var cap := Capture.new()
	cap.name = "Capture"
	add_child(cap)
	add_child(preload("res://tools/benchmark.gd").new())
	add_child(preload("res://tools/perf_overlay.gd").new())


func _on_zoom(z: float) -> void:
	var smoke := get_node_or_null("Smoke")
	if smoke:
		smoke.visible = z > 0.09
	var bsh := shadows.get_node_or_null("BuildingShadows")
	if bsh:
		bsh.visible = z > 0.035
	if fx:
		var ss := fx.get_node_or_null("SliceSmoke")
		if ss:
			ss.visible = z > 0.09
