"""Tests of the art-pack fetch script (scripts/art_pack.sh), plain Python driving bash, no network.

    PY="/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"   # Linux: PY=python3; or: py
    "$PY" -I tools/art_pack/test_fetch.py          # from Git Bash on Windows, so `bash` is Git's bash

Each test pins a small stand-in release (a ZIP served from a file:// URL, its checksum manifest and a pin file) through
the script's ART_PACK_* overrides, then fetches it into a temporary install directory with a temporary cache.
"""

import hashlib
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SCRIPT = os.path.join(REPO, "scripts", "art_pack.sh").replace("\\", "/")
BASH = shutil.which("bash")

FILES = {
    "asset_index.json": b'{"files": []}\n',
    "characters/glb/Heena.glb": b"glTF-heena" * 50,
    "monsters/Snail.glb": b"glTF-snail" * 40,
    "reference/.gdignore": b"",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def zip_bytes(files):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for path in sorted(files):
            z.writestr(zipfile.ZipInfo(path, date_time=(2026, 10, 13, 0, 0, 0)), files[path])
    return buf.getvalue()


def fwd(p):
    return p.replace("\\", "/")


class Fetch(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        t = self._tmp.name
        self.served = os.path.join(t, "served")
        os.makedirs(self.served)
        self.zip_path = os.path.join(self.served, "Pack_v9.9.zip")
        self.zip_data = zip_bytes(FILES)
        with open(self.zip_path, "wb") as f:
            f.write(self.zip_data)
        self.tsv = os.path.join(t, "art-pack-v9.9.files.tsv")
        self.write_tsv(FILES)
        self.pin = os.path.join(t, "art_pack.json")
        self.write_pin(sha(self.zip_data), len(self.zip_data))
        self.install = os.path.join(t, "game", "assets", "art_pack")
        self.cache = os.path.join(t, "cache")
        self.url = "file:///" + fwd(self.zip_path).lstrip("/")

    def tearDown(self):
        self._tmp.cleanup()

    def write_tsv(self, files):
        with open(self.tsv, "w", newline="\n") as f:
            for path in sorted(files):
                f.write("%s\t%d\t%s\n" % (path, len(files[path]), sha(files[path])))

    def write_pin(self, asset_sha, asset_bytes):
        pin = {"release": {"tag": "art-pack-v9.9", "asset": "Pack_v9.9.zip", "asset_bytes": asset_bytes,
                           "asset_sha256": asset_sha, "url": "https://example.invalid/Pack_v9.9.zip",
                           "checksum_manifest": fwd(self.tsv)}}
        with open(self.pin, "w") as f:
            json.dump(pin, f, indent=2)

    def run_script(self, *args, url=None):
        env = dict(os.environ, ART_PACK_PIN=fwd(self.pin), ART_PACK_DIR=fwd(self.install),
                   ART_PACK_CACHE=fwd(self.cache), ART_PACK_URL=url if url is not None else self.url)
        return subprocess.run([BASH, SCRIPT, *args], env=env, capture_output=True, text=True, timeout=120)

    def installed(self, path):
        with open(os.path.join(self.install, path), "rb") as f:
            return f.read()

    def test_a_fresh_fetch_downloads_verifies_and_installs_every_file(self):
        r = self.run_script("fetch")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        for path, data in FILES.items():
            self.assertEqual(self.installed(path), data, path)
        self.assertEqual(self.run_script("verify").returncode, 0)

    def test_a_warm_cache_works_offline(self):
        self.assertEqual(self.run_script("fetch").returncode, 0)
        shutil.rmtree(self.install)
        r = self.run_script("fetch", url="file:///nowhere/at/all.zip")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.installed("monsters/Snail.glb"), FILES["monsters/Snail.glb"])

    def test_an_up_to_date_install_is_left_untouched(self):
        self.assertEqual(self.run_script("fetch").returncode, 0)
        target = os.path.join(self.install, "monsters", "Snail.glb")
        os.utime(target, (1_000_000_000, 1_000_000_000))
        r = self.run_script("fetch", url="file:///nowhere/at/all.zip")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(os.path.getmtime(target), 1_000_000_000)

    def test_a_corrupted_installed_file_fails_verify_and_fetch_restores_it(self):
        self.assertEqual(self.run_script("fetch").returncode, 0)
        with open(os.path.join(self.install, "characters", "glb", "Heena.glb"), "r+b") as f:
            f.write(b"X")
        r = self.run_script("verify")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("characters/glb/Heena.glb", r.stdout + r.stderr)
        self.assertEqual(self.run_script("fetch").returncode, 0)
        self.assertEqual(self.installed("characters/glb/Heena.glb"), FILES["characters/glb/Heena.glb"])

    def test_extra_files_fail_verify_but_godot_import_files_do_not(self):
        self.assertEqual(self.run_script("fetch").returncode, 0)
        with open(os.path.join(self.install, "monsters", "Snail.glb.import"), "w") as f:
            f.write("[remap]\n")
        self.assertEqual(self.run_script("verify").returncode, 0)
        with open(os.path.join(self.install, "monsters", "Stray.glb"), "wb") as f:
            f.write(b"stray")
        r = self.run_script("verify")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("monsters/Stray.glb", r.stdout + r.stderr)
        self.assertEqual(self.run_script("fetch").returncode, 0)
        self.assertFalse(os.path.exists(os.path.join(self.install, "monsters", "Stray.glb")))
        self.assertTrue(os.path.exists(os.path.join(self.install, "monsters", "Snail.glb.import")))

    def test_a_download_with_the_wrong_checksum_fails_and_installs_nothing(self):
        with open(self.zip_path, "wb") as f:
            f.write(zip_bytes(dict(FILES, **{"monsters/Snail.glb": b"tampered"})))
        r = self.run_script("fetch")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("SHA-256", r.stdout + r.stderr)
        self.assertFalse(os.path.exists(self.install))

    def test_a_corrupted_cache_without_network_fails(self):
        self.assertEqual(self.run_script("fetch").returncode, 0)
        shutil.rmtree(self.install)
        cached = [os.path.join(d, f) for d, _, fs in os.walk(self.cache) for f in fs if f.endswith(".zip")]
        self.assertEqual(len(cached), 1)
        with open(cached[0], "r+b") as f:
            f.seek(10)
            f.write(b"\xff\xff")
        r = self.run_script("fetch", url="file:///nowhere/at/all.zip")
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(os.path.exists(self.install))

    def test_an_asset_that_disagrees_with_the_checksum_manifest_fails(self):
        self.write_tsv(dict(FILES, **{"monsters/Snail.glb": b"something else"}))
        r = self.run_script("fetch")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("monsters/Snail.glb", r.stdout + r.stderr)

    def test_verify_without_a_pack_says_so(self):
        r = self.run_script("verify")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("no art pack", r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
