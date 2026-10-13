"""Kit assets built from the pinned art pack (Project art; ADR 0002, docs/adr/0002-pinned-art-pack.md).

For the categories in ``CATEGORIES``, ``kit.ensure(name)`` builds a catalog asset from its pack GLB instead of
running the procedural @asset builder. The asset keeps its name, category, footprint and tags, so placement,
lookups and the export's collision classes are unchanged; only the mesh comes from the pack. How
(docs/AUTHORING.md, "Kit assets from the art pack"):

1. **Lookup by catalog name.** ``environment/source_catalog_mapping.json`` maps every @asset name
   (``source_asset_id``) to its pack file (``output_file``); aliases (``mapping_kind``
   ``semantically_equivalent_original_adaptation``) resolve the same way. Never by file name.
2. **Import** into the scene root (the excluded ``ENVIRONMENT_ASSETS`` collection would silently not take it), new
   objects found as the difference of ``bpy.data.objects``; transforms are baked into the mesh, parts unparented,
   glTF's per-face split vertices welded and its custom normals dropped.
3. **Materials:** every pack material (a linear Principled base color) is written per face into the ``PackColor``
   corner color attribute, and every pack asset uses the one material ``M_Pack``, a painted gradient of that color
   through the shared ``MS_Shading`` group. That is what the soft shading, the renders and the export's albedo bake
   read (an imported Principled material bakes black), and it keeps an asset one surface, one draw call.
4. **Fit to the kit:** the parts are joined into one object (fewer draw calls), optionally rotated, then scaled
   uniformly so the largest horizontal size equals the procedural kit asset's (measured by running its builder
   once and throwing the result away), then stood on z = 0. Per-asset exceptions go in ``@asset(..., pack={...})``,
   see ``SPEC_KEYS``.
5. **Triangle budget:** a pack model heavier than the kit asset it replaces is decimated (collapse) down to the kit
   asset's own triangle count, so no map gets heavier than before (``validate.py`` polygon budget). ``max_tris``
   overrides that per asset.
6. Shading like the kit's (smooth, edges sharper than ``sharp_angle`` hard), the object is renamed after the asset
   (never ``.NNN``) and moved into the asset collection; ``kit.ensure`` then adds the ink outline.

Modes (``configure``): ``off`` (default: procedural builders; tests, fixtures, a fresh clone), ``auto`` (the pack
when it is installed, e.g. asset_gallery.py) and ``required`` (scripts/build_island.py and build_map.py: they call
``require_or_exit`` first, so a missing pack stops the build with exit 1 and the fetch command, never a silent
fallback). ``MISOSTORY_ART_PACK_DIR`` overrides the install directory (tests).
"""

import json
import math
import os
import re
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

from .. import core
from .. import materials as M

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
DEFAULT_DIR = os.path.join(ROOT, "game", "assets", "art_pack")
MAPPING_FILE = "environment/source_catalog_mapping.json"
FETCH_COMMAND = "bash scripts/art_pack.sh fetch"
ALIAS_KIND = "semantically_equivalent_original_adaptation"

# The kit categories whose catalog assets come from the pack. #72: Trees and Foliage; #73: Props and Markers;
# #74 Architecture, Rocks and Terrain. Per-map X<mapid>_* landmarks are not in the mapping and never swap here.
CATEGORIES = {"Trees", "Foliage", "Props", "Markers"}
LANDMARK = re.compile(r"X\d+_")

# @asset(..., pack={...}) keys, all optional:
#   fit          "xy" (default): largest horizontal size = the kit asset's; "z": height = the kit asset's
#   rot_z        degrees about Z applied to the pack model before fitting (its long side onto the kit's)
#   align_xy     "origin" (default): keep the pack's own horizontal pivot; "kit": centre the model's bounding box on
#                the kit asset's (a kit asset whose origin is at one end, e.g. Hedge_Wall_4m runs 0..4 m along +X)
#   anchor_z     "ground" (default): z-min = 0; "kit_bottom": z-min = the kit asset's (hovering butterflies);
#                "kit_top": z-max = the kit asset's (a hanging vine whose origin is its top)
#   scale_mul    extra uniform factor after the fit (an art adjustment checked by eye)
#   max_tris     triangle budget instead of the kit asset's own triangle count
#   sharp_angle  degrees; edges sharper than this stay hard (default 60)
#   node_scale   {substring: (sx, sy, sz)}: scale the pack nodes whose name contains the substring about the pack
#                origin, before the fit (an art adjustment, e.g. the trees' splayed roots, whose reach sets the
#                export's trunk prism)
#   parts        {suffix: [substring, ...]}: pack nodes whose name contains a substring become their own object
#                <name>_<suffix> (e.g. an overhanging cap that needs collision_tags.OVERHEAD_HULL); the rest is one
#                object named after the asset
#   post         fn(coll, parts) called last with {suffix or "": object}, to tag parts or give them a kit material
#                (kit_materials(Glow="M_Glow_window"): the glow of lamps and portals, which the pack lacks)
SPEC_KEYS = {"fit", "rot_z", "align_xy", "anchor_z", "scale_mul", "max_tris", "sharp_angle", "node_scale", "parts",
             "post"}

