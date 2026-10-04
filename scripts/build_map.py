"""Build ONE map in isolation (its plinth + the map) and render its cameras.

Used while authoring a map:
blender -b --factory-startup --python scripts/build_map.py -- <map_id> [--out DIR] [--debug] [--res 1600x900]
        [--save file.blend] [--extra-cams x,y,scale;x,y,scale]

Writes <DIR>/<slug>_Overview.png, <slug>_Gameplay.png (+ _debug variants with --debug)
and prints the map's build status, portals, routes and timing.
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))

import bpy  # noqa: E402

from misostory import build, render, scene_setup, core, traversal  # noqa: E402
from misostory import layout as LY  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
mid = int(argv[0])
outdir = argv[argv.index("--out") + 1] if "--out" in argv else os.path.join(ROOT, "renders", "_maps")
res = tuple(int(v) for v in (argv[argv.index("--res") + 1] if "--res" in argv else "1600x900").split("x"))
debug = "--debug" in argv

report, ctxs, world = build.build(map_ids=[mid], scenery=False, res=res, samples=32)
info = report["maps"][str(mid)]
print("MAP_STATUS", json.dumps({k: info[k] for k in ("slug", "status", "seconds")}))
if info["error"]:
    print("MAP_ERROR", info["error"])
print("MAP_PORTALS", json.dumps(info["portals"]))
print("MAP_ROUTES", json.dumps(info["routes"]))
slug = info["slug"]
ctx = ctxs[mid]
trav = traversal.check_map(ctx)
# scattered clutter (m.scatter / m.mobs) that build.build_map removed from routes before this check
cleared = (info.get("traversal") or {}).get("cleared_from_routes", [])
trav["cleared_from_routes"] = cleared
print("MAP_TRAVERSAL", json.dumps(trav))
print("MAP_TRAVERSAL_OK", trav["ok"])
print("MAP_CLEARED", json.dumps(cleared))
vd = ctx.view_dir()
print("MAP_VIEW_DIR", json.dumps({"local_view_dir": [round(vd[0], 3), round(vd[1], 3)],
                                   "visible_faces": "faces whose local normal n has dot(n, view_dir) < 0",
                                   "world_yaw": ctx.yaw}))
print("MAP_SPAWNS", json.dumps([{"mob": s["mob"], "points": [[round(p[0], 1), round(p[1], 1)] for p in s["points"]]}
                               for s in ctx.spawns]))
# player / mob proxies inside the Gameplay camera frame (same dict as build_report maps.<id>.gameplay_frame)
try:
    frame = ctx.gameplay_frame_check()
except Exception as e:  # noqa: BLE001
    frame = {"ok": False, "error": repr(e)}
print("PLAYER_IN_FRAME", json.dumps(frame))
print("PLAYER_IN_FRAME_OK", frame.get("ok"))
extra = []
if "--extra-cams" in argv:
    for i, spec in enumerate(argv[argv.index("--extra-cams") + 1].split(";")):
        x, y, s = (float(v) for v in spec.split(","))
        z = ctx.ground_z(x, y) or 0.0
        c = scene_setup.make_camera(f"CAM_{slug}_Extra{i}", ctx.col_cams, target=ctx.w(x, y, z + 1.0), ortho_scale=s)
        extra.append(c.name)
if "--save" in argv:
    build.save(argv[argv.index("--save") + 1])
for cam in render.map_cameras(slug):
    p = render.render_camera(cam, os.path.join(outdir, cam.replace("CAM_", "") + ".png"))
    print("RENDERED", p)
    if debug:
        p = render.render_camera(cam, os.path.join(outdir, cam.replace("CAM_", "") + "_debug.png"), debug=True)
        print("RENDERED", p)
