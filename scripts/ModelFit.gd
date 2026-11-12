class_name ModelFit
extends RefCounted
## Utilidades para colocar los .glb generados por Higgsfield, que llegan con
## una escala y un origen arbitrarios (normalizados a ~1 unidad, centrados).


## Instancia `path`, lo escala para que mida `size` (en altura o en anchura)
## y lo coloca centrado en X/Z, con su base en y = 0.
## Devuelve null si el archivo no existe, para poder usar un modelo de reserva.
static func load_fitted(path: String, size: float, by_width := false,
		metallic := 0.0, roughness := 0.85) -> Node3D:
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("Modelo no encontrado: %s (se usa forma de reserva)" % path)
		return null
	var model: Node3D = (load(path) as PackedScene).instantiate()
	fix_materials(model, metallic, roughness)
	var box := compute_aabb(model)
	if box.size == Vector3.ZERO:
		return model
	var dim := maxf(box.size.x, box.size.z) if by_width else box.size.y
	var s := size / dim
	model.scale = Vector3.ONE * s
	var center := box.get_center()
	model.position = -Vector3(center.x, box.position.y, center.z) * s
	model.set_meta("raw_aabb", box)
	model.set_meta("fit_scale", s)
	return model


## Los .glb de Higgsfield no definen metallicFactor, y en glTF eso significa
## metal puro (1.0): todo se ve oscuro. Aquí se fija un valor razonable.
## Los materiales importados se comparten, así que basta con hacerlo una vez.
static func fix_materials(model: Node, metallic: float, roughness: float) -> void:
	for_each_mesh(model, func(mi: MeshInstance3D):
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if mat:
				mat.metallic = metallic
				mat.roughness = roughness
				mat.metallic_specular = 0.4)


## AABB combinado de todas las mallas bajo `node`, en el espacio de `node`.
static func compute_aabb(node: Node, xform := Transform3D.IDENTITY, is_root := true) -> AABB:
	var t := xform
	if node is Node3D and not is_root:
		t = xform * (node as Node3D).transform
	var result := AABB()
	var has := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		result = t * (node as MeshInstance3D).mesh.get_aabb()
		has = true
	for c in node.get_children():
		var b := compute_aabb(c, t, false)
		if b.size != Vector3.ZERO:
			result = result.merge(b) if has else b
			has = true
	return result


## Aplica una función a todos los MeshInstance3D bajo `node`.
static func for_each_mesh(node: Node, fn: Callable) -> void:
	if node is MeshInstance3D:
		fn.call(node)
	for c in node.get_children():
		for_each_mesh(c, fn)


## Material sencillo para las formas de reserva.
static func flat_material(color: Color, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m
