class_name Fighter
extends CharacterBody3D
## Luchador estilo plataformas (Smash): se mueve en el plano XY (z = 0).
## Daño en %, el empuje crece con el %, se pierde una vida al salir de la zona.
## Usa las animaciones de Mixamo de <nombre>_rigged.glb (tools/build_fighter.gd); si no hay
## modelo riggeado, se anima por código (inclinación, estirar/aplastar, embestida).

signal damaged(fighter: Fighter)
signal knocked_out(fighter: Fighter)

const LAYER_GROUND := 1
const LAYER_SOFT := 2      ## plataformas que se atraviesan desde abajo
const LAYER_FIGHTER := 4

## Ataques: tiempos en segundos, ángulo en grados (0 = hacia delante, 90 = arriba),
## offset = centro del golpe respecto a los pies (x hacia donde mira).
## Empuje = base + % del rival × growth.
const ATTACKS := {
	"jab": {startup = 0.05, active = 0.08, recovery = 0.12, damage = 4.0,
		base = 4.0, growth = 0.05, angle = 30.0, offset = Vector2(0.7, 0.8), radius = 0.5},
	"side": {startup = 0.14, active = 0.1, recovery = 0.3, damage = 11.0,
		base = 8.0, growth = 0.2, angle = 35.0, offset = Vector2(0.85, 0.75), radius = 0.6},
	"up": {startup = 0.1, active = 0.12, recovery = 0.25, damage = 9.0,
		base = 7.0, growth = 0.17, angle = 85.0, offset = Vector2(0.15, 1.7), radius = 0.7},
	"down": {startup = 0.1, active = 0.1, recovery = 0.25, damage = 7.0,
		base = 6.0, growth = 0.12, angle = 20.0, offset = Vector2(0.7, 0.2), radius = 0.6},
	"air": {startup = 0.07, active = 0.15, recovery = 0.15, damage = 8.0,
		base = 6.0, growth = 0.13, angle = 40.0, offset = Vector2(0.6, 0.8), radius = 0.65},
	"air_up": {startup = 0.08, active = 0.12, recovery = 0.15, damage = 8.0,
		base = 6.0, growth = 0.14, angle = 80.0, offset = Vector2(0.1, 1.6), radius = 0.65},
	"air_down": {startup = 0.12, active = 0.1, recovery = 0.2, damage = 10.0,
		base = 6.0, growth = 0.12, angle = -70.0, offset = Vector2(0.1, -0.1), radius = 0.6},
}

## Animación de Mixamo de cada ataque: [clip, segundo del clip en que conecta el golpe].
## La velocidad se ajusta para que ese momento coincida con la parte activa del ataque.
const ATTACK_ANIM := {
	"jab": ["jab", 0.22], "side": ["hook", 0.33], "up": ["cross", 0.2], "down": ["kick", 0.42],
	"air": ["air_kick", 0.33], "air_up": ["air_kick", 0.33], "air_down": ["air_kick", 0.33],
}
const LOOPING := ["idle", "run", "fall", "block", "win"]
## Tras caer al suelo después de salir volando: tumbado y levantarse (segundos).
const KNOCKDOWN_TIME := 0.45
const GETUP_TIME := 0.9
## Empuje a partir del cual sales "volando" (y al caer quedas tumbado).
const LAUNCH_KB := 13.0

@export var player := 1
@export var display_name := "Trapo"
## Con animaciones de Mixamo (<nombre>_rigged.glb). Si no existe, usa el estático y
## la animación por código.
@export_file("*.glb") var model_path := "res://assets/models/trapo_rigged.glb"
@export_file("*.glb") var fallback_model := "res://assets/models/trapo.glb"
@export var model_height := 1.5
## Multiplica el color de la textura (para distinguir a dos luchadores iguales).
@export var tint := Color.WHITE
@export var facing := 1
@export var stocks := 3

@export_group("Movimiento")
@export var run_speed := 7.5
@export var ground_accel := 60.0
@export var air_speed := 6.0
@export var air_accel := 28.0
@export var gravity := 32.0
@export var max_fall := 15.0
@export var fast_fall := 24.0
@export var jump_velocity := 14.0
@export var air_jump_velocity := 13.5
## Duración de la voltereta del doble salto (segundos).
@export var flip_time := 0.45
@export var air_jumps := 1
## Más peso = sale volando menos.
@export var weight := 1.0

