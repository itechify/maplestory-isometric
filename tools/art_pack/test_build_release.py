"""Tests of the art-pack release packager (tools/art_pack/build_release.py), plain Python, no bpy.

    PY="/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"   # Linux: PY=python3
    "$PY" -I tools/art_pack/test_build_release.py

Each test builds small stand-in delivery ZIPs (the shape of Jarvis's nine part ZIPs: one MisoStory_Asset_Pack/ folder
spread over several archives, or one ZIP of a merged and patched source) and packages them the way the real release is
built.
"""

import hashlib
import io
import json
import os
import sys
import tempfile
import unittest
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_release as BR  # noqa: E402

ROOT = "MisoStory_Asset_Pack/"


def make_zip(path, members):
    with zipfile.ZipFile(path, "w") as z:
        for name, data in members.items():
            z.writestr(name, data if isinstance(data, bytes) else data.encode())


def read_zip(path):
    with zipfile.ZipFile(path) as z:
        return {i.filename: z.read(i) for i in z.infolist() if not i.is_dir()}


def index(small_bed):
    return {
        "canonical_npcs": [{"id": "1", "name": "Heena", "file": "characters/glb/Heena.glb"}],
        "files": [
            {"file": "environment/glb/Bed.glb", "bytes": 3, "sha256": hashlib.sha256(b"BIG").hexdigest()},
            {"file": "environment/glb/" + small_bed, "bytes": 5, "sha256": hashlib.sha256(b"small").hexdigest()},
        ],
    }


def manifest(small_bed):
    return {"assets": [{"id": small_bed[:-4], "file": "glb/" + small_bed}, {"id": "Bed", "file": "glb/Bed.glb"}]}


V10_BED_RENAME = {"environment/glb/bed.glb": ("environment/glb/bed_single.glb", "case clash")}


def delivery(tmp, small_bed="bed_single.glb"):
    """Two part ZIPs shaped like Jarvis's delivery. v1.1 (the default) ships the generic small bed as bed_single.glb
    beside Bed.glb; small_bed="bed.glb" gives v1.0's pair, which collides on a case-insensitive file system."""
    a = os.path.join(tmp, "Part01.zip")
    b = os.path.join(tmp, "Part04.zip")
    make_zip(a, {
        "MisoStory_Assets_Extraction_README.txt": "merge the parts",
        ROOT + "README.md": "# pack",
        ROOT + "asset_index.json": json.dumps(index(small_bed), indent=2),
        ROOT + "build_all.py": "print('never run')",
        ROOT + "MapleIsland_Diorama.blend": b"BLEND",
        ROOT + "previews/MapleIsland_Diorama.png": b"PNG",
        ROOT + "godot_demo/viewer.gd": "extends Node",
        ROOT + "characters/glb/Heena.glb": b"HEENA",
        ROOT + "characters/wardrobe_swap.gd": "class_name MisoWardrobeSwap",
        ROOT + "characters/renders/Heena.png": b"PNG",
        ROOT + "icons/equipment/item_1_Sword.png": b"ICON",
        ROOT + "docs/v1_1/icons/inventory_pairs_before_after_32px.png": b"PREVIEW",
        ROOT + "qa/monsters/qa_runtime/project.godot": "[application]",
    })
    make_zip(b, {
        ROOT + "environment/glb/Bed.glb": b"BIG",
        ROOT + "environment/glb/" + small_bed: b"small",
        ROOT + "environment/manifest_complete.json": json.dumps(manifest(small_bed), indent=2),
        ROOT + "environment/contact_props.png": b"PNG",
        ROOT + "environment/build.sh": "echo never",
        ROOT + "monsters/Snail.glb": b"SNAIL",
        ROOT + "monsters/Snail.png": b"PREVIEW",
        ROOT + "monsters/icons/Snail.png": b"ICON",
        ROOT + "monsters/Snail.blend": b"BLEND",
    })
    return [a, b]