_state = {"mode": "off", "mapping": {}}
_reference = {}
BUILT = {}


# ---------------------------------------------------------------------------
# Mode and lookup
# ---------------------------------------------------------------------------

def configure(mode):
    if mode not in ("off", "auto", "required"):
        raise ValueError(f"art pack mode {mode!r}: off, auto or required")
    _state["mode"] = mode


def mode():
    return _state["mode"]


def pack_dir():
    return os.environ.get("MISOSTORY_ART_PACK_DIR") or DEFAULT_DIR


def mapping(directory=None):
    """{catalog name: mapping entry} of the installed pack ({} when there is none)."""
    directory = directory or pack_dir()
    if directory not in _state["mapping"]:
        path = os.path.join(directory, MAPPING_FILE)
        if not os.path.isfile(path):
            return {}
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        _state["mapping"][directory] = {e["source_asset_id"]: e for e in data.get("entries", [])}
    return _state["mapping"][directory]


def entry(name):
    """The mapping entry of a catalog name, plus ``alias`` (True when it shares a model under another name)."""
    e = mapping().get(name)
    if e is None:
        raise KeyError(f"'{name}' is not in the art pack's {MAPPING_FILE}")
    return dict(e, alias=e.get("mapping_kind") == ALIAS_KIND)


def glb_path(name):
    return os.path.join(pack_dir(), *entry(name)["output_file"].split("/"))


def swapped_names(registry):
    """Registry names built from the pack: a category in CATEGORIES and an entry in the mapping."""
    m = mapping()
    return sorted(n for n, info in registry.items() if _catalog(n, info) and n in m)


def _catalog(name, info):
    """A kit catalog name of a swapped category (not a per-map X<mapid>_* landmark)."""
    return info["category"] in CATEGORIES and not LANDMARK.match(name)


def swaps(name, info):
    """Is this asset built from the pack? In required mode a catalog name missing from the mapping is an error
    (raised by build), never a silent procedural fallback."""
    if _state["mode"] == "off" or not _catalog(name, info):
        return False
    return _state["mode"] == "required" or name in mapping()


def preflight(names, pack_dir=None):
    """Problems that stop a pack build of these catalog names ([] = ready)."""
    directory = pack_dir or globals()["pack_dir"]()
    if not os.path.isdir(directory):
        return [f"no art pack installed at {directory}"]
    path = os.path.join(directory, MAPPING_FILE)
    if not os.path.isfile(path):
        return [f"the art pack at {directory} has no {MAPPING_FILE}"]
    m = mapping(directory)
    problems = []
    for n in names:
        e = m.get(n)
        if e is None:
            problems.append(f"{n}: not in {MAPPING_FILE}")
        elif not os.path.isfile(os.path.join(directory, *e["output_file"].split("/"))):
            problems.append(f"{n}: {e['output_file']} is missing")
    return problems


def missing_message(problems):
    lines = ["ART_PACK_MISSING: the Blender build takes its kit assets (categories "
             f"{', '.join(sorted(CATEGORIES))}) from the pinned art pack, and it is not usable:"]
    lines += [f"  - {p}" for p in problems[:20]]
    lines.append(f"Install it with:  {FETCH_COMMAND}   (ADR 0002; there is no fallback to the procedural kit)")
    return "\n".join(lines)


def require_or_exit(registry):
    """Build-script preflight: the pack must hold a model for every swapped catalog name, else exit 1."""
    names = sorted(n for n, info in registry.items() if _catalog(n, info))
    problems = preflight(names)
    if problems:
        msg = missing_message(problems)
        print(msg)
        print(msg, file=sys.stderr)
        sys.stdout.flush()
        sys.exit(1)
    configure("required")


def reset():
    BUILT.clear()


def report():
    return {"mode": _state["mode"], "categories": sorted(CATEGORIES), "assets": dict(sorted(BUILT.items()))}


# ---------------------------------------------------------------------------
# Kit reference (size and triangles of the procedural asset being replaced)
# ---------------------------------------------------------------------------

def _mesh_bounds(objs):
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in objs:
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            lo, hi = Vector(map(min, lo, p)), Vector(map(max, hi, p))
    return lo, hi


def _tris(objs):
    return sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)


