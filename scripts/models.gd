extends RefCounted
## 3D models of buildings, units and minerals, assembled from primitive meshes.
## World scale: 1 unit = 10 game pixels. Units face +X. The ground is y = 0.
## Used at runtime by scripts/view3d.gd and exported to models/*.tscn by tools/export_models.gd.

const PX := 10.0  # game pixels per world unit

var team_color := Color(0.27, 0.57, 1.0)
var _mats := {}


func _init(tc: Color) -> void:
	team_color = tc


## Footprint depth multiplier (1.0 = true proportions).
var depth_k := 1.0


# --- Materials --------------------------------------------------------------

func mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.roughness = 0.6
	match name:
		"metal":
			_textured(m, "metal", Color(0.44, 0.47, 0.52), 0.35)
			m.metallic = 0.3
			m.roughness = 0.55
		"dark":
			_textured(m, "metal", Color(0.3, 0.32, 0.36), 0.35)
			m.metallic = 0.2
		"warm":
			_textured(m, "metal", Color(0.5, 0.43, 0.35), 0.3)
		"roof":
			_textured(m, "ribs", Color(0.5, 0.53, 0.56), 0.8)
		"hazard":
			_textured(m, "hazard", Color.WHITE, 1.2)
		"hull":  # white sci-fi plating
			_textured(m, "metal", Color(0.68, 0.7, 0.74), 0.35)
			m.metallic = 0.35
			m.roughness = 0.38
		"gunmetal":
			_textured(m, "metal", Color(0.2, 0.22, 0.26), 0.35)
			m.metallic = 0.75
			m.roughness = 0.35
		"energy":  # glowing team-coloured energy seams
			_emissive(m, team_color, 2.2)
		"door":
			_emissive(m, team_color.darkened(0.2), 0.9)
			m.roughness = 0.2
		"glass_dark":
			m.albedo_color = Color(0.05, 0.08, 0.12)
			m.metallic = 0.6
			m.roughness = 0.08
			m.metallic_specular = 1.0
		"holo", "holo_line", "shield":
			var c := team_color.lightened(0.5) if name != "shield" else team_color.lerp(Color(0.4, 0.9, 1.0), 0.5)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.albedo_color = Color(c, {"holo": 0.22, "holo_line": 0.8, "shield": 0.1}[name])
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 2.5 if name == "holo_line" else 1.0
		"team":
			m.albedo_color = team_color.darkened(0.15)
			m.roughness = 0.45
			m.metallic = 0.2
		"team_dark":
			m.albedo_color = team_color.darkened(0.45)
			m.roughness = 0.5
		"glow":
			_emissive(m, team_color.lightened(0.45), 4.0)
		"red_glow":
			_emissive(m, Color(1.0, 0.35, 0.25), 4.0)
		"amber_glow":
			_emissive(m, Color(1.0, 0.75, 0.3), 4.0)
		"fire_glow":
			_emissive(m, Color(1.0, 0.45, 0.1), 4.0)
		"glass":
			m.albedo_color = team_color.lerp(Color(0.3, 0.8, 1.0), 0.35).darkened(0.25)
			m.roughness = 0.08
			m.metallic = 0.4
			m.metallic_specular = 1.0
			m.rim_enabled = true
			m.rim = 0.6
		"black":
			m.albedo_color = Color(0.07, 0.07, 0.08)
		"rubber":
			m.albedo_color = Color(0.14, 0.14, 0.15)
			m.roughness = 0.9
		"yellow":
			m.albedo_color = Color(0.9, 0.7, 0.15)
			m.roughness = 0.45
		"crystal":
			m.albedo_color = Color(0.35, 0.8, 1.0)
			m.roughness = 0.12
			m.metallic_specular = 1.0
			m.emission_enabled = true
			m.emission = Color(0.1, 0.5, 1.0)
			m.emission_energy_multiplier = 1.6
			m.rim_enabled = true
			m.rim = 0.8
	_mats[name] = m
	return m


func _emissive(m: StandardMaterial3D, c: Color, energy: float) -> void:
	m.albedo_color = c.darkened(0.3)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy


func _textured(m: StandardMaterial3D, tex: String, tint: Color, scale: float) -> void:
	m.albedo_texture = load("res://assets/materials/%s.png" % tex)
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.metallic_specular = 0.25


# --- Primitives -------------------------------------------------------------

func box(parent: Node3D, size: Vector3, pos: Vector3, m: String, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, mesh, pos, m, rot)


func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: String,
		rot := Vector3.ZERO, seg := 24) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bot
	mesh.height = h
	mesh.radial_segments = seg
	mesh.rings = 1
	return _add(parent, mesh, pos, m, rot)


