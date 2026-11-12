extends Node
## Autoload: crea las acciones de entrada de cada jugador.
## Acciones: p1_left, p1_right, p1_up, p1_down, p1_jump, p1_attack, p1_special (igual con p2_).
##   J1: A/D mover, W saltar, S abajo, F ataque, G especial · mando 1
##   J2: flechas, flecha arriba saltar, K ataque, L especial · mando 2
##   Contra la CPU, el J1 puede usar las dos (set_solo).

const KEYS := {
	1: {"left": [KEY_A], "right": [KEY_D], "up": [KEY_W], "down": [KEY_S],
		"jump": [KEY_W, KEY_SPACE], "attack": [KEY_F], "special": [KEY_G]},
	2: {"left": [KEY_LEFT], "right": [KEY_RIGHT], "up": [KEY_UP], "down": [KEY_DOWN],
		"jump": [KEY_UP], "attack": [KEY_K], "special": [KEY_L]},
}
const PAD_BUTTONS := {"jump": [JOY_BUTTON_A, JOY_BUTTON_Y], "attack": [JOY_BUTTON_X],
	"special": [JOY_BUTTON_B], "up": [JOY_BUTTON_DPAD_UP], "down": [JOY_BUTTON_DPAD_DOWN],
	"left": [JOY_BUTTON_DPAD_LEFT], "right": [JOY_BUTTON_DPAD_RIGHT]}
const PAD_AXES := {"left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0],
	"up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0]}


## true en móviles / pantallas táctiles: muestra los controles en pantalla.
var touch_mode := false


func _ready() -> void:
	touch_mode = OS.has_feature("mobile") or OS.has_feature("web_android") \
		or OS.has_feature("web_ios")
	for p in KEYS:
		for name in KEYS[p]:
			var action := "p%d_%s" % [p, name]
			if InputMap.has_action(action):
				continue
			InputMap.add_action(action, 0.35)
			for k in KEYS[p][name]:
				var e := InputEventKey.new()
				e.physical_keycode = k
				InputMap.action_add_event(action, e)
			for b in PAD_BUTTONS.get(name, []):
				var e := InputEventJoypadButton.new()
				e.button_index = b
				e.device = p - 1
				InputMap.action_add_event(action, e)
			if PAD_AXES.has(name):
				var e := InputEventJoypadMotion.new()
				e.axis = PAD_AXES[name][0]
				e.axis_value = PAD_AXES[name][1]
				e.device = p - 1
				InputMap.action_add_event(action, e)
	_simple("restart", [KEY_R], JOY_BUTTON_BACK)
	_simple("pause", [KEY_ESCAPE, KEY_P], JOY_BUTTON_START)


var _solo_events := []


## Contra la CPU, el jugador 1 también puede usar las teclas del jugador 2.
func set_solo(on: bool) -> void:
	for pair in _solo_events:
		InputMap.action_erase_event(pair[0], pair[1])
	_solo_events.clear()
	if not on:
		return
	for name in KEYS[2]:
		for k in KEYS[2][name]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event("p1_" + name, e)
			_solo_events.append(["p1_" + name, e])


func _simple(action: String, keys: Array, button: int) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	var b := InputEventJoypadButton.new()
	b.button_index = button
	b.device = -1
	InputMap.action_add_event(action, b)


## Márgenes (izq, arriba, der, abajo) que hay que dejar libres por muescas,
## esquinas redondeadas o barras del sistema, en unidades del canvas.
## (Copiado de Sky Explorer.)
func safe_margins(vp: Viewport) -> Vector4:
	if not touch_mode:
		return Vector4.ZERO
	var win := Rect2(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.size.x <= 0 or safe.size.x <= 0:
		return Vector4.ZERO
	var scale := vp.get_visible_rect().size / win.size
	return Vector4(
		maxf(safe.position.x - win.position.x, 0.0) * scale.x,
		maxf(safe.position.y - win.position.y, 0.0) * scale.y,
		maxf(win.end.x - safe.end.x, 0.0) * scale.x,
		maxf(win.end.y - safe.end.y, 0.0) * scale.y)
