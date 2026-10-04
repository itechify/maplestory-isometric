"""Top-down preview of the world layout (footprints, anchors, links, overlaps).

blender -b --factory-startup --python scripts/layout_preview.py -- <out.png>
"""

import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))

import bmesh  # noqa: E402
import bpy  # noqa: E402

from misostory import layout as LY  # noqa: E402
from misostory import materials as M  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = argv[0] if argv else os.path.join(ROOT, "renders", "_layout", "layout.png")

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
scn = bpy.context.scene
scn.render.engine = "BLENDER_EEVEE"
scn.render.resolution_x, scn.render.resolution_y = 1800, 1100
scn.view_settings.view_transform = "Standard"
scn.world = bpy.data.worlds.new("W")
scn.world.use_nodes = True
scn.world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.08, 0.12, 1)

origins = LY.resolve()
overl = set(a for p in LY.overlaps() for a in p)
COL = {"Maple Road": "#7BC86C", "Rainbow Street": "#F2B84B"}


def emit(name, hx):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = M.hex_to_linear(hx)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o.inputs[0])
    return m


def poly_obj(name, pts, z, mat):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, z)) for x, y in pts]
    bm.faces.new(vs)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    scn.collection.objects.link(ob)
    return ob


def text(s, x, y, size=4.0, mat=None):
    cu = bpy.data.curves.new("t", "FONT")
    cu.body = s
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    ob = bpy.data.objects.new("t", cu)
    ob.location = (x, y, 2)
    ob.rotation_euler = (0, 0, math.radians(LY.GEO_ROT))
    scn.collection.objects.link(ob)
    if mat:
        cu.materials.append(mat)
    return ob


m_white = emit("white", "#FFFFFF")
m_red = emit("red", "#FF3030")
m_link = emit("link", "#FF60D0")
allpts = []
for mid, m in LY.MAPS.items():
    if m["kind"] == "interior":
        continue
    fp = LY.footprint_world(mid, origins)
    allpts += fp
    col = "#FF5050" if mid in overl else COL[m["street"]]
    poly_obj(f"fp_{mid}", fp, 0, emit(f"m{mid}", col))
    inner = LY.footprint_world(mid, origins, margin=-0.8)
    poly_obj(f"fpi_{mid}", inner, 0.1, emit(f"mi{mid}", "#2A3A2A" if m["street"] == "Maple Road" else "#3A3220"))
    cx = sum(p[0] for p in fp) / 4
    cy = sum(p[1] for p in fp) / 4
    text(f"{mid}\n{m['name'][:22]}", cx, cy, size=3.2, mat=m_white)
    # progression arrow (local +X)
    o = origins[mid]
    for name, (ax, ay, az) in m["anchors"].items():
        wx, wy, wz = LY.anchor_world(mid, name, origins)
        poly_obj("a", [(wx - 1.2, wy - 1.2), (wx + 1.2, wy - 1.2), (wx + 1.2, wy + 1.2), (wx - 1.2, wy + 1.2)], 0.5,
                 m_white)
for child, ca, parent, pa, gap, bearing in LY.LINKS:
    a = LY.anchor_world(parent, pa, origins)
    b = LY.anchor_world(child, ca, origins)
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dy) or 1
    nx, ny = -dy / L * 0.7, dx / L * 0.7
    poly_obj("l", [(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny), (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)],
             0.6, m_link)

c, sn = math.cos(math.radians(-LY.GEO_ROT)), math.sin(math.radians(-LY.GEO_ROT))
gpts = [(x * c - y * sn, x * sn + y * c) for x, y in allpts]
xs = [p[0] for p in gpts]
ys = [p[1] for p in gpts]
cam_d = bpy.data.cameras.new("cam")
cam_d.type = "ORTHO"
cam_d.ortho_scale = max(max(xs) - min(xs), (max(ys) - min(ys)) * 1800 / 1100) * 1.06
cam = bpy.data.objects.new("cam", cam_d)
gx, gy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
c2, s2 = math.cos(math.radians(LY.GEO_ROT)), math.sin(math.radians(LY.GEO_ROT))
cam.location = (gx * c2 - gy * s2, gx * s2 + gy * c2, 100)
cam.rotation_euler = (0, 0, math.radians(LY.GEO_ROT))
scn.collection.objects.link(cam)
scn.camera = cam
scn.render.filepath = out
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.render.render(write_still=True)
print("OVERLAPS", LY.overlaps())
