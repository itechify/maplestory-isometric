"""Render review images from an existing .blend.

blender -b MapleIsland.blend --python scripts/render_review.py -- <TAG> [substring filters...] [--debug]
        [--res 1920x1080] [--samples 48]

Renders every camera whose name contains any filter (all cameras if none) into
renders/<TAG>/<camera>.png; --debug additionally renders gameplay markers
(routes, spawn rings, NPC beacons, labels) into renders/<TAG>/debug/.
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))

import bpy  # noqa: E402

from misostory import render  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
tag = argv[0]
opts = argv[1:]
debug = "--debug" in opts
res = None
samples = None
if "--res" in opts:
    res = tuple(int(v) for v in opts[opts.index("--res") + 1].split("x"))
if "--samples" in opts:
    samples = int(opts[opts.index("--samples") + 1])
skip = set()
for flag in ("--res", "--samples"):
    if flag in opts:
        skip.add(opts.index(flag) + 1)
filters = [a for i, a in enumerate(opts) if not a.startswith("--") and i not in skip]
cams = sorted(o.name for o in bpy.data.objects if o.type == "CAMERA")
if filters:
    if "--exact" in opts:
        cams = [c for c in cams if c in filters]
    else:
        cams = [c for c in cams if any(f in c for f in filters)]
rdir = os.path.join(ROOT, "renders", tag)
for c in cams:
    render.render_camera(c, os.path.join(rdir, c.replace("CAM_", "") + ".png"), res=res, samples=samples)
    print("RENDERED", c)
    if debug:
        render.render_camera(c, os.path.join(rdir, "debug", c.replace("CAM_", "") + ".png"), debug=True, res=res,
                             samples=samples)
print("REVIEW_DONE", len(cams))