var percent := 0.0
var hitstun := 0.0
var invulnerable := 0.0
var is_out := false        ## sin vidas o esperando a reaparecer
var attack := ""
var attack_time := 0.0
## > 0 mientras está tumbado o levantándose (no se puede mover).
var downed := 0.0
var shielding := false
## Energía del escudo (0..1). Si llega a 0 se rompe y queda aturdido.
var shield := 1.0
var winner := false

var _launched := false
var _anim: AnimationPlayer
var _anim_key := ""
var _attack_serial := 0
var _hit_serial := 0

var _jumps_left := 0
var _fast_falling := false
var _drop_timer := 0.0
var _hit_list: Array[Fighter] = []
var _was_on_floor := false
var _pivot: Node3D           ## gira hacia donde mira
var _body: Node3D            ## estirar/aplastar y embestidas
var _squash := Vector3.ONE
var _flip := 0.0              ## tiempo que queda de voltereta (doble salto)
var _flash := 0.0
var _flash_material: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("fighter")
	collision_layer = LAYER_FIGHTER
	collision_mask = LAYER_GROUND | LAYER_SOFT
	floor_snap_length = 0.2
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = model_height
	shape.shape = capsule
	shape.position.y = model_height / 2.0
	add_child(shape)
	_build_visual()


func _build_visual() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_body = Node3D.new()
	_pivot.add_child(_body)
	var model := ModelFit.load_fitted(model_path, model_height, false, 0.0, 0.9)
	if model == null:
		model = ModelFit.load_fitted(fallback_model, model_height, false, 0.0, 0.9)
	if model:
		var players := model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty() and (players[0] as AnimationPlayer).has_animation("idle"):
			_anim = players[0]
			# glTF no guarda si una animación es un bucle.
			for a in LOOPING:
				if _anim.has_animation(a):
					_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	if model == null:
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.4
		cap.height = model_height
		mi.mesh = cap
		mi.position.y = model_height / 2.0
		model = mi
	_body.add_child(model)
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = Color(1, 1, 1, 0)
	ModelFit.for_each_mesh(model, func(mi: MeshInstance3D):
		_meshes.append(mi)
		mi.material_overlay = _flash_material
		if tint != Color.WHITE:
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
				if m:
					var copy := m.duplicate() as BaseMaterial3D
					copy.albedo_color = m.albedo_color * tint
					mi.set_surface_override_material(i, copy))
	_pivot.rotation.y = _facing_angle()


## Si tiene cerebro, lo controla la CPU; si no, el teclado/mando del jugador `player`.
var brain: CpuBrain


func act(name: String) -> String:
	return "p%d_%s" % [player, name]


func _axis() -> float:
	return brain.axis() if brain else Input.get_axis(act("left"), act("right"))


func _p(name: String) -> bool:
	return brain.pressed(name) if brain else Input.is_action_pressed(act(name))


func _jp(name: String) -> bool:
	return brain.just_pressed(name) if brain else Input.is_action_just_pressed(act(name))


func _jr(name: String) -> bool:
	return brain.just_released(name) if brain else Input.is_action_just_released(act(name))


func _physics_process(dt: float) -> void:
	if is_out:
		return
	if brain:
		brain.update(dt)
	invulnerable = maxf(invulnerable - dt, 0.0)
	_drop_timer = maxf(_drop_timer - dt, 0.0)
	var on_floor := is_on_floor()
	if on_floor:
		_jumps_left = air_jumps
		_fast_falling = false

	if not shielding:
		shield = minf(shield + dt * 0.15, 1.0)
	if downed > 0.0:
		_update_downed(dt, on_floor)
	elif hitstun > 0.0:
		_update_hitstun(dt)
	else:
		_update_control(dt, on_floor)
	_update_attack(dt)
	_update_soft_platforms()

	move_and_slide()
	position.z = 0.0
	velocity.z = 0.0

	if is_on_floor() and not _was_on_floor:
		if _launched:
			# Cae al suelo tras salir volando: queda tumbado y se levanta.
			_launched = false
			hitstun = 0.0
			downed = KNOCKDOWN_TIME + GETUP_TIME
			velocity = Vector3.ZERO
		else:
			_squash = Vector3(1.25, 0.75, 1.25)
		_flip = 0.0
		if attack.begins_with("air"):
			_end_attack()
	_was_on_floor = is_on_floor()


