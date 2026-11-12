extends SceneTree
## Prueba automática del combate:
##   godot --headless --path . --script res://tools/fight_test.gd
var arena: Node
var p1: Fighter
var p2: Fighter
var frame := 0
var fails := 0
var mark := {}

func _initialize() -> void:
	root.get_node("Game").mode = "versus"   # aquí se manejan los dos con "teclas" simuladas
	arena = load("res://scenes/Arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena

func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond: fails += 1

func press(a: String) -> void: Input.action_press(a)
func release(a: String) -> void: Input.action_release(a)

func tp(f: Fighter, p: Vector3) -> void:
	f.global_position = p
	f.velocity = Vector3.ZERO
	f.reset_physics_interpolation()

func _physics_process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		p1 = arena.fighters[0]
		p2 = arena.fighters[1]
	match frame:
		30:
			check(p1.is_on_floor() and p2.is_on_floor(), "los dos empiezan en el suelo")
			mark.x = p1.global_position.x
			press("p1_right")
		60:
			release("p1_right")
			check(p1.global_position.x > mark.x + 2.0, "J1 corre hacia la derecha")
			check(p1.facing == 1, "J1 mira hacia donde corre")
		# --- golpe lateral cerca del rival ---
		70:
			tp(p1, Vector3(0, 0.05, 0)); tp(p2, Vector3(1.2, 0.05, 0))
			p1.facing = 1
		78:
			press("p1_right")
		80:
			press("p1_attack")
		84:
			release("p1_right"); release("p1_attack")
		110:
			check(p2.percent > 0.0, "el ataque lateral hace daño (%d%%)" % p2.percent)
			check(p2.global_position.x > 1.5, "el golpe empuja al rival")
		# --- más % = más empuje ---
		150:
			tp(p1, Vector3(0, 0.05, 0)); tp(p2, Vector3(1.2, 0.05, 0))
			p1.facing = 1; p2.percent = 0.0
			mark.kb_low = _kb()
			p2.percent = 120.0
			mark.kb_high = _kb()
			check(mark.kb_high > mark.kb_low * 2.0, "con 120%% sale volando mucho más (%.1f vs %.1f)" % [mark.kb_high, mark.kb_low])
			p2.percent = 0.0
		# --- salto doble ---
		170:
			tp(p1, Vector3(-2, 0.05, 0))
		180:
			press("p1_jump")
		181:
			release("p1_jump")
		195:
			press("p1_jump")
		197:
			release("p1_jump")
			mark.vy = p1.velocity.y
			check(mark.vy > 8.0, "J1 hace doble salto en el aire")
		# --- plataforma blanda: atravesar desde abajo y aterrizar ---
		240:
			tp(p2, Vector3(4.2, 1.5, 0))
			p2.velocity.y = 14.0
		300:
			check(p2.is_on_floor() and absf(p2.global_position.y - 3.2) < 0.2,
				"J2 atraviesa la plataforma desde abajo y se queda encima (y=%.2f)" % p2.global_position.y)
		310:
			press("p2_down")
		311:
			release("p2_down")
		340:
			check(p2.global_position.y < 3.0, "J2 baja de la plataforma con abajo")
		# --- KO y reaparición ---
		380:
			mark.stocks = p2.stocks
			tp(p2, Vector3(25, 2, 0))
		382:
			check(p2.stocks == mark.stocks - 1 and p2.is_out, "salir de la zona quita una vida")
		460:
			check(not p2.is_out and p2.invulnerable > 0.0 and p2.percent == 0.0,
				"reaparece con 0% e invulnerable")
		# --- escudo ---
		465:
			tp(p1, Vector3(0, 0.05, 0)); tp(p2, Vector3(1.0, 0.05, 0))
			p1.facing = 1; p2.invulnerable = 0.0; mark.pct = p2.percent
			press("p2_special")
		470:
			press("p1_attack")
		472:
			release("p1_attack")
		490:
			check(p2.shielding and p2.percent == mark.pct and p2.shield < 1.0,
				"el escudo para el golpe (sin daño, escudo gastado)")
			release("p2_special")
		# --- salir volando y caer tumbado ---
		500:
			tp(p2, Vector3(0, 2.5, 0)); p2.invulnerable = 0.0; p2.percent = 60.0
			p2.take_hit(Fighter.ATTACKS["side"], 1)
			p2.velocity = Vector3(0, -5, 0)
			check(p2._launched, "un golpe fuerte lanza al rival")
		540:
			check(p2.downed > 0.0, "al caer tras salir volando queda tumbado")
		640:
			check(p2.downed == 0.0 and p2.is_on_floor(), "se levanta y vuelve a poder moverse")
		# --- fin de partida ---
		650:
			p2.stocks = 1
			tp(p2, Vector3(0, -15, 0))
		655:
			check(arena.game_over, "al quedarse sin vidas termina la partida")
		660:
			check(p1.winner, "el ganador celebra")
			print("FALLOS: %d" % fails)
			quit(1 if fails else 0)
	return false

func _kb() -> float:
	var a: Dictionary = Fighter.ATTACKS["side"]
	return (a.base + (p2.percent + a.damage) * a.growth) / p2.weight
