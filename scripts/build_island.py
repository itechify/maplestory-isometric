"""Build the complete Maple Island into MapleIsland.blend.

blender -b --factory-startup --python scripts/build_island.py -- [out.blend] [--no-scenery] [--render TAG]

--render TAG   also render every camera into renders/TAG/ (beauty) and renders/TAG/debug/.
"""

import os
import runpy
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))

import bpy  # noqa: E402

from misostory import build, render  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = next((a for a in argv if a.endswith(".blend")), os.path.join(ROOT, "MapleIsland.blend"))
scenery = "--no-scenery" not in argv
tag = argv[argv.index("--render") + 1] if "--render" in argv else None

report, ctxs, world = build.build(scenery=scenery)
build.write_report(report, os.path.join(ROOT, "docs", "build_report.json"))
build.save(out)
print("BUILD_DONE", out, "objects:", report["objects"], "seconds:", report["seconds"])
try:  # keep docs/manifest.json and MAPLE_ISLAND_MANIFEST.md in step with every build
    runpy.run_path(os.path.join(ROOT, "scripts", "export_manifest.py"), run_name="__main__")
except Exception as e:  # noqa: BLE001
    print("MANIFEST_WARN", repr(e))
bad = {k: v["status"] for k, v in report["maps"].items() if v["status"] != "authored"}
print("NON_AUTHORED_MAPS", bad)

if tag:
    rdir = os.path.join(ROOT, "renders", tag)
    cams = sorted(o.name for o in bpy.data.objects if o.type == "CAMERA")
    for c in cams:
        render.render_camera(c, os.path.join(rdir, c.replace("CAM_", "") + ".png"))
        print("RENDERED", c)