func _update_downed(dt: float, on_floor: bool) -> void:
	downed = maxf(downed - dt, 0.0)
	# Invulnerable mientras se levanta (como en Smash).
	if downed < GETUP_TIME:
		invulnerable = maxf(invulnerable, 0.05)
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * dt)
	if not on_floor:
		velocity.y = maxf(velocity.y - gravity * dt, -max_fall)


func _update_control(dt: float, on_floor: bool) -> void:
	var ix := _axis()
	var attacking := attack != ""
	if winner:
		velocity.x = move_toward(velocity.x, 0.0, ground_accel * dt)
		if not on_floor:
			velocity.y = maxf(velocity.y - gravity * dt, -max_fall)
		return

	# Escudo: mantener el especial en el suelo. Se gasta mientras lo sostienes.
	shielding = on_floor and not attacking and _p("special")
	if shielding:
		shield = maxf(shield - dt * 0.3, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, ground_accel * dt)
		if shield <= 0.0:
			_break_shield()
		return

	# Si haces algo después de salir volando, ya no caes tumbado.
	if _launched and (absf(ix) > 0.3 or _jp("jump") \
			or _jp("attack")):
		_launched = false
	var target := ix * (run_speed if on_floor else air_speed)
	if attacking and on_floor:
		target = 0.0
	var accel := ground_accel if on_floor else air_accel
	velocity.x = move_toward(velocity.x, target, accel * dt)
	if on_floor and not attacking and absf(ix) > 0.3:
		facing = 1 if ix > 0.0 else -1

	if _jp("jump") and not attacking:
		if on_floor:
			velocity.y = jump_velocity
			_squash = Vector3(0.8, 1.25, 0.8)
		elif _jumps_left > 0:
			_jumps_left -= 1
			velocity.y = air_jump_velocity
			velocity.x = ix * air_speed
			_fast_falling = false
			_flip = flip_time
	# Salto corto si sueltas pronto.
	if _jr("jump") and velocity.y > 0.0:
		velocity.y *= 0.55

	if on_floor and _jp("down") and _standing_on_soft():
		_drop_timer = 0.3
		position.y -= 0.05

	if not on_floor:
		if _jp("down") and velocity.y < 3.0 and not attacking:
			_fast_falling = true
		velocity.y -= gravity * dt
		velocity.y = maxf(velocity.y, -max_fall)
		if _fast_falling:
			velocity.y = -fast_fall

	if _jp("attack") and not attacking:
		_start_attack(on_floor, ix)


func _update_hitstun(dt: float) -> void:
	hitstun -= dt
	velocity.y -= gravity * dt
	# Frenado del empuje para que no sea un tiro parabólico puro.
	var drag := exp(-1.4 * dt)
	velocity.x *= drag
	if velocity.y > 0.0:
		velocity.y *= drag


func _start_attack(on_floor: bool, ix: float) -> void:
	var up := _p("up")
	var down := _p("down")
	if on_floor:
		if up:
			attack = "up"
		elif down:
			attack = "down"
		elif absf(ix) > 0.3:
			facing = 1 if ix > 0.0 else -1
			attack = "side"
		else:
			attack = "jab"
	else:
		attack = "air_up" if up else ("air_down" if down else "air")
	attack_time = 0.0
	_attack_serial += 1
	_flip = 0.0
	_hit_list.clear()


func _update_attack(dt: float) -> void:
	if attack == "":
		return
	attack_time += dt
	var a: Dictionary = ATTACKS[attack]
	if attack_time >= a.startup and attack_time < a.startup + a.active:
		_check_hits(a)
	if attack_time >= a.startup + a.active + a.recovery:
		_end_attack()


func _end_attack() -> void:
	attack = ""
	attack_time = 0.0


