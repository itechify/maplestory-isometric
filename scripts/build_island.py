"""Build the complete Maple Island into MapleIsland.blend.

blender -b --factory-startup --python scripts/build_island.py -- [out.blend] [--no-scenery] [--render TAG]

--render TAG   also render every camera into renders/TAG/ (beauty) and renders/TAG/debug/.

Needs the pinned art pack (bash scripts/art_pack.sh fetch; ADR 0002): without it the build stops before it starts,
with exit 1 and the fetch command. It also exits 1 when the build raises or a map is not authored (Blender itself
exits 0 on an uncaught script error). The kit assets built from the pack are printed as ART_PACK_ASSET lines and
listed under "art_pack" in docs/build_report.json.
"""

import os
import runpy
import sys
import traceback

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))

import bpy  # noqa: E402

from misostory import build, kit, render  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = next((a for a in argv if a.endswith(".blend")), os.path.join(ROOT, "MapleIsland.blend"))
scenery = "--no-scenery" not in argv
tag = argv[argv.index("--render") + 1] if "--render" in argv else None

kit.art_pack.require_or_exit(kit.REGISTRY)
try:
    report, ctxs, world = build.build(scenery=scenery)
except Exception:  # noqa: BLE001
    traceback.print_exc()
    print("BUILD_FAILED")
    sys.stdout.flush()
    sys.exit(1)
build.write_report(report, os.path.join(ROOT, "docs", "build_report.json"))
build.save(out)
print("BUILD_DONE", out, "objects:", report["objects"], "seconds:", report["seconds"])
try:  # keep docs/manifest.json and MAPLE_ISLAND_MANIFEST.md in step with every build
    runpy.run_path(os.path.join(ROOT, "scripts", "export_manifest.py"), run_name="__main__")
except Exception as e:  # noqa: BLE001
    print("MANIFEST_WARN", repr(e))
bad = {k: v["status"] for k, v in report["maps"].items() if v["status"] != "authored"}
print("NON_AUTHORED_MAPS", bad)
print("ART_PACK_ASSETS", len(report["art_pack"]["assets"]), "kit assets built from the pinned art pack")

if tag:
    rdir = os.path.join(ROOT, "renders", tag)
    cams = sorted(o.name for o in bpy.data.objects if o.type == "CAMERA")
    for c in cams:
        render.render_camera(c, os.path.join(rdir, c.replace("CAM_", "") + ".png"))
        print("RENDERED", c)
if bad:  # a map module (or a kit asset it placed) raised: build.build_map reported it and carried on
    sys.stdout.flush()
    sys.exit(1)
