"""Tests of the kit's pinned-art-pack swap (kit/art_pack.py, ADR 0002), run inside Blender (bpy):

    B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"   # Linux: B=blender
    "$B" -b --factory-startup --python src/misostory/test_art_pack_kit.py [-- ClassName[.test_name] ...]

Seams: the pack lookup by catalog name (aliases included), ``kit.ensure(name)`` with the pack required (what an
@asset built from a pack GLB looks like to the rest of the build), the runtime export's albedo bake of such an
asset, and the build scripts' preflight (no pack: exit 1 with a message naming the fetch script). Tests that need
the installed pack print SKIP without it (``bash scripts/art_pack.sh fetch``). Exit code 1 when a test fails.
"""

import importlib.util
import math
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.dirname(HERE))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

from misostory import build, kit  # noqa: E402
from misostory.kit import art_pack  # noqa: E402

HAVE_PACK = not art_pack.preflight(["Bush_A"], pack_dir=art_pack.DEFAULT_DIR)


def bounds(objs):
    """From the vertices: asset sources live in an excluded collection, whose cached bound_box goes stale."""
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in objs:
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            lo, hi = Vector(map(min, lo, p)), Vector(map(max, hi, p))
    return lo, hi


def tris(objs):
    return sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)


class PackLookup(unittest.TestCase):
    def setUp(self):
        if not HAVE_PACK:
            self.skipTest("no art pack installed (bash scripts/art_pack.sh fetch)")

    def test_alias_resolves_to_the_mapped_file_not_the_name(self):
        entry = art_pack.entry("Flower_Patch_A")
        self.assertEqual(entry["output_file"], "environment/glb/flower_1.glb")
        self.assertTrue(entry["alias"])
        self.assertTrue(art_pack.glb_path("Flower_Patch_A").replace("\\", "/").endswith("environment/glb/flower_1.glb"))

    def test_source_named_entry_is_not_an_alias(self):
        self.assertFalse(art_pack.entry("Bush_A")["alias"])

    def test_trees_and_foliage_swap_but_other_categories_and_landmarks_do_not(self):
        swapped = art_pack.swapped_names(kit.REGISTRY)
        self.assertIn("Tree_Round_A", swapped)
        self.assertIn("Vine_Hanging_A", swapped)
        self.assertNotIn("Crate", swapped)           # Props: #73
        self.assertFalse([n for n in swapped if n.startswith("X")])  # per-map landmarks: #75


class ArchitectureRocksTerrainLookup(unittest.TestCase):
    """#74: the architecture, rocks and terrain catalog names come from the pack too."""

    def setUp(self):
        if not HAVE_PACK:
            self.skipTest("no art pack installed (bash scripts/art_pack.sh fetch)")

    def test_architecture_rocks_and_terrain_swap_but_their_landmarks_do_not(self):
        swapped = art_pack.swapped_names(kit.REGISTRY)
        for name in ("Fence_Wood_Seg", "House_Mushroom_OrangeSpotted", "Sign_Board", "Rock_A", "Rock_Cliff_Stone",
                     "Mountain_Peak_A", "Cloud_Puff_A"):
            self.assertIn(name, swapped)
        self.assertFalse([n for n in swapped if n.startswith("X")])  # per-map landmarks: #75

    def test_the_missing_pack_message_names_every_swapped_category(self):
        msg = art_pack.missing_message(["no art pack installed at nowhere"])
        for cat in ("Architecture", "Rocks", "Terrain", "Trees", "Foliage"):
            self.assertIn(cat, msg)


