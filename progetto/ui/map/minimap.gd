class_name Minimap
extends PanelContainer
## The map in the corner of the eye, with the rectangle of what the camera is looking at; a click takes the
## camera there. Rebirth (Phase 1): it shows the map on the table —
## - on the map of the valley, the VALLEY (its ground, its water, the buildings of the community) and a button to
##   the map of the world;
## - on the map of the world, the CONTINENT coloured like the map mode in use, and the way back to the domain.
##
## The picture is built once and redrawn only when the borders, the map mode or the buildings change: it costs
## nothing per frame.

## The player asked for the other map (the button in the head).
signal switch_requested

const WIDTH := 232

var _camera: WorldCamera
var _controller: MapModeController
var _space: StringName = MapSpace.GLOBAL
var _col: VBoxContainer
var _title: Label
var _switch: Button
var _view: TextureRect
var _frame: Control
var _image: Image
var _texture: ImageTexture
var _size_px: Vector2i
var _drawn_version := -1
var _drawn_buildings := -1
var _drawn_mode: StringName = &""


func setup(camera: WorldCamera, controller: MapModeController) -> void:
	_camera = camera
	_controller = controller
	add_theme_stylebox_override("panel", KDTheme.dark_panel())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	_col = col
	_title = SettlementHud._label(col, 16, Color(KDTheme.GOLD, 0.95), true)
	_title.text = "MAPPA DEL MONDO"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_switch = Button.new()
	_switch.focus_mode = Control.FOCUS_NONE
	_switch.custom_minimum_size = Vector2(WIDTH, 32)
	_switch.add_theme_font_size_override("font_size", 15)
	KDTheme.button_styles(_switch)
	_switch.pressed.connect(func() -> void: switch_requested.emit())
	_switch.visible = false   # shown once a shell can answer (set_map)
	col.add_child(_switch)
	_view = TextureRect.new()
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.tooltip_text = "Clic per portarci la camera"
	_view.gui_input.connect(_on_input)
	col.add_child(_view)
	_frame = Control.new()          # the rectangle of the camera, drawn over the picture
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.draw.connect(_draw_camera_rect)
	_view.add_child(_frame)
	if _controller:
		_controller.mode_changed.connect(func(_m: StringName) -> void: _redraw())
	EventBus.province_owner_changed.connect(func(_p: int, _o: int, _n: int, _r: StringName) -> void: _redraw())
	_resize()
	_redraw()


## Shows one of the two maps (MapSpace.LOCAL / GLOBAL), followed by that map's camera.
func set_map(space: StringName, camera: WorldCamera) -> void:
	_space = space
	_camera = camera
	var local := MapSpace.is_local(space)
	_title.text = "LA VALLE" if local else "MAPPA DEL MONDO"
	_switch.visible = true
	_switch.text = "Mappa del mondo  (Tab)" if local else "Torna al dominio  (Tab)"
	_switch.tooltip_text = "Il continente, i regni, le province e le guerre" if local \
		else "La valle della tua gente: costruzioni, abitanti, lavoro"
	_resize()
	_image = null
	_redraw()


func space() -> StringName:
	return _space


func _area() -> Vector2:
	if MapSpace.is_local(_space) and Session.has_game() and Session.current.world.domain:
		return Session.current.world.domain.size_m
	return WorldConstants.world_size()


func _resize() -> void:
	var area := _area()
	_size_px = Vector2i(WIDTH, maxi(int(WIDTH * area.y / maxf(area.x, 1.0)), 16))
	if _view:
		_view.custom_minimum_size = Vector2(_size_px)


func _process(_delta: float) -> void:
	if not visible or not Session.has_game():
		return
	var world := Session.current.world
	if MapSpace.is_local(_space):
		if world.buildings_version != _drawn_buildings:
			_redraw()
	elif world.political_version != _drawn_version:
		_redraw()
	_frame.queue_redraw()


## Puts a control under the title, over the picture (the map modes live here since the HUD review).
func add_to_head(control: Control) -> void:
	_col.add_child(control)
	_col.move_child(control, 1)


## The picture as it stands, for the tests and for whoever wants to look at it.
func picture() -> Image:
	return _image