## Centro del golpe del ataque `a` en coordenadas globales.
func hit_center(a: Dictionary) -> Vector3:
	return global_position + Vector3(a.offset.x * facing, a.offset.y, 0.0)


func _check_hits(a: Dictionary) -> void:
	var c := hit_center(a)
	for node in get_tree().get_nodes_in_group("fighter"):
		var f := node as Fighter
		if f == self or f.is_out or f.invulnerable > 0.0 or _hit_list.has(f):
			continue
		var body_center := f.global_position + Vector3(0.0, f.model_height * 0.5, 0.0)
		if body_center.distance_to(c) <= a.radius + 0.5:
			_hit_list.append(f)
			f.take_hit(a, facing)


func take_hit(a: Dictionary, dir: int) -> void:
	if shielding:
		# El escudo para el golpe: solo empuja un poco y se gasta.
		shield -= 0.08 + a.damage * 0.03
		velocity.x = dir * (2.0 + a.damage * 0.25)
		_flash = 0.4
		if shield <= 0.0:
			_break_shield()
		return
	percent = minf(percent + a.damage, 999.0)
	var kb: float = (a.base + percent * a.growth) / weight
	var ang := deg_to_rad(a.angle)
	velocity = Vector3(cos(ang) * dir * kb, sin(ang) * kb, 0.0)
	hitstun = maxf(kb * 0.03, 0.15)
	_launched = kb >= LAUNCH_KB
	downed = 0.0
	facing = -dir
	_fast_falling = false
	_end_attack()
	_hit_serial += 1
	_flip = 0.0
	_flash = 1.0
	damaged.emit(self)


## Escudo roto: aturdido un rato, sin poder hacer nada.
func _break_shield() -> void:
	shielding = false
	shield = 0.35
	hitstun = 1.6
	velocity.y = 8.0
	_hit_serial += 1


## Las plataformas blandas solo cuentan cuando caes y tus pies están por encima.
func _update_soft_platforms() -> void:
	var solid := velocity.y <= 0.0 and _drop_timer <= 0.0
	if solid:
		for p in get_tree().get_nodes_in_group("soft_platform"):
			var top: float = p.get_meta("top")
			var half: float = p.get_meta("half_width")
			if absf(global_position.x - p.global_position.x) <= half + 0.4 \
					and global_position.y < top - 0.1:
				solid = false
				break
	set_collision_mask_value(2, solid)


func _standing_on_soft() -> bool:
	for p in get_tree().get_nodes_in_group("soft_platform"):
		if absf(global_position.x - p.global_position.x) <= p.get_meta("half_width") + 0.4 \
				and absf(global_position.y - p.get_meta("top")) < 0.15:
			return true
	return false


## Pierde una vida. Devuelve true si aún le quedan.
func lose_stock() -> bool:
	stocks -= 1
	is_out = true
	visible = false
	velocity = Vector3.ZERO
	hitstun = 0.0
	downed = 0.0
	shielding = false
	_launched = false
	_end_attack()
	knocked_out.emit(self)
	return stocks > 0


func respawn(at: Vector3) -> void:
	global_position = at
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	percent = 0.0
	shield = 1.0
	is_out = false
	visible = true
	invulnerable = 2.0
	_jumps_left = air_jumps


func celebrate() -> void:
	winner = true
	_end_attack()


# --- Visual ------------------------------------------------------------------

func _facing_angle() -> float:
	# Girado 3/4 hacia la cámara para que se le vea la cara.
	return facing * PI * 0.5 * 0.7


