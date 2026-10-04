"""Per-map modules.

Each classic map lives in ``m<mapid>_<slug>.py`` and exposes ``MAP_ID`` and
``build(m)`` where ``m`` is a :class:`misostory.mapkit.MapCtx`. Maps without a module
get a clearly-flagged placeholder blockout so the island always builds completely.
"""

import importlib
import os
import pkgutil

from .. import geo
from .. import layout as LY

_HERE = os.path.dirname(__file__)


def module_for(mid):
    for info in pkgutil.iter_modules([_HERE]):
        if info.name.startswith(f"m{mid}_"):
            return importlib.import_module(f"{__name__}.{info.name}")
    return None


def placeholder(m):
    """Blockout: flat field, label, edge portals and a straight route between them."""
    L, D = m.size
    if m.meta["kind"] == "interior":
        m.terrace("Floor", geo.rect(0, 0, L, D), top=0.0, bottom=-0.6, style="wood_floor")
    m.label(f"{m.map_id}\n{m.name}\n(placeholder)", L / 2, D / 2, z=4.0, size=2.5)
    pts = []
    for name in LY.MAPS[m.map_id]["anchors"]:
        m.edge_portal(name)
        x, y, _z = m.anchor(name)
        pts.append((x, y))
    if len(pts) >= 2:
        m.route("Placeholder", pts)
    m.col_map["placeholder"] = True
