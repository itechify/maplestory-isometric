"""Terrain-scale assets: chunky conical peaks (classic world-map mountains) and clouds."""

import math

from mathutils import Vector, noise

from .. import core
from ..geo import MeshBuilder
from . import asset


def _peak(coll, name, seed, height=1.6, lumps=0.12, segments=28, rings=10, tip=0.12, mat="M_Mountain",
          ledge=True):
    """Unit-radius stylized peak; instances are scaled to 10-30 m radius."""
    mb = MeshBuilder()
    bm = mb.bm
    mi = mb.mat(mat)
    off = Vector((seed * 1.7, seed * 2.3, seed * 0.9))
    rows = []
    for j in range(rings + 1):
        t = j / rings
        # concave-ish profile: broad base, steeper middle, rounded tip
        r = (1.0 - t) ** 1.15 * (1 - tip) + tip * (1 - t)
        z = height * (t ** 0.9)
        row = []
        for i in range(segments):
            a = 2 * math.pi * i / segments
            p = Vector((math.cos(a) * r, math.sin(a) * r, z))
            d = noise.noise(p * 2.2 + off) * lumps * (0.4 + r)
            p.x += math.cos(a) * d
            p.y += math.sin(a) * d
            if ledge and 0.3 < t < 0.45:  # a soft rocky ledge band
                p.x *= 1.04
                p.y *= 1.04
            row.append(bm.verts.new(p))
        rows.append(row)
    for j in range(rings):
        for i in range(segments):
            f = bm.faces.new((rows[j][i], rows[j][(i + 1) % segments], rows[j + 1][(i + 1) % segments],
                              rows[j + 1][i]))
            f.material_index = mi
    top = bm.verts.new((0, 0, height + 0.04))
    for i in range(segments):
        f = bm.faces.new((rows[-1][i], rows[-1][(i + 1) % segments], top))
        f.material_index = mi
    mb.build(name, coll, smooth=True, sharp_angle=70)


@asset("Mountain_Peak_A", "Terrain", footprint=2.0, tags=("mountain",), outline=0.025)
def mountain_a(coll):
    _peak(coll, "Mountain_Peak_A", 1)


@asset("Mountain_Peak_B", "Terrain", footprint=2.0, tags=("mountain",), outline=0.025)
def mountain_b(coll):
    _peak(coll, "Mountain_Peak_B", 2, height=2.1, lumps=0.16, tip=0.08)


@asset("Mountain_Peak_C", "Terrain", footprint=2.0, tags=("mountain",), outline=0.025)
def mountain_c(coll):
    """Low rounded grassy peak (ground grass tint, M_Hill) for the island's filler hills."""
    _peak(coll, "Mountain_Peak_C", 3, height=1.2, lumps=0.1, tip=0.2, ledge=False, mat="M_Hill")


@asset("Mountain_Peak_Rocky", "Terrain", footprint=2.0, tags=("mountain",), outline=0.025)
def mountain_rocky(coll):
    """Tall peak with a bare rocky crown (the cloud-ringed peaks of the world map)."""
    _peak(coll, "Mountain_Peak_Rocky", 4, height=2.1, lumps=0.15, tip=0.07, mat="M_Mountain_Rocky")


@asset("Mountain_Hill", "Terrain", footprint=2.0, tags=("mountain",), outline=0.02)
def mountain_hill(coll):
    """Low rounded green hill (ground grass tint, M_Hill)."""
    _peak(coll, "Mountain_Hill", 5, height=0.8, lumps=0.08, tip=0.35, ledge=False, mat="M_Hill")


@asset("Mountain_Mesa_A", "Terrain", footprint=2.0, tags=("mountain",), outline=0.02)
def mountain_mesa(coll):
    """Flat-topped rock outcrop (waterfall source)."""
    mb = MeshBuilder()
    mb.cyl(1.0, 1.0, mat="M_Dirt_Cliff", verts=18, r2=0.82)
    mb.dome(0.84, 0.18, loc=(0, 0, 1.0), mat="M_Grass", u=18, v=3, underside=False)
    mb.build("Mountain_Mesa_A", coll, smooth=True, sharp_angle=40)


def _cloud(coll, name, seed, puffs=7, spread=1.6):
    """Soft cumulus: 5-7 round puffs around a big core, all smooth-shaded with no sharp edges.

    bmesh icosphere subdivisions count from the bare icosahedron (1 = 20 faces), so the puffs use 2 (80 faces)
    and the core 3 (320 faces): about 900 triangles per cloud. The clouds are instanced (one mesh per variant),
    so the soft look costs almost nothing; subdiv 1 read as faceted white boulders at 6-30 m instance scales.
    """
    r = core.rng(name, seed)
    mb = MeshBuilder()
    puffs = max(5, min(7, puffs))
    for k in range(puffs):
        a = 2 * math.pi * k / puffs + r.uniform(-0.3, 0.3)
        d = spread * r.uniform(0.35, 1.0)
        rad = r.uniform(0.65, 1.1)
        mb.sphere(rad, loc=(math.cos(a) * d, math.sin(a) * d * 0.6, r.uniform(-0.1, 0.4)), scale=(1.2, 1.0, 0.8),
                  mat="M_Cloud", subdiv=2, lumpy=0.04, seed=seed + k, flatten_bottom=0.35)
    mb.sphere(1.3, loc=(0, 0, 0.35), scale=(1.3, 1.0, 0.85), mat="M_Cloud", subdiv=3, flatten_bottom=0.35)
    ob = mb.build(name, coll, smooth=True, sharp_angle=180)
    ob.visible_shadow = False  # clouds should not blot the sea / island with shadows


@asset("Cloud_Puff_A", "Terrain", footprint=4.0, tags=("cloud",), outline=0.0)
def cloud_a(coll):
    """Soft round cumulus (7 smooth puffs on a core); instanced at 2-30 m scales for mist, collars, sea, sky."""
    _cloud(coll, "Cloud_Puff_A", 1)


@asset("Cloud_Puff_B", "Terrain", footprint=4.0, tags=("cloud",), outline=0.0)
def cloud_b(coll):
    """Wider, flatter cloud bank (7 puffs over a longer spread)."""
    _cloud(coll, "Cloud_Puff_B", 2, puffs=7, spread=2.2)
