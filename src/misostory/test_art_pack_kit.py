"""Tests of the kit's pinned-art-pack swap (kit/art_pack.py, ADR 0002), run inside Blender (bpy):

    B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"   # Linux: B=blender
    "$B" -b --factory-startup --python src/misostory/test_art_pack_kit.py [-- TestClass[.test_name] ...]

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

    def test_trees_foliage_props_and_markers_swap_but_other_categories_and_landmarks_do_not(self):
        swapped = art_pack.swapped_names(kit.REGISTRY)
        self.assertIn("Tree_Round_A", swapped)
        self.assertIn("Vine_Hanging_A", swapped)
        self.assertIn("Crate", swapped)              # Props: #73
        self.assertIn("Portal_Swirl", swapped)       # Markers: #73
        self.assertNotIn("Rock_A", swapped)          # Rocks: #74
        self.assertNotIn("Sign_Board", swapped)      # Architecture: #74 (shares noticeboard.glb with Signpost_Notice)
        self.assertFalse([n for n in swapped if n.startswith("X")])  # per-map landmarks: #75

    def test_signpost_notice_resolves_the_alias_it_shares_with_sign_board(self):
        entry = art_pack.entry("Signpost_Notice")
        self.assertEqual(entry["output_file"], "environment/glb/noticeboard.glb")
        self.assertTrue(entry["alias"])


class PreflightWithoutPack(unittest.TestCase):
    def test_missing_pack_is_reported_with_the_fetch_command(self):
        problems = art_pack.preflight(["Bush_A"], pack_dir=os.path.join(tempfile.gettempdir(), "no_such_art_pack"))
        self.assertTrue(problems)
        self.assertIn("bash scripts/art_pack.sh fetch", art_pack.missing_message(problems))

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


def emission(mat):
    """The Emission input an MS_Shading material feeds its group (what the export bakes into the glow)."""
    for n in mat.node_tree.nodes:
        if n.type == "GROUP" and n.node_tree and n.node_tree.name == "MS_Shading":
            s = n.inputs.get("Emission")
            return 0.0 if s is None or s.is_linked else float(s.default_value)
    return 0.0


class EnsurePropsAndMarkersFromPack(unittest.TestCase):
    """#73: the props and markers built from the pack keep the kit asset's frame, height and glow."""

    NAMES = ("Lamp_Post", "Hanging_Lantern", "Portal_Swirl", "Portal_Door", "Bed", "Cart", "NPC_Beacon", "Crate",
             "Haystack", "Planter_Box")

    @classmethod
    def setUpClass(cls):
        if not HAVE_PACK:
            raise unittest.SkipTest("no art pack installed (bash scripts/art_pack.sh fetch)")
        build.reset_scene()
        art_pack.configure("required")
        cls.ref = {n: art_pack.reference(n, kit.REGISTRY[n]) for n in cls.NAMES}
        cls.colls = {n: kit.ensure(n) for n in cls.NAMES}

    @classmethod
    def tearDownClass(cls):
        art_pack.configure("off")

    def objs(self, name):
        return list(self.colls[name].objects)

    def glows(self, name):
        return [o.name for o in self.objs(name) for m in o.data.materials if m and emission(m) > 0.5]

    def test_lamps_and_lanterns_keep_a_glowing_glass(self):
        """The pack has no emission at all; the kit lamps glow (M_Glow_window), seen at night and in the shops."""
        for name in ("Lamp_Post", "Hanging_Lantern"):
            self.assertTrue(self.glows(name), f"{name}: no glowing part")

    def test_portals_glow_like_the_kit_portals(self):
        """Players find exits by the portal glow (the kit's M_Portal_* materials, emission >= 1.2)."""
        for name in ("Portal_Swirl", "Portal_Door"):
            self.assertTrue(self.glows(name), f"{name}: no glowing part")
            self.assertTrue(any(m.name.startswith("M_Portal_") for o in self.objs(name) for m in o.data.materials),
                            name)

    def test_lamp_post_keeps_the_kit_height(self):
        """The pack lamp is a slim centred post: fitting the kit lamp's arm width made it 4.4 m tall (kit 3.1 m)."""
        lo, hi = bounds(self.objs("Lamp_Post"))
        self.assertAlmostEqual(hi.z - lo.z, self.ref["Lamp_Post"]["hi"][2] - self.ref["Lamp_Post"]["lo"][2],
                               delta=0.05)

    def test_hanging_lantern_hangs_from_its_origin(self):
        """Kit frame: the origin is the hook at the top (placed under ceilings and eaves)."""
        lo, hi = bounds(self.objs("Hanging_Lantern"))
        self.assertAlmostEqual(hi.z, self.ref["Hanging_Lantern"]["hi"][2], delta=0.02)
        self.assertLess(lo.z, -0.3)

    def test_bed_runs_along_x_with_the_headboard_at_minus_x(self):
        """Kit frame (promoted.bed): length along +X, headboard at -X; the pack bed runs along Y."""
        objs = self.objs("Bed")
        lo, hi = bounds(objs)
        self.assertGreater(hi.x - lo.x, hi.y - lo.y)
        tall = [(o.matrix_world @ v.co).x for o in objs for v in o.data.vertices if (o.matrix_world @ v.co).z > 1.0]
        self.assertLess(sum(tall) / len(tall), 0.0, "the tall bedposts (headboard) stand at -X")

    def test_cart_shafts_point_to_plus_x_like_the_kit_cart(self):
        lo, hi = bounds(self.objs("Cart"))
        self.assertGreater(hi.x - lo.x, hi.y - lo.y)
        self.assertGreater((lo.x + hi.x) / 2, 0.3)

    def test_npc_beacon_hovers_centred_on_its_origin_like_the_kit_diamond(self):
        lo, hi = bounds(self.objs("NPC_Beacon"))
        self.assertAlmostEqual(lo.z, self.ref["NPC_Beacon"]["lo"][2], delta=0.02)
        self.assertAlmostEqual(hi.z, self.ref["NPC_Beacon"]["hi"][2], delta=0.02)

    def test_haystack_body_blocks_about_as_much_as_the_kit_haystack(self):
        """The kit haystack's width is the loose straw at its foot (2.8 m); its body is 1.9 m across. Fitted to the
        straw, the solid pack haystack blocked route EastYard in Tomato Field (1020001)."""
        reach = max(math.hypot(p.x, p.y) for o in self.objs("Haystack") for v in o.data.vertices
                    for p in [o.matrix_world @ v.co] if 0.15 <= p.z <= 1.6)
        self.assertLessEqual(reach, 1.0)

    def test_planter_box_stays_low_enough_to_step_over_like_the_kit_box(self):
        """The kit planter box is 0.44 m tall, under the export's 0.45 m STEP_HEIGHT, so it gets no collision prism.
        Fitted by width the pack box came out 0.45 m and six new prisms appeared in Tomato Field (1020001)."""
        lo, hi = bounds(self.objs("Planter_Box"))
        self.assertLess(hi.z - lo.z, 0.45)

    def test_plain_props_stand_on_z0_at_the_kit_size(self):
        lo, hi = bounds(self.objs("Crate"))
        klo, khi = self.ref["Crate"]["lo"], self.ref["Crate"]["hi"]
        self.assertAlmostEqual(lo.z, 0.0, delta=0.01)
        self.assertAlmostEqual(max(hi.x - lo.x, hi.y - lo.y), max(khi[0] - klo[0], khi[1] - klo[1]), delta=0.02)

    def test_parts_are_named_after_the_asset_and_carry_their_pack_file(self):
        for name in self.NAMES:
            for o in self.objs(name):
                self.assertTrue(o.name == name or o.name.startswith(name + "_"), o.name)
                self.assertNotRegex(o.name, r"\.\d{3}$")
                self.assertEqual(o.matrix_basis, o.matrix_basis.Identity(4), o.name)
                self.assertTrue(o.get("art_pack_file"), o.name)


if __name__ == "__main__":
    tests = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []  # e.g. -- PackLookup
    prog = unittest.main(exit=False, verbosity=2, argv=[sys.argv[0]] + tests)
    sys.exit(0 if prog.result.wasSuccessful() else 1)
