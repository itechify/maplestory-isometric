"""Low-level Blender helpers shared by every module.

Conventions
-----------
* Units are meters, Z is up.
* The isometric camera looks toward world +X+Y (from the south-west), so faces whose
  normals point -X or -Y are the ones the player sees. Terrain should generally rise
  *away* from the camera (toward +X/+Y) so cliff faces read clearly.
* Every generated object gets a descriptive name; nothing is left as ``Cube.001``.
"""

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

# ---------------------------------------------------------------------------
# Collections
# ---------------------------------------------------------------------------

ROOT_COLLECTION = "MAPLE_ISLAND"

PLAYER_HEIGHT = 1.5  # chibi player height (m); mapkit.PLAYER_HEIGHT and traversal.BODY_Z re-use it


def scene():
    return bpy.context.scene


def get_collection(path, exclude=None, hide_render=None):
    """Return (creating as needed) a collection addressed by a '/'-separated path.

    The first component hangs off the scene's ``MAPLE_ISLAND`` root collection.
    """
    scn = scene()
    root = bpy.data.collections.get(ROOT_COLLECTION)
    if root is None:
        root = bpy.data.collections.new(ROOT_COLLECTION)
        scn.collection.children.link(root)
    parent = root
    for part in [p for p in path.split("/") if p]:
        child = bpy.data.collections.get(part)
        if child is None:
            child = bpy.data.collections.new(part)
            parent.children.link(child)
        elif child.name not in parent.children:
            parent.children.link(child)
        parent = child
    if exclude is not None:
        lc = find_layer_collection(parent.name)
        if lc is not None:
            lc.exclude = exclude
    if hide_render is not None:
        parent.hide_render = hide_render
    return parent


def find_layer_collection(name, lc=None):
    if lc is None:
        lc = bpy.context.view_layer.layer_collection
    if lc.name == name:
        return lc
    for child in lc.children:
        found = find_layer_collection(name, child)
        if found is not None:
            return found
    return None


def link(obj, collection):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    collection.objects.link(obj)
    return obj


_NAME_NEXT = {}


def unique_name(base):
    """Return ``base`` or ``base_02``... so names stay descriptive (never ``.001``).

    Keeps a per-base counter so naming thousands of instances stays O(1) each.
    """
    objs = bpy.data.objects
    if base not in _NAME_NEXT:
        if objs.get(base) is None:
            _NAME_NEXT[base] = 2
            return base
        _NAME_NEXT[base] = 2
    i = _NAME_NEXT[base]
    while objs.get(f"{base}_{i:02d}") is not None:
        i += 1
    _NAME_NEXT[base] = i + 1
    return f"{base}_{i:02d}"


# ---------------------------------------------------------------------------
# Mesh helpers
# ---------------------------------------------------------------------------

