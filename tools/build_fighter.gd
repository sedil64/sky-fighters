extends SceneTree
## Junta un luchador riggeado en Mixamo y sus animaciones en assets/models/<nombre>_rigged.glb.
##   godot --headless --path . --script res://tools/build_fighter.gd -- trapo
## Entrada: los FBX de Mixamo (con piel) en assets/models_raw/<nombre>_anims/.
## Todos los luchadores usan los mismos clips de Mixamo, así que la tabla CLIPS sirve para todos.
## Limpia las animaciones: recorta la parte útil y quita el avance de la cadera
## (al personaje lo mueve la física, no la animación).

const HIPS := "Skeleton3D:mixamorig_Hips"

## nombre en el juego: [archivo, bucle, desde (s), hasta (s, -1 = final), modo de la cadera]
## modo de la cadera: "" = tal cual, "flat_xz" = sin avance, "no_rise" = sin avance ni subir
## por encima del reposo, "flat" = sin avance y a la altura de reposo (pose en el aire).
const CLIPS := {
	"idle": ["BouncingFightIdle", true, 0.0, -1.0, "flat_xz"],
	"run": ["Running", true, 0.0, -1.0, "flat_xz"],
	"jump": ["Jumping", false, 0.25, 0.75, "no_rise"],
	"fall": ["Falling Idle", true, 0.0, -1.0, "flat_xz"],
	"jab": ["Body Jab Cross", false, 0.15, 0.6, "flat_xz"],
	"cross": ["Body Jab Cross", false, 0.4, 0.95, "flat_xz"],
	"hook": ["Right Hook", false, 0.0, 0.75, "flat_xz"],
	"kick": ["Mma Kick", false, 0.25, 1.2, "flat_xz"],
	"air_kick": ["Flying Kick", false, 0.1, 0.9, "flat"],
	"block": ["Body Block", true, 0.0, -1.0, "flat_xz"],
	"hurt": ["Hit Reaction", false, 0.3, 1.3, "flat_xz"],
	"knockdown": ["Knocked Down", false, 0.8, 1.5, "flat_xz"],
	"getup": ["Getting Up", false, 2.4, 6.0, "flat_xz"],
	"win": ["Victory Idle", true, 0.0, -1.0, "flat_xz"],
}

var src_dir := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var who: String = args[0] if args.size() > 0 else "trapo"
	src_dir = "res://assets/models_raw/%s_anims/" % who
	var dst := "res://assets/models/%s_rigged.glb" % who

	var base: Node3D = _load_fbx(CLIPS.idle[0])
	base.name = who.capitalize()
	var player := base.get_node("AnimationPlayer") as AnimationPlayer
	for lib in player.get_animation_library_list():
		player.remove_animation_library(lib)
	var library := AnimationLibrary.new()
	var rest := Vector3.ZERO
	var cache := {}
	for clip_name in CLIPS:
		var c: Array = CLIPS[clip_name]
		if not cache.has(c[0]):
			var scene: Node = _load_fbx(c[0])
			cache[c[0]] = (scene.get_node("AnimationPlayer") as AnimationPlayer).get_animation("mixamo_com").duplicate()
			scene.free()
		var anim := _cut(cache[c[0]], c[2], c[3])
		anim.loop_mode = Animation.LOOP_LINEAR if c[1] else Animation.LOOP_NONE
		if clip_name == "idle":
			rest = _hips_value(anim, 0)
		_fix_hips(anim, c[4], rest)
		library.add_animation(clip_name, anim)
		var h0 := _hips_value(anim, 0) - rest
		print("%-9s <- %-18s %.2f s  cadera inicial respecto al reposo (%.3f, %.3f)" % [clip_name, c[0], anim.length, h0.x, h0.z])
	player.add_animation_library("", library)

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(base, state)
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(dst))
	print("guardado " + dst if err == OK else "ERROR %d" % err)
	base.free()
	quit(0 if err == OK else 1)


## Carga un FBX sin pasar por el importador (la carpeta de origen tiene .gdignore).
func _load_fbx(file: String) -> Node3D:
	var doc := FBXDocument.new()
	var state := FBXState.new()
	var path := ProjectSettings.globalize_path(src_dir + file + ".fbx")
	var err := doc.append_from_file(path, state)
	assert(err == OK, "no se pudo leer " + path)
	return doc.generate_scene(state)


## Copia el tramo [from, to] de la animación, empezando en t = 0.
func _cut(src: Animation, from: float, to: float) -> Animation:
	if to < 0.0:
		to = src.length
	to = minf(to, src.length)
	var a := Animation.new()
	a.length = to - from
	for t in src.get_track_count():
		var nt := a.add_track(src.track_get_type(t))
		a.track_set_path(nt, src.track_get_path(t))
		a.track_set_interpolation_type(nt, src.track_get_interpolation_type(t))
		# Clave al inicio y al final exactos (interpoladas), y las de en medio tal cual.
		a.track_insert_key(nt, 0.0, _sample(src, t, from))
		for k in src.track_get_key_count(t):
			var kt := src.track_get_key_time(t, k)
			if kt > from + 0.001 and kt < to - 0.001:
				a.track_insert_key(nt, kt - from, src.track_get_key_value(t, k))
		a.track_insert_key(nt, a.length, _sample(src, t, to))
	return a


func _sample(a: Animation, t: int, time: float) -> Variant:
	match a.track_get_type(t):
		Animation.TYPE_POSITION_3D: return a.position_track_interpolate(t, time)
		Animation.TYPE_ROTATION_3D: return a.rotation_track_interpolate(t, time)
		Animation.TYPE_SCALE_3D: return a.scale_track_interpolate(t, time)
	return a.value_track_interpolate(t, time)


func _hips_value(a: Animation, key: int) -> Vector3:
	return a.track_get_key_value(a.find_track(NodePath(HIPS), Animation.TYPE_POSITION_3D), key)


## Deja la cadera centrada sobre el personaje (en la x/z de reposo de "idle"), quitando
## el avance y también el desplazamiento con el que empiece el clip.
func _fix_hips(a: Animation, mode: String, rest: Vector3) -> void:
	var t := a.find_track(NodePath(HIPS), Animation.TYPE_POSITION_3D)
	if t < 0 or mode == "":
		return
	var n := a.track_get_key_count(t)
	var first: Vector3 = a.track_get_key_value(t, 0)
	var last: Vector3 = a.track_get_key_value(t, n - 1)
	for k in n:
		var v: Vector3 = a.track_get_key_value(t, k)
		var f := a.track_get_key_time(t, k) / a.length
		var drift := first.lerp(last, f)
		v.x += rest.x - drift.x
		v.z += rest.z - drift.z
		if mode == "flat":
			v = rest
		elif mode == "no_rise":
			v.y = minf(v.y, rest.y)
		a.track_set_key_value(t, k, v)
