"""Reusable asset kit.

Assets are registered with ``@asset(name, category)``. The first time an asset is
requested it is built into ``ENVIRONMENT_ASSETS/<category>/<name>`` (a collection
excluded from the view layer) and from then on it is *instanced* with collection
instance empties, so the whole island shares one copy of each mesh.

Asset conventions:
* origin = ground contact point, model stands on z=0;
* "front" (doors, faces, signs) faces -Y at rotation 0 (toward the camera side);
* sizes in meters, player proxy is ~1.5 m tall.
"""

import math

import bpy

from .. import core

REGISTRY = {}
ASSET_ROOT = "ENVIRONMENT_ASSETS"

# Category -> parent collection path (keeps the user's requested hierarchy)
CATEGORY_PATHS = {
    "Trees": "ENVIRONMENT_ASSETS/Trees",
    "Foliage": "ENVIRONMENT_ASSETS/Foliage",
    "Rocks": "ENVIRONMENT_ASSETS/Rocks",
    "Terrain": "ENVIRONMENT_ASSETS/Terrain",
    "Architecture": "ENVIRONMENT_ASSETS/Architecture",
    "Props": "ENVIRONMENT_ASSETS/Props",
    "Markers": "ENVIRONMENT_ASSETS/Markers",
    "Monsters": "MONSTER_PROXIES/_MonsterLibrary",
    "Characters": "CHARACTER_PROXIES/_CharacterLibrary",
}


# Inverted-hull ink outline thickness per category (meters). 0 = none.
OUTLINE = {
    "enabled": True,
    "Trees": 0.045, "Foliage": 0.02, "Rocks": 0.03, "Terrain": 0.0, "Architecture": 0.04, "Props": 0.022,
    "Markers": 0.0, "Monsters": 0.018, "Characters": 0.016,
}
NO_OUTLINE_TAGS = {"grass", "flower", "vine", "debug", "portal"}


def asset(name, category, footprint=1.0, tags=(), outline=None):
    """Register an asset builder. The builder receives the target collection."""
    def deco(fn):
        REGISTRY[name] = {"fn": fn, "category": category, "footprint": footprint, "tags": tuple(tags),
                          "outline": outline}
        return fn
    return deco


def add_outline(obj, thickness):
    from .. import materials as M
    me = obj.data
    if not any(m and m.name == "M_Outline" for m in me.materials):
        me.materials.append(M.get("M_Outline"))
    mod = obj.modifiers.new("Outline", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 1.0
    mod.use_flip_normals = True
    mod.use_rim = False
    mod.use_even_offset = False
    mod.material_offset = len(me.materials)  # shell faces clamp to the last material (outline)
    return mod


def _library_parent(category):
    path = CATEGORY_PATHS[category]
    coll = core.get_collection(path)
    # the top library collection is excluded from the view layer so sources never render
    top = path.split("/")[0]
    if top == ASSET_ROOT:
        core.get_collection(ASSET_ROOT, exclude=True)
    else:
        lib = "/".join(path.split("/")[:2])
        core.get_collection(lib, exclude=True)
    return coll


def ensure(name):
    """Build (once) and return the source collection of an asset."""
    coll = bpy.data.collections.get(name)
    if coll is not None:
        return coll
    if name not in REGISTRY:
        raise KeyError(f"Unknown asset '{name}'. Known: {sorted(REGISTRY)[:20]}...")
    info = REGISTRY[name]
    parent = _library_parent(info["category"])
    coll = bpy.data.collections.new(name)
    parent.children.link(coll)
    info["fn"](coll)
    thick = info.get("outline")
    if thick is None:
        thick = OUTLINE.get(info["category"], 0.0)
    if set(info["tags"]) & NO_OUTLINE_TAGS:
        thick = 0.0
    if info.get("footprint", 1.0) < 0.9 and info["category"] in ("Props", "Foliage"):
        thick = 0.0  # tiny props: ink lines are invisible at map scale but double the triangles
    for o in coll.objects:
        o["asset"] = name
        if OUTLINE["enabled"] and thick > 0 and o.type == "MESH" and not o.name.endswith(("_Flowers", "_Sails")):
            add_outline(o, thick)
    return coll


def instance(name, collection, loc, rot_z=0.0, scale=1.0, obj_name=None, tilt=(0.0, 0.0)):
    src = ensure(name)
    e = bpy.data.objects.new(core.unique_name(obj_name or name), None)
    e.instance_type = "COLLECTION"
    e.instance_collection = src
    e.empty_display_size = 0.5
    e.location = loc
    e.rotation_euler = (math.radians(tilt[0]), math.radians(tilt[1]), math.radians(rot_z))
    if isinstance(scale, (int, float)):
        scale = (scale, scale, scale)
    e.scale = scale
    e["asset"] = name
    collection.objects.link(e)
    return e


def footprint(name):
    return REGISTRY[name]["footprint"]


def names(prefix=""):
    return sorted(n for n in REGISTRY if n.startswith(prefix))


# Import asset modules so they register themselves.
from . import nature, architecture, props, markers, creatures, terrain, classic, interior, promoted  # noqa: E402,F401
