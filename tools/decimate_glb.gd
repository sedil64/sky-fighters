extends SceneTree
## Reduce los triángulos de un .glb usando el simplificador de Godot (meshoptimizer).
## Uso:
##   godot --headless --path . --script res://tools/decimate_glb.gd -- entrada.glb salida.glb TRIANGULOS
## Las rutas son del sistema de archivos (no res://). Pasa primero el modelo
## por tools/fix_glb.py para que tenga normales correctas.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		printerr("Uso: -- entrada.glb salida.glb TRIANGULOS")
		quit(1)
		return
	var src := args[0]
	var dst := args[1]
	var target_tris := int(args[2])

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(src, state) != OK:
		printerr("No se pudo leer ", src)
		quit(1)
		return

	# 1) Genera los LOD sobre los ImporterMesh y elige el más cercano al objetivo.
	var chosen := {}  # índice de malla glTF -> PackedInt32Array
	var gmeshes := state.get_meshes()
	for mi in gmeshes.size():
		var im: ImporterMesh = gmeshes[mi].mesh
		var base: PackedInt32Array = im.get_surface_arrays(0)[Mesh.ARRAY_INDEX]
		im.generate_lods(60.0, 60.0, [])
		var best := base
		for l in im.get_surface_lod_count(0):
			var idx := im.get_surface_lod_indices(0, l)
			if absi(idx.size() / 3 - target_tris) < absi(best.size() / 3 - target_tris):
				best = idx
		chosen[mi] = best
		print("  %s: %d -> %d triángulos (LOD disponibles: %s)" % [src.get_file(), base.size() / 3,
			best.size() / 3, range(im.get_surface_lod_count(0)).map(
				func(l): return im.get_surface_lod_indices(0, l).size() / 3)])

	# 2) Genera la escena y sustituye cada malla por la versión simplificada y compactada.
	var root := doc.generate_scene(state)
	var mesh_index := 0
	for node in _all_mesh_instances(root):
		var old: ArrayMesh = node.mesh
		var arrays := old.surface_get_arrays(0)
		var indices: PackedInt32Array = chosen.get(mesh_index, arrays[Mesh.ARRAY_INDEX])
		mesh_index += 1
		var new_mesh := ArrayMesh.new()
		new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _compact(arrays, indices))
		new_mesh.surface_set_material(0, old.surface_get_material(0))
		node.mesh = new_mesh

	# 3) Exporta a .glb.
	var out_doc := GLTFDocument.new()
	var out_state := GLTFState.new()
	out_doc.append_from_scene(root, out_state)
	var err := out_doc.write_to_filesystem(out_state, dst)
	print("  guardado ", dst, " (", "OK" if err == OK else "ERROR %d" % err, ")")
	root.free()
	quit(0 if err == OK else 1)


## Quita los vértices que ya no usa ningún triángulo.
func _compact(arrays: Array, indices: PackedInt32Array) -> Array:
	var remap := {}
	var new_idx := PackedInt32Array()
	new_idx.resize(indices.size())
	for i in indices.size():
		var v := indices[i]
		if not remap.has(v):
			remap[v] = remap.size()
		new_idx[i] = remap[v]
	var order := PackedInt32Array()
	order.resize(remap.size())
	for old_v in remap:
		order[remap[old_v]] = old_v
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for a in Mesh.ARRAY_MAX:
		var src = arrays[a]
		if src == null or a == Mesh.ARRAY_INDEX:
			continue
		var per_vertex: int = src.size() / arrays[Mesh.ARRAY_VERTEX].size()
		var dst = src.duplicate()
		dst.resize(order.size() * per_vertex)
		for i in order.size():
			for k in per_vertex:
				dst[i * per_vertex + k] = src[order[i] * per_vertex + k]
		out[a] = dst
	out[Mesh.ARRAY_INDEX] = new_idx
	return out


func _all_mesh_instances(n: Node) -> Array:
	var r := []
	if n is MeshInstance3D:
		r.append(n)
	for c in n.get_children():
		r += _all_mesh_instances(c)
	return r
