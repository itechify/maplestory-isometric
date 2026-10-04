"""Scene assembly shared by scripts/build_island.py and scripts/build_map.py."""

import json
import time
import traceback

import bpy

from . import core, kit, maps, traversal
from . import layout as LY
from . import scene_setup
from .mapkit import MapCtx
from .world import World

TOP_COLLECTIONS = ["MAPS", "WORLD", "ENVIRONMENT_ASSETS", "CHARACTER_PROXIES", "MONSTER_PROXIES", "PORTALS",
                   "CAMERAS", "LIGHTING", "DEBUG"]


def reset_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for block in (bpy.data.meshes, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
        for d in list(block):
            if d.users == 0:
                block.remove(d)
    for name in TOP_COLLECTIONS:
        core.get_collection(name)
    core.get_collection("ENVIRONMENT_ASSETS", exclude=True)


def build_map(mid, origins, ground_objs, report):
    ctx = MapCtx.for_map(mid, origins, ground_objs)
    mod = maps.module_for(mid)
    t0 = time.time()
    status = "authored"
    err = None
    try:
        if mod is None:
            status = "placeholder"
            maps.placeholder(ctx)
        else:
            mod.build(ctx)
    except Exception as e:  # keep the island building; report loudly
        status = "error"
        err = traceback.format_exc()
        print(f"!!! MAP BUILD FAILED {mid}: {e}\n{err}")
    try:
        focus = getattr(mod, "GAMEPLAY_FOCUS", None) if mod else None
        scale = getattr(mod, "GAMEPLAY_SCALE", 30.0) if mod else 30.0
        extra = getattr(mod, "OVERVIEW_EXTRA", None) if mod else None
        ctx.cameras(focus=focus, gameplay_scale=scale, **({"overview_extra": extra} if extra else {}))
    except Exception:
        err = (err or "") + traceback.format_exc()
    frame = None
    if hasattr(ctx, "gameplay_frame_check"):  # player / mob proxies inside the Gameplay camera frame
        try:
            frame = ctx.gameplay_frame_check()
        except Exception:
            frame = {"ok": False, "error": traceback.format_exc()}
    try:
        cleared = traversal.clear_routes(ctx)
    except Exception:
        cleared = ["error: " + traceback.format_exc()]
    ctx.finalize()
    try:
        trav = traversal.check_map(ctx)
        trav["cleared_from_routes"] = cleared
    except Exception:
        trav = {"ok": False, "error": traceback.format_exc()}
    report["maps"][str(mid)] = {"traversal": trav, "slug": ctx.slug, "status": status, "error": err, "seconds": round(time.time() - t0, 2),
                                "portals": ctx.portals, "routes": ctx.routes, "npcs": ctx.npcs,
                                "spawns": [{k: v for k, v in s.items() if k != "points"} for s in ctx.spawns],
                                "gameplay_frame": frame}
    return ctx


def build(map_ids=None, scenery=True, res=(1920, 1080), samples=48):
    """Build the island (or a subset of maps). Returns a report dict."""
    t0 = time.time()
    reset_scene()
    scene_setup.setup_render(res=res, samples=samples)
    scene_setup.setup_world()
    scene_setup.setup_sun()
    origins = LY.resolve()
    ids = list(map_ids) if map_ids else list(LY.MAPS)
    report = {"maps": {}, "started": time.strftime("%Y-%m-%d %H:%M:%S")}
    world = World(origins)
    full = map_ids is None
    if full:
        world.island()
    plinths = {}
    for mid in ids:
        if LY.MAPS[mid]["kind"] != "interior":
            plinths[mid] = [o for o in world.plinth(mid) if o.name.endswith("_Cap")]
    ctxs = {}
    for mid in ids:
        ctxs[mid] = build_map(mid, origins, plinths.get(mid, []), report)
    if full:
        built = {}
        for mid, ctx in ctxs.items():
            for p in ctx.portals:
                if p["kind"] == "edge":
                    built[(mid, p["name"])] = tuple(p["world"])
        world.trails(built, ctxs)
        report["trails"] = world.trail_report
        world.lake()
        if scenery:
            report["forest_trees"] = world.scenery()
        world.sea()
        island_cameras(world)
        map_labels(origins)
    core.get_collection("DEBUG").hide_render = True
    report["seconds"] = round(time.time() - t0, 1)
    report["objects"] = len(bpy.data.objects)
    return report, ctxs, world


def island_cameras(world):
    coll = core.get_collection("CAMERAS/Cams_Island")
    outline = world.island_outline
    pts = [(x, y, z) for x, y in outline[::6] for z in (0.0, 30.0)]
    pts += [(x, y, -170.0) for x, y in outline[::12]]
    cam = scene_setup.make_camera("CAM_Island_Overview", coll)
    scene_setup.fit_camera(cam, pts, margin=1.02)
    cam2 = scene_setup.make_camera("CAM_Island_Overview_Close", coll)
    scene_setup.fit_camera(cam2, [(x, y, z) for x, y in outline[::6] for z in (0.0, 30.0)], margin=0.98)
    # regional views
    regions = {
        "MapleRoad": [0, 10000, 20000, 30000, 40000, 40001, 40002, 50000],
        "MushroomTownArea": [0, 10000, 20000, 30000],
        "SnailHuntingGrounds": [40000, 40001, 40002],
        "SouthperryAndSplitRoad": [50000, 60000],
        "RainbowStreet": [1000000, 1000001, 1000002, 1000003, 1000004, 1000005, 1000006, 1010000, 1010002, 1010004,
                          1020000, 1020001],
        "AmherstArea": [1010000, 1010002, 1010004, 1020000],
        "WestAmherstForests": [1000000, 1000001, 1000002, 1000005, 1000006],
    }
    origins = world.origins
    for name, ids in regions.items():
        rp = []
        for mid in ids:
            for x, y in LY.footprint_world(mid, origins, margin=4.0):
                rp += [(x, y, LY.MAPS[mid]["z"]), (x, y, LY.MAPS[mid]["z"] + 14)]
        c = scene_setup.make_camera(f"CAM_Region_{name}", coll)
        scene_setup.fit_camera(c, rp, margin=1.04)
    # hero shot: lower pitch so the floating underside and cliff-base clouds show
    hero = scene_setup.make_camera("CAM_Island_Hero", coll, pitch=24)
    scene_setup.fit_camera(hero, pts, margin=1.0)
    # a steeper "world map" style view
    top = scene_setup.make_camera("CAM_Island_WorldMapStyle", coll, pitch=62)
    scene_setup.fit_camera(top, pts, margin=1.02)


def map_labels(origins):
    """Big floating '<id> <name>' labels above every map (DEBUG, for labeled overview renders)."""
    import math
    from . import materials as M
    coll = core.get_collection("DEBUG/Debug_MapLabels")
    for mid, m in LY.MAPS.items():
        if m["kind"] == "interior":
            continue
        fp = LY.footprint_world(mid, origins)
        cx = sum(p[0] for p in fp) / 4
        cy = sum(p[1] for p in fp) / 4
        cu = bpy.data.curves.new(f"Label_{m['slug']}", "FONT")
        cu.body = f"{m['name']}\n{mid}"
        cu.size = 6.0
        cu.align_x = "CENTER"
        cu.extrude = 0.4
        cu.materials.append(M.get("M_Marker_NPC"))
        ob = bpy.data.objects.new(f"MapLabel_{m['slug']}", cu)
        ob.location = (cx, cy, m["z"] + 26.0)
        ob.rotation_euler = (math.radians(90 - scene_setup.ISO_PITCH), 0, math.radians(scene_setup.ISO_YAW))
        coll.objects.link(ob)


def _viewer_defaults():
    """Open the .blend looking through the island overview camera, with the DEBUG layer hidden in the viewport
    (renders toggle DEBUG via hide_render, so this only affects what a person sees when opening the file)."""
    scene = bpy.context.scene
    cam = bpy.data.objects.get("CAM_Island_Overview")
    if cam:
        scene.camera = cam

    def find(layer, name):
        if layer.name == name:
            return layer
        for child in layer.children:
            hit = find(child, name)
            if hit:
                return hit
        return None
    dbg = find(bpy.context.view_layer.layer_collection, "DEBUG")
    if dbg:
        dbg.hide_viewport = True
    for screen in bpy.data.screens:
        for area in screen.areas:
            for space in area.spaces:
                if space.type == "VIEW_3D":
                    space.shading.type = "MATERIAL"
                    space.clip_end = 6000.0
                    # a clean first look: no camera/empty outlines (61 cameras), no floor grid or axes
                    space.overlay.show_extras = False
                    space.overlay.show_floor = False
                    space.overlay.show_axis_x = False
                    space.overlay.show_axis_y = False
                    if cam:
                        space.region_3d.view_perspective = "CAMERA"
                        space.region_3d.view_camera_zoom = 29.0  # the camera frame fills a typical viewport
                        space.region_3d.view_camera_offset = (0.0, 0.0)


def save(path):
    core.drop_eval_scene()
    _viewer_defaults()
    bpy.context.preferences.filepaths.save_version = 0  # the .blend is a build artifact: no .blend1 backups
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)


def write_report(report, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, default=str)