class ArchitectureRocksTerrainFromPack(unittest.TestCase):
    """#74: kit.ensure(name) of architecture, rocks and terrain keeps the frame the island places them in."""

    NAMES = ("Fence_Wood_Seg", "Fence_Picket_Seg", "Mountain_Peak_B", "Mountain_Hill", "Rock_A", "Rock_B",
             "Rock_Boulder", "Rock_Cliff_Stone", "Cloud_Puff_A", "Post_StoneCap", "Eave_Lashed_4m",
             "House_Mushroom_OrangeSpotted", "House_Mushroom_OrangeOven", "House_Wood_TwoStory_Capped",
             "Tomato_Gate", "Hill_Door", "Barrel_Door_Mound", "Door_Plank")

    @classmethod
    def setUpClass(cls):
        if not HAVE_PACK:
            raise unittest.SkipTest("no art pack installed (bash scripts/art_pack.sh fetch)")
        build.reset_scene()
        art_pack.configure("required")
        cls.kit = {n: art_pack.reference(n, kit.REGISTRY[n]) for n in cls.NAMES}
        cls.colls = {n: kit.ensure(n) for n in cls.NAMES}

    @classmethod
    def tearDownClass(cls):
        art_pack.configure("off")

    def objs(self, name):
        return list(self.colls[name].objects)

    def points(self, name, z0=-1e9, z1=1e9):
        return [p for o in self.objs(name) for v in o.data.vertices for p in [o.matrix_world @ v.co] if z0 <= p.z <= z1]

    def test_fences_run_from_the_origin_along_x_like_the_kit_segment(self):
        """m.fence and the trails scale a segment (L/n/2, 1, 1) from its origin: the kit runs 0..2 m along +X."""
        for name in ("Fence_Wood_Seg", "Fence_Picket_Seg"):
            lo, hi = bounds(self.objs(name))
            self.assertAlmostEqual(lo.x, self.kit[name]["lo"][0], delta=0.05, msg=name)
            self.assertAlmostEqual(hi.x, self.kit[name]["hi"][0], delta=0.05, msg=name)

    def test_mountains_keep_the_kit_frame_radius_and_height(self):
        """The island scales a mountain (radius, radius, height / kit height): the pack peak must fill the kit's
        unit radius and its exact height, whatever the pack's proportions."""
        for name in ("Mountain_Peak_B", "Mountain_Hill"):
            lo, hi = bounds(self.objs(name))
            klo, khi = self.kit[name]["lo"], self.kit[name]["hi"]
            self.assertAlmostEqual(hi.z - lo.z, khi[2] - klo[2], delta=0.02, msg=name)
            self.assertAlmostEqual(max(hi.x - lo.x, hi.y - lo.y), max(khi[0] - klo[0], khi[1] - klo[1]), delta=0.02,
                                   msg=name)

    def test_clouds_fill_the_kit_cloud_frame(self):
        """The island squashes clouds (sea layers at (s, 0.8 s, 0.55 s)): the slim pack cloud, fitted by its width
        only, read as a field of white petals, so it fills the kit cloud's box on every axis."""
        lo, hi = bounds(self.objs("Cloud_Puff_A"))
        klo, khi = self.kit["Cloud_Puff_A"]["lo"], self.kit["Cloud_Puff_A"]["hi"]
        for i in range(3):
            self.assertAlmostEqual(hi[i] - lo[i], khi[i] - klo[i], delta=0.02, msg=i)
            self.assertAlmostEqual(lo[i], klo[i], delta=0.02, msg=i)

    def test_rocks_keep_the_kit_height_so_their_collision_class_is_unchanged(self):
        """The export gives a rock a prism only when its scaled top reaches 0.9 m: the kit Rock_A (top 0.64 m) never
        blocks at its usual scales, and the pack rock must not start to: same top (Rock_B, 0.86 m, is close)."""
        for name in ("Rock_A", "Rock_B"):
            lo, hi = bounds(self.objs(name))
            klo, khi = self.kit[name]["lo"], self.kit[name]["hi"]
            self.assertAlmostEqual(hi.z, khi[2], delta=0.01, msg=name)

    def test_cliff_stones_stay_set_into_the_cliff_face(self):
        """Rock_Cliff_Stone's origin is inside the stone (kit z -0.33..0.55): 8,389 stones are placed at the face."""
        lo, hi = bounds(self.objs("Rock_Cliff_Stone"))
        klo, khi = self.kit["Rock_Cliff_Stone"]["lo"], self.kit["Rock_Cliff_Stone"]["hi"]
        self.assertAlmostEqual(lo.z, klo[2], delta=0.02)
        self.assertAlmostEqual((lo.y + hi.y) / 2, (klo[1] + khi[1]) / 2, delta=0.03)

    def test_assets_the_kit_keeps_out_of_the_shadows_still_cast_none(self):
        for name in ("Cloud_Puff_A", "Post_StoneCap", "Eave_Lashed_4m"):
            self.assertTrue(all(not o.visible_shadow for o in self.objs(name)), name)
        self.assertTrue(all(o.visible_shadow for o in self.objs("Rock_A")))

    def test_clouds_and_hills_keep_the_kit_look_materials(self):
        """Clouds glow softly (M_Cloud) and hills wear the meadow's grass painting (M_Hill)."""
        self.assertEqual({m.name for o in self.objs("Cloud_Puff_A") for m in o.data.materials}, {"M_Cloud"})
        self.assertIn("M_Hill", {m.name for o in self.objs("Mountain_Hill") for m in o.data.materials})

    def test_house_windows_and_lantern_glow_and_the_cap_is_its_own_part(self):
        """The pack has no emission: the kit's lit windows (M_Window) and lantern (M_Glow_window) come back on
        purpose, and the cap is a separate <name>_Cap like the kit's (no collision tag: it starts above any jump)."""
        name = "House_Mushroom_OrangeSpotted"
        mats = {m.name for o in self.objs(name) for m in o.data.materials}
        self.assertTrue({"M_Window", "M_Glow_window"} <= mats, mats)
        cap = self.colls[name].objects.get(f"{name}_Cap")
        self.assertIsNotNone(cap)
        self.assertIsNone(cap.get("collision"))
        self.assertGreater(min((cap.matrix_world @ v.co).z for v in cap.data.vertices), 3.0)

    def test_mushroom_house_walls_stand_where_the_kit_walls_did(self):
        """The map's door path and portal line up with the kit stem (front 2.12 m, base ring 2.5 m): fitted by its
        wider cap, the pack Sen's house (1.25x) blocked route ToSensHouse in 20000."""
        name = "House_Mushroom_OrangeOven"
        self.assertGreaterEqual(min(p.y for p in self.points(name, 0.15, 1.6)), -2.6)

    def test_weapon_store_door_stays_where_the_kit_door_and_its_portal_are(self):
        """Amherst's in00 door portal stands in front of the kit door at (-1.2, -2.4)."""
        pts = self.points("House_Wood_TwoStory_Capped", 0.15, 1.6)
        ymin = min(p.y for p in pts)
        front = [p for p in pts if p.y < ymin + 0.1]
        self.assertAlmostEqual(sum(p.x for p in front) / len(front), -1.2, delta=0.2)
        self.assertTrue(-2.9 <= ymin <= -2.4, ymin)

    def test_portal_doors_leave_the_portal_and_its_arrival_clear(self):
        """The body band (0.15-1.6 m, the export's prism slice) stays behind the kit's front: Barrel_Door_Mound
        reaches 1.65 m in front of its origin (m1000000 _door), Tomato_Gate's posts and arch stand on its origin
        line with the portal 1.5 m in front (m1020001), Hill_Door is set into a hill face at its origin."""
        for name, front in (("Barrel_Door_Mound", -1.7), ("Hill_Door", -0.85)):
            self.assertGreaterEqual(min(p.y for p in self.points(name, 0.15, 1.6)), front, name)

    def test_tomato_gate_door_stands_behind_its_portal_so_arrivals_walk_in(self):
        """m1020001 puts the gate 1.5 m inward of out00, so the arrival point (1.5 m inward of the anchor) is the gate
        origin and route Main runs on through it: the kit gate was an open arch. The pack gate is a closed door, so
        its body stands behind the portal anchor (y -1.5) by more than a body radius (0.3 m)."""
        self.assertLessEqual(max(p.y for p in self.points("Tomato_Gate", 0.15, 1.6)), -1.85)

    def test_interior_door_stays_as_flat_against_its_wall_as_the_kit_door(self):
        """The door portals' route starts stand in front of Door_Plank (1010001, 1010003): the pack door's
        threshold, raised into the body band by the fit, touched them."""
        coll = bpy.data.collections.new("_kit_door")
        try:
            kit.REGISTRY["Door_Plank"]["fn"](coll)
            kit_front = min(p.y for o in coll.objects for v in o.data.vertices for p in [o.matrix_world @ v.co]
                            if 0.15 <= p.z <= 1.6)
        finally:
            for o in list(coll.objects):
                bpy.data.objects.remove(o)
            bpy.data.collections.remove(coll)
        self.assertGreaterEqual(min(p.y for p in self.points("Door_Plank", 0.15, 1.6)), kit_front - 0.15)

    def test_hill_door_fits_under_the_turf_lip_without_a_mound_of_its_own(self):
        """The map's hill is the mound: the door alone, at the kit door's size, tops out under a 2 m hill's lip."""
        lo, hi = bounds(self.objs("Hill_Door"))
        self.assertLessEqual(hi.z, 1.9)
        self.assertLessEqual(hi.x - lo.x, 2.1)

    def test_eave_runs_along_the_wall_top_like_the_kit_eave(self):
        lo, hi = bounds(self.objs("Eave_Lashed_4m"))
        self.assertAlmostEqual(lo.x, 0.0, delta=0.05)
        self.assertAlmostEqual(hi.x, 4.0, delta=0.05)
        self.assertAlmostEqual(hi.y, self.kit["Eave_Lashed_4m"]["hi"][1], delta=0.05)


