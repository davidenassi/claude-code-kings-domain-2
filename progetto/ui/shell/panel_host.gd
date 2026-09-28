class_name PanelHost
extends VBoxContainer
## The one place where the sheets of the realm open: a row of tabs and, under it, a single page at a time.
## Nothing ever overlaps anything else, and every system of the game is one click away.

signal page_changed(page_id: StringName)

var _bar: PanelContainer
var _tabs: HBoxContainer
## In compact mode the name of the sheet and its cross sit in the painted band at the top of the sheet's own
## frame (Phase 18 audit: they were a second box floating over the sheet, with the band of the frame empty).
var _head: HBoxContainer
var _head_title: Label
var _pages: Dictionary = {}     # id -> Control
var _buttons: Dictionary = {}   # id -> Button
var _titles: Dictionary = {}    # id -> String
var _keys: Dictionary = {}      # keycode -> page id
var _open: StringName = &""
## With the columns of Phase 12.5 the navigation lives outside: the bar then carries only the name of the
## open sheet and the cross that closes it.
var compact := false


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", KDTheme.card_panel())
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_bar.visible = false
	add_child(_bar)
	var stack := HBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	_bar.add_child(stack)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	stack.add_child(_tabs)
	_head = HBoxContainer.new()
	_head.add_theme_constant_override("separation", 12)
	_head.visible = false
	_head.top_level = true   # laid over the band of the open sheet, not in the column of the host
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_head)
	_head_title = SettlementHud._label(_head, 18, KDTheme.GOLD, true)
	_head_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_head_title.add_theme_constant_override("shadow_offset_y", 1)
	var close_btn := KDTheme.close_button()
	close_btn.tooltip_text = "Chiudi (Esc)"
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close)
	_head.add_child(close_btn)


## Registers a page and its tab. `key` is the letter that opens it (0 for none).
func add_page(page_id: StringName, title: String, page: Control, key: int = 0) -> void:
	_pages[page_id] = page
	page.visible = false
	add_child(page)
	var btn := Button.new()
	btn.text = title
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = "%s%s" % [title, "  (%s)" % char(key) if key > 0 else ""]
	KDTheme.button_styles(btn)
	btn.pressed.connect(func() -> void: toggle(page_id))
	_tabs.add_child(btn)
	_buttons[page_id] = btn
	_titles[page_id] = title
	if key > 0:
		_keys[key] = page_id


func _process(_delta: float) -> void:
	# a page that closed itself (its own cross) leaves the tabs alone again
	if _open != &"" and not (_pages[_open] as Control).visible:
		close()
	if _open != &"" and compact:
		_place_head(_pages[_open] as Control)


## The band of the window frame is 46 pixels high with a fleur on the left: the title starts after the fleur.
const BAND_HEIGHT := 46.0


func _place_head(page: Control) -> void:
	_head.global_position = page.global_position + Vector2(44.0, 5.0)
	_head.size = Vector2(maxf(page.size.x - 56.0, 60.0), BAND_HEIGHT - 10.0)


func open(page_id: StringName) -> void:
	if not _pages.has(page_id):
		return
	_open = page_id
	_bar.visible = not compact
	_tabs.visible = not compact
	_head.visible = compact
	move_child(_head, get_child_count() - 1)   # drawn and clicked above the sheet
	_head_title.text = String(_titles.get(page_id, page_id)).to_upper()
	for id: StringName in _pages.keys():
		var page: Control = _pages[id]
		page.visible = id == page_id
		if page.visible and page.has_method("refresh"):
			page.call("refresh")
			if page is KDSheet:
				(page as KDSheet).call_deferred("_fit")   # fitted to what the refresh just wrote
		(_buttons[id] as Button).add_theme_color_override("font_color",
			KDTheme.GOLD if id == page_id else KDTheme.TEXT_LIGHT)
	if compact:
		_place_head(_pages[page_id] as Control)
	page_changed.emit(page_id)


func close() -> void:
	_open = &""
	_bar.visible = false
	_head.visible = false
	for id: StringName in _pages.keys():
		(_pages[id] as Control).visible = false
	page_changed.emit(&"")


func toggle(page_id: StringName) -> void:
	if _open == page_id:
		close()
	else:
		open(page_id)


func is_open() -> bool:
	return _open != &""


func current() -> StringName:
	return _open


## Handled by the HUD: a letter opens its page, ESC closes whatever is open.
func handle_key(keycode: int) -> bool:
	if keycode == KEY_ESCAPE and is_open():
		close()
		return true
	if _keys.has(keycode):
		toggle(StringName(_keys[keycode]))
		return true
	return false


## Renames a page (its tab and the compact head): "Comunità" before the crown, "Regno" after.
func set_title(page_id: StringName, title: String) -> void:
	_titles[page_id] = title
	if _buttons.has(page_id):
		(_buttons[page_id] as Button).text = title
	if _open == page_id and _head_title:
		_head_title.text = title.to_upper()

