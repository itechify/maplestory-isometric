"""Refresh the small README images in docs/images/ from the full renders in renders/final/.

blender -b --factory-startup --python scripts/readme_images.py

Each pick is scaled to 1600 px wide and saved as a quality-82 JPEG (about 0.2-0.3 MB) with the Standard view
transform, so colours match the renders. Run it after `scripts/render_all.sh final ...` when the look changes
noticeably, then commit docs/images/ (see CONTRIBUTING.md).
"""

import os

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# render (renders/final/<name>.png) -> docs/images/<file>.jpg
PICKS = {
    "Island_Overview": "island_overview",
    "Island_Hero": "island_hero",
    "Region_MushroomTownArea": "mushroom_town",
    "Amherst_1010000_Gameplay": "amherst",
    "Southperry_60000_Gameplay": "southperry",
    "SnailHuntingGround2_40001_Gameplay": "snail_hunting_ground",
}
WIDTH = 1600

scene = bpy.context.scene
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = 0.0
scene.view_settings.gamma = 1.0
scene.render.image_settings.file_format = "JPEG"
scene.render.image_settings.quality = 82
os.makedirs(os.path.join(ROOT, "docs", "images"), exist_ok=True)
for src, dst in PICKS.items():
    path = os.path.join(ROOT, "renders", "final", src + ".png")
    if not os.path.exists(path):
        print("README_IMAGE_MISSING", path)
        continue
    img = bpy.data.images.load(path)
    w, h = img.size
    if w > WIDTH:
        img.scale(WIDTH, int(h * WIDTH / w))
    out = os.path.join(ROOT, "docs", "images", dst + ".jpg")
    img.save_render(out, scene=scene)
    print("README_IMAGE", out, os.path.getsize(out) // 1024, "KB")
