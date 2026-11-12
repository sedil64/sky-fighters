class_name CpuBrain
extends RefCounted
## "Mando virtual" de la CPU. Cada cierto tiempo (su tiempo de reacción) decide qué hacer
## y pulsa los mismos botones que un jugador (left/right, up, down, jump, attack, special),
## así que juega con exactamente las mismas reglas.
## Fighter le pregunta con pressed() / just_pressed() / just_released() / axis().

## Parámetros por dificultad:
##  reaction  = segundos entre decisiones (más bajo = reacciona antes)
##  aggression = probabilidad de atacar cuando está a tiro
##  shield    = probabilidad de cubrirse si el rival ataca de cerca
##  recover   = probabilidad de intentar volver al escenario si se cae
##  air       = probabilidad de usar ataques aéreos / perseguir en el aire
##  focus     = 1 = siempre va a por ti; menos = a veces se queda dudando
##  smart     = elige el ataque según el % (remata con los fuertes)
const LEVELS := [
	{reaction = 0.45, aggression = 0.45, shield = 0.0, recover = 0.6, air = 0.15, focus = 0.7, smart = false},
	{reaction = 0.25, aggression = 0.6, shield = 0.3, recover = 0.95, air = 0.45, focus = 0.85, smart = false},
	{reaction = 0.1, aggression = 0.85, shield = 0.6, recover = 1.0, air = 0.75, focus = 1.0, smart = true},
]

var me: Fighter
var level: Dictionary
## Mitad del ancho del escenario principal (desde el centro hasta el borde).
var stage_half := 5.3

var _hold := {}        ## acción -> segundos que sigue pulsada
var _cur := {}
var _prev := {}
var _move := 0.0
var _think := 0.0
var _was_off := false
var _will_recover := true


func _init(fighter: Fighter, difficulty: int, half_width: float) -> void:
	me = fighter
	level = LEVELS[clampi(difficulty, 0, LEVELS.size() - 1)]
	stage_half = half_width
	_think = randf_range(0.3, 0.6)


func pressed(action: String) -> bool:
	return _cur.has(action)


func just_pressed(action: String) -> bool:
	return _cur.has(action) and not _prev.has(action)


func just_released(action: String) -> bool:
	return _prev.has(action) and not _cur.has(action)


func axis() -> float:
	return _move


## Se llama una vez por fotograma de física, antes de que el luchador lea los botones.
func update(dt: float) -> void:
	_prev = _cur
	for k in _hold.keys():
		_hold[k] -= dt
		if _hold[k] < 0.0:
			_hold.erase(k)
	_think -= dt
	if _think <= 0.0:
		_think = level.reaction * randf_range(0.7, 1.3)
		_decide()
	_steer()
	_cur = {}
	for k in _hold:
		_cur[k] = true


## Pulsa `action` durante `time` segundos (0 = un solo fotograma).
func press(action: String, time := 0.0) -> void:
	if not _hold.has(action):
		_hold[action] = time


func _target() -> Fighter:
	var best: Fighter = null
	var best_d := INF
	for node in me.get_tree().get_nodes_in_group("fighter"):
		var f := node as Fighter
		if f == me or f.is_out:
			continue
		var d := f.global_position.distance_to(me.global_position)
		if d < best_d:
			best_d = d
			best = f
	return best


func _is_off_stage() -> bool:
	var p := me.global_position
	return absf(p.x) > stage_half - 0.1 or p.y < -0.4


## Decisión táctica (cada `reaction` segundos).
func _decide() -> void:
	if me.hitstun > 0.0 or me.downed > 0.0 or me.winner or _is_off_stage():
		return
	var t := _target()
	if t == null:
		_move = 0.0
		return
	var d := t.global_position - me.global_position
	var dist := absf(d.x)
	var dir := signf(d.x) if d.x != 0.0 else float(me.facing)
	var on_floor := me.is_on_floor()

	# A veces duda (sobre todo en fácil).
	if randf() > level.focus:
		_move = 0.0 if randf() < 0.6 else -dir * 0.6
		return

	# Cubrirse si el rival está atacando de cerca.
	if on_floor and t.attack != "" and dist < 2.4 and absf(d.y) < 1.6 \
			and randf() < level.shield:
		_move = 0.0
		press("special", 0.3)
		return

	var close := dist < 1.5 and absf(d.y) < 1.3
	if close and randf() < level.aggression:
		_attack(t, d, dir, on_floor)
		return
	if not on_floor and dist < 1.9 and absf(d.y) < 1.6 and randf() < level.air:
		_attack(t, d, dir, on_floor)
		return
	# El rival está encima (en una plataforma o saltando): salta a por él.
	if on_floor and d.y > 1.8 and dist < 3.0 and randf() < 0.3 + level.air:
		press("jump", 0.25)
		_move = dir * 0.6
		return
	# El rival está debajo en una plataforma: bajar.
	if on_floor and d.y < -1.5 and dist < 2.5 and me.global_position.y > 1.0:
		press("down")
		return
	# Acercarse (sin pasar del borde, eso lo controla _steer).
	_move = dir if not close else 0.0


func _attack(t: Fighter, d: Vector3, dir: float, on_floor: bool) -> void:
	if not on_floor:
		_move = dir * 0.5
		if d.y < -0.8:
			press("down", 0.1)
		elif d.y > 0.8:
			press("up", 0.1)
		press("attack")
		return
	if d.y > 0.9:
		press("up", 0.1)
		_move = 0.0
		press("attack")
		return
	var strong: bool = level.smart and t.percent > 80.0
	var r := randf()
	if strong or r < 0.4:
		_move = dir          # ataque lateral (se gira hacia el rival)
	elif r < 0.75 and int(signf(dir)) == me.facing:
		_move = 0.0          # jab (solo si ya le mira)
	else:
		_move = 0.0
		press("down", 0.1)   # patada baja
		if int(signf(dir)) != me.facing:
			_move = dir
	press("attack")


## Reflejos de cada fotograma: volver al escenario y no tirarse por el borde.
func _steer() -> void:
	if me.hitstun > 0.0 or me.downed > 0.0:
		_move = 0.0
		_was_off = false
		return
	var p := me.global_position
	var off := _is_off_stage()
	if off and not _was_off:
		_will_recover = randf() < level.recover
	_was_off = off
	if off:
		if not _will_recover:
			_move = 0.0
			return
		_move = -signf(p.x)
		_hold.erase("down")
		_hold.erase("special")
		# Doble salto cuando está cayendo por debajo del borde.
		if p.y < 0.5 and me.velocity.y < 1.0 and me._jumps_left > 0 and not _hold.has("jump"):
			press("jump", 0.3)
		return
	# En el suelo, no caminar fuera del borde.
	if me.is_on_floor() and absf(p.x) > stage_half - 0.7 and signf(_move) == signf(p.x):
		_move = 0.0