def reference(name, info):
    """{"lo", "hi", "tris"} of the procedural builder's model (built once in a scratch collection, then removed)."""
    if name not in _reference:
        coll = bpy.data.collections.new(f"_kit_reference_{name}")
        try:
            info["fn"](coll)
            objs = [o for o in coll.all_objects if o.type == "MESH"]
            lo, hi = _mesh_bounds(objs)
            _reference[name] = {"lo": tuple(lo), "hi": tuple(hi), "tris": _tris(objs)}
        finally:
            for o in list(coll.all_objects):
                me = o.data if o.type == "MESH" else None
                bpy.data.objects.remove(o)
                if me is not None and me.users == 0:
                    bpy.data.meshes.remove(me)
            bpy.data.collections.remove(coll)
    return _reference[name]


def tri_budget(name, ref, spec=None):
    from . import REGISTRY
    spec = spec if spec is not None else (REGISTRY.get(name, {}).get("pack") or {})
    return int(spec.get("max_tris") or ref["tris"])


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

# One material for every pack asset: the pack's colors ride on the mesh (a corner color attribute), so an asset is
# one surface (one draw call) whatever its number of pack materials, and all pack assets batch together. The look is
# the kit's painted gradient (like M_Leaf / M_Bush, leaf_dk -> leaf_lt): from SHADE_BOTTOM x the color (in sRGB) at
# the bottom of the object's bounding box to the color at its top. Flat bright pack greens melt into the grass.
PACK_MATERIAL = "M_Pack"
COLOR_ATTRIBUTE = "PackColor"
SHADE_BOTTOM = 0.6


def pack_material():
    """The shared MS_Shading material of the pack assets (albedo from the PackColor attribute)."""
    mat = bpy.data.materials.get(PACK_MATERIAL)
    if mat is not None:
        return mat
    b = M._MatBuilder(PACK_MATERIAL)
    attr = b.n.new("ShaderNodeAttribute")
    attr.attribute_name = COLOR_ATTRIBUTE
    color = attr.outputs["Color"]
    z = b.separate(b.coord("Generated"))[2]
    nz = b.noise(scale=1.2, detail=1.0, coord_kind="Generated")
    f = b.math("ADD", z, b.math("MULTIPLY", b.math("SUBTRACT", nz, 0.5), 0.16), clamp=True)
    k = SHADE_BOTTOM ** 2.2  # the sRGB factor, in linear
    dark = b.mix(color, (k, k, k, 1.0), 1.0, blend="MULTIPLY")
    return b.finish(b.mix(dark, color, f))


def kit_materials(**by_part):
    """A ``post`` hook giving parts a kit material instead of ``M_Pack``: ``kit_materials(Glow="M_Glow_window")``
    puts the lamp glass (``parts={"Glow": [...]}``) back in the kit's emissive material. The pack has no emission,
    so this is how a lamp, a lantern or a portal keeps its glow (the export reads the MS_Shading Emission)."""
    def post(coll, parts):
        for suffix, mat_name in by_part.items():
            me = parts[suffix].data
            me.materials.clear()
            me.materials.append(M.get(mat_name))
    return post