def landmark_names():
    """Every per-map X<mapid>_* @asset (they register when their map module is imported)."""
    from misostory.maps import module_for
    from misostory import layout
    for mid in layout.MAPS:
        module_for(mid)
    return {n for n in kit.REGISTRY if art_pack.LANDMARK.match(n)}


class LandmarkAliasTable(unittest.TestCase):
    """#75: the committed alias table decides, per landmark, its pack model or that it stays kit art."""

    def test_every_landmark_is_listed_once_with_a_rationale(self):
        from misostory.kit import landmark_aliases as LA
        names = landmark_names()
        self.assertEqual(len(names), 183)
        self.assertEqual(set(LA.ALIASES) | set(LA.KIT_ART), names)
        self.assertFalse(set(LA.ALIASES) & set(LA.KIT_ART))
        for n, (model, why) in LA.ALIASES.items():
            self.assertTrue(model and why.strip(), n)
        for n, why in LA.KIT_ART.items():
            self.assertTrue(why.strip(), n)


class LandmarkAliasesFromPack(unittest.TestCase):
    """#75: kit.ensure(landmark) of an aliased landmark builds its pack model, fitted to the landmark's own size."""

    NAMES = ("X1010000_TownGate", "X60000_ArmorStore", "X1010000_DeptStore", "X1010000_YellowHouse",
             "X1010000_GiantTree", "X60000_Lighthouse_Tall", "X30000_HouseYellowBrim", "X20000_StoneArch",
             "X1000006_Gate_Posts")

    @classmethod
    def setUpClass(cls):
        if not HAVE_PACK:
            raise unittest.SkipTest("no art pack installed (bash scripts/art_pack.sh fetch)")
        landmark_names()
        build.reset_scene()
        art_pack.configure("required")
        cls.kit = {n: art_pack.reference(n, kit.REGISTRY[n]) for n in cls.NAMES}
        cls.colls = {n: kit.ensure(n) for n in cls.NAMES}

    @classmethod
    def tearDownClass(cls):
        art_pack.configure("off")

    def objs(self, name):
        return list(self.colls[name].objects)

    def test_aliased_landmarks_swap_and_kit_art_landmarks_do_not(self):
        self.assertTrue(art_pack.swaps("X60000_ArmorStore", kit.REGISTRY["X60000_ArmorStore"]))
        self.assertFalse(art_pack.swaps("X60000_Ship_Victoria", kit.REGISTRY["X60000_Ship_Victoria"]))
        self.assertFalse(art_pack.swaps("X0_HeenaBush", kit.REGISTRY["X0_HeenaBush"]))

    def test_built_from_the_alias_model_found_by_id(self):
        """A catalog name resolves through the mapping; a model no catalog name maps to, by its manifest id."""
        self.assertEqual(art_pack.BUILT["X60000_ArmorStore"]["model"], "Shop_Armor")
        self.assertEqual(art_pack.BUILT["X60000_ArmorStore"]["file"], "environment/glb/Shop_Armor.glb")
        self.assertEqual(art_pack.BUILT["X1010000_TownGate"]["file"], "environment/glb/village_welcome_gate.glb")
        self.assertTrue(all(o.get("art_pack_file") for o in self.objs("X1010000_TownGate")))

    def test_scaled_uniformly_to_the_landmark_size(self):
        lo, hi = bounds(self.objs("X1010000_TownGate"))
        klo, khi = self.kit["X1010000_TownGate"]["lo"], self.kit["X1010000_TownGate"]["hi"]
        self.assertAlmostEqual(max(hi.x - lo.x, hi.y - lo.y), max(khi[0] - klo[0], khi[1] - klo[1]), delta=0.05)
        self.assertAlmostEqual(lo.z, 0.0, delta=0.01)

    def points(self, name, z0=-1e9, z1=1e9):
        return [p for o in self.objs(name) for v in o.data.vertices for p in [o.matrix_world @ v.co] if z0 <= p.z <= z1]

    def band(self, name, z0=0.15, z1=1.6):
        """The mesh inside the export's prism slice (0.15-1.6 m), what blocks a walk: the edges cut at the slice
        (a tall post has no vertex inside it)."""
        out = []
        for o in self.objs(name):
            vs = [o.matrix_world @ v.co for v in o.data.vertices]
            for e in o.data.edges:
                a, b = vs[e.vertices[0]], vs[e.vertices[1]]
                if a.z > b.z:
                    a, b = b, a
                lo, hi = max(a.z, z0), min(b.z, z1)
                if lo > hi:
                    continue
                for z in (lo, (lo + hi) / 2, hi):
                    t = 0.0 if b.z - a.z < 1e-9 else (z - a.z) / (b.z - a.z)
                    out.append(a.lerp(b, t))
        return out

    def test_every_aliased_landmark_is_built_from_the_pack(self):
        from misostory.kit import landmark_aliases as LA
        for name in self.NAMES:
            self.assertEqual(art_pack.BUILT[name]["model"], LA.ALIASES[name][0], name)

    def test_mushroom_house_walls_stand_where_the_kit_walls_did(self):
        """Door paths and portals line up with the kit stem's front (stem_r x 1.06; the stone base ring
        stem_r x 1.25): fitted by the wider cap, the walls would stand on them (#74, Sen's house)."""
        for name, stem_r in (("X1010000_DeptStore", 2.0), ("X1010000_YellowHouse", 2.0),
                             ("X30000_HouseYellowBrim", 1.8)):
            self.assertGreaterEqual(min(p.y for p in self.band(name)), -stem_r * 1.25 - 0.1, name)

    def test_department_store_door_spans_its_portal(self):
        """Amherst in02 stands 0.59 m west of the store's axis (38.65 vs 39.3 at scale 1.1), at the kit door."""
        pts = self.band("X1010000_DeptStore")
        ymin = min(p.y for p in pts)
        front = [p.x for p in pts if p.y < ymin + 0.15]
        self.assertLess(min(front), -0.8)
        self.assertGreater(max(front), -0.4)

    def test_armor_store_door_and_its_portal_stay_clear(self):
        """Southperry in00 stands at (-1.0, -3.25) from the store's origin, route ArmorStore ending 0.4 m short:
        the walls stand at the kit front (y -2.5, base -2.75) and nothing (no pack counter) blocks the walk-in."""
        pts = self.band("X60000_ArmorStore")
        walk = [p for p in pts if -1.7 <= p.x <= -0.3 and p.y < -2.9]
        self.assertFalse(walk, f"{len(walk)} points in front of the door")
        body = [p for p in pts if abs(p.x) < 2.8]  # the pack awning's corner posts stand out at x +-3.1
        self.assertGreaterEqual(min(p.y for p in body), -3.0)  # kit base -2.75; in00 -3.25

    def test_gates_leave_the_walk_between_their_posts_clear(self):
        """Route Main runs between the town gate's pillars (kit at x +-2.9); the meadow gate's posts at +-1.6."""
        for name, post, gap in (("X1010000_TownGate", 2.9, 2.2), ("X1000006_Gate_Posts", 1.6, 1.3)):
            pts = self.band(name)
            self.assertFalse([p for p in pts if abs(p.x) < gap], name)
            for s in (-1, 1):
                side = [p.x for p in pts if p.x * s > 0]
                self.assertAlmostEqual(sum(side) / len(side), s * post, delta=0.3, msg=name)

    def test_stone_arch_opening_stays_as_wide_as_the_kit_arch(self):
        """The walk to Sen's door (in01) runs through the arch: the kit's inner faces are 0.77 m off centre."""
        pts = [p for p in self.band("X20000_StoneArch") if p.z > 0.3]
        self.assertGreaterEqual(min(abs(p.x) for p in pts), 0.72)

    def test_giant_tree_trunk_carries_the_kit_pods_and_door(self):
        """X1010000_TreePods (kit art) sit at 2.55-2.75 m from the origin, grown into the kit trunk (r 2.6)."""
        pts = self.band("X1010000_GiantTree", 2.0, 5.0)
        trunk = [math.hypot(p.x, p.y) for p in pts if abs(p.x) < 0.5 and p.y > 0]  # the back, clear of door/balcony
        self.assertAlmostEqual(max(trunk), 2.4, delta=0.5)
        front = min(p.y for p in self.band("X1010000_GiantTree"))
        self.assertTrue(-3.6 <= front <= -2.2, front)  # the kit door stands at -2.45 on a 3.6 m root flare

    def test_lighthouse_foot_stays_within_the_kit_plinth(self):
        """Route Main passes the quay corner 4.7 m from the tower (m60000): fitted to the kit height, the stouter
        pack tower's foot (r 3.96) blocked it. At 1.15x the kit plinth's width (r 2.95) it clears it, all but the
        door step."""
        foot = [p for p in self.band("X60000_Lighthouse_Tall") if not (abs(p.x) < 1.5 and p.y < 0)]
        self.assertLessEqual(max(math.hypot(p.x, p.y) for p in foot), 2.95 * 1.15 + 0.05)

    def test_lit_windows_come_back_as_kit_glow(self):
        for name in ("X1010000_DeptStore", "X60000_ArmorStore", "X60000_Lighthouse_Tall", "X1010000_GiantTree"):
            mats = {m.name for o in self.objs(name) for m in o.data.materials}
            self.assertIn("M_Window", mats, name)

    def test_the_landmark_keeps_its_name_and_registry_entry(self):
        self.assertEqual(self.colls["X1010000_TownGate"].name, "X1010000_TownGate")
        self.assertTrue(all(o.name.startswith("X1010000_TownGate") for o in self.objs("X1010000_TownGate")))
        self.assertTrue(all(o.get("asset") == "X1010000_TownGate" for o in self.objs("X1010000_TownGate")))


