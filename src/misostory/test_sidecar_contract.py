"""Tests of the Blender -> runtime export contract (src/misostory/sidecar_diff.py), plain Python, no bpy.

    PY="/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"
    "$PY" src/misostory/test_sidecar_contract.py                                     # the shipped game/assets/world
    MISOSTORY_EXPORT_DIR=_scratch/export_staging "$PY" src/misostory/test_sidecar_contract.py   # a staged export

The first test runs the whole contract on a real export (MeowDB parity per map, the one-way ledge invariant, player
spawns, spawn regions, additive schema). The others mutate a temporary copy of that export's sidecars and prove that
each check actually fails on the defect it exists for (an NPC on the wrong map, a ledge a player could climb, a
blocked player spawn, a renamed field, ...), so a check cannot silently pass everything.
"""

import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from misostory import ledge_rules, sidecar_diff  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
EXPORT = os.environ.get("MISOSTORY_EXPORT_DIR") or os.path.join(ROOT, "game", "assets", "world")
if not os.path.isabs(EXPORT):
    EXPORT = os.path.join(ROOT, EXPORT)


def _sidecar_by_map(d, meowdb_id):
    for f in os.listdir(d):
        if f.endswith(".json"):
            with open(os.path.join(d, f), encoding="utf-8") as fh:
                s = json.load(fh)
            if s.get("meowdb_map_id") == meowdb_id:
                return f, s
    raise KeyError(meowdb_id)


def _write(d, f, s):
    with open(os.path.join(d, f), "w", encoding="utf-8") as fh:
        json.dump(s, fh)


@unittest.skipUnless(os.path.isdir(EXPORT) and os.path.exists(os.path.join(EXPORT, "index.json")),
                     f"no runtime export at {EXPORT} (run scripts/export_runtime.py first)")