def _base_color(pack_mat):
    """The linear base color of an imported pack material (no textures in the environment GLBs)."""
    if pack_mat is not None and pack_mat.node_tree is not None:
        bsdf = next((n for n in pack_mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is not None:
            return tuple(bsdf.inputs["Base Color"].default_value)
    return (0.8, 0.8, 0.8, 1.0)


def _colors_to_attribute(me):
    """Write each face's pack material color into the PackColor corner attribute, then use the one pack material."""
    colors = [_base_color(m) for m in me.materials] or [(0.8, 0.8, 0.8, 1.0)]
    ca = me.color_attributes.new(COLOR_ATTRIBUTE, "FLOAT_COLOR", "CORNER")
    for p in me.polygons:
        c = colors[min(p.material_index, len(colors) - 1)]
        for li in p.loop_indices:
            ca.data[li].color = c
    me.materials.clear()
    me.materials.append(pack_material())
    for p in me.polygons:
        p.material_index = 0


def _import(path):
    vl = bpy.context.view_layer
    vl.active_layer_collection = vl.layer_collection  # an excluded collection would silently not take the import
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path, import_scene_as_collection=False, merge_vertices=False,
                              import_shading="NORMALS", import_select_created_objects=False)
    return [o for o in bpy.data.objects if o not in before]


def _weld(me):
    """Merge the vertices glTF split per face (flat shading), so the kit's smooth shading and the decimation see
    connected surfaces."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(me)
    bm.free()


def _join(objs, name):
    if len(objs) > 1:
        with bpy.context.temp_override(active_object=objs[0], object=objs[0], selected_objects=objs,
                                       selected_editable_objects=objs):
            bpy.ops.object.join()
    o = objs[0]
    o.name = core.unique_name(name) if bpy.data.objects.get(name) is not None else name
    o.data.name = o.name
    return o


def _decimate(objs, budget):
    """Collapse-decimate every part by the same ratio until the parts fit the triangle budget."""
    total = _tris(objs)
    for _ in range(6):
        if total <= budget:
            break
        ratio = max(0.01, budget / total * 0.98)
        for o in objs:
            md = o.modifiers.new("_ArtPackBudget", "DECIMATE")
            md.decimate_type = "COLLAPSE"
            md.ratio = ratio
            md.use_collapse_triangulate = True
            dg = bpy.context.evaluated_depsgraph_get()
            me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
            old = o.data
            o.modifiers.remove(md)
            o.data = me
            if old.users == 0:
                bpy.data.meshes.remove(old)
        total = _tris(objs)
    return total


def build(name, info, coll):
    """Fill the asset collection ``coll`` with the pack model of catalog name ``name`` (see the module doc)."""
    spec = info.get("pack") or {}
    unknown = set(spec) - SPEC_KEYS
    if unknown:
        raise KeyError(f"{name}: unknown art pack spec keys {sorted(unknown)}")
    ref = reference(name, info)
    e = entry(name)
    path = glb_path(name)
    new = _import(path)
    for o in [o for o in new if o.type != "MESH"]:
        new.remove(o)
        bpy.data.objects.remove(o)
    if not new:
        raise RuntimeError(f"{name}: {e['output_file']} has no meshes")
    pack_tris = 0
    groups = {}
    for o in new:
        o.parent = None
        if o.data.users > 1:
            o.data = o.data.copy()
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
        for key, k in (spec.get("node_scale") or {}).items():
            if key in o.name:  # the pack node's own name, before any renaming
                o.data.transform(Matrix.Diagonal((*k, 1.0)))
        me = o.data
        if "custom_normal" in me.attributes:
            me.attributes.remove(me.attributes["custom_normal"])
        _weld(me)
        _colors_to_attribute(me)
        pack_tris += _tris([o])
        suffix = next((s for s, keys in (spec.get("parts") or {}).items() if any(k in o.name for k in keys)), "")
        groups.setdefault(suffix, []).append(o)
    parts = {s: _join(objs, f"{name}_{s}" if s else name) for s, objs in sorted(groups.items())}
    objs = list(parts.values())

    # triangle budget first (a collapse can move the silhouette), then rotate, fit the kit asset's size, anchor
    budget = tri_budget(name, ref, spec)
    tris = _decimate(objs, budget)
    rot = Matrix.Rotation(math.radians(spec.get("rot_z", 0.0)), 4, "Z")
    for o in objs:
        o.data.transform(rot)
    lo, hi = _mesh_bounds(objs)
    klo, khi = Vector(ref["lo"]), Vector(ref["hi"])
    if spec.get("fit", "xy") == "z":
        s = (khi.z - klo.z) / max(1e-6, hi.z - lo.z)
    else:
        s = max(khi.x - klo.x, khi.y - klo.y) / max(1e-6, hi.x - lo.x, hi.y - lo.y)
    s *= spec.get("scale_mul", 1.0)
    lo, hi = lo * s, hi * s
    if spec.get("align_xy", "origin") == "kit":
        dx, dy = (klo.x + khi.x - lo.x - hi.x) / 2, (klo.y + khi.y - lo.y - hi.y) / 2
    else:
        dx = dy = 0.0
    anchor = spec.get("anchor_z", "ground")
    dz = {"ground": -lo.z, "kit_bottom": klo.z - lo.z, "kit_top": khi.z - hi.z}[anchor]
    fit = Matrix.Translation((dx, dy, dz)) @ Matrix.Scale(s, 4)
    for o in objs:
        o.data.transform(fit)
    sharp = math.radians(spec.get("sharp_angle", 60.0))
    for o in objs:
        me = o.data
        me.shade_smooth()
        me.set_sharp_from_angle(angle=sharp)
        o["art_pack_file"] = e["output_file"]
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
    for m in [m for m in bpy.data.materials if m.users == 0 and not m.name.startswith("M_")]:
        bpy.data.materials.remove(m)
    if spec.get("post"):
        spec["post"](coll, parts)
    BUILT[name] = {"file": e["output_file"], "alias": e["alias"], "mapping_kind": e.get("mapping_kind"),
                   "scale": round(s, 4), "pack_tris": pack_tris, "tris": tris, "kit_tris": ref["tris"],
                   "decimated": tris < pack_tris, "parts": sorted(o.name for o in objs)}
    print("ART_PACK_ASSET", name, json.dumps(BUILT[name]))
    return objs
