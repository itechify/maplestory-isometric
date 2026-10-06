"""Collision classes of the source world: the passable-tag registry (MAP_ARCHITECTURE section 5 item 6).

The runtime export (scripts/export_runtime.py) decides what collides from data on the object, not from words in its
name:

* **Non-instanced meshes** carry ``obj["collision"]``, one of ``CLASSES``, set by the builder that made them
  (``geo.terrace`` tags its body ``wall``, its cap ``ground`` and its grass fringe ``none``; a painted path ribbon is
  ``none``; ``m.rail`` is ``wall``; ...). ``tag(obj, cls)`` sets it. Objects that never get a tag fall back to their
  collection group (Architecture: wall, Props: hull, Vegetation: trunk hull, Terrain / Plinth / WORLD: none); the
  exporter reports how many did (``collision.mesh_class_source``) and ``validate.py`` checks that every Terrain,
  Architecture, Plinth and WORLD mesh is tagged, so a new builder cannot silently rely on the fallback.
* **Instanced kit assets** are classified by their registry category and tags (``kit.REGISTRY``): any tag in
  ``PASSABLE_TAGS`` makes the asset passable; a tag in ``EXACT_TAGS`` makes it collide with its exact mesh (joined
  to the chunk's Walls trimesh) instead of a convex prism of its body-height slice.
* **Parts of a kit asset** may carry ``OVERHEAD_HULL`` (set by the asset's builder): an overhang that starts above a
  walking body, such as a mushroom house's cap whose brim reaches far past its walls. The body-band slice ignores
  those parts; instead the asset gets one more prism, the 2D convex hull of all its overhead parts from their lowest
  point to their top, so nothing can stand inside the cap while the space under the brim stays open.

Plain Python (no bpy): ``tag`` only sets a custom property on whatever object it is given.
"""

KEY = "collision"

GROUND = "ground"      # walkable: joins the Ground trimesh
WALL = "wall"          # solid: joins the Walls trimesh (cliff bodies, room walls, rails)
NONE = "none"          # no collision (painted ribbons, grass fringes, foam, decals, text)
HULL = "hull"          # a convex prism of the body-height slice (props)
VEG_HULL = "veg_hull"  # a convex prism of the trunk band (giant stems), only if >= 1 m tall and >= 0.3 m2
WATER = "water"        # sidecar `water` data, no solid
EXACT = "exact"        # the exact mesh joins the Walls trimesh (thin overhead dressing a prism would overfill)
OVERHEAD_HULL = "overhead_hull"  # a convex prism of the part's own height range, above a walking body (see below)
CLASSES = (GROUND, WALL, NONE, HULL, VEG_HULL, WATER, EXACT, OVERHEAD_HULL)

# kit asset tags (kit.REGISTRY[name]["tags"]) that make an instanced asset passable
PASSABLE_TAGS = frozenset({"passable", "cloud", "debug", "portal", "vine", "flower", "grass"})
# kit asset tags that make an instanced asset collide with its exact mesh: thin overhead pieces (the interior eaves)
# whose body-band prism, sunk below the asset base like every prop prism, would reach down into the space a player
# walks under (Rafters: 1.30 m above the beam, inside the 1.5 m body)
EXACT_TAGS = frozenset({"collide_exact"})

# the class an untagged mesh gets from the collection group it lives in (the export's fallback)
GROUP_DEFAULT = {"Architecture": WALL, "Props": HULL, "Misc": HULL, "Vegetation": VEG_HULL}


def tag(obj, cls):
    """Set obj's collision class (one of CLASSES). Returns obj, so builders can tag inline."""
    if cls not in CLASSES:
        raise ValueError(f"unknown collision class {cls!r}; expected one of {CLASSES}")
    obj[KEY] = cls
    return obj


def of(obj):
    """obj's authored collision class, or None when it has no tag."""
    v = obj.get(KEY) if obj is not None else None
    return v if v in CLASSES else None


def passable(obj, asset_tags=()):
    """True when the registry says obj never blocks a walking body: a ``climbable`` or ``passable`` flag, the
    collision tag ``none`` (a mesh), or any of ``PASSABLE_TAGS`` among the kit asset's tags (an instance; pass
    ``kit.REGISTRY[name]["tags"]``). Never reads the object's name. The traversal validator (traversal.py) and
    ``validate.py`` decide what blocks a route walk with it; the export applies the same flags and tags to collision."""
    if obj.get("climbable") or obj.get("passable"):
        return True
    if of(obj) == NONE:
        return True
    return bool(set(asset_tags) & PASSABLE_TAGS)