class ExportContract(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="sidecar_contract_")
        listed = set()
        for f in os.listdir(EXPORT):
            if f.endswith(".json"):
                shutil.copy(os.path.join(EXPORT, f), self.tmp)
                with open(os.path.join(EXPORT, f), encoding="utf-8") as fh:
                    files = json.load(fh).get("files")
                listed |= {n for n in (files or {}).values() if n} if isinstance(files, dict) else set()
            elif f.endswith(".glb"):
                open(os.path.join(self.tmp, f), "wb").close()  # presence is all the diff checks for geometry
        for n in listed:  # placeholders for listed geometry, so each test sees only its own mutation
            if not os.path.exists(os.path.join(self.tmp, n)):
                open(os.path.join(self.tmp, n), "wb").close()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def contract(self):
        return sidecar_diff.compare(EXPORT, self.tmp)

    def assertFails(self, rep, key, *needles):
        text = json.dumps(rep[key])
        for n in needles:
            self.assertIn(n, text, f"{key} should mention {n!r}: {rep[key]}")
        self.assertFalse(rep["ok"])

    # ------------------------------------------------------------------ the real export
    def test_export_meets_the_contract(self):
        rep = sidecar_diff.compare(EXPORT, EXPORT)
        for key in ("missing_files", "unparsable", "count_failures", "listed_files_missing", "contract_failures"):
            self.assertEqual(rep[key], [], f"{key}: {rep[key]}")
        self.assertTrue(rep["ok"])
        c = rep["counts"]
        self.assertEqual((c["portals"], c["npcs"], c["player_spawn0"], c["trails"], c["one_way_trails"]),
                         (47, 21, 25, 20, 1))

    def test_unmodified_copy_is_clean(self):
        rep = self.contract()
        self.assertEqual(rep["contract_failures"], [])
        self.assertEqual(rep["removed_paths"], {})
        self.assertEqual(rep["type_changes"], {})

    # ------------------------------------------------------------------ NPC parity (MAP_ARCHITECTURE 3.3)
    def test_npc_on_the_wrong_map_fails(self):
        fa, a = _sidecar_by_map(self.tmp, "000000050")
        fb, b = _sidecar_by_map(self.tmp, "000001010")
        mai = next(n for n in a["npcs"] if n["meowdb_npc_id"] == "11")
        a["npcs"].remove(mai)
        b["npcs"].append(mai)  # Iteration One's Mai stood in Amherst
        _write(self.tmp, fa, a)
        _write(self.tmp, fb, b)
        self.assertFails(self.contract(), "contract_failures", "000000050 npcs", "000001010 npcs")

    def test_npc_with_a_wrong_meowdb_id_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000030")
        next(n for n in s["npcs"] if n["name"] == "Todd")["meowdb_npc_id"] = "6"
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "000000030 npcs")

    # ------------------------------------------------------------------ portals and the one-way link
    def test_two_way_portal_to_the_wrong_destination_portal_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000030")
        next(p for p in s["portals"] if p["name"] == "in00")["to_portal"] = "in01"
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "000000030.in00")

    def test_one_way_portal_without_its_spawn_index_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000030")
        next(p for p in s["portals"] if p["name"] == "out00")["to_spawn_index"] = None
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "000000030.out00")

    def test_portal_no_route_reaches_fails(self):
        # a route that stops short of the press-Up trigger no longer proves the portal is reachable (round 2 moved
        # door-route ends back from in01 / in00; they must stay inside the 1.6 m deep box)
        f, s = _sidecar_by_map(self.tmp, "000000020")
        p = next(p for p in s["portals"] if p["name"] == "in01")
        r = next(r for r in s["routes"] if r["name"] == "ToSensHouse")
        self.assertIsNotNone(sidecar_diff.route_reach(s, p, 0.8, 2.25, 3.0), "the shipped route enters the trigger")
        ix, iz = sidecar_diff._portal_inward_xz(p)
        end = r["points"][-1]
        r["points"][-1] = [end[0] + 1.5 * ix, end[1], end[2] + 1.5 * iz]  # stop 1.5 m further back from the door
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "000000020.in01", "press-Up trigger")

    def test_one_way_arrival_point_missing_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000040")
        s["arrival_points"] = []
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "000000030.out00", "arrival point")

    # ------------------------------------------------------------------ the one-way ledge (MAP_ARCHITECTURE 4.4)
    def test_ledge_low_enough_to_climb_back_fails(self):
        lo, _hi, _ = ledge_rules.ledge_bounds(ROOT)
        f, s = _sidecar_by_map(self.tmp, "000000040")
        s["ledges"][0]["height_m"] = round(lo - 0.05, 3)  # jump apex + step reaches it
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "height")

    def test_ledge_higher_than_a_drop_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000040")
        s["ledges"][0]["height_m"] = ledge_rules.MAX_DROP_M + 0.1
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "height")

    def test_ledge_face_off_the_gate_plane_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000040")
        s["ledges"][0]["face_offset_from_gate_m"] = 0.3
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "off the gate plane")

    def test_gate_plane_not_at_footprint_plus_offset_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000040")
        led = s["ledges"][0]
        n = led["gate_plane"]["outward_normal_xz"]
        pt = led["gate_plane"]["point"]
        led["gate_plane"]["point"] = [pt[0] + 0.5 * n[0], pt[1], pt[2] + 0.5 * n[1]]  # 1.5 m out, not 1 m
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "gate plane point")

    def test_gate_plane_off_the_runtime_containment_ring_fails(self):
        data = os.path.join(self.tmp, "_data")
        shutil.copytree(os.path.join(ROOT, "game", "data", "canonical", "maps"), os.path.join(data, "canonical", "maps"))
        shutil.copytree(os.path.join(ROOT, "game", "data", "misostory"), os.path.join(data, "misostory"))
        p = os.path.join(data, "misostory", "presentation.json")
        with open(p, encoding="utf-8") as fh:
            pres = json.load(fh)
        pres["containment"]["ring_offset_m"] = 1.5  # the runtime moved its ring; the ledge face did not follow
        with open(p, "w", encoding="utf-8") as fh:
            json.dump(pres, fh)
        self.assertFails(sidecar_diff.compare(EXPORT, self.tmp, data_dir=data), "contract_failures",
                         "containment ring")

    def test_ledge_not_blocked_in_reverse_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000040")
        s["ledges"][0]["reverse_blocked_at_face"] = False
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "not blocked at the face")

    # ------------------------------------------------------------------ player spawns and spawn regions
    def test_blocked_player_spawn_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000001021")
        s["spawn_clearance"] = {"player_spawns": [{"index": 0, "clear": False, "blockers": ["Tomato_Gate"]}],
                                "portal_arrivals": []}
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "player_spawns[0] is blocked", "Tomato_Gate")

    def test_player_spawn_outside_the_footprint_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000040")
        fp = s["footprint"]["outline_xz"]
        s["player_spawns"][0]["position"] = [min(p[0] for p in fp) - 2.0, s["player_spawns"][0]["position"][1],
                                             min(p[1] for p in fp) - 2.0]
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "outside the footprint")

    def test_missing_player_spawn_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000061")
        s["player_spawns"] = []
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "no player_spawns[0]")

    def test_spawn_region_with_a_species_meowdb_does_not_list_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000040")
        s["spawn_regions"][0]["species"] = ["Blue Snail"]  # v8 had Blue Snails here; MeowDB has Snails only
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "Blue Snail")

    def test_hunting_map_without_spawn_regions_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000030")  # a town with 6 MeowDB Tutorial Jr. Sentinel spawns
        s["spawn_regions"] = []
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "000000030: 6 MeowDB spawn points but 0")

    def _set_clearance(self, meowdb_id, **rows):
        f, s = _sidecar_by_map(self.tmp, meowdb_id)
        clr = s.setdefault("spawn_clearance", {})
        clr.setdefault("player_spawns", [])
        clr.setdefault("portal_arrivals", [])
        clr.update(rows)
        _write(self.tmp, f, s)

    def test_climbable_grabbable_from_a_portal_trigger_fails(self):
        # the 000001005 case before fix round F1: a ladder foot 2.7 m from out00 inside the trigger plus the grab radius
        f, s = _sidecar_by_map(self.tmp, "000001005")
        p = next(q for q in s["portals"] if q["name"] == "out00")
        c = s["climbables"][0]
        ox, oy, oz = p["position"]
        c["bottom"] = c["foot_ground"] = [ox + 0.3, oy, oz + 0.3]
        c["top"] = [ox + 0.3, oy + 2.4, oz + 0.3]
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "000001005.out00", "grabbable from its press-Up trigger")

    def test_blocked_portal_arrival_fails(self):
        # any blocked arrival fails, even when the old export had the same one (it used to fail only on growth)
        self._set_clearance("000001000", portal_arrivals=[
            {"portal": "in02", "clear": False, "grounded": True, "blockers": ["DoorMound_in02"]}])
        self.assertFails(self.contract(), "contract_failures", "000001000.in02 arrival blocked", "DoorMound_in02")

    def test_ungrounded_portal_arrival_fails(self):
        self._set_clearance("000001021", portal_arrivals=[
            {"portal": "out00", "clear": False, "grounded": False, "blockers": []}])
        self.assertFails(self.contract(), "contract_failures", "000001021.out00", "not grounded")

    def test_blocked_route_end_fails(self):
        # the Godot route bot starts a run at either end of a route (the 1010001 Rafters end stood under an eave)
        self._set_clearance("000001011", route_ends=[
            {"route": "Rafters", "end": "end", "position": [2810.95, 5.0, 4.2], "clear": False,
             "blockers": ["Eave_Lashed_4m"]}])
        self.assertFails(self.contract(), "contract_failures", "route Rafters end", "Eave_Lashed_4m")

    def test_route_under_a_real_overhang_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000001021")
        rc = s["collision"]["summary"].setdefault("route_check", {})
        rc["overhead_by_kind"] = {"step": 0, "climb_or_drop": 0, "body": 1}
        rc["overhead"] = [{"route": "WestBed", "kind": "body", "hit_above_m": 0.67, "wall": "Tomato_Plant_08"}]
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "contract_failures", "000001021", "WestBed")

    # ------------------------------------------------------------------ schema and files
    def test_removed_field_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000040")
        del s["player_start"]
        _write(self.tmp, f, s)
        rep = self.contract()
        self.assertIn("player_start", json.dumps(rep["removed_paths"].get(f, [])))
        self.assertFalse(rep["ok"])

    def test_emptied_list_is_not_a_removed_field(self):
        f, s = _sidecar_by_map(self.tmp, "000000040")
        for row in s["spawn_clearance"]["portal_arrivals"]:
            row["blockers"] = []  # every arrival clear: the list stays, its items are gone
        s["collision"]["exact_fallback"] = {}
        _write(self.tmp, f, s)
        rep = self.contract()
        self.assertNotIn(f, rep["removed_paths"])

    def test_emptied_marker_list_fails(self):
        # only problem lists (blockers, fallbacks, offenders) may empty: an exporter that drops every climbable or
        # route of a map must not pass as "the list is merely empty"
        for key in ("climbables", "routes"):
            f, s = _sidecar_by_map(self.tmp, "000000040")
            self.assertTrue(s[key], f"the test needs {key} on 000000040")
            s[key] = []
            _write(self.tmp, f, s)
            rep = self.contract()
            self.assertIn(f"{key}[]", rep["removed_paths"].get(f, []), key)
            self.assertFalse(rep["ok"], key)
            self.tearDown()
            self.setUp()

    def test_removed_field_inside_a_list_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000040")
        for row in s["spawn_clearance"]["portal_arrivals"]:
            del row["grounded"]
        _write(self.tmp, f, s)
        rep = self.contract()
        self.assertIn("spawn_clearance.portal_arrivals[].grounded", rep["removed_paths"].get(f, []))
        self.assertFalse(rep["ok"])

    def test_changed_field_type_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000040")
        for n in s["npcs"]:
            n["meowdb_npc_id"] = int(n["meowdb_npc_id"])  # ids are strings
        _write(self.tmp, f, s)
        rep = self.contract()
        self.assertIn("npcs[].meowdb_npc_id", rep["type_changes"].get(f, {}))
        self.assertFalse(rep["ok"])

    def test_listed_file_that_does_not_exist_fails(self):
        f, s = _sidecar_by_map(self.tmp, "000000040")
        s["files"]["collision"] = "Nope.collision.glb"
        _write(self.tmp, f, s)
        self.assertFails(self.contract(), "listed_files_missing", "Nope.collision.glb")

    def test_missing_canonical_data_is_a_failure_not_a_pass(self):
        rep = sidecar_diff.compare(EXPORT, self.tmp, data_dir=os.path.join(self.tmp, "no_such_data"))
        self.assertFails(rep, "contract_failures", "no canonical map data")


if __name__ == "__main__":
    unittest.main(verbosity=2)
