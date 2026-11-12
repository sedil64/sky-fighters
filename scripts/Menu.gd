extends Node3D
## Menú principal: 1 jugador (contra la CPU, con dificultad), 2 jugadores y salir.
## De fondo, la isla con el muñeco en guardia.

const DIFFICULTY_TEXT := [
	"Reacciona despacio, duda y a veces se cae.",
	"Te persigue, se cubre a veces y sabe volver al escenario.",
	"Reacciona al instante, se cubre a menudo y remata con los golpes fuertes.",
]

var _ui: Control
var _title: Label
var _subtitle: Label
var _main: PanelContainer
var _difficulty: PanelContainer
var _hint: Label
var _desc: Label


func _ready() -> void:
	Engine.time_scale = 1.0
	_build_world()
	_build_ui()
	_show(_main)
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	env.environment = load("res://assets/world_env.tres")
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.45, 0)
	sun.light_color = Color(1, 0.96, 0.88)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)

	var island := ModelFit.load_fitted("res://assets/models/island.glb", 7.0, true)
	if island:
		var raw: AABB = island.get_meta("raw_aabb")
		island.position.y -= raw.size.y * 0.92 * island.get_meta("fit_scale")
		add_child(island)
	for d in [Vector4(-9, 3, -14, 4), Vector4(10, 6, -22, 6), Vector4(-3, 8, -30, 5)]:
		var deco := ModelFit.load_fitted("res://assets/models/island.glb", d.w, true)
		if deco:
			deco.position = Vector3(d.x, d.y, d.z)
			add_child(deco)

	# Muñeco de trapo en guardia, girado hacia la cámara.
	var doll := ModelFit.load_fitted("res://assets/models/trapo_rigged.glb", 1.5, false, 0.0, 0.9)
	if doll == null:
		doll = ModelFit.load_fitted("res://assets/models/trapo.glb", 1.5, false, 0.0, 0.9)
	if doll:
		var pivot := Node3D.new()
		pivot.position = Vector3(-1.2, 0, 0.6)
		pivot.rotation.y = 0.5
		pivot.add_child(doll)
		add_child(pivot)
		var players := doll.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty() and (players[0] as AnimationPlayer).has_animation("idle"):
			var ap := players[0] as AnimationPlayer
			ap.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			ap.play("idle")

	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.look_at_from_position(Vector3(1.2, 1.7, 6.5), Vector3(0.6, 0.9, 0))


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)

	_title = UiKit.label(_ui, 88, Color("#fff3c4"), 16)
	_title.text = "Sky Fighters"
	_subtitle = UiKit.label(_ui, 26, Color(1, 1, 1, 0.9))
	_subtitle.text = "Peleas entre islas flotantes"

	_main = UiKit.panel(_ui)
	var vb := _main.get_child(0)
	UiKit.button(vb, "1 jugador (contra la CPU)", func(): _show(_difficulty), true, Vector2(420, 68))
	# En el móvil, 2 jugadores solo tiene sentido con dos mandos conectados.
	if not Inputs.touch_mode or Input.get_connected_joypads().size() >= 2:
		UiKit.button(vb, "2 jugadores", func(): Game.start("versus"), false, Vector2(420, 68))
	if not OS.has_feature("web"):
		UiKit.button(vb, "Salir", func(): get_tree().quit(), false, Vector2(420, 68))

	_difficulty = UiKit.panel(_ui, 22, 10)
	vb = _difficulty.get_child(0)
	var head := UiKit.label(vb, 34)
	head.text = "Dificultad de la CPU"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var colors := [Color(0.25, 0.65, 0.35), Color(0.2, 0.42, 0.85), Color(0.8, 0.25, 0.25)]
	for i in Game.LEVEL_NAMES.size():
		var b := UiKit.button(vb, Game.LEVEL_NAMES[i], func(): Game.start("cpu", i), true, Vector2(420, 54))
		var base: Color = colors[i]
		b.add_theme_stylebox_override("normal", UiKit.round_box(base, 14))
		b.add_theme_stylebox_override("hover", UiKit.round_box(base.lightened(0.15), 14))
		b.add_theme_stylebox_override("pressed", UiKit.round_box(base.darkened(0.2), 14))
		b.focus_entered.connect(func(): _desc.text = DIFFICULTY_TEXT[i])
		b.mouse_entered.connect(func(): _desc.text = DIFFICULTY_TEXT[i])
	_desc = UiKit.label(vb, 20, Color(1, 1, 1, 0.85), 4)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(420, 56)
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.button(vb, "Volver", func(): _show(_main), false, Vector2(420, 50))

	_hint = UiKit.label(_ui, 18, Color(1, 1, 1, 0.85), 5)
	if Inputs.touch_mode:
		_hint.text = "Joystick a la izquierda · Atacar, Saltar y Escudo a la derecha · " \
			+ "inclina el joystick para elegir el ataque"
	else:
		_hint.text = "J1: WASD + F ataque, G escudo  ·  J2: flechas + K ataque, L escudo  ·  " \
			+ "Contra la CPU puedes usar cualquiera  ·  Esc pausa"


func _show(panel: PanelContainer) -> void:
	for p in [_main, _difficulty]:
		p.visible = p == panel
	_layout()
	var buttons := panel.find_children("*", "Button", true, false)
	if panel == _difficulty and buttons.size() > 1:
		buttons[Game.cpu_level].grab_focus()   # la última dificultad elegida
	elif not buttons.is_empty():
		buttons[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _difficulty.visible:
		_show(_main)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Botón "atrás" de Android: volver, o salir desde el menú principal.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _difficulty and _difficulty.visible:
			_show(_main)
		else:
			get_tree().quit()


## Título y botones en la mitad derecha (el muñeco queda a la izquierda).
func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var right_center := size.x * 0.68
	for l in [_title, _subtitle]:
		l.reset_size()
	_title.position = Vector2(right_center - _title.size.x * 0.5, size.y * 0.1)
	_subtitle.position = Vector2(right_center - _subtitle.size.x * 0.5, _title.position.y + _title.size.y - 6)
	_hint.reset_size()
	_hint.position = Vector2((size.x - _hint.size.x) * 0.5, size.y - _hint.size.y - 14)
	for p in [_main, _difficulty]:
		if p.visible:
			p.reset_size()
			var top := _subtitle.position.y + _subtitle.size.y + 18
			var y := maxf(top, (size.y - p.size.y) * 0.62)
			# Que no tape la línea de controles de abajo.
			y = minf(y, _hint.position.y - p.size.y - 10)
			p.position = Vector2(right_center - p.size.x * 0.5, y)
