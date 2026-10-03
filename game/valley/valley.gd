extends Node2D
## The Valley scene: the city-builder half of King's Domain.
## Layers (bottom to top): terrain+water, ground decals (fields, roads), shadows, depth-sorted
## objects (trees, buildings, citizens), effects. Built in code so that every system stays data-driven.

const TerrainLayer := preload("res://valley/terrain/terrain_layer.gd")
const ValleyCamera := preload("res://valley/camera/valley_camera.gd")
const Capture := preload("res://tools/capture.gd")

var terrain: Node2D
var ground: Node2D       # fields, roads, plazas
var shadows: Node2D      # all object shadows, below every object
var objects: Node2D      # y-sorted trees, buildings, citizens, props
var camera: Camera2D


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

	objects = Node2D.new()
	objects.name = "Objects"
	objects.y_sort_enabled = true
	add_child(objects)

	camera = ValleyCamera.new()
	camera.name = "Camera"
	camera.add_to_group("valley_camera")
	add_child(camera)
	camera.make_current()
	camera.jump_to_ground(1600.0, 1000.0, 0.12)

	var cap := Capture.new()
	cap.name = "Capture"
	add_child(cap)
