extends Camera3D
## Cámara lateral que encuadra a todos los luchadores (se acerca y aleja
## según lo separados que estén), con límites para no enseñar el vacío de más.

@export var min_distance := 17.0
@export var max_distance := 28.0
@export var padding := 5.0
@export var height_offset := 3.4
@export var pitch := -0.12
@export var limit_x := 9.0
@export var limit_y := Vector2(3.0, 9.0)
@export var smooth := 4.0

var _shake := 0.0


func _ready() -> void:
	# Se mueve en _process (suavizado propio), no en la física.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	rotation.x = pitch
	fov = 40.0


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(dt: float) -> void:
	var pts: Array[Vector3] = []
	for f in get_tree().get_nodes_in_group("fighter"):
		if not f.is_out:
			pts.append(f.global_position)
	if pts.is_empty():
		return
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var center := (lo + hi) * 0.5
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var spread := maxf((hi.x - lo.x) / maxf(aspect, 0.5), hi.y - lo.y) + padding
	# Distancia para que `spread` quepa en vertical con este FOV.
	var dist := clampf(spread * 0.5 / tan(deg_to_rad(fov) * 0.5), min_distance, max_distance)
	var target := Vector3(
		clampf(center.x, -limit_x, limit_x),
		clampf(center.y + height_offset, limit_y.x, limit_y.y),
		dist)
	global_position = global_position.lerp(target, 1.0 - exp(-smooth * dt))
	if _shake > 0.0:
		global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.3
		_shake = maxf(_shake - dt * 3.0, 0.0)