class PreflightWithoutPack(unittest.TestCase):
    def test_missing_pack_is_reported_with_the_fetch_command(self):
        problems = art_pack.preflight(["Bush_A"], pack_dir=os.path.join(tempfile.gettempdir(), "no_such_art_pack"))
        self.assertTrue(problems)
        self.assertIn("bash scripts/art_pack.sh fetch", art_pack.missing_message(problems))

    def test_the_build_preflight_covers_the_landmark_alias_models(self):
        """build_island.py preflights before any map module (and so any landmark) is imported."""
        names = art_pack.required_names(kit.REGISTRY)
        self.assertIn("village_welcome_gate", names)
        self.assertIn("Shop_Armor", names)
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "environment"))
            for f in ("source_catalog_mapping.json", "manifest_complete.json"):
                with open(os.path.join(d, "environment", f), "w") as fh:
                    fh.write('{"entries": [], "assets": []}')
            problems = art_pack.preflight(["village_welcome_gate"], pack_dir=d)
        self.assertEqual(len(problems), 1)
        self.assertIn("manifest_complete.json", problems[0])

    def test_build_map_exits_1_without_the_pack(self):
        env = dict(os.environ, MISOSTORY_ART_PACK_DIR=os.path.join(tempfile.gettempdir(), "no_such_art_pack"))
        r = subprocess.run([bpy.app.binary_path, "-b", "--factory-startup", "--python",
                            os.path.join(ROOT, "scripts", "build_map.py"), "--", "0"],
                           env=env, capture_output=True, text=True, timeout=300)
        self.assertEqual(r.returncode, 1, r.stdout[-2000:])
        self.assertIn("bash scripts/art_pack.sh fetch", r.stdout + r.stderr)
        self.assertNotIn("RENDERED", r.stdout)