func _redraw() -> void:
	if not Session.has_game():
		return
	if _image == null or _image.get_size() != _size_px:
		_image = Image.create_empty(_size_px.x, _size_px.y, false, Image.FORMAT_RGBA8)
		_texture = null
	if MapSpace.is_local(_space):
		if not _redraw_valley():
			return
	elif not _redraw_continent():
		return
	if _texture == null:
		_texture = ImageTexture.create_from_image(_image)
		_view.texture = _texture
	else:
		_texture.update(_image)


## The continent: one province colour per pixel, sea left dark.
func _redraw_continent() -> bool:
	var world := Session.current.world
	var wd := WorldData.get_instance()
	if not wd.loaded:
		return false
	var mode: StringName = _controller.mode if _controller else &"political"
	_drawn_version = world.political_version
	_drawn_mode = mode
	var world_size := WorldConstants.world_size()
	var sea := Color("#20304A")
	var land := Color("#4A5A3A")
	for y in _size_px.y:
		for x in _size_px.x:
			var pos := Vector2((x + 0.5) / _size_px.x * world_size.x, (y + 0.5) / _size_px.y * world_size.y)
			var pid := wd.province_at(pos)
			if pid < 0:
				_image.set_pixel(x, y, sea)
				continue
			var c := MapModes.province_color(mode, world, pid)
			_image.set_pixel(x, y, land if c.a <= 0.01 else Color(c, 1.0))
	return true


## The valley: its ground in the colours of its biomes, woods darker, water blue, the buildings of the
## community as small dark marks, and the misty rim.
func _redraw_valley() -> bool:
	var world := Session.current.world
	var dd := DomainData.of(world)
	if dd == null:
		return false
	_drawn_buildings = world.buildings_version
	var area := dd.size_m
	var water := Color("#35607A")
	for y in _size_px.y:
		for x in _size_px.x:
			var pos := Vector2((x + 0.5) / _size_px.x * area.x, (y + 0.5) / _size_px.y * area.y)
			var c: Color
			var w := dd.water_at(pos)
			if w != WorldData.WATER_LAND or dd.river_clearance(pos) < 0.0:
				c = water
			else:
				var bd: BiomeDef = Defs.biome_by_index(dd.biome_at(pos))
				c = bd.color if bd else Color("#5A6A40")
				c = c.darkened(clampf(dd.canopy_smooth(pos) * 0.45, 0.0, 0.45))
			# the rim of mist, as on the map
			var edge := minf(minf(pos.x, area.x - pos.x), minf(pos.y, area.y - pos.y))
			c = c.lerp(Color("#C9C7BE"), 1.0 - smoothstep(0.0, 420.0, edge))
			_image.set_pixel(x, y, c)
	var scale := Vector2(_size_px) / area
	for b: BuildingState in world.buildings.values():
		if b.is_road():
			continue
		var p := Vector2i(b.pos * scale)
		for dy in [0, 1]:
			for dx in [0, 1]:
				var q := p + Vector2i(dx, dy)
				if q.x >= 0 and q.y >= 0 and q.x < _size_px.x and q.y < _size_px.y:
					_image.set_pixel(q.x, q.y, Color("#3A2616") if b.is_active() else Color("#8A6A40"))
	return true


func _draw_camera_rect() -> void:
	if _camera == null:
		return
	var area := _area()
	var rect := _camera.visible_world_rect()
	var scale := Vector2(_size_px) / area
	var r := Rect2(rect.position * scale, rect.size * scale)
	r.size = r.size.max(Vector2(3, 3))
	# kept inside the picture: zoomed out, the view is wider than the world and the frame spilled over the panel
	r = r.intersection(Rect2(Vector2.ZERO, Vector2(_size_px)))
	if r.size.x < 1.0 or r.size.y < 1.0:
		return
	_frame.draw_rect(r, Color(1, 1, 1, 0.12), true)
	_frame.draw_rect(r, Color("#F0E6CC"), false, 1.0)


func _on_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	var pressed := mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	var dragged := mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if not pressed and not dragged:
		return
	if _camera == null:
		return
	var local := (mb.position if mb else mm.position) / Vector2(_size_px)
	_camera.focus_on(Vector2(local.x, local.y) * _area(), _camera.meters_per_pixel(), false)
