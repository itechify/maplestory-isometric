"""Fixture tests of the Blender-side checks, run inside Blender (bpy): the traversal validator (traversal.py), the
island validator (scripts/validate.py) and the runtime export's own checks (scripts/export_runtime.py).

    B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"   # Linux: B=blender
    "$B" -b --factory-startup --python src/misostory/test_validator_fixtures.py

Each test builds a tiny map in an empty scene (a flat walkable slab, a route, one obstacle) and proves that a check
reports the defect it exists for, and only that: an object tagged passable is passable whatever its name, a post a
body meets only with a shoulder blocks a route, a climbable is read at its stored climb position, an untagged or
floating architecture mesh fails validate.py, and an obstacle on the line from a portal's anchor to its arrival
point blocks it at body height. The validate.py tests save the scene and run the real script in a second Blender
(about 30 s). Exit code 1 when a test fails.
"""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.dirname(HERE))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

from misostory import build, geo, traversal  # noqa: E402
from misostory import collision_tags as CT  # noqa: E402
from misostory.mapkit import MapCtx  # noqa: E402

SLUG = "Fixture_990001"


def fixture_map(L=20.0, D=10.0):
    """An empty scene with one map at the world origin (yaw 0, so local = world): a flat walkable slab at z 0."""
    build.reset_scene()
    m = MapCtx({"id": 990001, "slug": SLUG, "name": "Fixture", "size": (L, D), "kind": "field", "street": ""})
    slab = geo.MeshBuilder()
    slab.box((L + 2.0, D + 2.0, 0.2), loc=(L / 2, D / 2, -0.1), mat="M_Grass")
    m.ground.add(CT.tag(slab.build(f"{SLUG}_Slab", m.col_terrain, smooth=False), CT.WALL))
    return m


def block(m, name, lo, hi, coll=None, tag=CT.WALL):
    """A box mesh from local corner lo to hi (x, y, z) in the map's Architecture (or coll); tag None = untagged."""
    mb = geo.MeshBuilder()
    mb.box(tuple(b - a for a, b in zip(lo, hi)), loc=tuple((a + b) / 2 for a, b in zip(lo, hi)), mat="M_Wood")
    obj = mb.build(f"{SLUG}_{name}", coll or m.col_arch, smooth=False)
    return obj if tag is None else CT.tag(obj, tag)


def route_result(m):
    """{route label: check_route result} of traversal.check_map on the map."""
    return {r["route"]: r for r in traversal.check_map(m)["routes"]}


def blocked(res):
    return [i for i in res["issues"] if i["type"] == "blocked"]


class TraversalBlocking(unittest.TestCase):
    def test_passable_tag_with_an_unrelated_name_is_passable(self):
        # #27: what blocks a route is registry data (collision_tags.passable), never a word in the name
        m = fixture_map()
        m.route("Across", [(2.0, 5.0), (18.0, 5.0)])
        crate = block(m, "Crate_Stack", (9.5, 4.5, 0.0), (10.5, 5.5, 1.2))
        self.assertTrue(blocked(route_result(m)["Across"]), "an untagged crate on the route blocks it")
        crate["passable"] = True
        self.assertEqual(blocked(route_result(m)["Across"]), [], "a crate tagged passable does not")

    def test_a_passable_word_in_the_name_no_longer_makes_an_object_passable(self):
        m = fixture_map()
        m.route("Across", [(2.0, 5.0), (18.0, 5.0)])
        block(m, "Signpost_Rope_Lantern", (9.5, 4.5, 0.0), (10.5, 5.5, 1.2))
        self.assertTrue(blocked(route_result(m)["Across"]))

    def test_an_obstacle_only_a_side_ray_meets_is_reported(self):
        # #28: a post 0.2-0.4 m beside the centreline: the centre ray misses it, a body's shoulder does not
        m = fixture_map()
        m.route("Across", [(2.0, 5.0), (18.0, 5.0)])
        m.route("Back", [(18.0, 5.0), (2.0, 5.0)])
        block(m, "Post_Shoulder", (9.9, 5.2, 0.0), (10.1, 5.4, 1.4))
        res = route_result(m)
        self.assertFalse(res["Across"]["ok"])
        self.assertEqual({h["ray"] for h in blocked(res["Across"])}, {"left"})  # walking +x, +y is on the left
        self.assertEqual({h["ray"] for h in blocked(res["Back"])}, {"right"})
        self.assertEqual({h["by"] for h in blocked(res["Across"])}, {f"{SLUG}_Post_Shoulder"})

    def test_an_obstacle_beyond_a_body_width_is_not_reported(self):
        m = fixture_map()
        m.route("Across", [(2.0, 5.0), (18.0, 5.0)])
        block(m, "Post_Clear", (9.9, 5.4, 0.0), (10.1, 5.6, 1.4))
        self.assertTrue(route_result(m)["Across"]["ok"])


class ClimbPosition(unittest.TestCase):
    def test_the_stored_climb_position_is_read_not_the_mesh(self):
        # #26: m.ladder stores the climb line's bottom and top; traversal and the export read them, not the mesh
        m = fixture_map()
        lad = m.ladder("Ladder", 10.0, 8.0, 0.0, 3.0, facing=90, kind="ladder")
        self.assertEqual(tuple(round(v, 6) for v in lad["climb_bottom"]), (10.0, 8.0, 0.0))
        self.assertEqual(tuple(round(v, 6) for v in lad["climb_top"]), (10.0, 8.0, 3.0))
        for v in lad.data.vertices:  # shift the mesh 1.5 m: the climb position must not follow it
            v.co.x += 1.5
        (cx, cy, z0, z1, name, down), = traversal.climbables(m)
        self.assertEqual((round(cx, 6), round(cy, 6), round(z0, 6), round(z1, 6)), (10.0, 8.0, 0.0, 3.0))
        er = _export_runtime()
        c = er.climb_marker(lad, None)
        self.assertEqual((c["bottom"], c["top"]), ([10.0, 0.0, -8.0], [10.0, 3.0, -8.0]))


