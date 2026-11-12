extends SceneTree
## Simula un móvil: joystick, botones de atacar, saltar y escudo, y pausa.
##   godot --headless --path . --script res://tools/touch_test.gd
var arena: Node
var hud: Node
var touch: Control
var p1: Fighter
var cpu: Fighter
var frame := 0
var fails := 0
var mark := {}

func _start() -> void:
	# Después de que los autoloads arranquen (Inputs decide touch_mode en su _ready).
	root.get_node("Inputs").touch_mode = true
	var game := root.get_node("Game")
	game.mode = "cpu"
	game.cpu_level = 0
	arena = load("res://scenes/Arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena

func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond: fails += 1

## Los eventos llegan en píxeles de la ventana; el juego los pasa al lienzo (1280 de ancho).
## Sin ventana (headless) la "pantalla" es diminuta, así que hay que convertir.
func to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p

func finger(i: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i; e.position = to_window(pos); e.pressed = down
	Input.parse_input_event(e)

func drag(i: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i; e.position = to_window(pos)
	Input.parse_input_event(e)

func button(name: String) -> Vector2:
	return touch._button_center(name)

func _physics_process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		_start()
		return false
	if frame == 2:
		hud = arena.hud
		touch = hud._touch
		p1 = arena.fighters[0]
		cpu = arena.fighters[1]
		cpu.set_physics_process(false)   # la CPU se queda quieta (pero se le puede golpear)
		check(touch != null and touch.visible, "hay controles táctiles contra la CPU")
		check(hud._pause_button != null, "hay botón de pausa en pantalla")
	match frame:
		30:
			mark.x = p1.global_position.x
			finger(0, Vector2(200, 500), true)
		31:
			drag(0, Vector2(290, 500))
		60:
			check(p1.global_position.x > mark.x + 1.5, "el joystick mueve al jugador a la derecha")
			check(p1.facing == 1, "mira hacia donde mueves el joystick")
			finger(0, Vector2(290, 500), false)
		70:
			check(not Input.is_action_pressed("p1_right"), "al soltar el joystick deja de moverse")
			cpu.global_position = p1.global_position + Vector3(1.0, 0, 0)
			cpu.velocity = Vector3.ZERO
			finger(1, button("attack"), true)
		72:
			finger(1, button("attack"), false)
		90:
			check(cpu.percent > 0.0, "el botón de atacar golpea (%d%%)" % cpu.percent)
		100:
			finger(2, button("jump"), true)
		115:
			check(p1.velocity.y > 0.0 or not p1.is_on_floor(), "el botón de saltar salta")
			finger(2, button("jump"), false)
		170:
			finger(3, button("shield"), true)
		180:
			check(p1.shielding, "mantener el botón de escudo cubre")
			finger(3, button("shield"), false)
		185:
			check(not p1.shielding, "al soltarlo se quita el escudo")
			# Dos dedos a la vez: joystick + ataque arriba.
			finger(4, Vector2(200, 500), true)
			drag(4, Vector2(200, 400))
		187:
			finger(5, button("attack"), true)
		189:
			check(p1.attack == "up", "joystick arriba + atacar = ataque hacia arriba (%s)" % p1.attack)
			finger(5, button("attack"), false)
			finger(4, Vector2(200, 400), false)
		200:
			hud.toggle_pause()
		202:
			check(paused and hud._pause.visible and not touch.visible, "pausa: panel visible y controles ocultos")
			hud.toggle_pause()
		205:
			check(not paused and touch.visible, "al continuar vuelven los controles")
			print("FALLOS: %d" % fails)
			quit(1 if fails else 0)
	return false