class Package(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.zips = delivery(self.tmp)
        self.out = os.path.join(self.tmp, "out", "pack.zip")
        self.result = BR.build(self.zips, self.out, tag="art-pack-v9.9")
        self.files = read_zip(self.out)

    def tearDown(self):
        self._tmp.cleanup()

    def test_the_runtime_subset_keeps_models_icons_json_and_docs(self):
        for path in ("characters/glb/Heena.glb", "environment/glb/Bed.glb", "monsters/Snail.glb",
                     "icons/equipment/item_1_Sword.png", "monsters/icons/Snail.png", "asset_index.json",
                     "environment/manifest_complete.json", "README.md"):
            self.assertIn(path, self.files)

    def test_galleries_previews_blends_and_the_godot_demo_are_left_out(self):
        for path in self.files:
            self.assertFalse(path.endswith(".blend"), path)
            self.assertFalse(path.startswith("godot_demo/") or "/godot_demo/" in path, path)
        for path in ("previews/MapleIsland_Diorama.png", "characters/renders/Heena.png",
                     "environment/contact_props.png", "monsters/Snail.png", "MisoStory_Assets_Extraction_README.txt",
                     "docs/v1_1/icons/inventory_pairs_before_after_32px.png", "qa/monsters/qa_runtime/project.godot"):
            self.assertNotIn(path, self.files)

    def test_generator_code_is_kept_only_as_an_ignored_reference(self):
        self.assertIn("reference/.gdignore", self.files)
        self.assertIn("reference/build_all.py", self.files)
        self.assertIn("reference/characters/wardrobe_swap.gd", self.files)
        self.assertIn("reference/environment/build.sh", self.files)
        code = [p for p in self.files if p.endswith((".py", ".gd", ".sh", ".bat"))]
        self.assertTrue(all(p.startswith("reference/") for p in code), code)

    def test_the_v1_1_delivery_ships_both_beds_as_delivered(self):
        self.assertEqual(self.files["environment/glb/Bed.glb"], b"BIG")
        self.assertEqual(self.files["environment/glb/bed_single.glb"], b"small")
        listed = [f["file"] for f in json.loads(self.files["asset_index.json"])["files"]]
        self.assertEqual(listed, ["environment/glb/Bed.glb", "environment/glb/bed_single.glb"])

    def test_the_packager_no_longer_renames_the_bed(self):
        self.assertNotIn("environment/glb/bed.glb", BR.RENAMES)

    def test_no_two_paths_differ_only_in_case(self):
        lowered = [p.lower() for p in self.files]
        self.assertEqual(len(lowered), len(set(lowered)))

    def test_the_packaging_record_names_sources_and_rules(self):
        rec = json.loads(self.files["PACKAGING.json"])
        self.assertEqual(rec["tag"], "art-pack-v9.9")
        self.assertEqual([s["name"] for s in rec["source_zips"]], ["Part01.zip", "Part04.zip"])
        with open(self.zips[1], "rb") as f:
            self.assertEqual(rec["source_zips"][1]["sha256"], hashlib.sha256(f.read()).hexdigest())
        self.assertEqual(rec["renamed"], [])

    def test_the_checksum_rows_cover_every_file_with_size_and_sha(self):
        rows = {r["path"]: r for r in self.result["files"]}
        self.assertEqual(set(rows), set(self.files))
        for path, data in self.files.items():
            self.assertEqual(rows[path]["bytes"], len(data), path)
            self.assertEqual(rows[path]["sha256"], hashlib.sha256(data).hexdigest(), path)
        with open(self.out, "rb") as f:
            self.assertEqual(self.result["sha256"], hashlib.sha256(f.read()).hexdigest())

    def test_the_same_delivery_packages_to_identical_bytes(self):
        again = os.path.join(self.tmp, "again.zip")
        BR.build(self.zips, again, tag="art-pack-v9.9")
        with open(self.out, "rb") as f1, open(again, "rb") as f2:
            self.assertEqual(f1.read(), f2.read())

    def test_tsv_lists_path_bytes_and_sha_sorted(self):
        tsv = BR.checksums_tsv(self.result["files"])
        lines = tsv.strip().split("\n")
        self.assertEqual(lines, sorted(lines))
        path, size, sha = lines[0].split("\t")
        self.assertEqual(int(size), len(self.files[path]))
        self.assertEqual(sha, hashlib.sha256(self.files[path]).hexdigest())


class Renames(unittest.TestCase):
    """The rename mechanism, kept for later deliveries: v1.0's bed.glb renamed the way art-pack-v1.0 was built."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.zips = delivery(self.tmp, small_bed="bed.glb")

    def tearDown(self):
        self._tmp.cleanup()

    def test_a_renamed_file_keeps_its_bytes_and_every_json_follows(self):
        out = os.path.join(self.tmp, "out", "pack.zip")
        BR.build(self.zips, out, tag="art-pack-v1.0", renames=V10_BED_RENAME)
        files = read_zip(out)
        self.assertEqual(files["environment/glb/Bed.glb"], b"BIG")
        self.assertNotIn("environment/glb/bed.glb", files)
        self.assertEqual(files["environment/glb/bed_single.glb"], b"small")
        by_file = {f["file"]: f for f in json.loads(files["asset_index.json"])["files"]}
        self.assertEqual(by_file["environment/glb/bed_single.glb"]["sha256"], hashlib.sha256(b"small").hexdigest())
        self.assertIn("environment/glb/Bed.glb", by_file)
        manifest_files = [a["file"] for a in json.loads(files["environment/manifest_complete.json"])["assets"]]
        self.assertEqual(manifest_files, ["glb/bed_single.glb", "glb/Bed.glb"])
        rec = json.loads(files["PACKAGING.json"])
        self.assertEqual(rec["renamed"], [{
            "from": "environment/glb/bed.glb", "to": "environment/glb/bed_single.glb", "bytes": 5,
            "sha256": hashlib.sha256(b"small").hexdigest(),
            "json_rewritten": ["asset_index.json", "environment/manifest_complete.json"], "reason": "case clash"}])

    def test_the_v1_0_pair_without_its_rename_is_refused_as_a_case_clash(self):
        with self.assertRaises(BR.PackagingError):
            BR.build(self.zips, os.path.join(self.tmp, "o.zip"), tag="t")


class Rejects(unittest.TestCase):
    def test_a_member_escaping_the_pack_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            z = os.path.join(tmp, "evil.zip")
            make_zip(z, {ROOT + "../outside.glb": b"x"})
            with self.assertRaises(BR.PackagingError):
                BR.build([z], os.path.join(tmp, "o.zip"), tag="t")

    def test_an_unresolved_case_clash_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            z = os.path.join(tmp, "clash.zip")
            make_zip(z, {ROOT + "monsters/Snail.glb": b"a", ROOT + "monsters/snail.glb": b"b"})
            with self.assertRaises(BR.PackagingError):
                BR.build([z], os.path.join(tmp, "o.zip"), tag="t")

    def test_the_same_path_with_different_bytes_in_two_parts_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            a, b = os.path.join(tmp, "a.zip"), os.path.join(tmp, "b.zip")
            make_zip(a, {ROOT + "README.md": "one"})
            make_zip(b, {ROOT + "README.md": "two"})
            with self.assertRaises(BR.PackagingError):
                BR.build([a, b], os.path.join(tmp, "o.zip"), tag="t")


if __name__ == "__main__":
    unittest.main(verbosity=2)
