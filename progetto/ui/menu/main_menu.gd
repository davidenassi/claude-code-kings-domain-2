class_name MainMenu
extends Control
## The door of the game: the title, the campaigns already begun, and the way into a new one. Everything the
## player can do before a world exists happens here, so `scenes/main.tscn` can assume there is a session.

const GAME_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"

## True once the game has been entered: coming back to the menu must not bounce into it again, even when
## the run was started with the automation arguments.
static var _entered_once := false

var _list: VBoxContainer
var _load_panel: PanelContainer
var _buttons: VBoxContainer
var _message: Label
var _shot_path := ""
var _frames_left := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	InputSetup.register()
	KDTheme.dress(self)
	var args := BootArgs.parse()
	# every automation argument (screenshots, tests, scenarios) goes straight to the game: the tools do not
	# know about menus and must keep working exactly as before. `--kd-menu` is the exception: it asks for
	# the door itself, so the menu can be looked at and photographed.
	if args.has("menu"):
		_build()
		if args.has("screenshot"):
			_shot_path = String(args["screenshot"])
			_frames_left = String(args.get("frames", "30")).to_int()
		return
	if not args.is_empty() and not _entered_once:
		call_deferred("_enter_game")
		return
	_build()


func _process(_delta: float) -> void:
	if _frames_left < 0:
		return
	_frames_left -= 1
	if _frames_left == 0:
		_take_screenshot(_shot_path)


func _take_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var abs_path := path
	if not path.is_absolute_path() and not path.begins_with("res://") and not path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path("res://").path_join(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := img.save_png(abs_path)
	print("[KD:screenshot] %s -> %s" % [abs_path, error_string(err)])
	get_tree().quit(0 if err == OK else 1)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#1B120B")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var centre := VBoxContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.grow_vertical = Control.GROW_DIRECTION_BOTH
	centre.add_theme_constant_override("separation", 18)
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(centre)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", KDTheme.card_panel())
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre.add_child(frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	frame.add_child(col)

	var title := Label.new()
	title.text = "KING'S DOMAIN"
	title.add_theme_font_override("font", KDFonts.title())
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", KDTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var subtitle := SettlementHud._label(col, 15, Color(KDTheme.TEXT_LIGHT, 0.85), false)
	subtitle.text = "Un regno, una casata, una cronaca che si scrive da sé."
	col.add_child(KDTheme.ornate_rule())
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 6)
	col.add_child(_buttons)
	var recent := SaveCatalogue.most_recent()
	if not recent.is_empty():
		var label := "Continua — %s, %s" % [String(recent.get("realm", "il regno")), String(recent.get("date_text", ""))]
		_add_button(label, func() -> void: _load(String(recent["path"])), &"crown")
	_add_button("Nuova partita", _new_game, &"lily")
	if not recent.is_empty():
		_add_button("Carica partita", func() -> void: _load_panel.visible = not _load_panel.visible, &"chronicle")
	_add_button("Esci", func() -> void: get_tree().quit(), &"")

	_message = SettlementHud._label(col, 14, Color("#FFB09A"), false)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.visible = false

	_build_load_panel(centre)

	var version := SettlementHud._label(self, 12, Color(KDTheme.TEXT_LIGHT, 0.5), false)
	version.text = "versione %s" % String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.position -= Vector2(16, 10)


func _add_button(text: String, action: Callable, icon: StringName) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(380, 44)
	KDTheme.button_styles(btn)
	btn.add_theme_font_size_override("font_size", 17)
	if icon != &"" and KDUi.icon(icon):
		btn.icon = KDUi.icon(icon)
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 24)
		btn.add_theme_constant_override("h_separation", 10)
	btn.pressed.connect(action)
	_buttons.add_child(btn)
	return btn


# --- the shelf of the campaigns ------------------------------------------------------------------------

func _build_load_panel(parent: Control) -> void:
	_load_panel = PanelContainer.new()
	_load_panel.add_theme_stylebox_override("panel", KDTheme.card_panel())
	_load_panel.visible = false
	_load_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(_load_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_load_panel.add_child(col)
	var head := SettlementHud._label(col, 16, KDTheme.GOLD, true)
	head.text = "LE PARTITE SALVATE"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_refresh_list()


func _refresh_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for entry in SaveCatalogue.list():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		var open := Button.new()
		open.text = "%s — %s" % [String(entry["realm"]) if String(entry["realm"]) != "" else String(entry["slot"]),
			String(entry["date_text"])]
		open.tooltip_text = "%s\nsalvata il %s%s" % [String(entry["name"]), String(entry["saved_at"]),
			"\n(automatica)" if bool(entry["auto"]) else ""]
		open.focus_mode = Control.FOCUS_NONE
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.custom_minimum_size = Vector2(400, 36)
		KDTheme.button_styles(open)
		var path := String(entry["path"])
		open.pressed.connect(func() -> void: _load(path))
		row.add_child(open)
		var erase := Button.new()
		erase.text = "Elimina"
		erase.focus_mode = Control.FOCUS_NONE
		KDTheme.button_styles(erase, "red")
		erase.pressed.connect(func() -> void:
			SaveCatalogue.remove(path)
			_refresh_list())
		row.add_child(erase)
	if _list.get_child_count() == 0:
		var none := SettlementHud._label(_list, 14, Color(KDTheme.TEXT_LIGHT, 0.8), false)
		none.text = "Nessuna partita salvata."


# --- in and out ----------------------------------------------------------------------------------------

func _new_game() -> void:
	Session.start_new()
	_enter_game()


func _load(path: String) -> void:
	var loaded := SaveSystem.load_from_file(path)
	if loaded == null:
		_message.text = "Quel salvataggio non si apre: forse viene da una versione diversa."
		_message.visible = true
		return
	Session.adopt_loaded(loaded)
	_enter_game()


func _enter_game() -> void:
	_entered_once = true
	get_tree().change_scene_to_file(GAME_SCENE)

