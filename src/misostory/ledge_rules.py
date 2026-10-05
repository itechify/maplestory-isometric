"""The one-way ledge invariant (docs/runtime/MAP_ARCHITECTURE.md section 4.4), without bpy.

A one-way trail ends in a drop-down ledge whose face lies on the arrival map's gate plane. It must be higher than
anything a player can climb back up (the jump apex at the Jump cap + one walking step + a margin) and no higher than
a one-way drop. traversal.py (Blender build and validate.py) and sidecar_diff.py (the staging check, plain Python)
both read the bounds from here, so the build, the validator and the export gate cannot disagree.

The jump apex is not a constant here: it comes from the game data (the controller's adaptation table
game/data/misostory/movement.json `jump_apex_m_at_cap`, or else canonical formulas/movement.json height_px at
jump_cap x world_scale.json vertical_px_to_m), so a change of movement feel or world scale moves the bound.
"""

import json
import os

LEDGE_MARGIN_M = 0.30   # MAP_ARCHITECTURE 4.4: jump_apex_m_at_cap + step_up_m + 0.30 <= height
LEDGE_FACE_TOL_M = 0.10  # the face lies on the arrival gate plane within this
MAX_DROP_M = 2.6        # Iteration One's one-way drop cap (AUTHORING.md; traversal.MAX_DROP)
STEP_M = 0.45           # Iteration One's walking step (traversal.MAX_STEP), used when movement.json has none


def ledge_bounds(root, max_drop=MAX_DROP_M, max_step=STEP_M):
    """(min_height, max_height, detail) of the one-way ledge invariant, from the game data under root (the repo).

    jump apex at the cap: game/data/misostory/movement.json `jump_apex_m_at_cap` when present, else canonical
    formulas/movement.json (height_px at jump_cap) x world_scale.json vertical_px_to_m. Step-up: movement.json
    `step_up_m` when present, else max_step."""
    data = os.path.join(root, "game", "data")
    apex = step = None
    src = []
    adapt = os.path.join(data, "misostory", "movement.json")
    if os.path.exists(adapt):
        with open(adapt, encoding="utf-8") as f:
            mv = json.load(f)
        apex = mv.get("jump_apex_m_at_cap")
        step = mv.get("step_up_m")
        if apex is not None:
            src.append(f"jump_apex_m_at_cap {apex} (misostory/movement.json)")
        if step is not None:
            src.append(f"step_up_m {step} (misostory/movement.json)")
    if apex is None:
        with open(os.path.join(data, "canonical", "formulas", "movement.json"), encoding="utf-8") as f:
            canon = json.load(f)
        with open(os.path.join(data, "misostory", "world_scale.json"), encoding="utf-8") as f:
            scale = json.load(f)
        cap = canon["jump_cap"]
        px = next(r["height_px"] for r in canon["jump_height_px_by_jump"] if r["jump"] == cap)
        apex = px * float(scale["vertical_px_to_m"])
        src.append(f"jump apex {px} px at Jump {cap} (canonical) x {scale['vertical_px_to_m']} m/px = {apex:.3f} m "
                   f"(no misostory/movement.json jump_apex_m_at_cap yet)")
    if step is None:
        step = max_step
        src.append(f"step_up {max_step} m (traversal.MAX_STEP; no misostory/movement.json step_up_m yet)")
    lo = float(apex) + float(step) + LEDGE_MARGIN_M
    return lo, float(max_drop), "; ".join(src) + f"; margin {LEDGE_MARGIN_M} m; cap {max_drop} m (traversal.MAX_DROP)"
