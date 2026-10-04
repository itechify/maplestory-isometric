"""Style/regression test diorama.

blender -b --factory-startup --python scripts/style_test.py -- <out.png> [mode=cel|soft] [view=AgX|Standard]
         [look=...] [sun=3.6] [res=1600x900]
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))

import bpy  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = argv[0] if argv else os.path.join(ROOT, "renders", "_style", "test.png")
opts = dict(a.split("=", 1) for a in argv[1:] if "=" in a)

from misostory import materials as M  # noqa: E402

M.STYLE["mode"] = opts.get("mode", "cel")
from misostory import core, geo, kit, scene_setup  # noqa: E402
from misostory.mapkit import MapCtx  # noqa: E402

kit.OUTLINE["enabled"] = opts.get("outline", "1") == "1"

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)

res = tuple(int(v) for v in opts.get("res", "1600x900").split("x"))
scene_setup.setup_render(res=res, samples=int(opts.get("samples", 32)), view=opts.get("view", "Standard"),
                         look=opts.get("look", "AgX - Punchy" if opts.get("view", "Standard") == "AgX" else "None"))
scene_setup.setup_world(strength=float(opts.get("world", 1.0)))
scene_setup.setup_sun(energy=float(opts.get("sun", 3.6)))

meta = {"id": -1, "slug": "StyleTest", "name": "Style Test", "size": (60, 40), "kind": "field"}
m = MapCtx(meta, origin=(0, 0, 0), yaw=0)

# --- terrain ---
m.terrace("Ground", geo.rect(-6, -6, 66, 46), top=0.0, bottom=-4.0)
m.terrace("Mid", [(8, 18), (40, 16), (46, 24), (44, 38), (10, 38), (6, 28)], top=2.4, bottom=-0.5)
m.terrace("Upper", [(14, 28), (34, 27), (36, 36), (16, 37)], top=5.0, bottom=2.0, style="grass_stone")
m.terrace("Plaza", geo.rounded_rect(46, 2, 64, 14, 2.0), top=0.6, bottom=-0.5, style="cobble")
m.ramp("Ramp_Mid", (30, 12, 0.0), (30, 18.2, 2.4), 3.0)
m.stairs("Stairs_Upper", (20, 24.5, 2.4), (20, 28.6, 5.0), 2.2)
m.ladder("Ladder_Upper", 30, 27.2, 2.4, 5.0, facing=90)
m.ladder("Rope_Upper", 33, 27.0, 2.4, 5.0, kind="rope")
m.water("Pond", geo.ellipse(14, 6, 5, 3.2, 24), level=0.05)
m.bridge("Bridge_Pond", (14, 1.5, 0.15), (14, 10.8, 0.15), width=2.4)
m.path("Path_Main", [(-4, 8), (10, 12), (24, 10), (30, 10), (44, 8), (56, 8)], width=2.6)
m.deck("Deck", geo.rect(48, 18, 56, 24), top=1.6, post_bottom=-0.2, rail=True)

# --- dressing ---
m.place("House_Mushroom_Orange", 38, 31, rot=0)
m.place("House_Cottage_Red", 56, 32)
m.place("Shop_Weapon", 55, 8.5, rot=0)
for i, t in enumerate(["Tree_Round_A", "Tree_Round_B", "Tree_Round_C", "Tree_Tall_A", "Tree_Pine_A", "Tree_Autumn_A"]):
    m.place(t, -2 + i * 7.5, 42, rot=i * 40)
m.place("Tree_Giant_A", 2, 30)
m.place("Tree_Palm_A", 62, 0)
for i, a in enumerate(["Bush_A", "Bush_B", "Bush_C", "Bush_Flowering_A", "Flower_Patch_A", "Flower_Patch_B",
                       "Mushroom_Cluster_A", "Rock_A", "Rock_B", "Rock_C", "Stump_A", "Log_A"]):
    m.place(a, 2 + i * 3.0, 15.0 if i % 2 else 13.5, rot=i * 30)
m.place("Mushroom_Giant_Red", 44, 20)
m.place("Fence_Wood_Seg", 26, 2, rot=0)
m.fence([(36, 2), (40, 2), (42, 4)])
m.place("Sign_Arrow", 0, 4, rot=0)
m.place("Sign_Board", 6, 2)
m.place("Lamp_Post", 47, 15)
m.place("Mailbox_Red", 50, 15)
m.place("Well", 60, 15)
m.place("Crate_Stack", 51, 20.5)
m.place("Barrel", 54.5, 22.5)
m.place("Maple_Leaf_Monument", 24, 32)
m.scatter(["Grass_Tuft_A", "Flower_Patch_A"], geo.rect(0, 0, 44, 16), 30, seed=3, min_dist=1.2)

# --- gameplay ---
m.portal("east00", 64, 22, to_map=0, to_portal="west00")
m.portal("in00", 38, 27.6, to_map=0, to_portal="out00", kind="door")
m.player(26, 6, rot=-30)
for i, n in enumerate(["Heena", "Shanks", "Lucas", "Mai", "Pio", "Nina", "Tia", "Biggs"]):
    m.npc(n, 20 + i * 1.6, 3.0, rot=-30)
m.mobs("Snail", geo.rect(0, 16, 6, 26), 3, seed=1)
m.mobs("Blue Snail", geo.rect(8, 19, 24, 24), 3, seed=2)
m.mobs("Red Snail", geo.rect(16, 29, 30, 35), 2, seed=3)
m.mobs("Orange Mushroom", geo.rect(32, 19, 44, 26), 3, seed=4)
for i, a in enumerate(["Mob_Snail", "Mob_BlueSnail", "Mob_RedSnail", "Mob_Shroom", "Mob_OrangeMushroom"]):
    m.place(a, 20 + i * 1.8, 0.8, rot=-30)
m.route("Main", [(-4, 8), (30, 10), (30, 18), (20, 22), (20, 30), (30, 32)])
m.finalize()

# hide debug for beauty
core.get_collection("DEBUG").hide_render = opts.get("debug", "0") != "1"

cam = scene_setup.make_camera("CAM_StyleTest", core.get_collection("CAMERAS"))
pts = [m.w(x, y, z) for x in (-6, 66) for y in (-6, 46) for z in (0, 8)]
scene_setup.fit_camera(cam, pts, aspect=res[0] / res[1], margin=float(opts.get("margin", 0.98)))
if "zoom" in opts:
    zx, zy, zs = (float(v) for v in opts["zoom"].split(","))
    cam2 = scene_setup.make_camera("CAM_StyleTest", core.get_collection("CAMERAS"), target=m.w(zx, zy, 1.0),
                                   ortho_scale=zs)
bpy.context.scene.camera = cam
bpy.context.scene.render.filepath = out
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.render.render(write_still=True)
if opts.get("save"):
    bpy.ops.wm.save_as_mainfile(filepath=opts["save"])
print("STYLE_TEST_DONE", out)
