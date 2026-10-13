"""Render a row/grid of kit assets for review.

blender -b --factory-startup --python scripts/asset_gallery.py -- <out.png> <AssetName> [<AssetName> ...]
        [--cols 6] [--spacing 9] [--scale 1.0] [--res 1800x1000] [--procedural]

Kit assets built from the art pack (kit/art_pack.py) are shown from the pack when it is installed;
--procedural shows their procedural placeholders instead (for a kit-vs-pack comparison).
"""

import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))

import bpy  # noqa: E402

from misostory import build, core, geo, kit, render, scene_setup  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
opts = argv[1:]


def opt(flag, default):
    return opts[opts.index(flag) + 1] if flag in opts else default


cols = int(opt("--cols", "6"))
spacing = float(opt("--spacing", "9"))
res = tuple(int(v) for v in opt("--res", "1800x1000").split("x"))
skip = {opts.index(f) + 1 for f in ("--cols", "--spacing", "--res", "--scale") if f in opts}
names = [a for i, a in enumerate(opts) if not a.startswith("--") and i not in skip]
kit.art_pack.configure("off" if "--procedural" in opts else "auto")
build.reset_scene()
scene_setup.setup_render(res=res, samples=32)
scene_setup.setup_world()
scene_setup.setup_sun()
coll = core.get_collection("MAPS/Gallery")
rows = math.ceil(len(names) / cols)
w = cols * spacing
h = rows * spacing
geo.terrace("Gallery_Ground", geo.rect(-spacing, -spacing, w, h), 0.0, -2.0, coll)
pts = []
for i, n in enumerate(names):
    x = (i % cols) * spacing
    y = (i // cols) * spacing
    kit.instance(n, coll, (x, y, 0.0))
    pts += [(x, y, 0), (x, y, 8)]
cam = scene_setup.make_camera("CAM_Gallery", core.get_collection("CAMERAS"))
scene_setup.fit_camera(cam, pts + [(-spacing / 2, -spacing / 2, 0), (w, h, 0)], aspect=res[0] / res[1], margin=1.0)
render.render_camera("CAM_Gallery", out)
print("GALLERY_DONE", out)
