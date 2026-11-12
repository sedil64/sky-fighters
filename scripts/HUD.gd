extends CanvasLayer
## Marcador (% de daño y vidas), pausa (Esc / Start) y pantalla de fin de partida.

var _panels := {}
var _pause: PanelContainer
var _end: PanelContainer
var _end_title: Label
var _touch: Control
var _pause_button: Button


func _ready() -> void:
	# Sigue funcionando con el juego en pausa.
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(fighters: Array[Fighter]) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_top = -170
	row.offset_bottom = -8
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 120)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	for f in fighters:
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_END
		var pct := _label(56)
		var name := _label(22)
		name.text = f.display_name
		var stocks := _label(26)
		box.add_child(pct)
		box.add_child(name)
		box.add_child(stocks)
		row.add_child(box)
		_panels[f] = {pct = pct, stocks = stocks}

	_pause = UiKit.panel(self)
	var vb := _pause.get_child(0)
	var head := UiKit.label(vb, 40)
	head.text = "Pausa"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.button(vb, "Continuar", toggle_pause)
	UiKit.button(vb, "Reiniciar", func(): Game.start(Game.mode), false)
	UiKit.button(vb, "Menú principal", Game.to_menu, false)

	# Controles táctiles (solo para el jugador 1, así que solo contra la CPU)
	# y botón de pausa en pantalla.
	if Inputs.touch_mode:
		if Game.mode == "cpu":
			_touch = preload("res://scripts/TouchControls.gd").new()
			add_child(_touch)
			move_child(_touch, 0)
		_pause_button = UiKit.button(self, "II", toggle_pause, false, Vector2(76, 76))
		get_viewport().size_changed.connect(_place_touch)
		_place_touch.call_deferred()

	_end = UiKit.panel(self)
	vb = _end.get_child(0)
	_end_title = UiKit.label(vb, 52, Color("#fff3c4"), 12)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.button(vb, "Revancha", func(): Game.start(Game.mode))
	UiKit.button(vb, "Menú principal", Game.to_menu, false)


func _label(size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.12, 0.18))
	l.add_theme_constant_override("outline_size", maxi(size / 6, 4))
	return l


func _process(_dt: float) -> void:
	for f in _panels:
		var p: Dictionary = _panels[f]
		var pct: Label = p.pct
		pct.text = "%d%%" % int(f.percent)
		# Blanco -> amarillo -> rojo según el daño.
		var t := clampf(f.percent / 150.0, 0.0, 1.0)
		pct.modulate = Color.WHITE.lerp(Color(1.0, 0.85, 0.2), minf(t * 2.0, 1.0)) \
			.lerp(Color(0.95, 0.15, 0.15), maxf(t * 2.0 - 1.0, 0.0))
		(p.stocks as Label).text = "● ".repeat(maxi(f.stocks, 0)).strip_edges()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _end.visible:
		toggle_pause()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Botón "atrás" de Android: pausa (o la quita).
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _end and not _end.visible:
		toggle_pause()


func _place_touch() -> void:
	var m := Inputs.safe_margins(get_viewport())
	if _touch:
		_touch.safe_margins = m
	if _pause_button:
		var w := get_viewport().get_visible_rect().size.x
		_pause_button.position = Vector2(w - 76 - 20 - m.z, 20 + m.y)


func toggle_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_show(_pause, paused)
	if _touch:
		_touch.reset()
		_touch.visible = not paused
	if _pause_button:
		_pause_button.visible = not paused


func show_winner(name: String) -> void:
	_end_title.text = "¡Gana %s!" % name if name != "" else "¡Empate!"
	# Deja ver un momento la celebración antes de sacar el panel.
	await get_tree().create_timer(1.2).timeout
	if _touch:
		_touch.reset()
		_touch.visible = false
	if _pause_button:
		_pause_button.visible = false
	_show(_end, true)


func _show(panel: PanelContainer, on: bool) -> void:
	panel.visible = on
	if on:
		UiKit.center(panel)
		# Primer botón con el foco, para moverse con teclado o mando.
		for c in panel.get_child(0).get_children():
			if c is Button:
				c.grab_focus()
				break