def _export_runtime():
    spec = importlib.util.spec_from_file_location("export_runtime", os.path.join(ROOT, "scripts", "export_runtime.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _box_bvh(lo, hi):
    vs = [Vector((x, y, z)) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return BVHTree.FromPolygons(vs, quads)


class ArrivalSegment(unittest.TestCase):
    """#25: the export's line test from a portal's anchor to its arrival point (export_runtime.capsule_checker)."""

    def segment(self, walls=None, hulls=()):
        er = _export_runtime()
        ground = BVHTree.FromPolygons([Vector((-5, -5, 0)), Vector((5, -5, 0)), Vector((5, 5, 0)), Vector((-5, 5, 0))],
                                      [(0, 1, 2, 3)])
        analysis = {"Fixture": {"hull_items": [{"name": n, "world": [(poly, z0, z1)]} for n, poly, z0, z1 in hulls],
                                "walls_bvh": walls, "ground_bvh": ground}}
        _blockers, _ground, dims, segment = er.capsule_checker(analysis)
        # anchor at the origin, arrival point 1.5 m inward along +y
        return segment(Vector((0.0, 0.0, 0.0)), Vector((0.0, 1.5, 0.0)), dims["body_band"])

    def test_a_clear_segment_is_clear(self):
        self.assertEqual(self.segment()[0], [])

    def test_a_prop_hull_on_the_segment_blocks_it(self):
        crate = [(-0.3, 0.6), (0.3, 0.6), (0.3, 0.9), (-0.3, 0.9)]
        self.assertEqual(self.segment(hulls=[("Crate_Hull", crate, -0.3, 1.0)])[0], ["Crate_Hull"])

    def test_a_thin_wall_between_two_samples_blocks_it(self):
        # 2 cm thick, between the samples at 0.5 and 0.75 m, from the knee to the chest
        self.assertEqual(self.segment(walls=_box_bvh((-1.0, 0.6, 0.6), (1.0, 0.62, 1.2)))[0], ["Fixture walls"])

    def test_what_stands_beside_or_below_the_body_band_does_not_block_it(self):
        beside = [(0.4, 0.6), (0.8, 0.6), (0.8, 0.9), (0.4, 0.9)]
        self.assertEqual(self.segment(hulls=[("Beside", beside, -0.3, 1.5)])[0], [])
        kerb = [(-1.0, 0.6), (1.0, 0.6), (1.0, 0.9), (-1.0, 0.9)]
        self.assertEqual(self.segment(hulls=[("Kerb", kerb, -0.3, 0.3)])[0], [])  # stepped over (step_up_m)


class IslandValidator(unittest.TestCase):
    """#29: scripts/validate.py on a saved fixture scene (the real script, in a second Blender)."""

    @classmethod
    def setUpClass(cls):
        m = fixture_map()
        m.route("Across", [(2.0, 5.0), (18.0, 5.0)])
        block(m, "Wall_Grounded", (1.0, 8.0, 0.0), (6.0, 8.3, 2.0))                 # tagged, on the slab
        block(m, "Screen_Untagged", (8.0, 8.0, 0.0), (11.0, 8.2, 1.8), tag=None)    # untagged, on the slab
        block(m, "Lintel_Floating", (14.0, 8.0, 3.0), (17.0, 8.3, 3.3))             # tagged, 3 m up, touching nothing
        cls.tmp = tempfile.mkdtemp(prefix="validator_fixture_")
        blend = os.path.join(cls.tmp, "fixture.blend")
        bpy.ops.wm.save_as_mainfile(filepath=blend, copy=True)
        out = os.path.join(cls.tmp, "out")
        subprocess.run([bpy.app.binary_path, "-b", "--factory-startup", blend, "--python",
                        os.path.join(ROOT, "scripts", "validate.py"), "--", "--out", out, "--build-report",
                        os.path.join(cls.tmp, "no_build_report.json")], check=True, capture_output=True, timeout=600)
        with open(os.path.join(out, "validation_report.json"), encoding="utf-8") as f:
            cls.rep = json.load(f)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def messages(self, check):
        return " | ".join(i["msg"] for i in self.rep["issues"] if i["check"] == check)

    def test_an_untagged_architecture_mesh_fails_collision_tags(self):
        self.assertFalse(self.rep["checks"]["collision_tags"]["ok"])
        msgs = self.messages("collision_tags")
        self.assertIn(f"{SLUG}_Screen_Untagged", msgs)
        self.assertNotIn("Wall_Grounded", msgs)

    def test_a_floating_architecture_mesh_fails_floating_props(self):
        self.assertFalse(self.rep["checks"]["floating_props"]["ok"])
        floating = {f["object"] for f in self.rep["stats"]["floating"]}
        self.assertEqual(floating, {f"{SLUG}_Lintel_Floating"})


if __name__ == "__main__":
    result = unittest.main(argv=[sys.argv[0], "-v"], exit=False).result
    sys.exit(0 if result.wasSuccessful() else 1)
