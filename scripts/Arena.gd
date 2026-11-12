extends Node3D
## Escenario de combate: isla principal + plataformas blandas, dos jugadores,
## zonas de KO, reaparición y fin de partida. Todo se monta por código.

const FIGHTER := preload("res://scripts/Fighter.gd")
const ISLAND := "res://assets/models/island.glb"

## Fuera de estos límites el luchador pierde una vida.
@export var blast_zone := Rect2(-18.0, -10.0, 36.0, 26.0)
@export var main_width := 13.0
## Plataformas blandas: (x, y, ancho).
@export var platforms: Array[Vector3] = [
	Vector3(-4.2, 3.2, 3.6), Vector3(4.2, 3.2, 3.6), Vector3(0.0, 6.2, 3.6)]
@export var respawn_point := Vector3(0, 9, 0)
@export var respawn_delay := 1.0

var fighters: Array[Fighter] = []
var camera: Camera3D
var hud: Node
var game_over := false


func _ready() -> void:
	Inputs.set_solo(Game.mode == "cpu")
	_build_world()
	_build_stage()
	_spawn(1, Vector3(-3.5, 0.2, 0), 1, Color.WHITE)
	_spawn(2, Vector3(3.5, 0.2, 0), -1, Color(0.6, 0.75, 1.0))
	if Game.mode == "cpu":
		var cpu := fighters[1]
		cpu.brain = CpuBrain.new(cpu, Game.cpu_level, stage_half_width())
		cpu.display_name = "CPU · %s" % Game.LEVEL_NAMES[Game.cpu_level]
	camera = preload("res://scripts/FightCamera.gd").new()
	camera.position = Vector3(0, 3.4, 17)
	add_child(camera)
	hud = preload("res://scripts/HUD.gd").new()
	add_child(hud)
	hud.setup(fighters)


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
	sun.directional_shadow_max_distance = 50.0
	add_child(sun)
	# Islas de fondo, solo decorativas.
	for d in [Vector4(-22, 1, -45, 8), Vector4(20, 6, -55, 10), Vector4(-4, 12, -70, 9),
			Vector4(30, -4, -40, 6), Vector4(-36, 8, -65, 11)]:
		var deco := _island_visual(d.w, 1.0)
		deco.position = Vector3(d.x, d.y, d.z)
		deco.rotation.y = randf() * TAU
		add_child(deco)


func _build_stage() -> void:
	var main := StaticBody3D.new()
	main.collision_layer = Fighter.LAYER_GROUND
	main.add_child(_island_visual(main_width, 1.0))
	main.add_child(_box(Vector3(main_width * 0.82, 3.0, 4.0)))
	add_child(main)
	for p in platforms:
		var body := StaticBody3D.new()
		body.collision_layer = Fighter.LAYER_SOFT
		body.position = Vector3(p.x, p.y, 0)
		body.add_to_group("soft_platform")
		body.set_meta("top", p.y)
		body.set_meta("half_width", p.z * 0.5)
		var vis := _island_visual(p.z + 0.6, 0.45)
		body.add_child(vis)
		body.add_child(_box(Vector3(p.z, 0.3, 3.0)))
		add_child(body)


## Mitad del ancho de la parte pisable de la isla principal.
func stage_half_width() -> float:
	return main_width * 0.82 * 0.5


## Isla con el césped en y = 0. `flatten` aplasta la roca de abajo.
func _island_visual(width: float, flatten: float) -> Node3D:
	var pivot := Node3D.new()
	var model := ModelFit.load_fitted(ISLAND, width, true)
	if model:
		var raw: AABB = model.get_meta("raw_aabb")
		var s: float = model.get_meta("fit_scale")
		model.position.y -= raw.size.y * 0.92 * s
		pivot.add_child(model)
		pivot.scale.y = flatten
	return pivot


## Caja de colisión con la cara de arriba en y = 0.
func _box(size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position.y = -size.y * 0.5
	return cs


func _spawn(player: int, pos: Vector3, facing: int, tint: Color) -> void:
	var f: Fighter = FIGHTER.new()
	f.player = player
	f.display_name = "J%d · Trapo" % player
	f.facing = facing
	f.tint = tint
	f.position = pos
	add_child(f)
	f.damaged.connect(_on_damaged)
	fighters.append(f)


func _physics_process(_dt: float) -> void:
	for f in fighters:
		if f.is_out:
			continue
		var p := Vector2(f.global_position.x, f.global_position.y)
		if not blast_zone.has_point(p):
			_on_ko(f)


func _on_damaged(f: Fighter) -> void:
	hitstop(0.05 + minf(f.percent, 150.0) * 0.0006)
	if camera:
		camera.shake(0.2 + f.percent * 0.004)


func _on_ko(f: Fighter) -> void:
	if camera:
		camera.shake(1.2)
	if f.lose_stock():
		await get_tree().create_timer(respawn_delay).timeout
		f.respawn(respawn_point)
	_check_game_over()


func _check_game_over() -> void:
	var alive := fighters.filter(func(x): return x.stocks > 0)
	if alive.size() <= 1 and not game_over:
		game_over = true
		if alive.size() == 1:
			alive[0].celebrate()
		hud.show_winner(alive[0].display_name if alive.size() == 1 else "")


## Congela el juego un instante al golpear (da peso a los golpes).
func hitstop(duration: float) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		Game.start(Game.mode)
