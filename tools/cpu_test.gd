extends SceneTree
## Prueba de la CPU en las tres dificultades contra un jugador que no hace nada:
##   godot --headless --path . --script res://tools/cpu_test.gd
## Comprueba que se acerca, que pega, que no se tira sola del escenario y que la
## difícil hace más daño que la fácil en el mismo tiempo.
const SECONDS := 25.0
var game: Node
var arena: Node
var level := 0
var t := 0.0
var fails := 0
var results := []
var min_dist := INF
var dealt := 0.0
var last_pct := 0.0

func _initialize() -> void:
	game = root.get_node("Game")
	_start()

func _start() -> void:
	if arena:
		arena.queue_free()
	game.mode = "cpu"
	game.cpu_level = level
	arena = load("res://scenes/Arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	t = 0.0
	min_dist = INF
	dealt = 0.0
	last_pct = 0.0

func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond: fails += 1

func _physics_process(dt: float) -> bool:
	if arena == null or arena.fighters.size() < 2:
		return false
	var me: Fighter = arena.fighters[0]
	var cpu: Fighter = arena.fighters[1]
	# Suma cada golpe recibido (el % baja al reaparecer o al recolocarlo).
	if me.percent > last_pct:
		dealt += me.percent - last_pct
	# El jugador no se mueve, pero si sale volando vuelve al centro (para medir solo a la CPU).
	me.invulnerable = 0.0 if me.downed <= 0.0 else me.invulnerable
	if not me.is_out and (absf(me.global_position.x) > 4.0 or me.global_position.y < -1.0):
		me.global_position = Vector3(0, 0.3, 0); me.velocity = Vector3.ZERO; me.hitstun = 0.0
		me.stocks = 3
	last_pct = me.percent
	if not cpu.is_out:
		min_dist = minf(min_dist, cpu.global_position.distance_to(me.global_position))
	t += dt
	if t >= SECONDS:
		var name: String = game.LEVEL_NAMES[level]
		check(min_dist < 1.6, "%s: la CPU se acerca al jugador (dist. mínima %.1f)" % [name, min_dist])
		check(cpu.stocks == 3, "%s: la CPU no se cae sola (vidas %d)" % [name, cpu.stocks])
		check(cpu.brain != null and cpu.display_name.contains(name), "%s: el rival es la CPU '%s'" % [name, cpu.display_name])
		results.append(dealt)
		print("     daño hecho en %d s: %d%%" % [SECONDS, dealt])
		level += 1
		if level < 3:
			_start()
		else:
			check(results[0] > 0.0, "fácil: también pega (aunque poco)")
			check(results[2] > results[0], "difícil hace más daño que fácil (%d%% vs %d%%)" % [results[2], results[0]])
			print("FALLOS: %d" % fails)
			quit(1 if fails else 0)
	return false
