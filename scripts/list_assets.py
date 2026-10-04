"""Print the asset kit catalog (markdown).  blender -b --factory-startup --python scripts/list_assets.py"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))

from misostory import kit  # noqa: E402
from misostory.kit.creatures import MOB_ASSETS  # noqa: E402

cats = {}
for name, info in kit.REGISTRY.items():
    cats.setdefault(info["category"], []).append((name, info))
lines = ["| Category | Asset | footprint (m) | tags | doc |", "|---|---|---|---|---|"]
for cat in sorted(cats):
    for name, info in sorted(cats[cat]):
        doc = (info["fn"].__doc__ or "").strip().split("\n")[0]
        lines.append(f"| {cat} | `{name}` | {info['footprint']} | {', '.join(info['tags'])} | {doc} |")
lines.append("")
lines.append("Monster names for `m.mobs(name, ...)`: " + ", ".join(f"`{k}`" for k in MOB_ASSETS))
out = "\n".join(lines)
print("ASSET_CATALOG_BEGIN")
print(out)
print("ASSET_CATALOG_END")
