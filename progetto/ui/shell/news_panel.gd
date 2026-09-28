class_name NewsPanel
extends PanelContainer
## The "Notizie" block at the top of the right column (Phase 18 HUD review): a framed header with the way to
## the whole chronicle, and under it the last pieces of news (NotificationStack). It folds to its header with
## a click, and when there is no recent news it says so in one line instead of standing empty.

signal chronicle_requested

var stack: NotificationStack
var _body: VBoxContainer
var _empty: Label
var _fold: Button
var _folded := false


func setup(camera: WorldCamera) -> void:
	add_theme_stylebox_override("panel", KDTheme.dark_panel())
	custom_minimum_size = Vector2(370, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(KDUi.icon_node(&"chronicle", 24.0))
	var title := SettlementHud._label(head, 17, KDTheme.GOLD, true)
	title.text = "NOTIZIE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var all := Button.new()
	all.text = "Vedi tutto"
	all.focus_mode = Control.FOCUS_NONE
	all.tooltip_text = "La cronaca completa del regno (C)"
	all.add_theme_font_size_override("font_size", 14)
	KDTheme.button_styles(all)
	all.pressed.connect(func() -> void: chronicle_requested.emit())
	head.add_child(all)
	_fold = Button.new()
	_fold.focus_mode = Control.FOCUS_NONE
	_fold.icon = KDTheme.chevron_texture()
	_fold.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fold.custom_minimum_size = Vector2(30, 28)
	_fold.tooltip_text = "Chiudi o apri le notizie"
	KDTheme.button_styles(_fold)
	_fold.pressed.connect(func() -> void: set_folded(not _folded))
	head.add_child(_fold)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	col.add_child(_body)
	stack = NotificationStack.new()
	stack.name = "Notifications"
	stack.setup(camera)
	_body.add_child(stack)
	_empty = SettlementHud._label(_body, 13, Color(KDTheme.TEXT_LIGHT, 0.55), false)
	_empty.text = "Nessuna notizia recente."
	_sync_fold()


func _process(_delta: float) -> void:
	if stack:
		_empty.visible = stack.get_child_count() == 0 and not _folded


func set_folded(on: bool) -> void:
	_folded = on
	_body.visible = not on
	_sync_fold()


func is_folded() -> bool:
	return _folded


func _sync_fold() -> void:
	# the chevron points down when the block is open, right when it is folded
	_fold.icon = KDTheme.chevron_texture() if _folded else KDTheme.chevron_down_texture()

