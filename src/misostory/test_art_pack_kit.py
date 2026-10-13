"""Tests of the kit's pinned-art-pack swap (kit/art_pack.py, ADR 0002), run inside Blender (bpy):

    B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"   # Linux: B=blender
    "$B" -b --factory-startup --python src/misostory/test_art_pack_kit.py

Seams: the pack lookup by catalog name (aliases included), ``kit.ensure(name)`` with the pack required (what an
@asset built from a pack GLB looks like to the rest of the build), the runtime export's albedo bake of such an
asset, and the build scripts' preflight (no pack: exit 1 with a message naming the fetch script). Tests that need
the installed pack print SKIP without it (``bash scripts/art_pack.sh fetch``). Exit code 1 when a test fails.
"""

import importlib.util
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
        self.assertNotIn("Rock_A", swapped)          # Rocks: #74
        self.assertNotIn("Crate", swapped)           # Props: #73
        self.assertFalse([n for n in swapped if n.startswith("X")])  # per-map landmarks: #75


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
        for name in ("Bush_A", "Flower_Patch_A", "Vine_Hanging_A", "Butterfly", "Tree_Round_A"):
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
    prog = unittest.main(exit=False, verbosity=2, argv=[sys.argv[0]])
    sys.exit(0 if prog.result.wasSuccessful() else 1)
