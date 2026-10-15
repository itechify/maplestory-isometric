"""Package Jarvis's art-pack delivery ZIPs into the pinned release asset (ADR 0002, docs/adr/0002-pinned-art-pack.md).

    PY="/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"   # Linux: PY=python3; or: py
    "$PY" -I tools/art_pack/build_release.py --tag art-pack-v1.1 --out-dir <new empty dir outside the repo> <zips...>

The ZIPs are one complete, non-conflicting delivery: Jarvis's part ZIPs, or a single ZIP of a source copy a correction
patch was merged into (v1.1). Never pass a full delivery and a patch together: a path whose bytes differ between ZIPs
is refused. The delivery is untrusted data: this script only reads the ZIPs' bytes (it never extracts to disk and never runs any of
the pack's code), so run it with -I, from outside the pack. It writes into --out-dir:

    MisoStory_Art_Pack_<version>.zip   the release asset (upload with gh release create/upload)
    <tag>.files.tsv                    path<TAB>bytes<TAB>sha256 per file: commit it as tools/art_pack/<tag>.files.tsv

What goes in (the pack's runtime subset): every .glb, the icons (icons/** and monsters/icons/*), every .json (the
asset index, manifests, mapping, Godot validation and the audits) and the .md docs, at their delivered paths. The
generator source (.py/.gd/.sh/.bat) is kept as a not-run reference under reference/, which holds a .gdignore so Godot
never parses it. Left out: .blend files, galleries, contact sheets, previews and renders (every other .png and .jpg),
godot_demo/ and the extraction README. PACKAGING.json in the asset records the source ZIPs, every rename and what was
left out. The output is deterministic: the same ZIPs give the same bytes.
"""

import argparse
import hashlib
import json
import os
import posixpath
import sys
import zipfile

PACK_ROOT = "MisoStory_Asset_Pack/"
REFERENCE_DIR = "reference/"
CODE_EXTENSIONS = (".py", ".gd", ".sh", ".bat")
FIXED_TIME = (2026, 10, 13, 0, 0, 0)

# Paths renamed by our packaging: {old: (new, reason)}; every JSON naming the old path is rewritten. Empty since v1.1:
# art-pack-v1.0 renamed environment/glb/bed.glb to bed_single.glb (it collided with Bed.glb on case-insensitive file
# systems), and Jarvis's v1.1 correction ships it under that name.
RENAMES = {}


class PackagingError(Exception):
    pass


def _sha(data):
    return hashlib.sha256(data).hexdigest()


def _pack_path(member):
    """The pack-relative path of a ZIP member, None when it lies outside the pack folder. Refuses escaping paths."""
    name = member.replace("\\", "/")
    if not name.startswith(PACK_ROOT):
        if name.startswith("/") or ".." in name.split("/"):
            raise PackagingError("unsafe member path: %r" % member)
        return None
    rel = name[len(PACK_ROOT):]
    if rel.startswith("/") or ".." in rel.split("/") or posixpath.normpath(rel) != rel or ":" in rel:
        raise PackagingError("unsafe member path: %r" % member)
    return rel


def classify(path):
    """'keep', 'reference' or None (left out) for one pack-relative path."""
    if path.startswith("godot_demo/"):
        return None
    ext = posixpath.splitext(path)[1].lower()
    if ext in (".glb", ".json", ".md"):
        return "keep"
    if ext in CODE_EXTENSIONS:
        return "reference"
    if ext == ".png" and path.startswith(("icons/", "monsters/icons/")):
        return "keep"
    return None


def _rewrite_json(text, renames):
    """Every quoted path naming a renamed file (full pack path or any trailing part of it) now names the new file."""
    out = text
    for old, new in renames:
        old_parts, new_parts = old.split("/"), new.split("/")
        for k in range(len(old_parts)):
            out = out.replace('"%s"' % "/".join(old_parts[k:]), '"%s"' % "/".join(new_parts[k:]))
    return out


