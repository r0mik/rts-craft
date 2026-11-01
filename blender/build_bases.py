"""Builds the two main bases (human Headquarters and the Fog's Altar) in Blender.

Run from the game folder:
    Blender -b -P blender/build_bases.py
    Blender -b -P blender/build_bases.py -- --preview DIR   (also renders preview images into DIR)

Saves the editable scenes (modifiers kept live) to blender/hq.blend and blender/altar.blend, then
bakes every modifier, joins the static parts into one mesh and exports assets/models/hq.glb and
assets/models/altar.glb for Godot.

Conventions shared with scripts/models.gd:
  * parts are authored in Godot coordinates (Y up, the front faces +Z) and converted to Blender
    (Z up, the front faces -Y); 1 unit = 1 world unit, the ground is at height 0;
  * footprint 13 x 10 (Defs.BUILDINGS["cc"].size / 10), centred on the origin;
  * material names are the keys of Models.mat() - the game swaps in its own materials by name;
  * "Dish" spins around its local up axis, "Pulse_*" breathe in scale (pivot = object origin).
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OUT = os.path.join(REPO, "assets", "models")

# Godot (x, y, z) -> Blender (x, -z, y): a +90 degree turn around X.
C = Matrix.Rotation(math.pi / 2.0, 4, "X")
Y_UP = Matrix.Rotation(-math.pi / 2.0, 4, "X")  # Blender primitive axis (Z) -> Godot up (Y)

# Preview colours for Blender only; the game replaces each material by Models.mat(<name>).
MATS = {
    "concrete": ((0.40, 0.39, 0.36), 0.95, 0.0),
    "olive": ((0.30, 0.32, 0.20), 0.75, 0.25),
    "plate": ((0.38, 0.38, 0.39), 0.65, 0.5),
    "plate_dark": ((0.20, 0.20, 0.21), 0.65, 0.55),
    "primer": ((0.40, 0.20, 0.15), 0.8, 0.15),
    "rust": ((0.42, 0.24, 0.14), 0.85, 0.3),
    "blood_rust": ((0.30, 0.10, 0.07), 0.7, 0.3),
    "blood": ((0.24, 0.04, 0.03), 0.4, 0.0),
    "black": ((0.07, 0.07, 0.08), 0.6, 0.0),
    "sandbag": ((0.55, 0.48, 0.34), 0.95, 0.0),
    "team": ((0.26, 0.41, 0.61), 0.45, 0.2),
    "grate": ((0.26, 0.27, 0.30), 0.6, 0.5),
    "rubber": ((0.14, 0.14, 0.15), 0.9, 0.0),
    "glass_dark": ((0.05, 0.08, 0.12), 0.08, 0.6),
    "hazard": ((0.75, 0.6, 0.1), 0.6, 0.0),
    "bandage": ((0.66, 0.62, 0.52), 0.95, 0.0),
    "chainlink": ((0.28, 0.16, 0.10), 0.7, 0.5),
    "window": ((1.0, 0.78, 0.45), 1.4),
    "red_glow": ((1.0, 0.3, 0.2), 2.6),
    "amber_glow": ((1.0, 0.7, 0.3), 2.4),
    "fog_glow": ((0.6, 0.1, 0.06), 0.55),
}

_mats = {}
_coll = {}
rng = random.Random(7)


def mat(name):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    spec = MATS[name]
    col = (*spec[0], 1.0)
    bsdf.inputs["Base Color"].default_value = col
    if len(spec) == 2:  # emissive light
        bsdf.inputs["Base Color"].default_value = (spec[0][0] * 0.7, spec[0][1] * 0.7, spec[0][2] * 0.7, 1.0)
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = spec[1] * 2.0
    else:
        bsdf.inputs["Roughness"].default_value = spec[1]
        bsdf.inputs["Metallic"].default_value = spec[2]
    m.diffuse_color = col
    _mats[name] = m
    return m


def coll(name):
    if name not in _coll:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
        _coll[name] = c
    return _coll[name]


def euler(r):
    """Godot rotation_degrees (YXZ order) as a matrix."""
    rx, ry, rz = (math.radians(a) for a in r)
    return Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X") @ Matrix.Rotation(rz, 4, "Z")


def g(p):
    """Godot point -> Blender point."""
    return C @ Vector(p)


def gdir(v):
    """Godot direction -> Blender direction."""
    return C.to_3x3() @ Vector(v)


# --- Mesh builders (Godot local frame, Y up) ------------------------------------

def bm_box(sx, sy, sz):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    return bm


def bm_cyl(r_top, r_bot, h, seg=16):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r_bot, radius2=r_top, depth=h)
    bmesh.ops.transform(bm, matrix=Y_UP, verts=bm.verts)
    return bm


def bm_sphere(r, seg=16, rings=8):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    return bm


def bm_torus(r_major, r_minor, seg=24, seg_minor=8):
    """Ring in the XZ plane around the Y axis (like Godot's TorusMesh)."""
    bm = bmesh.new()
    rows = []
    for i in range(seg):
        a = i * math.tau / seg
        row = []
        for j in range(seg_minor):
            b = j * math.tau / seg_minor
            rr = r_major + r_minor * math.cos(b)
            row.append(bm.verts.new((rr * math.cos(a), r_minor * math.sin(b), rr * math.sin(a))))
        rows.append(row)
    for i in range(seg):
        for j in range(seg_minor):
            a, b = rows[i], rows[(i + 1) % seg]
            bm.faces.new((a[j], b[j], b[(j + 1) % seg_minor], a[(j + 1) % seg_minor]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def bm_prism(points, depth):
    """Polygon in the local XY plane extruded along Z (centred), e.g. a gable or a pointed arch."""
    bm = bmesh.new()
    front = [bm.verts.new((x, y, depth / 2.0)) for x, y in points]
    back = [bm.verts.new((x, y, -depth / 2.0)) for x, y in points]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(points)
    for i in range(n):
        bm.faces.new((front[i], back[i], back[(i + 1) % n], front[(i + 1) % n]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def bm_tube(a, b, r, seg=6):
    """Cylinder from point a to point b (both Godot local)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bm = bm_cyl(r, r, d.length, seg)
    q = Vector((0, 1, 0)).rotation_difference(d.normalized())
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) / 2.0) @ q.to_matrix().to_4x4(), verts=bm.verts)
    return bm


def bm_merge(parts):
    """Merges (bmesh, matrix) pairs into one bmesh."""
    out = bmesh.new()
    for bm, m in parts:
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        me = bpy.data.meshes.new("_tmp")
        bm.to_mesh(me)
        bm.free()
        out.from_mesh(me)
        bpy.data.meshes.remove(me)
    return out


def at(pos=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    return Matrix.Translation(pos) @ euler(rot) @ Matrix.Diagonal((*scale, 1.0))


# --- Objects -----------------------------------------------------------------

def emit(bm, name, m, pos=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), where="Structure"):
    """Turns a Godot-local bmesh into a Blender object at Godot position pos; rotation and scale are
    baked into the mesh so the object stays axis-aligned (its origin is the pivot)."""
    bmesh.ops.transform(bm, matrix=C @ euler(rot) @ Matrix.Diagonal((*scale, 1.0)), verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat(m))
    ob = bpy.data.objects.new(name, me)
    ob.location = g(pos)
    coll(where).objects.link(ob)
    return ob


def box(size, pos, m, rot=(0, 0, 0), name="Box", bevel=0.0, where="Structure"):
    ob = emit(bm_box(*size), name, m, pos, rot, where=where)
    if bevel > 0:
        add_bevel(ob, bevel)
    return ob


def cyl(r_top, r_bot, h, pos, m, rot=(0, 0, 0), seg=16, name="Cyl", where="Structure"):
    return emit(bm_cyl(r_top, r_bot, h, seg), name, m, pos, rot, where=where)


def cutter(size, pos, rot=(0, 0, 0), name="Cut", bm=None):
    ob = emit(bm if bm is not None else bm_box(*size), name, "black", pos, rot, where="Cutters")
    ob.display_type = "WIRE"
    ob.hide_render = True
    return ob


def add_bevel(ob, width, seg=2, angle=40.0):
    md = ob.modifiers.new("Bevel", "BEVEL")
    md.width = width
    md.segments = seg
    md.limit_method = "ANGLE"
    md.angle_limit = math.radians(angle)
    md.miter_outer = "MITER_ARC"
    return md


def add_cut(ob, cutters, name="Cut"):
    """Boolean difference with a set of cutter objects (kept in their own collection)."""
    c = bpy.data.collections.new(ob.name + "_" + name)
    coll("Cutters").children.link(c)
    for ct in cutters:
        for old in list(ct.users_collection):
            old.objects.unlink(ct)
        c.objects.link(ct)
    md = ob.modifiers.new(name, "BOOLEAN")
    md.operation = "DIFFERENCE"
    md.operand_type = "COLLECTION"
    md.collection = c
    md.solver = "EXACT"
    return md


def add_array(ob, count, step_godot, name="Array"):
    md = ob.modifiers.new(name, "ARRAY")
    md.count = count
    md.use_relative_offset = False
    md.use_constant_offset = True
    md.constant_offset_displace = gdir(step_godot)
    return md


def lathe(name, m, profile, pos, rot=(0, 0, 0), thickness=0.03, steps=32, where="Structure"):
    """Spins a (radius, height) profile around the local up axis with a Screw modifier."""
    me = bpy.data.meshes.new(name)
    verts = [(r, 0.0, h) for r, h in profile]
    me.from_pydata(verts, [(i, i + 1) for i in range(len(verts) - 1)], [])
    me.materials.append(mat(m))
    ob = bpy.data.objects.new(name, me)
    ob.matrix_world = Matrix.Translation(g(pos)) @ C @ euler(rot) @ Y_UP
    coll(where).objects.link(ob)
    sc = ob.modifiers.new("Lathe", "SCREW")
    sc.axis = "Z"
    sc.angle = math.tau
    sc.steps = steps
    sc.render_steps = steps
    sc.screw_offset = 0.0
    sc.use_merge_vertices = True
    sc.merge_threshold = 0.001
    if thickness > 0:
        so = ob.modifiers.new("Thickness", "SOLIDIFY")
        so.thickness = thickness
        so.offset = 0.0
    return ob


def cloth(name, m, w, h, pos, rot=(0, 0, 0), wave=0.08, droop=0.05, tatter=0.0, hang=False):
    """Cloth-like flag or banner: a subdivided sheet with a travelling wave that grows away from the
    pole (or the top bar when hang=True), smoothed and given a thickness by modifiers."""
    nx, ny = 14, 10
    bm = bmesh.new()
    grid = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            u, v = i / nx, j / ny
            free = v if hang else u  # 0 at the fixed edge
            x = u * w if not hang else (u - 0.5) * w
            y = -v * h if hang else (0.5 - v) * h
            if hang and j == ny and tatter > 0 and 0 < i < nx:
                y += tatter * (0.5 + 0.5 * math.sin(i * 2.7)) * (1 if i % 2 else 0.4)
            z = wave * free * math.sin(u * 7.0 + v * 2.0) + wave * 0.4 * free * math.sin(v * 9.0)
            y -= droop * free * free
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for j in range(ny):
        for i in range(nx):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    ob = emit(bm, name, m, pos, rot, where="Props")
    so = ob.modifiers.new("Thickness", "SOLIDIFY")
    so.thickness = 0.025
    so.offset = 0.0
    ss = ob.modifiers.new("Smooth", "SUBSURF")
    ss.levels = 1
    ss.render_levels = 1
    return ob


def pulse(name, r, pos, m, stretch=1.0):
    return emit(bm_sphere(r, 12, 6), name, m, pos, scale=(1.0, stretch, 1.0), where="Anim")


def sandbags(a, b, layers=2, name="Sandbags"):
    """Sandbag wall from a to b (Godot ground points): pillow-shaped bags from subdivided boxes."""
    a, b = Vector(a), Vector(b)
    d = b - a
    n = max(1, int(d.length / 0.55))
    yaw = -math.degrees(math.atan2(d.z, d.x))
    parts = []
    for layer in range(layers):
        for i in range(n):
            t = (i + 0.5 + (layer % 2) * 0.5) / n
            if i + 1 + (layer % 2) * 0.5 > n + 0.01:
                continue
            p = a + d * t + Vector((0, 0.13 + layer * 0.24, 0))
            parts.append((bm_box(0.74, 0.34, 0.48),
                          at(p, (rng.uniform(-3, 3), yaw + rng.uniform(-6, 6), rng.uniform(-3, 3)))))
    ob = emit(bm_merge(parts), name, "sandbag", where="Props")
    ss = ob.modifiers.new("Pillow", "SUBSURF")
    ss.levels = 2
    ss.render_levels = 2
    return ob


def barrel(p, m, tilt=(0, 0, 0)):
    parts = [(bm_cyl(0.28, 0.28, 0.85, 16), at(p + Vector((0, 0.425, 0)), tilt))]
    for y in (0.25, 0.6):
        parts.append((bm_torus(0.28, 0.025, 16, 4), at(p + Vector((0, y, 0)), tilt)))
    return emit(bm_merge(parts), "Barrel", m, where="Props")


# --- Bake and export ---------------------------------------------------------------

def bake(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    me.name = ob.name
    if old.users == 0:
        bpy.data.meshes.remove(old)


def join(target, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()
    return target


def finish(name, blend, glb):
    """Saves the editable scene, then bakes, joins and exports the game model."""
    for c in coll("Cutters").children_recursive:
        c.hide_render = True
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 backups
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, blend), compress=True)
    static = [o for c in ("Structure", "Props") for o in coll(c).all_objects if o.type == "MESH"]
    anims = [o for o in coll("Anim").all_objects if o.type == "MESH"]
    for o in static + anims:
        bake(o)
    for o in list(coll("Cutters").all_objects):
        bpy.data.objects.remove(o)
    base = static[0]
    join(base, static)
    base.name = name
    groups = {}  # "Dish" parts are joined into the object named "Dish"
    for o in anims:
        groups.setdefault(o.name.split(".")[0], []).append(o)
    for key, objs in groups.items():
        root = next((o for o in objs if o.name == key), objs[0])
        if len(objs) > 1:
            join(root, objs)
        root.name = key
    bpy.ops.object.select_all(action="DESELECT")
    for o in [base] + list(coll("Anim").all_objects):
        o.select_set(True)
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, glb), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_texcoords=False,
                              export_animations=False, export_extras=False)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in [base] + list(coll("Anim").all_objects))
    mats = sorted({ms.material.name for o in [base] + list(coll("Anim").all_objects) for ms in o.material_slots})
    print("%s: %d triangles, nodes %s, materials %s" % (glb, tris, [base.name] + [o.name for o in coll("Anim").all_objects], mats))


def preview(path, look=(0.0, 2.2, 0.0)):
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 48
    scn.cycles.use_denoising = True
    scn.render.resolution_x, scn.render.resolution_y = 1280, 860
    world = bpy.data.worlds.new("World")
    if world.node_tree is None:
        world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.32, 0.34, 0.38, 1.0)
    bg.inputs["Strength"].default_value = 0.6
    scn.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(6)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    scn.collection.objects.link(sun)
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.lens = 40
    cam.location = g((10.5, 11.5, 15.0))
    cam.rotation_euler = (g(look) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scn.collection.objects.link(cam)
    scn.camera = cam
    ground = emit(bm_box(60, 0.1, 60), "Ground", "concrete", (0, -0.06, 0), where="Preview")
    gm = bpy.data.materials.new("ground")
    if gm.node_tree is None:
        gm.use_nodes = True
    ground.data.materials[0] = gm
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.16, 0.18, 0.12, 1)
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    _coll.clear()
    rng.seed(7)
    for n in ("Structure", "Props", "Anim", "Cutters"):
        coll(n)


# --- Human Headquarters ------------------------------------------------------------

def container(p, m, yaw=90.0, length=2.4, name="Container"):
    """20 ft shipping container: corrugated sides (an arrayed rib), corner castings, door bars."""
    q = euler((0, yaw, 0))
    ob = box((length, 1.0, 1.0), p + Vector((0, 0.5, 0)), m, (0, yaw, 0), name, bevel=0.03, where="Props")
    n = int(length / 0.3)
    rib = box((0.06, 0.86, 1.06), p + q @ Vector((-length / 2.0 + 0.2, 0.5, 0)), m, (0, yaw, 0), name + "Ribs", where="Props")
    add_array(rib, n, (q @ Vector(((length - 0.4) / (n - 1), 0, 0))).to_tuple())
    corners = []
    for sx in (-1, 1):
        for sy in (0, 1):
            for sz in (-1, 1):
                corners.append((bm_box(0.12, 0.12, 0.12), at(q @ Vector((sx * (length / 2 - 0.05), 0.06 + sy * 0.88, sz * 0.45)))))
    for k in range(4):  # locking bars on the door end
        corners.append((bm_cyl(0.025, 0.025, 0.9, 6), at(q @ Vector((length / 2 + 0.02, 0.5, -0.36 + k * 0.24)))))
    emit(bm_merge(corners), name + "Fittings", "plate_dark", p, where="Props")
    return ob


def lattice_mast(p, h, name="Mast"):
    """Triangular lattice radio mast: three legs, arrayed zig-zag bracing, guy wires."""
    rad = 0.13
    legs = [Vector((math.cos(a) * rad, 0, math.sin(a) * rad)) for a in (0.0, math.tau / 3, 2 * math.tau / 3)]
    parts = [(bm_tube(l, l + Vector((0, h, 0)) * 1.0 - l * 0.35, 0.022, 5), Matrix()) for l in legs]
    emit(bm_merge(parts), name + "Legs", "plate_dark", p, where="Props")
    seg = 0.4
    brace = []
    for i in range(3):
        a, b = legs[i], legs[(i + 1) % 3]
        brace.append((bm_tube(a, b + Vector((0, seg, 0)), 0.012, 4), Matrix()))
        brace.append((bm_tube(a, b, 0.012, 4), Matrix()))
    n = int(h * 0.82 / seg)
    br = emit(bm_merge(brace), name + "Bracing", "plate_dark", p + Vector((0, 0.05, 0)), where="Props")
    add_array(br, n, (0, seg, 0))
    br.modifiers.new("Taper", "SIMPLE_DEFORM").deform_method = "TAPER"
    br.modifiers["Taper"].deform_axis = "Z"
    br.modifiers["Taper"].factor = -0.35 / h
    for d in ((1.1, 1.0), (-0.5, 0.3), (0.3, -0.45)):  # guy wires, anchored on the office roof
        top = p + Vector((0, h * 0.75, 0))
        emit(bm_tube(top, p + Vector((d[0], 0.02, d[1])), 0.008, 3), name + "Guy", "plate_dark", where="Props")
    cyl(0.07, 0.07, 0.04, p + Vector((0, 0.02, 0)), "plate_dark", name=name + "Foot", where="Props")


def hq():
    reset()
    W, D = 13.0, 10.0
    # ground slab with expansion joints
    slab = box((W, 0.3, D), (0, 0.15, 0), "concrete", name="Slab", bevel=0.06)
    joints = [cutter((0.06, 0.1, D + 1), (-W / 2 + 2.6 * k, 0.3, 0)) for k in range(1, 5)]
    joints += [cutter((W + 1, 0.1, 0.06), (0, 0.3, -D / 2 + 2.5 * k)) for k in range(1, 4)]
    add_cut(slab, joints, "Joints")
    # bunker: battered concrete walls, splayed firing slits, recessed blast door
    bx, bz, bw, bd = -0.6, -0.6, 7.5, 5.5
    bm = bm_box(bw, 1.8, bd)
    for v in bm.verts:
        if v.co.y > 0:
            v.co.x *= (bw - 0.3) / bw
            v.co.z *= (bd - 0.3) / bd
    bunker = emit(bm, "Bunker", "concrete", (bx, 1.2, bz))
    add_bevel(bunker, 0.08, 3)
    front = bz + bd / 2.0
    slits = []
    for x in (-3.4, -2.2, 1.3, 2.5):
        slits.append(cutter(None, (x, 1.55, front), (0, 0, 0), "Slit",
                            bm_merge([(bm_box(1.0, 0.2, 0.7), Matrix()), (bm_box(1.2, 0.3, 0.2), at((0, 0, 0.3)))])))
    for z in (-2.2, 0.4):
        slits.append(cutter((0.8, 0.2, 1.0), (bx - bw / 2.0, 1.55, z)))
    slits.append(cutter((1.3, 1.5, 0.5), (-0.45, 1.05, front)))  # door recess
    add_cut(bunker, slits, "Openings")
    box((7.2, 1.2, 5.2), (bx, 1.2, bz), "black", name="BunkerInside")
    box((1.1, 1.38, 0.08), (-0.45, 1.0, front - 0.18), "plate_dark", name="BlastDoor", bevel=0.02)
    for k in range(3):  # door reinforcement ribs and a hazard lintel
        box((1.0, 0.07, 0.05), (-0.45, 0.55 + k * 0.45, front - 0.13), "plate", name="DoorRib")
    box((1.35, 0.14, 0.06), (-0.45, 1.85, front + 0.02), "hazard", name="Lintel")
    box((0.3, 0.12, 0.18), (-0.45, 2.0, front + 0.05), "plate_dark", name="DoorLamp")
    box((0.22, 0.06, 0.04), (-0.45, 1.95, front + 0.13), "amber_glow", name="DoorLampGlow")
    box((bw - 0.2, 0.16, bd - 0.2), (bx, 2.15, bz), "concrete", name="Cornice", bevel=0.04)
    box((bw - 0.05, 0.18, 0.04), (bx, 1.9, front - 0.11), "team", name="TeamBand")
    # prefab two-storey office of container modules on the bunker roof
    ox, oz, ow, od = -1.0, -1.0, 5.6, 3.6
    ofront = oz + od / 2.0
    for s in range(2):
        y = 2.8 + s * 1.2
        mod = box((ow, 1.12, od), (ox, y, oz), "olive", name="Office", bevel=0.03)
        wins = [cutter((0.62, 0.48, 0.2), (-3.2 + k * 1.1, y + 0.05, ofront)) for k in range(5)]
        wins += [cutter((0.2, 0.48, 0.62), (ox + ow / 2.0, y + 0.05, oz - 0.9 + k * 1.1)) for k in range(2)]
        if s == 0:
            wins.append(cutter((0.2, 0.9, 0.7), (ox + ow / 2.0, y - 0.1, oz + 1.25)))  # side door
        add_cut(mod, wins, "Windows")
        glow = box((0.6, 0.46, 0.04), (-3.2, y + 0.05, ofront - 0.07), "window", name="Windows")
        add_array(glow, 5, (1.1, 0, 0))
        side = box((0.04, 0.46, 0.6), (ox + ow / 2.0 - 0.07, y + 0.05, oz - 0.9), "window", name="WindowsSide")
        add_array(side, 2, (0, 0, 1.1))
        sill = box((0.72, 0.05, 0.1), (-3.2, y - 0.21, ofront + 0.03), "plate_dark", name="Sills")
        add_array(sill, 5, (1.1, 0, 0))
        mull = box((0.03, 0.46, 0.03), (-3.2, y + 0.05, ofront - 0.04), "plate_dark", name="Mullions")
        add_array(mull, 5, (1.1, 0, 0))
        back = box((0.06, 1.0, 0.05), (ox - ow / 2.0 + 0.2, y, oz - od / 2.0 - 0.01), "olive", name="BackRibs")
        add_array(back, 18, (0.3, 0, 0))
        posts = []
        for sx in (-1, 1):
            for sz in (-1, 1):
                posts.append((bm_box(0.12, 1.16, 0.12), at((ox + sx * (ow / 2 - 0.04), y, oz + sz * (od / 2 - 0.04)))))
        for yy in (y - 0.55, y + 0.55):
            posts.append((bm_box(ow + 0.04, 0.08, 0.08), at((ox, yy, ofront))))
        emit(bm_merge(posts), "OfficeFrame", "plate_dark")
    box((0.7, 0.85, 0.05), (ox + ow / 2.0 - 0.06, 2.7, oz + 1.25), "plate_dark", name="SideDoor", rot=(0, 90, 0))
    box((0.04, 0.4, 1.4), (ox - ow / 2.0 - 0.02, 3.4, oz + 0.3), "team", name="TeamPanel")
    box((ow + 0.2, 0.12, od + 0.2), (ox, 4.66, oz), "plate_dark", name="Roof", bevel=0.03)
    # roof railing, AC units, a water tank
    rail = cyl(0.025, 0.025, 0.5, (ox - ow / 2.0, 4.97, ofront), "plate_dark", seg=6, name="RailPosts")
    add_array(rail, 9, (ow / 8.0, 0, 0))
    box((ow, 0.04, 0.04), (ox, 5.2, ofront), "plate_dark", name="Rail")
    box((ow, 0.04, 0.04), (ox, 4.98, ofront), "plate_dark", name="Rail")
    for x, z in ((-3.2, -0.2), (-2.2, -0.2)):
        box((0.8, 0.5, 0.7), (x, 4.97, z), "plate", name="AC", bevel=0.03)
        cyl(0.28, 0.28, 0.04, (x, 5.23, z), "grate", seg=16, name="ACFan")
    cyl(0.4, 0.4, 0.9, (-0.2, 5.17, -2.3), "primer", seg=20, name="WaterTank")
    cyl(0.42, 0.42, 0.06, (-0.2, 5.62, -2.3), "plate_dark", seg=20, name="WaterTankLid")
    # lattice radio masts with pulsing warning lights
    for i, x in enumerate((-3.3, -1.3)):
        p = Vector((x, 4.72, -2.4))
        lattice_mast(p, 3.6 - i * 0.6)
        top = p + Vector((0, 3.6 - i * 0.6 + 0.06, 0))
        pulse("Pulse_%d" % (i + 1), 0.08, top, "red_glow")
        pulse("Pulse_%d_mid" % (i + 1), 0.05, p + Vector((0.06, 1.9, 0)), "red_glow")
    # satellite dish (spins around its pedestal): lathed paraboloid, yoke, feed horn on struts
    dp = Vector((0.9, 4.72, -1.4))
    cyl(0.14, 0.18, 0.5, dp + Vector((0, 0.25, 0)), "plate_dark", seg=12, name="Dish", where="Anim")
    box((0.36, 0.22, 0.3), dp + Vector((0, 0.6, 0)), "plate", name="Dish", where="Anim").modifiers.clear()
    for sz in (-1, 1):
        box((0.06, 0.45, 0.06), dp + Vector((0.02, 0.85, sz * 0.18)), "plate_dark", name="Dish", where="Anim")
    centre = dp + Vector((0.12, 1.05, 0))
    tilt = (0, 0, -55)
    prof = [(0.0, 0.0)] + [(0.85 * t, 0.3 * t * t) for t in (0.2, 0.4, 0.6, 0.8, 1.0)] + [(0.88, 0.31)]
    lathe("Dish", "plate", prof, centre, tilt, thickness=0.035, where="Anim")
    q = euler(tilt)
    lathe("Dish", "plate_dark", [(0.86, 0.29), (0.9, 0.33)], centre, tilt, thickness=0.03, where="Anim")
    feed = centre + q @ Vector((0, 0.75, 0))
    struts = [(bm_tube(centre + q @ Vector((math.cos(a) * 0.62, 0.17, math.sin(a) * 0.62)), feed, 0.012, 4), Matrix())
              for a in (0.3, 0.3 + math.tau / 3, 0.3 + 2 * math.tau / 3)]
    struts.append((bm_cyl(0.05, 0.07, 0.16, 10), at(feed, tilt)))
    emit(bm_merge(struts), "Dish", "plate_dark", where="Anim")
    # pivot of every Dish part = the pedestal foot
    for o in coll("Anim").all_objects:
        if o.name.startswith("Dish"):
            shift = o.matrix_world.translation - g(dp)
            if o.modifiers.get("Lathe"):
                continue
            o.data.transform(Matrix.Translation(shift))
            o.location = g(dp)
    # external steel stairs up the bunker's right side
    sx0, steps = 3.6, 9
    step = box((0.8, 0.05, 0.3), (sx0, 0.4, 2.25), "grate", name="Steps")
    add_array(step, steps, (0, 0.2, -0.31))
    length = math.hypot(0.2 * steps, 0.31 * steps)
    ang = math.degrees(math.atan2(0.2, 0.31))
    for sxx in (-0.42, 0.42):
        box((0.06, 0.2, length), (sx0 + sxx, 1.25, 0.85), "plate_dark", name="Stringer", rot=(ang, 0, 0))
        box((0.04, 0.04, length), (sx0 + sxx, 2.15, 0.95), "plate_dark", name="Handrail", rot=(ang, 0, 0))
    post = cyl(0.02, 0.02, 0.9, (sx0 + 0.42, 0.85, 2.25), "plate_dark", seg=6, name="StairPosts")
    add_array(post, 4, (0, 0.6, -0.93))
    post2 = cyl(0.02, 0.02, 0.9, (sx0 - 0.42, 0.85, 2.25), "plate_dark", seg=6, name="StairPosts")
    add_array(post2, 4, (0, 0.6, -0.93))
    box((0.9, 0.06, 0.04), (sx0, 0.75, 2.46), "hazard", name="StairEdge")
    # team flag on a pole, cloth-like
    fp = Vector((5.6, 0.3, 3.9))
    cyl(0.04, 0.05, 4.2, fp + Vector((0, 2.1, 0)), "plate_dark", seg=8, name="FlagPole", where="Props")
    emit(bm_sphere(0.07, 10, 5), "FlagFinial", "plate", fp + Vector((0, 4.25, 0)), where="Props")
    cloth("Flag", "team", 1.1, 0.68, fp + Vector((0.04, 3.75, 0)), (0, 0, 0), wave=0.09)
    cyl(0.18, 0.22, 0.25, fp + Vector((0, 0.12, 0)), "concrete", seg=10, name="FlagBase", where="Props")
    # sandbag walls guarding the front, with a gap at the door
    sandbags((-5.8, 0.3, 4.3), (-1.6, 0.3, 4.3), 3)
    sandbags((0.7, 0.3, 4.3), (3.9, 0.3, 4.3), 3)
    sandbags((-5.8, 0.3, 4.3), (-5.8, 0.3, 2.4), 2)
    # stacked containers and fuel drums at the back
    container(Vector((4.9, 0.3, -2.6)), "primer", 90.0, name="Container")
    container(Vector((4.9, 1.3, -2.4)), "olive", 84.0, name="Container")
    container(Vector((-5.2, 0.3, -3.6)), "plate", 0.0, 2.2, name="Container")
    for k, (x, z) in enumerate(((-5.6, -1.6), (-5.0, -1.8), (-5.4, -1.0), (-4.9, -1.15))):
        barrel(Vector((x, 0.3, z)), "olive" if k % 2 else "rust")
    barrel(Vector((-5.85, 0.58, -0.4)), "rust", (90, 30, 0))
    # generator with an exhaust pipe and a floodlight on a pole
    box((1.1, 0.8, 0.7), (-5.4, 0.7, 1.0), "olive", name="Generator", bevel=0.04)
    box((0.9, 0.05, 0.5), (-5.4, 1.13, 1.0), "grate", name="GeneratorGrille")
    emit(bm_tube((-5.0, 1.1, 0.8), (-5.0, 1.7, 0.8), 0.04, 8), "Exhaust", "plate_dark", where="Props")
    cyl(0.04, 0.05, 3.2, (-6.0, 1.9, 3.4), "plate_dark", seg=8, name="LightPole", where="Props")
    box((0.5, 0.3, 0.25), (-5.85, 3.5, 3.55), "plate_dark", name="Floodlight", rot=(-25, 30, 0), where="Props")
    box((0.42, 0.22, 0.04), (-5.8, 3.47, 3.68), "amber_glow", name="FloodlightGlow", rot=(-25, 30, 0), where="Props")
    # jeep: bevelled body, bonnet, windscreen frame, wheels with hubs, spare wheel and antenna
    jp, jy = Vector((5.4, 0.3, 0.9)), 90.0
    q = euler((0, jy, 0))
    J = lambda v: jp + q @ Vector(v)
    box((1.7, 0.42, 0.9), J((0, 0.5, 0)), "olive", (0, jy, 0), "Jeep", bevel=0.06, where="Props")
    bon = box((0.62, 0.16, 0.86), J((0.5, 0.78, 0)), "olive", (0, jy, 0), "JeepBonnet", bevel=0.04, where="Props")
    box((0.05, 0.36, 0.84), J((0.16, 1.0, 0)), "plate_dark", (0, jy, -12), "JeepScreen", where="Props")
    box((0.03, 0.3, 0.76), J((0.18, 1.0, 0)), "glass_dark", (0, jy, -12), "JeepGlass", where="Props")
    box((0.8, 0.06, 0.9), J((-0.4, 1.15, 0)), "olive", (0, jy, 0), "JeepCanvasTop", bevel=0.02, where="Props")
    for sz in (-1, 1):
        emit(bm_tube(J((-0.75, 0.7, sz * 0.42)), J((-0.75, 1.15, sz * 0.42)), 0.02, 5), "JeepFrame", "plate_dark", where="Props")
        emit(bm_tube(J((-0.05, 0.7, sz * 0.42)), J((-0.05, 1.15, sz * 0.42)), 0.02, 5), "JeepFrame", "plate_dark", where="Props")
    for sx in (-1, 1):
        for sz in (-1, 1):
            emit(bm_torus(0.15, 0.08, 16, 8), "JeepWheel", "rubber", J((sx * 0.55, 0.53, sz * 0.47)), (90, jy, 0), where="Props")
            cyl(0.09, 0.09, 0.1, J((sx * 0.55, 0.53, sz * 0.47)), "plate_dark", (90, jy, 0), 10, "JeepHub", where="Props")
    emit(bm_torus(0.14, 0.07, 16, 6), "JeepSpare", "rubber", J((-0.9, 0.6, 0)), (0, jy, 90), where="Props")
    emit(bm_tube(J((-0.8, 0.7, 0.4)), J((-0.95, 2.1, 0.45)), 0.01, 3), "JeepAntenna", "plate_dark", where="Props")
    box((0.06, 0.1, 0.6), J((0.83, 0.55, 0)), "plate_dark", (0, jy, 0), "JeepBumper", where="Props")
    # concrete jersey barriers flanking the entrance
    for x in (-2.2, 1.2):
        bar = emit(bm_prism([(-0.3, 0), (0.3, 0), (0.12, 0.25), (0.08, 0.6), (-0.08, 0.6), (-0.12, 0.25)], 1.0),
                   "Barrier", "concrete", (x, 0.3, 4.9), (0, 90 + (x * 7), 0), where="Props")
        add_bevel(bar, 0.02)
        box((1.0, 0.02, 0.17), (x, 0.91, 4.9), "hazard", (0, x * 7, 0), "BarrierStripe", where="Props")
    return "Headquarters"


# --- Fog Altar ------------------------------------------------------------------

def gothic(w, h, depth):
    """Pointed-arch opening (bottom centre at the origin)."""
    pts = [(-w / 2, 0), (w / 2, 0), (w / 2, h - w * 0.6)]
    for k in range(1, 6):
        a = k / 6.0
        pts.append((w / 2 * (1 - a) ** 0.8, h - w * 0.6 + w * 0.6 * math.sin(a * math.pi / 2)))
    pts.append((0, h))
    for x, y in reversed(pts[3:-1]):
        pts.append((-x, y))
    pts.append((-w / 2, h - w * 0.6))
    return bm_prism(pts, depth)


def chainlink(name, length, height, pos, rot, torn=0.25):
    """Chain-link mesh: a diagonal grid turned into wire with a Wireframe modifier, holes torn out."""
    cell = 0.22
    nx, ny = int(length / cell), int(height / cell)
    bm = bmesh.new()
    vs = [[bm.verts.new((-length / 2 + i * cell, j * cell, 0.0)) for i in range(nx + 1)] for j in range(ny + 1)]
    for j in range(ny):
        for i in range(nx):
            hole = rng.random() < torn * (1.0 if j > ny // 2 else 0.4)
            if not hole:
                bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    for v in bm.verts:  # sag
        v.co.z += 0.06 * math.sin(v.co.x * 1.3) * (v.co.y / height)
    ob = emit(bm, name, "chainlink", pos, rot, where="Props")
    wf = ob.modifiers.new("Wire", "WIREFRAME")
    wf.thickness = 0.018
    wf.use_replace = True
    return ob


def altar():
    reset()
    W, D = 13.0, 10.0
    # cracked concrete slab
    slab = box((W, 0.35, D), (0, 0.175, 0), "concrete", name="Slab", bevel=0.05)
    cracks = []
    for k in range(6):
        x0, z0 = rng.uniform(-5.5, 5.0), rng.uniform(-4.2, 4.2)
        pts, x, z = [], x0, z0
        for s in range(5):
            x += rng.uniform(0.25, 0.55)
            z += rng.uniform(-0.3, 0.3)
            pts.append((x, z))
        parts = []
        px, pz = x0, z0
        for x, z in pts:
            parts.append((bm_tube((px, 0.35, pz), (x, 0.35, z), 0.05, 3), Matrix()))
            px, pz = x, z
        cracks.append(cutter(None, (0, 0, 0), name="Crack", bm=bm_merge(parts)))
    add_cut(slab, cracks, "Cracks")
    # broken chain-link fence along both sides
    for sx in (-1, 1):
        for k in range(4):
            z = -D / 2 + 0.4 + k * (D - 0.8) / 3.0
            cyl(0.05, 0.05, 1.7, (sx * (W / 2 - 0.15), 1.2, z), "rust", (0, 0, sx * (4 + k * 3)), 6, "FencePost", "Props")
        chainlink("Fence", D * 0.62, 1.25, (sx * (W / 2 - 0.15), 0.5, -D * 0.12), (sx * 4, 90, 0), torn=0.3)
        emit(bm_tube((sx * (W / 2 - 0.15), 1.95, -D / 2 + 0.4), (sx * (W / 2 - 0.1), 1.8, D / 2 - 1.2), 0.025, 5),
             "FenceRail", "rust", where="Props")
    # nave: buttressed concrete walls, gothic windows and door cut by booleans
    nx, nz, nw, nd, nh = -0.5, -0.8, 7.0, 5.6, 3.2
    ny = 0.35 + nh / 2
    front = nz + nd / 2
    nave = box((nw, nh, nd), (nx, ny, nz), "concrete", name="Nave", bevel=0.05)
    opens = [cutter(None, (-0.5, 0.35, front), name="Door", bm=gothic(1.4, 2.4, 0.8))]
    for x in (-2.8, 1.75):
        opens.append(cutter(None, (x, 1.35, front), name="Window", bm=gothic(0.85, 1.7, 0.8)))
    for z in (-2.6, -0.6, 1.2):
        opens.append(cutter(None, (nx - nw / 2, 1.35, z), (0, 90, 0), "Window", gothic(0.8, 1.6, 0.8)))
    add_cut(nave, opens, "Openings")
    box((nw - 0.5, nh - 0.2, nd - 0.5), (nx, ny, nz), "black", name="NaveInside")
    for x in (-2.8, 1.75):  # boards nailed across the windows
        for b in range(3):
            box((1.05, 0.11, 0.05), (x + rng.uniform(-0.05, 0.05), 1.75 + b * 0.42, front + 0.04), "rust",
                (0, 0, rng.uniform(-22, 22)), "Board")
    for z in (-2.6, -0.6, 1.2):
        for b in range(2):
            box((0.05, 0.11, 1.0), (nx - nw / 2 - 0.04, 1.8 + b * 0.5, z), "rust", (rng.uniform(-20, 20), 0, 0), "Board")
    for side in (-1, 1):  # double door leaves, one ajar
        box((0.68, 2.0, 0.07), (-0.5 + side * 0.35, 1.36, front - 0.22), "blood_rust",
                   (0, 0 if side < 0 else -18, 0), "DoorLeaf", bevel=0.01)
    plank = box((0.66, 0.06, 0.04), (-0.85, 0.6, front - 0.2), "rust", name="DoorPlanks")
    add_array(plank, 5, (0, 0.38, 0))
    emit(bm_torus(0.07, 0.015, 12, 4), "DoorRing", "rust", (-0.6, 1.3, front - 0.2), (90, 0, 0))
    for z in (-3.1, -1.6, -0.1, 1.4):  # buttresses on the left wall
        bm = bm_prism([(0, 0), (0.6, 0), (0.6, 0.15), (0.15, 2.6), (0, 2.8)], 0.5)
        b = emit(bm, "Buttress", "concrete", (nx - nw / 2, 0.35, z), (0, 180, 0))
        add_bevel(b, 0.03)
    for x in (nx - nw / 2 + 0.25, nx + nw / 2 - 0.25):  # corner buttresses on the front
        bm = bm_prism([(0, 0), (0.55, 0), (0.55, 0.15), (0.12, 2.7), (0, 2.9)], 0.5)
        b = emit(bm, "Buttress", "concrete", (x, 0.35, front), (0, -90, 0))
        add_bevel(b, 0.03)
    for k in range(2):  # steps to the door
        box((1.9 - k * 0.3, 0.14, 0.45 - k * 0.15), (-0.5, 0.42 + k * 0.14, front + 0.22 - k * 0.07), "concrete",
            name="Step", bevel=0.02)
    # pitched roof (ridge along X): rusted slabs with corrugation ribs, holes rotted through both
    pitch = 32.0
    ry = 0.35 + nh
    t = math.tan(math.radians(pitch))
    rise = t * nd / 2
    run = nd / 2 + 0.35
    slope = run / math.cos(math.radians(pitch))
    for sz in (-1, 1):
        cz = nz + sz * run / 2
        cy = ry + rise - t * run / 2 + 0.06
        roof = box((nw + 0.5, 0.12, slope), (nx, cy, cz), "blood_rust", (sz * pitch, 0, 0), "Roof")
        ribs = box((0.07, 0.07, slope), (nx - nw / 2 - 0.15, cy + 0.08, cz), "rust", (sz * pitch, 0, 0), "RoofRibs")
        add_array(ribs, 26, (0.29, 0, 0))
        holes = [(rng.uniform(0.7, 1.1), rng.uniform(0.5, 0.9), nx - 2.2 + k * 2.8 + sz * 0.5, rng.uniform(-30, 30))
                 for k in range(2 if sz > 0 else 1)]
        for target in (roof, ribs):
            add_cut(target, [cutter((hw, 1.0, hd), (hx, cy, cz + sz * 0.2), (sz * pitch, yaw, 0)) for hw, hd, hx, yaw in holes],
                    "Holes")
    box((nw + 0.5, 0.14, 0.14), (nx, ry + rise + 0.1, nz), "rust", name="Ridge", rot=(45, 0, 0))
    emit(bm_prism([(-nd / 2 + 0.3, 0), (nd / 2 - 0.3, 0), (0, rise - 0.25)], nw - 0.6), "RoofInside", "black",
         (nx, ry, nz), (0, 90, 0))
    # gables close the X ends; a rose window is cut into the left one
    gables = []
    for xx in (nx - nw / 2 + 0.15, nx + nw / 2 - 0.15):
        gb = emit(bm_prism([(-nd / 2, 0), (nd / 2, 0), (0, rise)], 0.3), "Gable", "concrete", (xx, ry, nz), (0, 90, 0))
        add_bevel(gb, 0.03)
        gables.append(gb)
    add_cut(gables[0], [cutter(None, (gables[0].location.x, ry + rise * 0.4, nz), (0, 0, 90), "Rose",
                               bm_cyl(0.45, 0.45, 0.6, 16))], "Rose")
    # a portico over the door: gable on two columns, steep rusted roof; it carries the sun halo
    pz = front + 0.3
    porch = emit(bm_prism([(-1.2, 0), (1.2, 0), (0, 1.3)], 0.8), "PorchGable", "concrete", (-0.5, 2.9, pz))
    add_bevel(porch, 0.03)
    box((2.5, 0.16, 0.9), (-0.5, 2.85, pz + 0.02), "concrete", name="PorchBeam", bevel=0.03)
    for sx in (-1, 1):
        cyl(0.13, 0.15, 2.4, (-0.5 + sx * 1.05, 1.57, pz + 0.3), "concrete", seg=12, name="PorchColumn")
        box((0.36, 0.12, 0.36), (-0.5 + sx * 1.05, 2.72, pz + 0.3), "concrete", name="PorchCapital", bevel=0.02)
        run_p = 1.4
        box((run_p / math.cos(math.radians(47)), 0.1, 1.0), (-0.5 + sx * run_p / 2, 4.26 - math.tan(math.radians(47)) * run_p / 2, pz + 0.05),
            "blood_rust", (0, 0, -sx * 47), "PorchRoof")
    # bell tower: concrete shaft, belfry with arched openings, rusted spire, bent cross, broken clock
    tx, tz, tw = 3.6, -1.5, 1.8
    shaft = box((tw, 5.85, tw), (tx, 0.35 + 5.85 / 2, tz), "concrete", name="Tower", bevel=0.04)
    add_cut(shaft, [cutter(None, (tx, 2.5, tz + tw / 2), name="TowerSlit", bm=gothic(0.3, 0.9, 0.5)),
                    cutter(None, (tx, 3.9, tz + tw / 2), name="TowerSlit", bm=gothic(0.3, 0.9, 0.5))], "Slits")
    box((tw - 0.3, 5.5, tw - 0.3), (tx, 3.1, tz), "black", name="TowerInside")
    for y in (6.2, 7.6):
        box((tw + 0.25, 0.18, tw + 0.25), (tx, y + 0.09, tz), "concrete", name="Cornice", bevel=0.04)
    belfry = box((tw, 1.25, tw), (tx, 6.9, tz), "concrete", name="Belfry", bevel=0.03)
    add_cut(belfry, [cutter(None, (tx, 6.3, tz), name="Arch", bm=gothic(1.1, 1.1, 2.4)),
                     cutter(None, (tx, 6.3, tz), (0, 90, 0), "Arch", gothic(1.1, 1.1, 2.4))], "Arches")
    spire = cyl(0.0, 1.35, 2.1, (tx, 7.78 + 1.05, tz), "blood_rust", (0, 45, 0), 4, "Spire")
    add_bevel(spire, 0.02, 1)
    cross = [(bm_box(0.09, 1.0, 0.09), at((0, 0.5, 0))), (bm_box(0.55, 0.09, 0.09), at((0, 0.68, 0)))]
    emit(bm_merge(cross), "Cross", "rust", (tx, 9.85, tz), (0, 20, 14))
    clock = Vector((tx, 5.2, tz + tw / 2 + 0.03))
    cyl(0.42, 0.42, 0.04, clock, "black", (90, 0, 0), 20, "ClockFace")
    emit(bm_torus(0.42, 0.05, 20, 6), "ClockRim", "rust", clock + Vector((0, 0, 0.02)), (90, 0, 0))
    box((0.04, 0.32, 0.02), clock + Vector((0.08, -0.12, 0.04)), "rust", (0, 0, 150), "ClockHand")
    box((0.04, 0.22, 0.02), clock + Vector((-0.04, 0.08, 0.04)), "rust", (0, 0, 20), "ClockHand")
    # the bell: lathed bronze-rust profile, hung from a beam, with a clapper
    bell_prof = [(0.0, 0.85), (0.18, 0.85), (0.25, 0.78), (0.28, 0.6), (0.31, 0.35), (0.4, 0.12), (0.5, 0.02), (0.5, 0.0)]
    lathe("Bell", "rust", bell_prof, (tx, 6.45, tz), thickness=0.05, steps=28)
    emit(bm_sphere(0.08, 10, 5), "Clapper", "plate_dark", (tx, 6.48, tz))
    box((tw, 0.14, 0.14), (tx, 7.4, tz), "rust", name="BellBeam")
    emit(bm_tube((tx, 7.33, tz), (tx, 7.27, tz), 0.06, 8), "BellHanger", "rust")
    # the Order's sun halo over the entrance: concentric rings and long and short rays
    hp = Vector((-0.5, 5.45, pz + 0.5))
    parts = [(bm_torus(0.72, 0.07, 32, 8), Matrix()), (bm_torus(0.34, 0.05, 24, 6), Matrix())]
    for k in range(16):
        a = k * math.tau / 16
        ln = 0.55 if k % 2 == 0 else 0.3
        ray = bm_cyl(0.0, 0.06, ln, 4)
        parts.append((ray, Matrix.Translation((math.cos(a) * (0.79 + ln / 2), 0, math.sin(a) * (0.79 + ln / 2)))
                      @ Matrix.Rotation(-a + math.pi / 2, 4, "Y") @ Matrix.Rotation(math.pi / 2, 4, "X")))
    for k in range(3):
        a = k * math.tau / 3 + math.pi / 2
        parts.append((bm_tube((0, 0, 0), (math.cos(a) * 0.72, 0, math.sin(a) * 0.72), 0.03, 5), Matrix()))
    emit(bm_merge(parts), "Halo", "rust", hp, (90, 0, 0))
    emit(bm_tube((-0.5, 4.2, pz + 0.3), hp + Vector((0, -0.34, 0)), 0.04, 6), "HaloMount", "rust")
    # altar stone: bevelled block with a mensa slab, the halo carved into the front, blood and candles
    ap = Vector((-0.5, 0.35, 3.75))
    stone = box((2.0, 0.75, 0.9), ap + Vector((0, 0.375, 0)), "concrete", name="AltarStone", bevel=0.05)
    carve = cutter(None, ap + Vector((0, 0.38, 0.45)), (90, 0, 0), "Carve", bm_torus(0.22, 0.04, 20, 6))
    chip = cutter((0.5, 0.4, 0.4), ap + Vector((0.95, 0.75, 0.4)), (20, 30, 15), "Chip")
    add_cut(stone, [carve, chip], "Carving")
    box((2.3, 0.12, 1.1), ap + Vector((0, 0.81, 0)), "concrete", name="Mensa", bevel=0.03)
    box((1.8, 0.03, 0.8), ap + Vector((0.1, 0.885, -0.05)), "blood", name="BloodPool", bevel=0.01)
    drips = []
    for k in range(6):
        x = -0.8 + k * 0.33 + rng.uniform(-0.05, 0.05)
        ln = rng.uniform(0.15, 0.55)
        drips.append((bm_cyl(0.025, 0.02, ln, 6), at(ap + Vector((x, 0.86 - ln / 2, 0.56)))))
        drips.append((bm_sphere(0.03, 6, 4), at(ap + Vector((x, 0.86 - ln, 0.56)))))
    emit(bm_merge(drips), "BloodDrips", "blood")
    emit(bm_sphere(0.5, 16, 6), "BloodSplat", "blood", ap + Vector((0.4, 0.0, 0.75)), scale=(1.4, 0.03, 0.9), where="Props")
    cand = []
    for k in range(7):
        x = -0.9 + k * 0.3
        z = -0.2 + (k % 2) * 0.3
        h = 0.18 + (k * 37 % 5) * 0.05
        base = ap + Vector((x, 0.87, z))
        cand.append((bm_cyl(0.045, 0.05, h, 8), at(base + Vector((0, h / 2, 0)))))
        cand.append((bm_cyl(0.07, 0.09, 0.03, 8), at(base + Vector((0, 0.015, 0)))))  # wax puddle
        pulse("Pulse_Candle_%d" % k, 0.035, base + Vector((0, h + 0.06, 0)), "amber_glow", 1.7)
    emit(bm_merge(cand), "Candles", "bandage")
    for sx in (-1, 1):  # iron candelabra stands at the altar's ends
        p = ap + Vector((sx * 1.45, 0, 0.1))
        parts = [(bm_cyl(0.03, 0.03, 1.4, 6), at(p + Vector((0, 0.7, 0)))), (bm_cyl(0.0, 0.2, 0.15, 6), at(p + Vector((0, 0.07, 0)))),
                 (bm_cyl(0.12, 0.08, 0.06, 8), at(p + Vector((0, 1.42, 0))))]
        emit(bm_merge(parts), "Candelabrum", "rust", where="Props")
        cyl(0.05, 0.05, 0.25, p + Vector((0, 1.58, 0)), "bandage", seg=8, name="TallCandle", where="Props")
        pulse("Pulse_Candle_%s" % ("L" if sx < 0 else "R"), 0.045, p + Vector((0, 1.78, 0)), "amber_glow", 1.7)
    # the team banner: a tattered cloth on a pole with a crossbar
    bp = Vector((-4.6, 0.35, 2.9))
    cyl(0.04, 0.05, 3.4, bp + Vector((0, 1.7, 0)), "rust", seg=6, name="BannerPole", where="Props")
    emit(bm_tube(bp + Vector((-0.55, 3.15, 0)), bp + Vector((0.55, 3.15, 0)), 0.025, 5), "BannerBar", "rust", where="Props")
    cloth("Banner", "team", 1.0, 1.5, bp + Vector((0, 3.13, 0.04)), wave=0.05, droop=0.0, tatter=0.18, hang=True)
    # graveyard: tilted headstones and an iron cross at the right front; rusted drums at the back
    for k, (x, z) in enumerate(((4.6, 2.2), (5.5, 3.0), (4.2, 4.1), (5.4, 4.3), (3.0, 3.4))):
        hs = [(bm_box(0.55, 0.6, 0.14), at((0, 0.3, 0))), (bm_cyl(0.275, 0.275, 0.14, 12), at((0, 0.6, 0), (90, 0, 0)))]
        st = emit(bm_merge(hs), "Headstone", "concrete", (x, 0.3, z), (rng.uniform(-14, 10), rng.uniform(-25, 25), rng.uniform(-12, 12)), where="Props")
        add_bevel(st, 0.02)
        box((0.7, 0.08, 0.3), (x, 0.38, z + 0.4), "concrete", (0, rng.uniform(-20, 20), 0), "GraveSlab", where="Props")
    cross = [(bm_box(0.07, 1.2, 0.07), at((0, 0.6, 0))), (bm_box(0.6, 0.07, 0.07), at((0, 0.85, 0)))]
    emit(bm_merge(cross), "IronCross", "rust", (2.6, 0.35, 4.3), (8, -15, -18), where="Props")
    for k, (x, z) in enumerate(((-5.4, -3.6), (-4.8, -3.9), (-5.6, -2.9))):
        barrel(Vector((x, 0.35, z)), "rust" if k != 1 else "blood_rust", (0, 0, 6 * k))
    barrel(Vector((-4.5, 0.62, -3.0)), "rust", (90, 70, 0))
    # pews thrown out of the chapel
    for k in range(2):
        pw = [(bm_box(1.6, 0.06, 0.4), at((0, 0.45, 0))), (bm_box(1.6, 0.5, 0.05), at((0, 0.7, -0.2)))]
        for sx in (-1, 1):
            pw.append((bm_box(0.06, 0.5, 0.42), at((sx * 0.75, 0.22, 0))))
        emit(bm_merge(pw), "Pew", "rust", (-5.0 + k * 0.4, 0.35 + k * 0.25, 0.4 - k * 0.9), (k * 70, 20 + k * 40, k * 10), where="Props")
    return "FogAltar"


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    prev = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    for fn, blend, glb in ((hq, "hq.blend", "hq.glb"), (altar, "altar.blend", "altar.glb")):
        name = fn()
        finish(name, blend, glb)
        if prev:
            preview(os.path.join(prev, glb.replace(".glb", ".png")))


main()
