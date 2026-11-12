extends Control
## Controles táctiles del jugador 1 (solo en pantallas táctiles):
##  - Joystick (mitad izquierda, aparece donde pones el dedo): mover. Arriba/abajo sirven
##    para elegir el ataque (como en Smash); abajo también es caída rápida y bajar de plataforma.
##  - Botones a la derecha: Atacar (grande), Saltar y Escudo.
## Pulsa las mismas acciones que el teclado (p1_left, p1_attack...), así que el luchador no
## distingue si juegas con teclado, mando o pantalla. Multitáctil: un dedo por control.

const STICK_RADIUS := 90.0
const DEADZONE := 0.25
## Inclinación vertical a partir de la que cuenta como "arriba" o "abajo".
const VERTICAL := 0.55

## nombre: [acción, radio, desplazamiento desde la esquina inferior derecha, color, icono]
const BUTTONS := {
	"attack": ["p1_attack", 74.0, Vector2(-130, -130), Color(1.0, 0.45, 0.3), "puño"],
	"jump": ["p1_jump", 58.0, Vector2(-300, -95), Color(1.0, 0.8, 0.3), "arriba"],
	"shield": ["p1_special", 50.0, Vector2(-175, -305), Color(0.35, 0.6, 1.0), "escudo"],
}

var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick := Vector2.ZERO
var _button_fingers := {}   ## botón -> dedo
## Márgenes seguros (izq, arriba, der, abajo) por muescas o barras del sistema.
var safe_margins := Vector4.ZERO:
	set(v):
		safe_margins = v
		queue_redraw()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _button_center(name: String) -> Vector2:
	var corner := size - Vector2(safe_margins.z, safe_margins.w)
	return corner + BUTTONS[name][2]


func _default_stick() -> Vector2:
	return Vector2(170 + safe_margins.x, size.y - 170 - safe_margins.w)


## Suelta todos los dedos (al pausar, al terminar la partida...).
func reset() -> void:
	for b in _button_fingers:
		Input.action_release(BUTTONS[b][0])
	_button_fingers.clear()
	_stick_finger = -1
	_set_stick(Vector2.ZERO)


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			var hit := _button_at(p)
			if hit != "" and not _button_fingers.has(hit):
				_button_fingers[hit] = event.index
				Input.action_press(BUTTONS[hit][0])
			elif hit == "" and p.x < size.x * 0.5 and _stick_finger == -1:
				_stick_finger = event.index
				_stick_origin = p
				_set_stick(Vector2.ZERO)
		else:
			if event.index == _stick_finger:
				_stick_finger = -1
				_set_stick(Vector2.ZERO)
			for b in _button_fingers.keys():
				if _button_fingers[b] == event.index:
					_button_fingers.erase(b)
					Input.action_release(BUTTONS[b][0])
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == _stick_finger:
		_set_stick(((event.position - _stick_origin) / STICK_RADIUS).limit_length(1.0))
		queue_redraw()


func _button_at(p: Vector2) -> String:
	for b in BUTTONS:
		if p.distance_to(_button_center(b)) < BUTTONS[b][1] * 1.3:
			return b
	return ""


## Convierte el joystick en las acciones de dirección del jugador 1.
func _set_stick(v: Vector2) -> void:
	_stick = v
	_axis("p1_left", -v.x)
	_axis("p1_right", v.x)
	_digital("p1_up", v.y < -VERTICAL)
	_digital("p1_down", v.y > VERTICAL)


func _axis(action: String, amount: float) -> void:
	if amount > DEADZONE:
		Input.action_press(action, clampf(amount, 0.0, 1.0))
	elif Input.is_action_pressed(action):
		Input.action_release(action)


func _digital(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


func _draw() -> void:
	var origin := _stick_origin if _stick_finger != -1 else _default_stick()
	draw_circle(origin, STICK_RADIUS, Color(1, 1, 1, 0.12))
	draw_arc(origin, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0, true)
	draw_circle(origin + _stick * STICK_RADIUS, 38, Color(1, 1, 1, 0.45))

	for b in BUTTONS:
		var c := _button_center(b)
		var r: float = BUTTONS[b][1]
		var col: Color = BUTTONS[b][3]
		col.a = 0.65 if _button_fingers.has(b) else 0.35
		draw_circle(c, r, col)
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.6), 3.0, true)
		_draw_icon(BUTTONS[b][4], c, r)


func _draw_icon(icon: String, c: Vector2, r: float) -> void:
	var w := Color(1, 1, 1, 0.9)
	var s := r / 60.0
	match icon:
		"arriba":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -26) * s,
				c + Vector2(24, 12) * s, c + Vector2(-24, 12) * s]), w)
		"puño":
			# Puño: cuatro nudillos sobre un bloque.
			draw_rect(Rect2(c + Vector2(-22, -6) * s, Vector2(44, 28) * s), w)
			for i in 4:
				draw_circle(c + Vector2(-16.5 + i * 11, -10) * s, 6.5 * s, w)
		"escudo":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-20, -22) * s,
				c + Vector2(20, -22) * s, c + Vector2(20, 2) * s, c + Vector2(0, 26) * s,
				c + Vector2(-20, 2) * s]), w)