func sphere(parent: Node3D, r: float, pos: Vector3, m: String, scale := Vector3.ONE, half := false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r if half else r * 2.0
	mesh.is_hemisphere = half
	mesh.radial_segments = 32
	mesh.rings = 16
	var mi := _add(parent, mesh, pos, m, Vector3.ZERO)
	mi.scale = scale
	return mi


## Chamfered octagonal slab: w x d footprint, height h, pos = centre of its BOTTOM face.
## taper < 1 narrows the top, giving sloped armour sides.
func octa(parent: Node3D, w: float, d: float, h: float, pos: Vector3, m: String, taper := 1.0) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos + Vector3(0, h / 2.0, 0)
	holder.scale = Vector3(w, 1.0, d)
	parent.add_child(holder)
	var mesh := CylinderMesh.new()
	var rad := 0.5 / cos(PI / 8.0)  # flat-to-flat width of 1
	mesh.top_radius = rad * taper
	mesh.bottom_radius = rad
	mesh.height = h
	mesh.radial_segments = 8
	mesh.rings = 1
	_add(holder, mesh, Vector3.ZERO, m, Vector3(0, 22.5, 0))
	return holder


## Capsule (rounded limb) along its local Y axis; h is the full length including the caps.
func capsule(parent: Node3D, r: float, h: float, pos: Vector3, m: String, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = r
	mesh.height = maxf(h, r * 2.0)
	mesh.radial_segments = 20
	mesh.rings = 6
	return _add(parent, mesh, pos, m, rot)


func torus(parent: Node3D, r_in: float, r_out: float, pos: Vector3, m: String, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = r_in
	mesh.outer_radius = r_out
	mesh.rings = 40
	mesh.ring_segments = 8
	return _add(parent, mesh, pos, m, rot)


## Tags a node for animation in view3d.gd: "spin" (rotate around Y) or "pulse" (breathing scale).
func anim(node: Node3D, kind: String, speed := 1.0) -> Node3D:
	node.set_meta("anim", kind)
	node.set_meta("speed", speed)
	return node


func _add(parent: Node3D, mesh: Mesh, pos: Vector3, m: String, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(m)
	if m in ["holo", "holo_line", "shield"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


func _root(name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	return n


# --- Buildings --------------------------------------------------------------

func build(kind: String) -> Node3D:
	match kind:
		"cc": return command_center()
		"depot": return supply_depot()
		"barracks": return barracks()
		"factory": return factory()
		"worker": return worker()
		"marine": return marine()
		"tank": return tank()
		"wraith": return wraith()
		"titan": return titan()
		"bunker": return bunker()
		"ebay": return engineering_bay()
		"turret": return missile_turret()
		"starport": return starport()
		"silo": return missile_silo()
	push_error("unknown model " + kind)
	return null


## Futuristic buildings: chamfered octagonal hulls of white plating over gunmetal, glowing team
## energy seams, glass domes and holograms. Nodes tagged with anim() are animated by view3d.gd.

func command_center() -> Node3D:
	var r := _root("CommandCenter")
	var w := 13.0
	var d := 10.0 * depth_k
	octa(r, w, d, 0.6, Vector3(0, 0, 0), "gunmetal", 0.94)
	octa(r, w - 0.4, d - 0.4, 0.1, Vector3(0, 0.6, 0), "energy")
	octa(r, 11.0, 8.2, 1.9, Vector3(0, 0.62, 0), "hull", 0.9)
	octa(r, 10.0, 7.4, 0.14, Vector3(0, 2.52, 0), "energy")
	octa(r, 9.6, 7.0, 0.5, Vector3(0, 2.6, 0), "gunmetal", 0.92)
	octa(r, 7.2, 5.4, 1.5, Vector3(0, 3.1, -0.4), "hull", 0.78)
	# command bridge: sloped dark glass across the front of the tower
	box(r, Vector3(5.2, 0.12, 1.6), Vector3(0, 3.95, 1.85), "glass_dark", Vector3(-38, 0, 0))
	for sx in [-1, 1]:  # engine pods with glowing intake rings (it can lift off, like in SC)
		var x: float = sx * 6.1
		cyl(r, 1.0, 1.0, 4.2, Vector3(x, 1.6, 0.2), "gunmetal", Vector3(90, 0, 0), 20)
		cyl(r, 0.8, 0.8, 4.3, Vector3(x, 1.6, 0.2), "hull", Vector3(90, 0, 0), 20)
		for z in [-2.1, 2.3]:
			torus(r, 0.85, 1.12, Vector3(x, 1.6, z), "energy", Vector3(90, 0, 0))
	# central spire with a pulsing beacon
	cyl(r, 0.25, 0.9, 3.2, Vector3(0, 6.1, -1.4), "gunmetal", Vector3.ZERO, 6)
	anim(sphere(r, 0.32, Vector3(0, 7.8, -1.4), "energy"), "pulse", 2.0)
	# holographic globe of the sector, slowly rotating
	cyl(r, 0.9, 1.1, 0.3, Vector3(3.0, 4.75, 0.2), "gunmetal", Vector3.ZERO, 16)
	var holo := Node3D.new()
	holo.position = Vector3(3.0, 6.0, 0.2)
	r.add_child(holo)
	anim(holo, "spin", 0.6)
	sphere(holo, 0.85, Vector3.ZERO, "holo")
	torus(holo, 1.05, 1.15, Vector3.ZERO, "holo_line", Vector3(70, 0, 0))
	torus(holo, 1.2, 1.28, Vector3.ZERO, "holo_line", Vector3(0, 0, 25))
	# radar
	var radar := Node3D.new()
	radar.position = Vector3(-3.0, 4.7, -1.2)
	r.add_child(radar)
	anim(radar, "spin", 1.6)
	cyl(radar, 0.08, 0.12, 1.0, Vector3(0, 0.5, 0), "gunmetal")
	box(radar, Vector3(2.2, 0.5, 0.12), Vector3(0, 1.1, 0), "hull", Vector3(-15, 0, 0))
	# front landing ramp with energy guide lights
	box(r, Vector3(3.6, 0.15, 2.2), Vector3(0, 0.62, d / 2.0 - 0.6), "gunmetal", Vector3(8, 0, 0))
	box(r, Vector3(3.0, 1.5, 0.15), Vector3(0, 1.4, 4.0), "door")
	for sx in [-1, 1]:
		box(r, Vector3(0.12, 0.06, 2.0), Vector3(sx * 1.6, 0.74, d / 2.0 - 0.6), "energy", Vector3(8, 0, 0))
	return r


func supply_depot() -> Node3D:
	var r := _root("SupplyDepot")
	var w := 7.0
	var d := 7.0 * depth_k
	octa(r, w, d, 0.5, Vector3.ZERO, "gunmetal", 0.92)
	octa(r, w - 0.6, d - 0.6, 0.08, Vector3(0, 0.5, 0), "energy")
	# four leaning armour pylons around the power cell
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		var p := Vector3(cos(a) * 2.5, 1.4, sin(a) * 2.5)
		var pyl := box(r, Vector3(0.9, 2.6, 0.9), p, "hull")
		pyl.rotation = Vector3(sin(a) * 0.25, -a, -cos(a) * 0.25)
		box(r, Vector3(0.2, 1.8, 0.95), p + Vector3(0, 0.1, 0), "energy").rotation = pyl.rotation
	# glass power cell with pulsing core and rotating containment ring
	cyl(r, 1.3, 1.5, 0.5, Vector3(0, 0.75, 0), "gunmetal", Vector3.ZERO, 16)
	cyl(r, 1.1, 1.1, 2.0, Vector3(0, 1.95, 0), "glass", Vector3.ZERO, 20)
	anim(cyl(r, 0.55, 0.55, 1.9, Vector3(0, 1.95, 0), "energy", Vector3.ZERO, 12), "pulse", 1.4)
	octa(r, 2.6, 2.6, 0.4, Vector3(0, 2.95, 0), "hull", 0.6)
	var ring := Node3D.new()
	ring.position = Vector3(0, 2.0, 0)
	r.add_child(ring)
	anim(ring, "spin", 1.2)
	torus(ring, 1.45, 1.6, Vector3.ZERO, "energy", Vector3(18, 0, 0))
	return r


func barracks() -> Node3D:
	var r := _root("Barracks")
	var w := 11.0
	var d := 9.0 * depth_k
	octa(r, w, d, 0.45, Vector3.ZERO, "gunmetal", 0.94)
	octa(r, w - 0.4, d - 0.4, 0.08, Vector3(0, 0.45, 0), "energy")
	# angular main hall
	octa(r, 9.0, 6.8, 2.6, Vector3(0, 0.5, -0.4), "hull", 0.72)
	octa(r, 6.4, 4.6, 0.16, Vector3(0, 3.1, -0.4), "energy")
	octa(r, 6.2, 4.4, 0.6, Vector3(0, 3.18, -0.4), "gunmetal", 0.8)
	for sx in [-1, 1]:  # armoured side wings, sloped
		box(r, Vector3(1.6, 1.8, 5.4), Vector3(sx * 4.7, 1.3, -0.4), "gunmetal", Vector3(0, 0, sx * 18.0))
		box(r, Vector3(0.12, 0.12, 5.0), Vector3(sx * 5.25, 1.75, -0.4), "energy", Vector3(0, 0, sx * 18.0))
		box(r, Vector3(0.2, 1.2, 1.4), Vector3(sx * 1.6, 3.95, -1.2), "hull", Vector3(0, 0, sx * -12.0))  # roof fins
	# energy gate framed by angled pylons, holographic emblem above
	var front := -0.4 + 3.3
	box(r, Vector3(3.0, 2.0, 0.15), Vector3(0, 1.5, front), "door")
	for sx in [-1, 1]:
		box(r, Vector3(0.6, 2.8, 0.7), Vector3(sx * 1.9, 1.9, front + 0.1), "gunmetal", Vector3(0, 0, sx * -8.0))
		box(r, Vector3(0.1, 2.4, 0.1), Vector3(sx * 1.6, 1.8, front + 0.45), "energy", Vector3(0, 0, sx * -8.0))
	var emblem := Node3D.new()
	emblem.position = Vector3(0, 3.6, front + 0.4)
	r.add_child(emblem)
	anim(emblem, "spin", 1.0)
	torus(emblem, 0.45, 0.55, Vector3.ZERO, "holo_line", Vector3(90, 0, 0))
	box(emblem, Vector3(0.12, 0.7, 0.04), Vector3.ZERO, "holo_line")
	box(r, Vector3(3.6, 0.12, 1.8), Vector3(0, 0.52, front + 1.0), "gunmetal", Vector3(6, 0, 0))
	return r


func factory() -> Node3D:
	var r := _root("Factory")
	var w := 12.0
	var d := 9.0 * depth_k
	octa(r, w, d, 0.45, Vector3.ZERO, "gunmetal", 0.94)
	octa(r, w - 0.4, d - 0.4, 0.08, Vector3(0, 0.45, 0), "energy")
	var hx := -1.4
	octa(r, 8.4, 7.0, 3.0, Vector3(hx, 0.5, -0.3), "gunmetal", 0.86)
	octa(r, 7.6, 6.2, 0.5, Vector3(hx, 3.5, -0.3), "hull", 0.8)
	for i in 3:  # white armour panels with energy seams on the hall
		box(r, Vector3(2.2, 2.0, 0.1), Vector3(hx - 2.6 + i * 2.6, 2.0, 3.05), "hull", Vector3(-6, 0, 0))
	box(r, Vector3(7.8, 0.1, 0.1), Vector3(hx, 3.2, 3.18), "energy")
	# big assembly door with energy frame
	box(r, Vector3(4.2, 2.1, 0.12), Vector3(hx, 1.6, 3.22), "door")
	box(r, Vector3(4.6, 0.14, 0.14), Vector3(hx, 2.75, 3.25), "energy")
	box(r, Vector3(4.6, 0.12, 1.6), Vector3(hx, 0.52, 3.9), "gunmetal", Vector3(6, 0, 0))
	# fusion reactor tower with stacked glowing rings
	var rx := 4.4
	cyl(r, 1.2, 1.5, 4.6, Vector3(rx, 2.6, -1.6), "hull", Vector3.ZERO, 16)
	for k in 3:
		anim(torus(r, 1.3 - k * 0.07, 1.48 - k * 0.07, Vector3(rx, 1.6 + k * 1.3, -1.6), "energy"), "pulse", 1.0 + k * 0.4)
	cyl(r, 0.6, 1.0, 0.8, Vector3(rx, 5.3, -1.6), "gunmetal", Vector3.ZERO, 12)
	anim(sphere(r, 0.38, Vector3(rx, 5.85, -1.6), "energy"), "pulse", 2.6)
	# cooling fins
	for k in 5:
		box(r, Vector3(1.8, 1.6, 0.12), Vector3(rx, 1.3, 1.0 + k * 0.45), "gunmetal")
	# robotic assembly arm on the roof
	var arm := Node3D.new()
	arm.position = Vector3(hx - 1.5, 4.0, -1.0)
	r.add_child(arm)
	anim(arm, "spin", 0.4)
	cyl(arm, 0.4, 0.5, 0.5, Vector3(0, 0.25, 0), "gunmetal", Vector3.ZERO, 12)
	box(arm, Vector3(3.2, 0.3, 0.35), Vector3(1.4, 0.8, 0), "hull", Vector3(0, 0, 14))
	sphere(arm, 0.22, Vector3(2.9, 1.15, 0), "energy")
	return r


func bunker() -> Node3D:
	var r := _root("Bunker")
	var w := 8.0
	var d := 6.4 * depth_k
	octa(r, w, d, 0.4, Vector3.ZERO, "gunmetal", 0.92)
	octa(r, 6.8, 5.2, 1.4, Vector3(0, 0.4, 0), "gunmetal", 0.62)
	octa(r, 4.3, 3.3, 0.3, Vector3(0, 1.8, 0), "hull", 0.85)
	octa(r, 6.9, 5.3, 0.1, Vector3(0, 0.85, 0), "energy")
	for k in 3:  # glowing firing slits on the front glacis
		box(r, Vector3(1.0, 0.16, 0.1), Vector3(-1.5 + k * 1.5, 1.05, 2.15), "amber_glow", Vector3(-30, 0, 0))
	var gun := Node3D.new()  # rotating gun turret, aims at the bunker's target
	gun.name = "Turret"
	gun.position = Vector3(0, 2.1, 0)
	r.add_child(gun)
	cyl(gun, 0.7, 0.8, 0.5, Vector3(0, 0.25, 0), "hull", Vector3.ZERO, 12)
	for sz in [-0.18, 0.18]:
		cyl(gun, 0.07, 0.07, 1.3, Vector3(0.9, 0.3, sz), "gunmetal", Vector3(0, 0, -90), 8)
	# translucent energy shield dome
	sphere(r, 1.0, Vector3(0, 0.3, 0), "shield", Vector3(4.2, 2.4, 3.4), true)
	return r


func engineering_bay() -> Node3D:
	var r := _root("EngineeringBay")
	var w := 10.0
	var d := 8.0 * depth_k
	octa(r, w, d, 0.45, Vector3.ZERO, "gunmetal", 0.94)
	octa(r, w - 0.4, d - 0.4, 0.08, Vector3(0, 0.45, 0), "energy")
	octa(r, 8.4, 6.2, 2.2, Vector3(0, 0.5, -0.3), "hull", 0.84)
	octa(r, 7.2, 5.2, 0.4, Vector3(0, 2.7, -0.3), "gunmetal", 0.9)
	# research dome with a pulsing core and orbiting rings
	sphere(r, 2.2, Vector3(-1.0, 3.1, -0.5), "glass", Vector3.ONE, true)
	anim(sphere(r, 0.75, Vector3(-1.0, 3.9, -0.5), "energy"), "pulse", 1.6)
	var orbit := Node3D.new()
	orbit.position = Vector3(-1.0, 3.9, -0.5)
	r.add_child(orbit)
	anim(orbit, "spin", 1.8)
	torus(orbit, 1.15, 1.25, Vector3.ZERO, "holo_line", Vector3(60, 0, 0))
	torus(orbit, 1.35, 1.43, Vector3.ZERO, "holo_line", Vector3(-50, 0, 30))
	# sensor tower
	cyl(r, 0.35, 0.7, 3.6, Vector3(3.0, 4.5, -1.8), "gunmetal", Vector3.ZERO, 6)
	box(r, Vector3(1.6, 0.1, 0.1), Vector3(3.0, 5.6, -1.8), "hull")
	box(r, Vector3(0.1, 0.1, 1.6), Vector3(3.0, 5.9, -1.8), "hull")
	anim(sphere(r, 0.2, Vector3(3.0, 6.45, -1.8), "red_glow"), "pulse", 3.0)
	# lab door and light strip
	box(r, Vector3(2.6, 1.6, 0.12), Vector3(-1.5, 1.3, 2.75), "door")
	for k in 4:
		box(r, Vector3(0.5, 0.5, 0.08), Vector3(1.2 + k * 0.75, 1.8, 2.72), "glass_dark")
	box(r, Vector3(3.2, 0.08, 0.08), Vector3(2.3, 1.35, 2.8), "energy")
	return r


func missile_turret() -> Node3D:
	var r := _root("MissileTurret")
	var w := 5.0
	var d := 5.0 * depth_k
	octa(r, w, d, 0.4, Vector3.ZERO, "gunmetal", 0.9)
	octa(r, w - 0.5, d - 0.5, 0.08, Vector3(0, 0.4, 0), "energy")
	cyl(r, 1.0, 1.7, 1.0, Vector3(0, 0.9, 0), "hull", Vector3.ZERO, 8)
	cyl(r, 0.45, 0.6, 2.0, Vector3(0, 2.4, 0), "gunmetal", Vector3.ZERO, 8)
	torus(r, 0.55, 0.68, Vector3(0, 2.2, 0), "energy")
	var head := Node3D.new()  # aims at the turret's target
	head.name = "Turret"
	head.position = Vector3(0, 3.5, 0)
	r.add_child(head)
	octa(head, 1.7, 1.3, 0.8, Vector3(0, -0.4, 0), "hull", 0.8)
	for sz in [-1, 1]:  # missile pods with glowing warheads
		box(head, Vector3(1.5, 0.75, 0.55), Vector3(0.15, 0.0, sz * 0.95), "gunmetal")
		for k in 4:
			sphere(head, 0.11, Vector3(0.92, -0.17 + (k / 2) * 0.34, sz * 0.95 + (k % 2 - 0.5) * 0.26), "red_glow")
	box(head, Vector3(0.6, 0.12, 0.5), Vector3(-0.3, 0.45, 0), "glass_dark")
	return r


func starport() -> Node3D:
	var r := _root("Starport")
	var w := 12.0
	var d := 10.0 * depth_k
	octa(r, w, d, 0.45, Vector3.ZERO, "gunmetal", 0.94)
	octa(r, w - 0.4, d - 0.4, 0.08, Vector3(0, 0.45, 0), "energy")
	# hangar below the raised landing platform
	octa(r, 7.6, 6.8, 1.8, Vector3(-1.4, 0.5, -0.2), "hull", 0.9)
	box(r, Vector3(4.6, 1.3, 0.12), Vector3(-1.4, 1.2, 3.2), "door")
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			cyl(r, 0.25, 0.35, 1.0, Vector3(-1.4 + sx * 3.0, 2.6, -0.2 + sz * 2.6), "gunmetal")
	octa(r, 8.0, 7.2, 0.35, Vector3(-1.4, 3.0, -0.2), "gunmetal", 0.96)
	octa(r, 7.0, 6.2, 0.06, Vector3(-1.4, 3.35, -0.2), "hull")
	torus(r, 2.5, 2.7, Vector3(-1.4, 3.42, -0.2), "energy")
	for i in 8:  # pulsing approach lights around the pad
		var a := i * TAU / 8.0
		anim(sphere(r, 0.13, Vector3(-1.4 + cos(a) * 3.2, 3.45, -0.2 + sin(a) * 2.9), "energy"), "pulse", 2.5)
	# a docked fighter on the pad
	var ship := wraith()
	ship.get_node("Body").position = Vector3(0, 0.55, 0)
	ship.position = Vector3(-1.4, 3.4, -0.2)
	ship.rotation_degrees = Vector3(0, 35, 0)
	ship.scale = Vector3.ONE * 1.25
	r.add_child(ship)
	# control tower with glass observation ring and spinning radar
	cyl(r, 0.6, 0.9, 4.8, Vector3(4.3, 2.8, -2.4), "hull", Vector3.ZERO, 8)
	cyl(r, 1.4, 1.1, 0.9, Vector3(4.3, 5.4, -2.4), "glass_dark", Vector3.ZERO, 16)
	torus(r, 1.35, 1.45, Vector3(4.3, 5.0, -2.4), "energy")
	cyl(r, 1.5, 1.5, 0.2, Vector3(4.3, 5.95, -2.4), "gunmetal", Vector3.ZERO, 16)
	var radar := Node3D.new()
	radar.position = Vector3(4.3, 6.1, -2.4)
	r.add_child(radar)
	anim(radar, "spin", 2.0)
	box(radar, Vector3(1.8, 0.4, 0.1), Vector3(0, 0.45, 0), "hull", Vector3(-20, 0, 0))
	box(r, Vector3(2.2, 1.0, 2.6), Vector3(4.3, 0.95, 1.8), "gunmetal")
	for k in 6:
		anim(sphere(r, 0.12, Vector3(-4.6 + k * 1.3, 0.55, d / 2.0 - 0.5), "energy"), "pulse", 1.5 + k * 0.3)
	return r


## Missile silo: armoured octagonal pad with hazard ring, two blast doors over the launch tube and
## a missile ("Missile", shown by view3d.gd while one is loaded) standing in the open hatch.
func missile_silo() -> Node3D:
	var r := _root("MissileSilo")
	var w := 7.0
	var d := 7.0 * depth_k
	octa(r, w, d, 0.5, Vector3.ZERO, "gunmetal", 0.9)
	octa(r, w * 0.92, d * 0.92, 0.08, Vector3(0, 0.5, 0), "hazard")
	octa(r, w * 0.8, d * 0.8, 0.3, Vector3(0, 0.55, 0), "hull", 0.9)
	octa(r, w * 0.81, d * 0.81, 0.06, Vector3(0, 0.7, 0), "energy")
	cyl(r, 1.55, 1.7, 0.3, Vector3(0, 0.95, 0), "dark", Vector3.ZERO, 32)  # launch tube rim
	cyl(r, 1.3, 1.3, 0.05, Vector3(0, 1.1, 0), "black", Vector3.ZERO, 32)
	for sz in [-1, 1]:  # blast doors, swung open
		box(r, Vector3(2.6, 0.18, 1.3), Vector3(0, 1.9, sz * 1.85), "team", Vector3(sz * 62.0, 0, 0))
		box(r, Vector3(2.4, 0.2, 0.1), Vector3(0, 1.95, sz * 1.92), "hazard", Vector3(sz * 62.0, 0, 0))
	for k in 4:  # corner warning beacons
		var a := k * TAU / 4.0 + PI / 4.0
		var p := Vector3(cos(a) * 2.6, 0.9, sin(a) * 2.6 * depth_k)
		cyl(r, 0.12, 0.15, 0.4, p, "gunmetal", Vector3.ZERO, 12)
		anim(sphere(r, 0.12, p + Vector3(0, 0.3, 0), "red_glow"), "pulse", 3.0)
	var m := Node3D.new()
	m.name = "Missile"
	m.visible = false
	r.add_child(m)
	cyl(m, 0.45, 0.45, 2.6, Vector3(0, 2.2, 0), "hull", Vector3.ZERO, 20)
	cyl(m, 0.0, 0.45, 1.1, Vector3(0, 4.05, 0), "red_glow", Vector3.ZERO, 20)
	torus(m, 0.42, 0.52, Vector3(0, 3.0, 0), "energy")
	for k in 4:
		box(m, Vector3(0.06, 0.8, 0.7), Vector3(0, 1.3, 0), "dark", Vector3(0, k * 45.0, 0))
	return r


# --- Units (face +X) ----------------------------------------------------------

## Units share the buildings' look: white hull plating over gunmetal, team-coloured armour and
## glowing energy seams. Higher-segment meshes and capsule limbs give smoother silhouettes.

## SCV: tracked utility mech with a glass cockpit, a spinning drill arm, a claw arm (holds the
## mineral it carries) and a glowing backpack reactor.
func worker() -> Node3D:
	var r := _root("SCV")
	for sz in [-1, 1]:  # tracks with rounded ends, road wheels and team mudguards
		box(r, Vector3(0.8, 0.34, 0.26), Vector3(0, 0.2, sz * 0.46), "rubber")
		for ex in [-0.4, 0.4]:
			cyl(r, 0.17, 0.17, 0.26, Vector3(ex, 0.2, sz * 0.46), "rubber", Vector3(90, 0, 0), 20)
		for k in 3:
			cyl(r, 0.12, 0.12, 0.04, Vector3(-0.32 + k * 0.32, 0.2, sz * 0.6), "gunmetal", Vector3(90, 0, 0), 16)
		box(r, Vector3(1.0, 0.05, 0.32), Vector3(0, 0.4, sz * 0.46), "team")
	octa(r, 1.0, 0.7, 0.28, Vector3(0, 0.34, 0), "gunmetal", 0.85)
	octa(r, 0.95, 0.92, 0.7, Vector3(-0.05, 0.6, 0), "hull", 0.78)
	octa(r, 0.94, 0.91, 0.05, Vector3(-0.05, 0.86, 0), "energy")
	for sz in [-1, 1]:
		box(r, Vector3(0.04, 0.07, 0.14), Vector3(0.46, 0.78, sz * 0.24), "amber_glow")
	# cockpit: glass dome on a team-coloured collar
	torus(r, 0.3, 0.38, Vector3(0.12, 1.3, 0), "team")
	sphere(r, 0.34, Vector3(0.12, 1.32, 0), "glass", Vector3(1.1, 0.85, 1.0))
	# backpack reactor with a pulsing energy ring and exhaust stacks
	cyl(r, 0.22, 0.24, 0.62, Vector3(-0.55, 1.12, 0), "gunmetal", Vector3.ZERO, 20)
	anim(torus(r, 0.21, 0.27, Vector3(-0.55, 1.22, 0), "glow"), "pulse", 2.0)
	cyl(r, 0.2, 0.2, 0.06, Vector3(-0.55, 1.45, 0), "hull", Vector3.ZERO, 20)
	for sz in [-1, 1]:
		cyl(r, 0.05, 0.06, 0.4, Vector3(-0.68, 1.55, sz * 0.12), "dark", Vector3.ZERO, 10)
	cyl(r, 0.012, 0.012, 0.55, Vector3(-0.3, 1.55, 0.3), "dark", Vector3.ZERO, 6)
	sphere(r, 0.04, Vector3(-0.3, 1.84, 0.3), "red_glow")
	for sz in [-1, 1]:  # shoulders and arms
		sphere(r, 0.19, Vector3(0.02, 1.15, sz * 0.52), "team")
		capsule(r, 0.08, 0.5, Vector3(0.22, 0.98, sz * 0.58), "gunmetal", Vector3(0, 0, -65))
	# right arm: motor housing and a spinning drill (spins around its own Y, which points forward)
	cyl(r, 0.13, 0.13, 0.26, Vector3(0.5, 0.88, 0.58), "gunmetal", Vector3(0, 0, -90), 16)
	var holder := Node3D.new()
	holder.position = Vector3(0.63, 0.88, 0.58)
	holder.rotation_degrees = Vector3(0, 0, -90)
	r.add_child(holder)
	var drill := anim(Node3D.new(), "spin", 14.0)
	holder.add_child(drill)
	cyl(drill, 0.0, 0.15, 0.55, Vector3(0, 0.28, 0), "yellow", Vector3.ZERO, 16)
	for k in 3:
		torus(drill, 0.1 - k * 0.03, 0.14 - k * 0.035, Vector3(0, 0.12 + k * 0.13, 0), "dark", Vector3(10, 0, 0))
	# left arm: two-finger claw
	cyl(r, 0.1, 0.12, 0.2, Vector3(0.5, 0.88, -0.58), "gunmetal", Vector3(0, 0, -90), 12)
	for sy in [-1, 1]:
		box(r, Vector3(0.3, 0.05, 0.07), Vector3(0.7, 0.88 + sy * 0.08, -0.58), "dark", Vector3(0, 0, sy * 18))
	var carry := Node3D.new()  # shown while carrying minerals: a crystal held in the claw
	carry.name = "Carry"
	carry.visible = false
	r.add_child(carry)
	cyl(carry, 0.02, 0.2, 0.5, Vector3(0.82, 0.92, -0.58), "crystal", Vector3(0, 0, -70), 6)
	return r


## Marine: powered armour with capsule limbs, big shoulder pads, a glowing visor,
## a backpack with thrusters and a detailed rifle.
func marine() -> Node3D:
	var r := _root("Marine")
	for sz in [-1, 1]:  # legs: boots, shins, knee guards, thighs
		octa(r, 0.4, 0.26, 0.16, Vector3(0.06, 0, sz * 0.2), "gunmetal", 0.8)
		capsule(r, 0.12, 0.55, Vector3(0, 0.44, sz * 0.2), "hull")
		sphere(r, 0.12, Vector3(0.08, 0.7, sz * 0.2), "team", Vector3(0.8, 1.0, 1.0))
		capsule(r, 0.14, 0.48, Vector3(0, 0.92, sz * 0.2), "gunmetal")
	octa(r, 0.48, 0.6, 0.2, Vector3(0, 1.04, 0), "dark", 0.9)
	# torso widening towards the chest, with a white chest plate and an energy strip
	octa(r, 0.6, 0.76, 0.56, Vector3(0, 1.22, 0), "team", 1.15)
	box(r, Vector3(0.1, 0.36, 0.48), Vector3(0.36, 1.5, 0), "hull", Vector3(0, 0, -12))
	box(r, Vector3(0.04, 0.05, 0.4), Vector3(0.4, 1.36, 0), "energy")
	cyl(r, 0.18, 0.24, 0.12, Vector3(0, 1.83, 0), "gunmetal", Vector3.ZERO, 16)
	# helmet with visor band and crest
	sphere(r, 0.23, Vector3(0.02, 1.98, 0), "hull", Vector3(1.05, 1.0, 0.95))
	box(r, Vector3(0.1, 0.08, 0.3), Vector3(0.2, 1.98, 0), "amber_glow")
	box(r, Vector3(0.34, 0.05, 0.06), Vector3(-0.02, 2.2, 0), "team")
	cyl(r, 0.01, 0.01, 0.4, Vector3(-0.12, 2.1, 0.18), "dark", Vector3.ZERO, 6)
	# backpack: armoured pack, twin thrusters, glowing vents
	octa(r, 0.3, 0.52, 0.55, Vector3(-0.42, 1.2, 0), "gunmetal", 0.85)
	for sz in [-1, 1]:
		cyl(r, 0.08, 0.1, 0.32, Vector3(-0.58, 1.3, sz * 0.15), "dark", Vector3.ZERO, 12)
		cyl(r, 0.07, 0.07, 0.03, Vector3(-0.58, 1.13, sz * 0.15), "glow", Vector3.ZERO, 12)
	box(r, Vector3(0.03, 0.2, 0.3), Vector3(-0.58, 1.48, 0), "energy")
	for sz in [-1, 1]:  # shoulder pads with white trim, arms reaching to the rifle
		sphere(r, 0.26, Vector3(0, 1.7, sz * 0.46), "team", Vector3(1.15, 0.75, 1.0), true)
		torus(r, 0.24, 0.29, Vector3(0, 1.7, sz * 0.46), "hull")
		capsule(r, 0.09, 0.38, Vector3(0.04, 1.5, sz * 0.44), "gunmetal")
		capsule(r, 0.09, 0.38, Vector3(0.24, 1.3, sz * 0.36), "hull", Vector3(sz * 25.0, 0, -70))
	# rifle on the right side
	var gun := Node3D.new()
	gun.position = Vector3(0.38, 1.26, -0.28)
	r.add_child(gun)
	box(gun, Vector3(0.8, 0.15, 0.11), Vector3(0.2, 0, 0), "gunmetal")
	box(gun, Vector3(0.28, 0.13, 0.09), Vector3(-0.3, -0.02, 0), "dark")
	cyl(gun, 0.04, 0.04, 0.55, Vector3(0.85, 0.02, 0), "black", Vector3(0, 0, -90), 12)
	cyl(gun, 0.06, 0.06, 0.12, Vector3(1.14, 0.02, 0), "dark", Vector3(0, 0, -90), 12)
	cyl(gun, 0.04, 0.04, 0.28, Vector3(0.2, 0.12, 0), "black", Vector3(0, 0, -90), 12)
	box(gun, Vector3(0.11, 0.22, 0.08), Vector3(0.12, -0.16, 0), "dark", Vector3(0, 0, 12))
	box(gun, Vector3(0.3, 0.04, 0.12), Vector3(0.42, -0.06, 0), "glow")
	return r


## Siege tank: rounded tracks under armoured skirts, layered hull, octagonal turret with an
## energy-coiled cannon, sensor dome and antenna.
func tank() -> Node3D:
	var r := _root("SiegeTank")
	for sz in [-1, 1]:
		box(r, Vector3(3.5, 0.62, 0.72), Vector3(0, 0.36, sz * 1.15), "rubber")
		for ex in [-1.75, 1.75]:
			cyl(r, 0.31, 0.31, 0.72, Vector3(ex, 0.36, sz * 1.15), "rubber", Vector3(90, 0, 0), 24)
			cyl(r, 0.2, 0.2, 0.06, Vector3(ex, 0.36, sz * 1.52), "gunmetal", Vector3(90, 0, 0), 16)
		for k in 5:
			cyl(r, 0.24, 0.24, 0.06, Vector3(-1.2 + k * 0.6, 0.32, sz * 1.52), "gunmetal", Vector3(90, 0, 0), 16)
			cyl(r, 0.08, 0.08, 0.08, Vector3(-1.2 + k * 0.6, 0.32, sz * 1.54), "dark", Vector3(90, 0, 0), 10)
		box(r, Vector3(3.4, 0.28, 0.08), Vector3(0, 0.7, sz * 1.55), "team")
		box(r, Vector3(3.2, 0.04, 0.09), Vector3(0, 0.6, sz * 1.56), "energy")
	octa(r, 3.7, 2.2, 0.5, Vector3(0, 0.62, 0), "team", 0.88)
	octa(r, 3.1, 1.8, 0.32, Vector3(-0.15, 1.1, 0), "hull", 0.85)
	octa(r, 3.15, 1.85, 0.05, Vector3(-0.15, 1.1, 0), "energy")
	box(r, Vector3(0.75, 0.42, 1.7), Vector3(1.62, 0.9, 0), "team_dark", Vector3(0, 0, 32))
	for sz in [-1, 1]:
		box(r, Vector3(0.05, 0.1, 0.22), Vector3(1.86, 0.95, sz * 0.6), "amber_glow", Vector3(0, 0, 32))
		cyl(r, 0.09, 0.1, 0.3, Vector3(-1.75, 1.15, sz * 0.6), "dark", Vector3(0, 0, 90), 12)
		cyl(r, 0.07, 0.07, 0.03, Vector3(-1.91, 1.15, sz * 0.6), "fire_glow", Vector3(0, 0, 90), 12)
	box(r, Vector3(0.7, 0.06, 1.1), Vector3(-1.15, 1.44, 0), "dark")
	var tur := Node3D.new()  # rotates independently towards the target
	tur.name = "Turret"
	tur.position = Vector3(-0.3, 0, 0)
	r.add_child(tur)
	octa(tur, 1.7, 1.4, 0.48, Vector3(0, 1.42, 0), "hull", 0.75)
	octa(tur, 1.74, 1.44, 0.05, Vector3(0, 1.5, 0), "energy")
	octa(tur, 1.0, 0.85, 0.18, Vector3(-0.15, 1.9, 0), "gunmetal", 0.8)
	box(tur, Vector3(0.35, 0.42, 0.6), Vector3(0.78, 1.66, 0), "gunmetal")
	cyl(tur, 0.1, 0.13, 2.2, Vector3(1.95, 1.68, 0), "gunmetal", Vector3(0, 0, -90), 16)
	cyl(tur, 0.16, 0.16, 0.55, Vector3(1.2, 1.68, 0), "team", Vector3(0, 0, -90), 16)
	for k in 3:
		torus(tur, 0.12, 0.17, Vector3(1.65 + k * 0.32, 1.68, 0), "glow", Vector3(0, 0, 90))
	cyl(tur, 0.17, 0.17, 0.32, Vector3(3.1, 1.68, 0), "dark", Vector3(0, 0, -90), 8)
	sphere(tur, 0.17, Vector3(-0.45, 2.1, 0.4), "glass")
	cyl(tur, 0.2, 0.2, 0.08, Vector3(-0.2, 2.1, -0.25), "gunmetal", Vector3.ZERO, 16)
	cyl(tur, 0.015, 0.02, 1.0, Vector3(-0.7, 2.45, -0.45), "dark", Vector3.ZERO, 6)
	sphere(tur, 0.04, Vector3(-0.7, 2.96, -0.45), "red_glow")
	return r


## Flying fighter, hovering above the ground: tapered fuselage, swept wings with energy leading
## edges and wingtip pods, twin engines with pulsing exhaust plumes.
func wraith() -> Node3D:
	var r := _root("Wraith")
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, 3.0, 0)
	r.add_child(body)
	cyl(body, 0.36, 0.46, 1.6, Vector3(-0.6, 0, 0), "hull", Vector3(0, 0, -90), 24)  # fuselage
	cyl(body, 0.03, 0.36, 1.7, Vector3(1.05, 0, 0), "team", Vector3(0, 0, -90), 24)  # nose
	cyl(body, 0.37, 0.37, 0.06, Vector3(0.2, 0, 0), "energy", Vector3(0, 0, -90), 24)
	sphere(body, 0.3, Vector3(0.5, 0.26, 0), "glass", Vector3(1.8, 0.75, 0.85))
	box(body, Vector3(1.2, 0.22, 0.06), Vector3(-0.75, 0.42, 0), "team", Vector3(0, 0, -6))
	for sz in [-1, 1]:
		var wing := Node3D.new()  # swept wing, rooted at the fuselage
		wing.position = Vector3(-0.2, -0.05, sz * 0.35)
		wing.rotation_degrees = Vector3(0, -sz * 32.0, 0)
		body.add_child(wing)
		box(wing, Vector3(1.1, 0.08, 1.8), Vector3(-0.35, 0, sz * 0.9), "hull")
		box(wing, Vector3(0.35, 0.09, 1.5), Vector3(-0.55, 0, sz * 0.95), "team")
		box(wing, Vector3(0.06, 0.1, 1.8), Vector3(0.2, 0, sz * 0.9), "energy")
		cyl(wing, 0.08, 0.1, 0.9, Vector3(-0.3, 0, sz * 1.85), "gunmetal", Vector3(0, 0, -90), 12)
		sphere(wing, 0.06, Vector3(-0.78, 0, sz * 1.85), "red_glow")
		cyl(body, 0.04, 0.04, 0.8, Vector3(0.5, -0.22, sz * 0.75), "black", Vector3(0, 0, -90), 10)
		# engines and exhaust
		cyl(body, 0.21, 0.25, 1.1, Vector3(-1.2, -0.02, sz * 0.5), "gunmetal", Vector3(0, 0, -90), 20)
		torus(body, 0.19, 0.25, Vector3(-0.65, -0.02, sz * 0.5), "team", Vector3(0, 0, 90))
		cyl(body, 0.17, 0.17, 0.06, Vector3(-1.77, -0.02, sz * 0.5), "glow", Vector3(0, 0, -90), 20)
		var plume := cyl(body, 0.0, 0.15, 0.7, Vector3(-2.15, -0.02, sz * 0.5), "holo", Vector3(0, 0, 90), 16)
		anim(plume, "pulse", 4.0)
		box(body, Vector3(0.7, 0.65, 0.06), Vector3(-1.35, 0.4, sz * 0.32), "team", Vector3(sz * 18.0, 0, 25))
	return r


## Titan (boss): huge two-legged walker. Legs "Leg0"/"Leg1" swing from the hips and the torso
## "Turret" turns towards the target (both animated in view3d.gd). Shoulder cannons, missile racks,
## a glass cockpit and a pulsing reactor on its back.
func titan() -> Node3D:
	var r := _root("Titan")
	octa(r, 1.4, 2.0, 0.5, Vector3(0, 2.15, 0), "gunmetal", 0.85)
	for i in 2:
		var sz := -1 if i == 0 else 1
		cyl(r, 0.36, 0.36, 0.5, Vector3(0, 2.4, sz * 0.95), "dark", Vector3(90, 0, 0), 20)
		var leg := Node3D.new()
		leg.name = "Leg%d" % i
		leg.position = Vector3(0, 2.4, sz * 0.95)
		r.add_child(leg)
		capsule(leg, 0.32, 1.3, Vector3(0.15, -0.55, 0), "gunmetal", Vector3(0, 0, -15))
		box(leg, Vector3(0.5, 0.9, 0.42), Vector3(0.28, -0.5, sz * 0.12), "team", Vector3(0, 0, -15))
		sphere(leg, 0.3, Vector3(0.3, -1.15, 0), "hull")
		capsule(leg, 0.28, 1.2, Vector3(0.15, -1.7, 0), "hull", Vector3(0, 0, 12))
		box(leg, Vector3(0.05, 0.6, 0.2), Vector3(0.43, -1.7, 0), "energy", Vector3(0, 0, 12))
		octa(leg, 1.2, 0.75, 0.3, Vector3(0.15, -2.4, 0), "gunmetal", 0.75)
		for tz in [-0.2, 0.2]:
			box(leg, Vector3(0.4, 0.14, 0.18), Vector3(0.82, -2.33, tz), "dark", Vector3(0, 0, -15))
	var tor := Node3D.new()
	tor.name = "Turret"
	r.add_child(tor)
	octa(tor, 2.0, 2.4, 1.3, Vector3(0, 2.6, 0), "hull", 0.8)
	octa(tor, 2.05, 2.45, 0.06, Vector3(0, 3.1, 0), "energy")
	octa(tor, 1.6, 1.9, 0.18, Vector3(0, 3.9, 0), "team", 0.8)
	sphere(tor, 0.42, Vector3(0.75, 3.45, 0), "glass", Vector3(1.0, 0.7, 1.2))
	torus(tor, 0.32, 0.46, Vector3(-0.95, 3.3, 0), "gunmetal", Vector3(0, 0, 90))
	anim(sphere(tor, 0.3, Vector3(-0.95, 3.3, 0), "glow"), "pulse", 2.0)
	for sz in [-1, 1]:
		cyl(tor, 0.1, 0.12, 0.6, Vector3(-0.75, 4.3, sz * 0.4), "dark", Vector3.ZERO, 12)
		cyl(tor, 0.08, 0.08, 0.03, Vector3(-0.75, 4.61, sz * 0.4), "fire_glow", Vector3.ZERO, 12)
		# shoulder, twin-barrel cannon pod with glowing muzzles, missile rack
		sphere(tor, 0.55, Vector3(0, 3.8, sz * 1.4), "team", Vector3(1.0, 0.9, 1.0))
		box(tor, Vector3(1.4, 0.6, 0.6), Vector3(0.45, 3.9, sz * 1.75), "gunmetal")
		box(tor, Vector3(1.0, 0.08, 0.62), Vector3(0.45, 3.85, sz * 1.75), "energy")
		for by in [-0.14, 0.14]:
			cyl(tor, 0.09, 0.09, 1.4, Vector3(1.75, 3.9 + by, sz * 1.75), "black", Vector3(0, 0, -90), 12)
			torus(tor, 0.08, 0.13, Vector3(2.45, 3.9 + by, sz * 1.75), "glow", Vector3(0, 0, 90))
		box(tor, Vector3(0.7, 0.35, 0.6), Vector3(-0.2, 4.37, sz * 1.75), "team_dark")
		for k in 3:
			sphere(tor, 0.07, Vector3(0.16, 4.37, sz * 1.75 + (k - 1) * 0.18), "red_glow")
		# arm hanging down to a forearm cannon
		capsule(tor, 0.25, 1.1, Vector3(0.05, 3.0, sz * 1.55), "gunmetal")
		cyl(tor, 0.28, 0.3, 0.9, Vector3(0.45, 2.45, sz * 1.55), "hull", Vector3(0, 0, -90), 16)
		cyl(tor, 0.2, 0.2, 0.04, Vector3(0.92, 2.45, sz * 1.55), "glow", Vector3(0, 0, -90), 16)
	var radar := anim(Node3D.new(), "spin", 1.5)
	radar.position = Vector3(-0.35, 4.1, 0)
	tor.add_child(radar)
	cyl(radar, 0.04, 0.04, 0.4, Vector3(0, 0.2, 0), "dark", Vector3.ZERO, 8)
	box(radar, Vector3(0.08, 0.3, 0.9), Vector3(0, 0.45, 0), "hull")
	return r


# --- Minerals -----------------------------------------------------------------

func minerals(variant: int) -> Node3D:
	var r := _root("Minerals%d" % variant)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant
	var shards := []
	for i in rng.randi_range(5, 7):
		shards.append({
			"pos": Vector3(rng.randf_range(-1.1, 1.1), 0, rng.randf_range(-0.8, 0.8)),
			"h": rng.randf_range(1.4, 2.8), "w": rng.randf_range(0.28, 0.45),
			"tilt": Vector3(rng.randf_range(-22, 22), rng.randf_range(0, 360), rng.randf_range(-22, 22)),
		})
	for s in shards:
		var h: float = s.h
		var node := Node3D.new()
		node.position = s.pos
		node.rotation_degrees = s.tilt
		r.add_child(node)
		cyl(node, 0.02, s.w, h, Vector3(0, h / 2.0 - 0.15, 0), "crystal", Vector3.ZERO, 6)
	return r
