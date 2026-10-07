"""Tests of the passable-tag registry (src/misostory/collision_tags.py), plain Python, no bpy.

    PY="/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"   # Linux: PY=python3
    "$PY" src/misostory/test_collision_tags.py

The traversal validator (traversal.obstacle_bvh) and validate.py decide what blocks a route walk with
collision_tags.passable, never with words in an object's name. These tests use dict stand-ins for Blender objects
(passable reads only .get), each named so that the old word list would have decided the other way.
"""

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from misostory import collision_tags as CT  # noqa: E402


class Ob(dict):
    """A Blender object's custom properties, plus a name the registry must ignore."""

    def __init__(self, name, **props):
        super().__init__(props)
        self.name = name


class Passable(unittest.TestCase):
    def test_passable_flag_with_an_unrelated_name_is_passable(self):
        self.assertTrue(CT.passable(Ob("Crate_Stack_03", passable=True)))

    def test_passable_asset_tag_with_an_unrelated_name_is_passable(self):
        self.assertTrue(CT.passable(Ob("MushroomTown_10000_Barrel_Big"), asset_tags=("prop", "passable")))
        for tag in CT.PASSABLE_TAGS:
            self.assertTrue(CT.passable(Ob("Crate_Stack"), asset_tags=(tag,)), tag)

    def test_climbable_and_collision_none_are_passable(self):
        self.assertTrue(CT.passable(Ob("Post_A", climbable="rope")))
        self.assertTrue(CT.passable(CT.tag(Ob("Wall_Board"), CT.NONE)))

    def test_a_name_alone_never_makes_an_object_passable(self):
        # the old word list let anything named rope, sign, banner, lantern, flag, ... through
        for name in ("Southperry_60000_MooringRope_0", "Sign_Board", "X1010000_BannerPole", "Hanging_Lantern",
                     "SnailFieldOfFlowers_1010004_Fence_Wood_Seg"):
            self.assertFalse(CT.passable(Ob(name)), name)
            self.assertFalse(CT.passable(Ob(name), asset_tags=("prop", "sign")), name)

    def test_solid_tags_are_not_passable(self):
        for cls in (CT.WALL, CT.HULL, CT.EXACT, CT.GROUND):
            self.assertFalse(CT.passable(CT.tag(Ob("Board_Overlay"), cls)), cls)
        self.assertFalse(CT.passable(Ob("Board", passable=False, climbable="")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