def mesh_object(name, bm, collection, materials=(), smooth=False, sharp_angle=None):
    """Create an object from a bmesh (bm is freed)."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in materials:
        me.materials.append(m)
    if smooth:
        me.shade_smooth()
        if sharp_angle is not None:
            me.set_sharp_from_angle(angle=math.radians(sharp_angle))
    else:
        me.shade_flat()
    obj = bpy.data.objects.new(unique_name(name), me)
    collection.objects.link(obj)
    return obj


def join_bmeshes(parts):
    """Merge a list of (bmesh, material_index) into one bmesh (inputs are freed)."""
    out = bmesh.new()
    for bm, mat_index in parts:
        me = bpy.data.meshes.new("_tmp_join")
        bm.to_mesh(me)
        bm.free()
        for p in me.polygons:
            p.material_index = mat_index
        out.from_mesh(me)
        bpy.data.meshes.remove(me)
    return out


EVAL_SCENE = "_CurveEval"


def eval_scene():
    sc = bpy.data.scenes.get(EVAL_SCENE)
    if sc is None:
        sc = bpy.data.scenes.new(EVAL_SCENE)
    return sc


def drop_eval_scene():
    sc = bpy.data.scenes.get(EVAL_SCENE)
    if sc is not None:
        for o in list(sc.collection.objects):
            bpy.data.objects.remove(o)
        bpy.data.scenes.remove(sc)


def curve_to_mesh_object(curve_obj, name, collection, materials=(), smooth=True, sharp_angle=40):
    """Evaluate a curve object to a mesh object and delete the curve.

    The curve is evaluated inside a tiny private scene so the cost does not grow with the
    size of the island (evaluating the main depsgraph re-syncs every object each time).
    """
    sc = eval_scene()
    for c in list(curve_obj.users_collection):
        c.objects.unlink(curve_obj)
    sc.collection.objects.link(curve_obj)
    with bpy.context.temp_override(scene=sc, view_layer=sc.view_layers[0]):
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(curve_obj.evaluated_get(dg))
    me.transform(GroundIndex.object_world_matrix(curve_obj))  # local space -> world (matrix_world may be stale)
    me.name = name
    curve_data = curve_obj.data
    bpy.data.objects.remove(curve_obj)
    bpy.data.curves.remove(curve_data)
    me.materials.clear()
    for m in materials:
        me.materials.append(m)
    if smooth:
        me.shade_smooth()
        me.set_sharp_from_angle(angle=math.radians(sharp_angle))
    obj = bpy.data.objects.new(unique_name(name), me)
    collection.objects.link(obj)
    return obj


def apply_transform_to_mesh(obj):
    """Bake loc/rot/scale into mesh data."""
    obj.data.transform(obj.matrix_basis)
    obj.matrix_basis = Matrix.Identity(4)


# ---------------------------------------------------------------------------
# Deterministic randomness
# ---------------------------------------------------------------------------

def rng(*seed_parts):
    """Deterministic RNG from any hashable seed parts (stable across runs)."""
    s = 0
    for p in seed_parts:
        for ch in str(p):
            s = (s * 131 + ord(ch)) % 2_147_483_647
    return random.Random(s)


# ---------------------------------------------------------------------------
# Ground queries
# ---------------------------------------------------------------------------

class GroundIndex:
    """BVH over walkable/terrain meshes for raycast grounding of props."""

    def __init__(self):
        self.objects = []
        self._bvh = None
        self._cache = {}  # object name -> (matrix snapshot, world verts, polys, n polys, material indices)
        self._owners = []  # (first face index, object, material indices) per object in the BVH

    def add(self, obj):
        self.objects.append(obj)
        self._bvh = None
        try:
            obj["walkable"] = True  # lets the island validator find real ground
        except Exception:
            pass

    @staticmethod
    def object_world_matrix(obj):
        """World matrix without a depsgraph update (matrix_world is stale for fresh objects)."""
        m = obj.matrix_basis.copy()
        p = obj.parent
        while p is not None:
            m = p.matrix_basis @ m
            p = p.parent
        return m

    @staticmethod
    def is_outline_modifier(md):
        """Kit ink outlines are flipped-normal SOLIDIFY shells (kit.add_outline). Their outer faces point
        down, so a downward ray would hit the shell first and read 'no ground'; the ground ignores them."""
        return md.type == "SOLIDIFY" and (md.use_flip_normals or md.name.startswith("Outline"))

    def _geometry(self, obj):
        verts, polys, _mats = self._geometry_mats(obj)
        return verts, polys

    def _geometry_mats(self, obj):
        mw = self.object_world_matrix(obj)
        key = obj.name
        hit = self._cache.get(key)
        if hit is not None and hit[0] == mw and hit[3] == len(obj.data.polygons):
            return hit[1], hit[2], hit[4]
        mods = [md for md in obj.modifiers if md.show_viewport]
        outlines = [md for md in mods if self.is_outline_modifier(md)]
        if len(mods) > len(outlines):
            # real modifiers: evaluate them, with any ink-outline shell switched off meanwhile
            for md in outlines:
                md.show_viewport = False
            try:
                dg = bpy.context.evaluated_depsgraph_get()
                ev = obj.evaluated_get(dg)
                me = ev.to_mesh()
                verts = [mw @ v.co for v in me.vertices]
                polys = [tuple(p.vertices) for p in me.polygons]
                mats = [p.material_index for p in me.polygons]
                ev.to_mesh_clear()
            finally:
                for md in outlines:
                    md.show_viewport = True
        else:  # no modifiers, or only ink outlines: the base mesh is the walkable surface
            me = obj.data
            verts = [mw @ v.co for v in me.vertices]
            polys = [tuple(p.vertices) for p in me.polygons]
            mats = [p.material_index for p in me.polygons]
        self._cache[key] = (mw, verts, polys, len(obj.data.polygons), mats)
        return verts, polys, mats

    def _build(self):
        verts, polys = [], []
        self._owners = []
        for obj in self.objects:
            if obj.type != "MESH":
                continue
            v, p, mats = self._geometry_mats(obj)
            self._owners.append((len(polys), obj, mats))
            off = len(verts)
            verts.extend(v)
            polys.extend([off + i for i in face] for face in p)
        self._bvh = BVHTree.FromPolygons(verts, polys) if polys else None

    def raycast_down(self, x, y, z_from=500.0, max_normal_tilt=None):
        """Return (z, normal) of the highest surface under (x, y) or (None, None)."""
        if self._bvh is None:
            self._build()
        if self._bvh is None:
            return None, None
        hit = self._bvh.ray_cast(Vector((x, y, z_from)), Vector((0, 0, -1)), 2000.0)
        if hit[0] is None:
            return None, None
        loc, normal = hit[0], hit[1]
        if normal.z < 0:  # hit a downward face (e.g. underside); treat as no ground
            return None, None
        return loc.z, normal

    def raycast_down_hit(self, x, y, z_from=500.0):
        """Like raycast_down, plus what was hit: (z, normal, object, material name) or (None,) * 4.

        Used where the surface's look matters (geo.stairs gives its top landing the material of the cap it
        lands on)."""
        if self._bvh is None:
            self._build()
        if self._bvh is None:
            return None, None, None, None
        hit = self._bvh.ray_cast(Vector((x, y, z_from)), Vector((0, 0, -1)), 2000.0)
        if hit[0] is None or hit[1].z < 0:
            return None, None, None, None
        import bisect
        i = bisect.bisect_right([o[0] for o in self._owners], hit[2]) - 1
        obj, mat = None, None
        if i >= 0:
            first, obj, mats = self._owners[i]
            li = hit[2] - first
            if 0 <= li < len(mats):
                slots = obj.data.materials
                mi = mats[li]
                if 0 <= mi < len(slots) and slots[mi] is not None:
                    mat = slots[mi].name
        return hit[0].z, hit[1], obj, mat

    def height_below(self, x, y, z_from):
        """Ground height under a point, starting the ray at z_from (for stacked terrain)."""
        return self.raycast_down(x, y, z_from=z_from)[0]


def vec(*a):
    return Vector(a)


def lerp(a, b, t):
    return a + (b - a) * t


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def stable_hash(s, mod=997):
    h = 0
    for ch in str(s):
        h = (h * 131 + ord(ch)) % 2_147_483_647
    return h % mod