def build(zip_paths, out_path, tag, renames=None):
    """Package the delivery ZIPs into out_path. Returns {path, bytes, sha256, files: [{path, bytes, sha256}]}.
    renames defaults to RENAMES."""
    renames = RENAMES if renames is None else renames
    files = {}
    left_out = set()
    sources = []
    for zp in zip_paths:
        with open(zp, "rb") as f:
            raw = f.read()
        sources.append({"name": os.path.basename(zp), "bytes": len(raw), "sha256": _sha(raw)})
        with zipfile.ZipFile(zp) as z:
            for info in z.infolist():
                if info.is_dir():
                    continue
                rel = _pack_path(info.filename)
                kind = classify(rel) if rel is not None else None
                if kind is None:
                    left_out.add(rel if rel is not None else info.filename)
                    continue
                data = z.read(info)
                if rel in files and files[rel] != data:
                    raise PackagingError("%s differs between delivery parts" % rel)
                files[rel] = data

    renamed = []
    for old, (new, reason) in sorted(renames.items()):
        if old not in files:
            continue
        if new in files:
            raise PackagingError("rename target %s already exists" % new)
        data = files.pop(old)
        renamed.append({"from": old, "to": new, "bytes": len(data), "sha256": _sha(data), "json_rewritten": [],
                        "reason": reason})
        files[new] = data
    pairs = [(r["from"], r["to"]) for r in renamed]
    for path in sorted(files):
        if not path.endswith(".json") or not pairs:
            continue
        text = files[path].decode("utf-8")
        for r in renamed:
            new_text = _rewrite_json(text, [(r["from"], r["to"])])
            if new_text != text:
                json.loads(new_text)
                r["json_rewritten"].append(path)
                text = new_text
        files[path] = text.encode("utf-8")

    out_files = {}
    for path, data in files.items():
        kind = classify(path)
        out_files[(REFERENCE_DIR + path) if kind == "reference" else path] = data
    out_files[REFERENCE_DIR + ".gdignore"] = b""
    record = {
        "format": 1,
        "tag": tag,
        "built_by": "tools/art_pack/build_release.py",
        "pack": "Jarvis's MisoStory 3D asset pack (Project art: made procedurally in Blender 4.3.2 by the owner's "
                "ChatGPT agent Jarvis); see docs/adr/0002-pinned-art-pack.md",
        "source_zips": sources,
        "renamed": renamed,
        "rules": {
            "kept": "every .glb, .json and .md at its delivered path; .png under icons/ and monsters/icons/",
            "reference": "generator source (%s) under %s, which a .gdignore hides from Godot; never run"
                         % (", ".join(CODE_EXTENSIONS), REFERENCE_DIR),
            "left_out": ".blend files, godot_demo/, galleries, contact sheets, previews and renders (other .png, "
                        ".jpg), files outside MisoStory_Asset_Pack/",
        },
        "left_out": sorted(left_out),
    }
    out_files["PACKAGING.json"] = (json.dumps(record, indent=2) + "\n").encode("utf-8")

    lowered = {}
    for path in out_files:
        if path.lower() in lowered:
            raise PackagingError("%s and %s differ only in case" % (lowered[path.lower()], path))
        lowered[path.lower()] = path

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path in sorted(out_files):
            info = zipfile.ZipInfo(path, date_time=FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o644 << 16
            z.writestr(info, out_files[path])
    with open(out_path, "rb") as f:
        raw = f.read()
    rows = [{"path": p, "bytes": len(out_files[p]), "sha256": _sha(out_files[p])} for p in sorted(out_files)]
    return {"path": out_path, "bytes": len(raw), "sha256": _sha(raw), "files": rows}


def checksums_tsv(rows):
    return "".join("%s\t%d\t%s\n" % (r["path"], r["bytes"], r["sha256"]) for r in sorted(rows, key=lambda r: r["path"]))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--tag", required=True, help="the release tag, art-pack-v<major>.<minor>")
    ap.add_argument("--out-dir", required=True, help="a new, empty directory outside the repo")
    ap.add_argument("zips", nargs="+", help="the delivery's part ZIPs")
    a = ap.parse_args(argv)
    version = a.tag[len("art-pack-"):] if a.tag.startswith("art-pack-") else a.tag
    out = os.path.join(a.out_dir, "MisoStory_Art_Pack_%s.zip" % version)
    result = build(sorted(a.zips, key=os.path.basename), out, a.tag)
    tsv = os.path.join(a.out_dir, "%s.files.tsv" % a.tag)
    with open(tsv, "w", newline="\n") as f:
        f.write(checksums_tsv(result["files"]))
    glbs = sum(1 for r in result["files"] if r["path"].endswith(".glb"))
    print(json.dumps({"asset": out, "bytes": result["bytes"], "sha256": result["sha256"], "files": len(result["files"]),
                      "glb": glbs, "checksums": tsv}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