func _process(dt: float) -> void:
	if _pivot == null:
		return
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, _facing_angle(), 1.0 - exp(-18.0 * dt))
	_squash = _squash.lerp(Vector3.ONE, 1.0 - exp(-12.0 * dt))
	var offset := Vector3.ZERO
	var rot := Vector3.ZERO
	var stretch := Vector3.ONE
	if _anim:
		_update_animation()
		# Con animaciones de verdad, el estirar/aplastar se deja suave.
		_squash = _squash.lerp(Vector3.ONE, 0.5)
	else:
		_procedural_pose()
		offset = _proc_offset
		rot = _proc_rot
		stretch = _proc_stretch
	if hitstun > 0.0:
		offset.x += randf_range(-0.04, 0.04)
	if _flip > 0.0:
		# Voltereta hacia delante: una vuelta completa, rápida al principio y frenando al final.
		_flip = maxf(_flip - dt, 0.0)
		var k := 1.0 - _flip / flip_time
		rot.x += TAU * (1.0 - pow(1.0 - k, 2.0))
	# Girar alrededor del centro del cuerpo (no de los pies).
	var center := Vector3(0.0, model_height * 0.5, 0.0)
	_body.position = offset + center - Basis.from_euler(rot) * center
	_body.rotation = rot
	_body.scale = _squash * stretch
	# Parpadeo blanco al recibir golpe (azulado si lo para el escudo).
	_flash = maxf(_flash - dt * 6.0, 0.0)
	_flash_material.albedo_color = Color(0.6, 0.85, 1.0, _flash * 0.7) if shielding \
		else Color(1, 1, 1, _flash * 0.85)
	if invulnerable > 0.0 and not is_out and downed <= 0.0:
		_body.visible = int(invulnerable * 12.0) % 2 == 0
	else:
		_body.visible = true


## Elige la animación de Mixamo según el estado.
func _update_animation() -> void:
	var want := "idle"
	var speed := 1.0
	var key := ""
	if downed > 0.0:
		if downed > GETUP_TIME:
			want = "knockdown"
			speed = _anim.get_animation("knockdown").length / KNOCKDOWN_TIME
		else:
			want = "getup"
			speed = _anim.get_animation("getup").length / GETUP_TIME
	elif hitstun > 0.0:
		want = "hurt"
		speed = 1.6
		key = str(_hit_serial)
	elif attack != "":
		var info: Array = ATTACK_ANIM[attack]
		var a: Dictionary = ATTACKS[attack]
		want = info[0]
		speed = info[1] / (a.startup + a.active * 0.5)
		key = str(_attack_serial)
	elif shielding:
		want = "block"
	elif winner:
		want = "win"
	elif not is_on_floor():
		want = "jump" if velocity.y > 2.0 else "fall"
	elif absf(velocity.x) > 0.6:
		want = "run"
		speed = clampf(absf(velocity.x) / run_speed * 1.15, 0.6, 1.3)
	key = want + key
	if key != _anim_key:
		_anim_key = key
		var blend := 0.04 if want in ["jab", "cross", "hook", "kick", "air_kick", "hurt"] else 0.12
		_anim.play(want, blend, speed)
		# Repetir el mismo ataque (o recibir otro golpe) empieza desde el principio.
		_anim.seek(0.0, true)
	elif want == "run":
		_anim.play(want, -1, speed)


# --- Animación provisional por código (si no hay modelo riggeado) ------------

var _proc_offset := Vector3.ZERO
var _proc_rot := Vector3.ZERO
var _proc_stretch := Vector3.ONE


func _procedural_pose() -> void:
	var lean := -velocity.x / maxf(run_speed, 0.1) * 0.18 if is_on_floor() else 0.0
	_proc_offset = Vector3.ZERO
	_proc_rot = Vector3(0.0, 0.0, lean)
	_proc_stretch = Vector3.ONE
	if downed > 0.0:
		_proc_rot.x = -1.4 * clampf(downed / GETUP_TIME, 0.0, 1.0)
	if attack != "":
		var a: Dictionary = ATTACKS[attack]
		var k := clampf((attack_time - a.startup * 0.5) / (a.startup + a.active), 0.0, 1.0)
		var punch := sin(k * PI)
		match attack:
			"up", "air_up":
				_proc_stretch = Vector3(1.0 - 0.15 * punch, 1.0 + 0.3 * punch, 1.0 - 0.15 * punch)
			"down":
				_proc_stretch = Vector3(1.0 + 0.25 * punch, 1.0 - 0.3 * punch, 1.0 + 0.25 * punch)
			"air_down":
				_proc_offset.y = -0.25 * punch
			_:
				_proc_offset.z = 0.35 * punch
				_proc_rot.x = 0.25 * punch
	if hitstun > 0.0:
		_proc_rot.z += sin(Time.get_ticks_msec() * 0.04) * 0.25
