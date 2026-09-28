class_name Minimap
extends PanelContainer
## The whole realm in the corner of the eye: the continent drawn small, coloured like the map mode on the
## table, with the rectangle of what the camera is looking at. A click takes the camera there.
##
## The picture is built once from the province raster (one pixel every few kilometres) and redrawn only when
## the borders move or the map mode changes: it costs nothing per frame.

const WIDTH := 232

var _camera: WorldCamera
var _controller: MapModeController
var _col: VBoxContainer
var _view: TextureRect
var _frame: Control
var _image: Image
var _texture: ImageTexture
var _size_px: Vector2i
var _drawn_version := -1
var _drawn_mode: StringName = &""


func setup(camera: WorldCamera, controller: MapModeController) -> void:
	_camera = camera
	_controller = controller
	add_theme_stylebox_override("panel", KDTheme.dark_panel())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	_col = col
	var head := SettlementHud._label(col, 16, Color(KDTheme.GOLD, 0.95), true)
	head.text = "MAPPA DEL MONDO"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var world_size := WorldConstants.world_size()
	_size_px = Vector2i(WIDTH, maxi(int(WIDTH * world_size.y / maxf(world_size.x, 1.0)), 16))
	_view = TextureRect.new()
	_view.custom_minimum_size = Vector2(_size_px)
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
	_redraw()


func _process(_delta: float) -> void:
	if not visible:
		return
	if Session.has_game() and Session.current.world.political_version != _drawn_version:
		_redraw()
	_frame.queue_redraw()


## Puts a control under the title, over the picture (the map modes live here since the HUD review).
func add_to_head(control: Control) -> void:
	_col.add_child(control)
	_col.move_child(control, 1)


## The picture: one province colour per pixel, sea left dark.
## The picture as it stands, for the tests and for whoever wants to look at it.
func picture() -> Image:
	return _image


func _redraw() -> void:
	if not Session.has_game():
		return
	var world := Session.current.world
	var wd := WorldData.get_instance()
	if not wd.loaded:
		return
	var mode: StringName = _controller.mode if _controller else &"political"
	_drawn_version = world.political_version
	_drawn_mode = mode
	if _image == null:
		_image = Image.create_empty(_size_px.x, _size_px.y, false, Image.FORMAT_RGBA8)
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
	if _texture == null:
		_texture = ImageTexture.create_from_image(_image)
		_view.texture = _texture
	else:
		_texture.update(_image)


func _draw_camera_rect() -> void:
	if _camera == null:
		return
	var world_size := WorldConstants.world_size()
	var rect := _camera.visible_world_rect()
	var scale := Vector2(_size_px) / world_size
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
	_camera.focus_on(Vector2(local.x, local.y) * WorldConstants.world_size(), _camera.meters_per_pixel(), false)