class EnsureFromPack(unittest.TestCase):
    """kit.ensure(name) with the pack required: the @asset's collection holds the pack model, fitted to the kit."""

    @classmethod
    def setUpClass(cls):
        if not HAVE_PACK:
            raise unittest.SkipTest("no art pack installed (bash scripts/art_pack.sh fetch)")
        build.reset_scene()
        art_pack.configure("required")
        cls.kit_size = {}
        for name in ("Bush_A", "Flower_Patch_A", "Vine_Hanging_A", "Butterfly", "Tree_Round_A", "Tree_Birch_Teal"):
            ref = art_pack.reference(name, kit.REGISTRY[name])   # the procedural builder's size and triangles
            cls.kit_size[name] = ref
        cls.colls = {n: kit.ensure(n) for n in cls.kit_size}

    @classmethod
    def tearDownClass(cls):
        art_pack.configure("off")

    def objs(self, name):
        return list(self.colls[name].objects)

    def test_parts_are_meshes_named_without_blender_suffixes_and_unparented(self):
        for name in self.colls:
            for o in self.colls[name].objects:
                self.assertEqual(o.type, "MESH")
                self.assertNotRegex(o.name, r"\.\d{3}$")
                self.assertIsNone(o.parent)
                self.assertEqual(o.matrix_basis, o.matrix_basis.Identity(4), o.name)
                self.assertEqual(o["asset"], name)
                self.assertTrue(o.get("art_pack_file"), o.name)

    def test_largest_horizontal_size_matches_the_kit_asset(self):
        for name in ("Bush_A", "Flower_Patch_A", "Tree_Round_A"):
            lo, hi = bounds(self.objs(name))
            klo, khi = self.kit_size[name]["lo"], self.kit_size[name]["hi"]
            self.assertAlmostEqual(max(hi.x - lo.x, hi.y - lo.y), max(khi[0] - klo[0], khi[1] - klo[1]), delta=0.02,
                                   msg=name)

    def test_ground_assets_stand_on_z0(self):
        for name in ("Bush_A", "Tree_Round_A"):
            lo, _ = bounds(self.objs(name))
            self.assertAlmostEqual(lo.z, 0.0, delta=0.01, msg=name)

    def test_hanging_vine_keeps_the_kit_frame_origin_at_the_top(self):
        lo, hi = bounds(self.objs("Vine_Hanging_A"))
        klo, khi = self.kit_size["Vine_Hanging_A"]["lo"], self.kit_size["Vine_Hanging_A"]["hi"]
        self.assertAlmostEqual(hi.z, khi[2], delta=0.02)
        self.assertAlmostEqual(hi.z - lo.z, khi[2] - klo[2], delta=0.05)

    def test_tree_trunk_band_blocks_about_as_much_as_the_kit_tree(self):
        """The export's trunk prism is the 0.1-1.0 m slice: the kit Tree_Round_A's reaches 0.92 m from the trunk.
        The pack's splayed roots, fitted to the kit canopy, reached 1.47 m and boxed players in at cliff feet."""
        self.assertLessEqual(self.trunk_reach("Tree_Round_A"), 1.0)

    def test_trees_keep_a_separate_canopy_part_like_the_kit(self):
        """The game reads <asset>_Canopy meshes (breakables.json placement.canopies: box sight lines)."""
        for name in ("Tree_Round_A", "Tree_Birch_Teal"):
            names = sorted(o.name for o in self.colls[name].objects)
            self.assertEqual(names, [name, f"{name}_Canopy"])

    def test_birch_trunk_band_stays_slim_like_the_kit_birch(self):
        """The kit birches' trunk prism reaches 0.39 m; the pack birch's trunk and roots reached 0.8 m."""
        self.assertLessEqual(self.trunk_reach("Tree_Birch_Teal"), 0.5)

    def trunk_reach(self, name):
        return max(math.hypot(p.x, p.y) for o in self.objs(name) for v in o.data.vertices
                   for p in [o.matrix_world @ v.co] if 0.1 <= p.z <= 1.0)

    def test_butterfly_hovers_at_the_kit_height(self):
        lo, _ = bounds(self.objs("Butterfly"))
        self.assertAlmostEqual(lo.z, self.kit_size["Butterfly"]["lo"][2], delta=0.02)

    def test_triangles_stay_within_the_kit_asset_budget(self):
        for name in self.colls:
            self.assertLessEqual(tris(self.objs(name)), art_pack.tri_budget(name, self.kit_size[name]), name)

    def test_materials_go_through_the_shared_shading_group(self):
        for name in self.colls:
            for o in self.colls[name].objects:
                for m in o.data.materials:
                    if m.name == "M_Outline":
                        continue
                    self.assertTrue(any(n.type == "GROUP" and n.node_tree and n.node_tree.name == "MS_Shading"
                                        for n in m.node_tree.nodes), f"{name}: {m.name}")

    def test_every_pack_asset_shares_one_material_so_it_draws_as_one_surface(self):
        """The pack's colors ride on the mesh, so a tree of five pack colors is one draw, not five."""
        looks = {m.name for n in self.colls for o in self.colls[n].objects for m in o.data.materials
                 if m.name != "M_Outline"}
        self.assertEqual(len(looks), 1, looks)
        bush = self.colls["Bush_A"].objects[0].data
        self.assertIn(art_pack.COLOR_ATTRIBUTE, bush.color_attributes)

    def test_trees_get_the_ink_outline_and_flowers_do_not(self):
        self.assertTrue(any(md.name == "Outline" for o in self.colls["Tree_Round_A"].objects for md in o.modifiers))
        self.assertFalse(any(md.name == "Outline" for o in self.colls["Flower_Patch_A"].objects for md in o.modifiers))

    def test_export_bake_of_a_pack_asset_is_not_black(self):
        spec = importlib.util.spec_from_file_location("export_runtime", os.path.join(ROOT, "scripts",
                                                                                      "export_runtime.py"))
        ex = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(ex)
        src = self.colls["Bush_A"].objects[0]
        o = src.copy()
        o.data = src.data.copy()
        o.modifiers.clear()
        bpy.context.scene.collection.objects.link(o)
        ex.bake_albedo([o], bpy.context.window_manager.windows[0])
        ca = o.data.color_attributes["Col"]
        mean = [sum(d.color[i] for d in ca.data) / len(ca.data) for i in range(3)]
        self.assertGreater(sum(mean), 0.1, f"baked albedo is black: {mean}")
        # bake_albedo rewired MS_Shading to emit its Albedo; later tests rebuild the scene


if __name__ == "__main__":
    # "-- ClassName[.test_name] ..." runs a subset
    prog = unittest.main(exit=False, verbosity=2,
                         argv=[sys.argv[0]] + (sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []))
    sys.exit(0 if prog.result.wasSuccessful() else 1)
