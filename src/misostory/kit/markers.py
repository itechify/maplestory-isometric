"""Gameplay markers: portals, spawn rings, NPC beacons, route arrows."""

import math

from .. import core
from ..geo import MeshBuilder
from . import asset
from .art_pack import kit_materials

# Built from the pinned art pack (kit/art_pack.py, docs/AUTHORING.md section 9); pack= are the per-asset exceptions.


# pack (portal.glb): a beaded arch on two pedestals over rune rings, with no glow; the arch and the rings get the kit
# portal materials back, so exits glow as before. The open arch reads thinner than the kit's filled vortex in the map
# renders, so it is x1.2 (2.5 m wide, 2.65 m tall; the kit portal was 2.9 m tall)
@asset("Portal_Swirl", "Markers", footprint=1.6, tags=("portal",),
       pack=dict(parts={"Ring": ["Portal luminous rim"], "Core": ["Arrival rune ring"]}, scale_mul=1.2,
                 post=kit_materials(Ring="M_Portal_Ring", Core="M_Portal_Core")))
def portal_swirl(coll):
    """Classic MapleStory portal: a tall glowing blue-white vortex standing on a ring."""
    mb = MeshBuilder()
    # glowing oval core (vertical, faces -Y and +Y)
    mb.uvsphere(0.75, loc=(0, 0, 1.3), scale=(0.95, 0.18, 1.45), mat="M_Portal_Core", u=20, v=10)
    for k, (tilt, sc) in enumerate(((0, 1.0), (18, 0.86), (-14, 0.72))):
        mb.torus(0.85 * sc, 0.06, loc=(0, 0, 1.3), rot=(90, tilt, k * 25), scale=(1.0, 1.6, 1.0),
                 mat="M_Portal_Ring", u=24, v=5)
    mb.torus(0.95, 0.07, loc=(0, 0, 0.04), mat="M_Portal_Ring", u=24, v=5)
    mb.cyl(0.95, 0.03, loc=(0, 0, 0.0), mat="M_Portal_Core", verts=24)
    r = core.rng("portal", 1)
    for k in range(9):
        a = r.uniform(0, 2 * math.pi)
        rad = r.uniform(0.6, 1.1)
        mb.sphere(0.06, loc=(math.cos(a) * rad, math.sin(a) * rad * 0.4, r.uniform(0.3, 2.6)),
                  mat="M_Portal_Ring", subdiv=1)
    mb.build("Portal_Swirl", coll, smooth=True, sharp_angle=60)


# pack: a threshold rune between two light bars, and a chevron, with no glow; they get the kit portal materials back
@asset("Portal_Door", "Markers", footprint=1.2, tags=("portal",),
       pack=dict(parts={"Core": ["Door threshold rune"], "Ring": ["Door marker"]},
                 post=kit_materials(Ring="M_Portal_Ring", Core="M_Portal_Core")))
def portal_door(coll):
    """Door portal: glowing threshold disc and ring, a 1.6 m light column fading to clear, chevrons at ~2.4 m."""
    mb = MeshBuilder()
    mb.cyl(0.66, 0.03, mat="M_Portal_Core", verts=28)
    mb.torus(0.66, 0.05, loc=(0, 0, 0.035), mat="M_Portal_Ring", u=28, v=4)
    mb.torus(0.4, 0.035, loc=(0, 0, 0.035), mat="M_Portal_Ring", u=20, v=4)
    for k in range(2):
        z = 2.35 + k * 0.28
        mb.prism([(-0.36, 0.0), (0.0, -0.25), (0.36, 0.0), (0.36, 0.11), (0.0, -0.14), (-0.36, 0.11)], -0.045,
                 0.045, loc=(0, 0, z), rot=(90, 0, 0), mat="M_Portal_Ring")
    mb.build("Portal_Door", coll, smooth=True)
    # light column: an open, slightly tapered tube in an emissive material that fades out toward the top, so the
    # entry reads from the map cameras like the edge portals' beams while the door stays visible through it
    glow = MeshBuilder()
    glow.cyl(0.62, 1.6, loc=(0, 0, 0.02), mat="M_Portal_Glow", verts=28, r2=0.5, cap=False)
    gob = glow.build("Portal_Door_Glow", coll, smooth=True, sharp_angle=180, recalc_normals=False)
    gob.visible_shadow = False


@asset("Portal_Arrival", "Markers", footprint=1.6, tags=("portal",))
def portal_arrival(coll):
    """Arrival-only point (classic one-way links): a soft glowing ground ring and a little welcome post."""
    mb = MeshBuilder()
    mb.torus(0.95, 0.06, loc=(0, 0, 0.04), mat="M_Portal_Ring", u=28, v=4)
    mb.torus(0.6, 0.04, loc=(0, 0, 0.04), mat="M_Portal_Core", u=24, v=4)
    mb.cyl(0.95, 0.015, mat="M_Portal_Core", verts=28)
    mb.box((0.12, 0.12, 1.5), loc=(1.25, 0.25, 0.75), mat="M_Wood")
    mb.box((0.9, 0.08, 0.45), loc=(1.25, 0.18, 1.35), mat="M_Plank", bevel=0.03, segs=1)
    mb.sphere(0.1, loc=(1.25, 0.12, 1.35), mat="M_Glow_portal_core", subdiv=1)
    mb.build("Portal_Arrival", coll, smooth=True, sharp_angle=40)


@asset("Spawn_Ring", "Markers", footprint=1.0, tags=("debug",))
def spawn_ring(coll):
    mb = MeshBuilder()
    mb.torus(0.5, 0.04, loc=(0, 0, 0.05), mat="M_Marker_Spawn", u=16, v=4)
    mb.build("Spawn_Ring", coll, smooth=True)


# pack: the diamond stands on z = 0; the kit diamond is centred on its origin (placed 2 m above the NPC)
@asset("NPC_Beacon", "Markers", footprint=0.4, tags=("debug",), pack=dict(fit="z", anchor_z="kit_bottom"))
def npc_beacon(coll):
    """Floating yellow diamond that hovers over NPC proxies."""
    mb = MeshBuilder()
    mb.cyl(0.22, 0.3, loc=(0, 0, 0.0), mat="M_Marker_NPC", verts=4, r2=0.0)
    mb.cyl(0.22, 0.3, loc=(0, 0, 0.0), rot=(180, 0, 0), mat="M_Marker_NPC", verts=4, r2=0.0)
    mb.build("NPC_Beacon", coll, smooth=False)


@asset("Route_Arrow", "Markers", footprint=0.6, tags=("debug",))
def route_arrow(coll):
    mb = MeshBuilder()
    mb.prism([(-0.3, -0.12), (0.1, -0.12), (0.1, -0.28), (0.4, 0.0), (0.1, 0.28), (0.1, 0.12), (-0.3, 0.12)],
             0.0, 0.05, mat="M_Marker_Route")
    mb.build("Route_Arrow", coll, smooth=False)
