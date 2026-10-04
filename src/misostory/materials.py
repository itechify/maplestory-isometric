"""Stylized, hand-painted-looking materials.

Every material computes an *albedo* with simple procedural painting (two-tone noise,
top/side tinting, vertical gradients, cobble/strata patterns) and feeds it into one
shared node group ``MS_Shading``. Changing that single group re-styles the whole
island (soft principled vs. painterly cel ramp), which keeps the look consistent.

No image textures, no PBR detail maps: large readable color areas only.
"""

import bpy

# ---------------------------------------------------------------------------
# Palette (sRGB hex). Saturated but harmonious, early-MapleStory inspired.
# ---------------------------------------------------------------------------

PALETTE = {
    # terrain
    "grass_top": "#86D64A", "grass_top_lt": "#A8E35E", "grass_side": "#4E9F2E", "grass_dark": "#3C8226",
    "dirt": "#8E6A3A", "dirt_dk": "#5F4423", "dirt_lt": "#A98048",
    "path_dirt": "#D6B27A", "path_dirt_dk": "#B98E57",
    "cobble_a": "#B9C4D8", "cobble_b": "#97A4BE", "cobble_c": "#CDBB97", "cobble_mortar": "#5C6274",
    "sand_a": "#EBDDBE", "sand_b": "#D8C59D", "sand_mortar": "#9A8A6A", "beach": "#F2E2B4",
    "rock": "#9EA3AE", "rock_dk": "#6E7380", "rock_moss": "#7FAE4A",
    # wood / architecture
    "wood": "#A56D3B", "wood_dk": "#6C4424", "wood_lt": "#C99560", "plank": "#B9824B",
    "plaster": "#F4E9D2", "plaster_dk": "#DCCBA8", "stone_wall": "#C9C2B4",
    "whitewash": "#FFFAF1", "whitewash_dk": "#F0E9DC",  # painted near-white (Southperry houses)
    "roof_orange": "#F27A2B", "roof_red": "#DA4430", "roof_blue": "#4A7FD8", "roof_green": "#5CB548",
    "roof_purple": "#9A6BD0", "roof_yellow": "#F2C531", "roof_teal": "#3DB5A6",
    "window": "#FFE9A8", "window_frame": "#6C4424", "door": "#8A5530",
    "metal": "#7D8794", "gold": "#E8B93A", "cloth_white": "#F7F2E6", "cloth_red": "#D8443A",
    "rope": "#A9814A",
    # nature
    "leaf": "#58B83C", "leaf_dk": "#2F7D2A", "leaf_lt": "#8ED85A",
    "leaf_b": "#3FA45B", "leaf_b_dk": "#24704A", "leaf_b_lt": "#78D07A",
    "leaf_yellow": "#F5D547", "leaf_yellow_dk": "#D69A25",
    "leaf_autumn": "#F0A030", "leaf_autumn_dk": "#C4601E",
    "bark": "#8A5A32", "bark_dk": "#5B3A1F",
    "mush_stem": "#F3E5C6", "mush_stem_dk": "#D9C49A",
    "mush_orange": "#F37B26", "mush_red": "#E0412F", "mush_blue": "#5A8CE0", "mush_yellow": "#F5C83A",
    "mush_green": "#7CC34A", "mush_spot": "#FFF8E6",
    "flower_pink": "#F58BB8", "flower_yellow": "#FFD447", "flower_white": "#FFFFFF", "flower_red": "#F0503C",
    "flower_purple": "#B07FE0", "flower_blue": "#6FA8F5",
    "tomato": "#E8402E", "tomato_leaf": "#4FA53A",
    # water & sky
    "mountain_dk": "#5E7F35", "mountain_lt": "#A9C25E", "cloud": "#FFFFFF", "cloud_dk": "#D5E3F2",
    "rock_under": "#B3A27A", "rock_under_dk": "#8E7F5E", "rock_under_lt": "#D2C29A", "sea": "#6AA8E8",
    "sea_dk": "#4A86D2",
    "water": "#3BA6E3", "water_shallow": "#6FD9E3", "water_dk": "#1F6FBF", "water_lt": "#9BE0F7", "foam": "#F2FBFF",
    "sky_top": "#6EC3FF", "sky_horizon": "#D9F2FF",
    # creatures (from classic sprite references)
    "snail_slug": "#ECE6F5", "snail_slug_dk": "#B8B0DC", "snail_teal": "#2E9E8F", "snail_teal_dk": "#1C6A61",
    "snail_teal_lt": "#7ED8C4", "blob_cream": "#F7DEB6", "blob_cream_dk": "#E3B98A", "lid_tan": "#C6955C",
    "shroom_cap": "#E2552B", "shroom_spot": "#F7B48A", "shroom_stem": "#E9CDA2",
    "om_cap": "#F58A1F", "om_cap_dk": "#D2600F", "om_spot": "#FFD23F", "om_body": "#FFF5E6", "om_gill": "#A8968A",
    "cheek_pink": "#F59AA0", "mouth_red": "#C7333B",
    "snail_body": "#9FCF6A", "snail_shell": "#C9873E", "snail_shell_dk": "#8F5523",
    "bsnail_body": "#9FCF6A", "bsnail_shell": "#4E7FD9", "bsnail_shell_dk": "#2E4FA0",
    "rsnail_body": "#9FCF6A", "rsnail_shell": "#E0442F", "rsnail_shell_dk": "#962318",
    "omush_cap": "#F68A26", "omush_cap_dk": "#C85A12", "omush_body": "#F6E2B8",
    "spore_cap": "#D96B30", "slime": "#62C6F0", "stump": "#A8743F",
    "eye_black": "#1E1A1A", "eye_white": "#FFFFFF", "skin": "#FFD9B8", "hair_brown": "#7A4A28",
    "hair_black": "#2D2626", "hair_blonde": "#F2CF6B",
    # gameplay markers
    "portal_core": "#3FB6FF", "portal_ring": "#BFF1FF", "marker_spawn": "#FF6A3D",
    "marker_npc": "#FFD23F", "marker_route": "#FF3DB8", "player_blue": "#3D7BFF",
}


def hex_to_linear(hx, alpha=1.0):
    hx = hx.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(hx[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], alpha)


def col(name_or_hex):
    hx = PALETTE.get(name_or_hex, name_or_hex)
    return hex_to_linear(hx)


# ---------------------------------------------------------------------------
# Shared shading group
# ---------------------------------------------------------------------------

STYLE = {
    # "cel": painterly soft-banded diffuse (Shader to RGB ramp) - default look
    # "soft": plain principled diffuse (fallback / comparison)
    "mode": "soft",
    "shadow_tint": "#6B6FB8",   # cool violet-blue shadow tint, painterly
    "shadow_level": 0.50,
    "mid_level": 0.86,
    "light_level": 1.06,
}

SHADING_GROUP = "MS_Shading"


def build_shading_group(force=False):
    ng = bpy.data.node_groups.get(SHADING_GROUP)
    if ng is not None and not force:
        return ng
    if ng is None:
        ng = bpy.data.node_groups.new(SHADING_GROUP, "ShaderNodeTree")
    ng.nodes.clear()
    ng.interface.clear()
    ng.interface.new_socket("Albedo", in_out="INPUT", socket_type="NodeSocketColor")
    ng.interface.new_socket("Emission", in_out="INPUT", socket_type="NodeSocketFloat")
    ng.interface.new_socket("Gloss", in_out="INPUT", socket_type="NodeSocketFloat")
    ng.interface.new_socket("Shader", in_out="OUTPUT", socket_type="NodeSocketShader")
    n = ng.nodes
    l = ng.links
    gi = n.new("NodeGroupInput")
    go = n.new("NodeGroupOutput")
    if STYLE["mode"] == "soft":
        p = n.new("ShaderNodeBsdfPrincipled")
        p.inputs["Roughness"].default_value = 0.75
        p.inputs["Specular IOR Level"].default_value = 0.2
        l.new(gi.outputs["Gloss"], p.inputs["Coat Weight"])
        l.new(gi.outputs["Albedo"], p.inputs["Base Color"])
        l.new(gi.outputs["Albedo"], p.inputs["Emission Color"])
        l.new(gi.outputs["Emission"], p.inputs["Emission Strength"])
        l.new(p.outputs[0], go.inputs["Shader"])
        return ng
    # --- cel / painterly ---
    diff = n.new("ShaderNodeBsdfDiffuse")
    diff.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = n.new("ShaderNodeShaderToRGB")
    l.new(diff.outputs[0], s2r.inputs[0])
    bw = n.new("ShaderNodeRGBToBW")
    l.new(s2r.outputs["Color"], bw.inputs[0])
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "EASE"
    els = ramp.color_ramp.elements
    st = hex_to_linear(STYLE["shadow_tint"])
    sl, ml, ll = STYLE["shadow_level"], STYLE["mid_level"], STYLE["light_level"]
    els[0].position = 0.05
    els[0].color = (st[0] * 0.0 + sl * 0.82, sl * 0.84, sl * 1.0 + 0.05, 1)  # cool shadow
    els[1].position = 0.55
    els[1].color = (ll, ll * 0.99, ll * 0.95, 1)  # warm light
    mid = els.new(0.30)
    mid.color = (ml * 0.97, ml * 0.96, ml * 1.0, 1)
    l.new(bw.outputs[0], ramp.inputs["Fac"])
    mult = n.new("ShaderNodeMix")
    mult.data_type = "RGBA"
    mult.blend_type = "MULTIPLY"
    mult.inputs["Factor"].default_value = 1.0
    l.new(gi.outputs["Albedo"], mult.inputs["A"])
    l.new(ramp.outputs["Color"], mult.inputs["B"])
    # tiny rim of sky-bounce so shadowed sides keep some color
    em = n.new("ShaderNodeEmission")
    l.new(mult.outputs["Result"], em.inputs["Color"])
    # optional glossy (water, metal)
    gloss = n.new("ShaderNodeBsdfGlossy")
    gloss.inputs["Roughness"].default_value = 0.15
    mixs = n.new("ShaderNodeMixShader")
    l.new(gi.outputs["Gloss"], mixs.inputs["Fac"])
    l.new(em.outputs[0], mixs.inputs[1])
    l.new(gloss.outputs[0], mixs.inputs[2])
    # extra self-emission (lanterns, portals)
    em2 = n.new("ShaderNodeEmission")
    l.new(gi.outputs["Albedo"], em2.inputs["Color"])
    l.new(gi.outputs["Emission"], em2.inputs["Strength"])
    add = n.new("ShaderNodeAddShader")
    l.new(mixs.outputs[0], add.inputs[0])
    l.new(em2.outputs[0], add.inputs[1])
    l.new(add.outputs[0], go.inputs["Shader"])
    return ng


# ---------------------------------------------------------------------------
# Albedo node helpers
# ---------------------------------------------------------------------------

class _MatBuilder:
    def __init__(self, name):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        self.mat = mat
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.n = self.nt.nodes
        self.l = self.nt.links
        self.out = self.n.new("ShaderNodeOutputMaterial")
        self.grp = self.n.new("ShaderNodeGroup")
        self.grp.node_tree = build_shading_group()
        self.l.new(self.grp.outputs["Shader"], self.out.inputs["Surface"])
        self._coord = None
        self._geom = None

    def coord(self, kind="Object"):
        if self._coord is None:
            self._coord = self.n.new("ShaderNodeTexCoord")
        return self._coord.outputs[kind]

    def geometry(self):
        if self._geom is None:
            self._geom = self.n.new("ShaderNodeNewGeometry")
        return self._geom

    def rgb(self, c):
        node = self.n.new("ShaderNodeRGB")
        node.outputs[0].default_value = col(c) if isinstance(c, str) else c
        return node.outputs[0]

    def value(self, v):
        node = self.n.new("ShaderNodeValue")
        node.outputs[0].default_value = v
        return node.outputs[0]

    def mix(self, a, b, fac, blend="MIX"):
        m = self.n.new("ShaderNodeMix")
        m.data_type = "RGBA"
        m.blend_type = blend
        for sock, v in (("A", a), ("B", b)):
            if isinstance(v, str) or isinstance(v, tuple):
                m.inputs[sock].default_value = col(v) if isinstance(v, str) else v
            else:
                self.l.new(v, m.inputs[sock])
        if isinstance(fac, (int, float)):
            m.inputs["Factor"].default_value = fac
        else:
            self.l.new(fac, m.inputs["Factor"])
        return m.outputs["Result"]

    def noise(self, scale=2.0, detail=2.0, roughness=0.5, coord_kind="Object", distortion=0.0):
        t = self.n.new("ShaderNodeTexNoise")
        t.inputs["Scale"].default_value = scale
        t.inputs["Detail"].default_value = detail
        t.inputs["Roughness"].default_value = roughness
        t.inputs["Distortion"].default_value = distortion
        self.l.new(self.coord(coord_kind), t.inputs["Vector"])
        return t.outputs["Fac"]

    def ramp(self, fac, stops, interp="EASE"):
        r = self.n.new("ShaderNodeValToRGB")
        r.color_ramp.interpolation = interp
        els = r.color_ramp.elements
        els[0].position, els[0].color = stops[0][0], stops[0][1]
        els[1].position, els[1].color = stops[-1][0], stops[-1][1]
        for pos, c in stops[1:-1]:
            e = els.new(pos)
            e.color = c
        self.l.new(fac, r.inputs["Fac"])
        return r.outputs["Color"]

    def math(self, op, a, b=None, clamp=False):
        m = self.n.new("ShaderNodeMath")
        m.operation = op
        m.use_clamp = clamp
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                m.inputs[i].default_value = v
            else:
                self.l.new(v, m.inputs[i])
        return m.outputs[0]

    def separate(self, vec_socket):
        s = self.n.new("ShaderNodeSeparateXYZ")
        self.l.new(vec_socket, s.inputs[0])
        return s.outputs

    def normal_z(self):
        return self.separate(self.geometry().outputs["Normal"])[2]

    def world_z(self):
        return self.separate(self.geometry().outputs["Position"])[2]

    def object_random(self):
        oi = self.n.new("ShaderNodeObjectInfo")
        return oi.outputs["Random"]

    def voronoi_edge(self, scale, coord_kind="Object", randomness=0.9):
        v = self.n.new("ShaderNodeTexVoronoi")
        v.feature = "DISTANCE_TO_EDGE"
        v.inputs["Scale"].default_value = scale
        v.inputs["Randomness"].default_value = randomness
        self.l.new(self.coord(coord_kind), v.inputs["Vector"])
        return v.outputs["Distance"]

    def voronoi_cell(self, scale, coord_kind="Object", randomness=0.9):
        v = self.n.new("ShaderNodeTexVoronoi")
        v.feature = "F1"
        v.inputs["Scale"].default_value = scale
        v.inputs["Randomness"].default_value = randomness
        self.l.new(self.coord(coord_kind), v.inputs["Vector"])
        return v.outputs["Color"]

    def finish(self, albedo, emission=0.0, gloss=0.0):
        if isinstance(albedo, str):
            self.grp.inputs["Albedo"].default_value = col(albedo)
        else:
            self.l.new(albedo, self.grp.inputs["Albedo"])
        if isinstance(emission, (int, float)):
            self.grp.inputs["Emission"].default_value = emission
        else:
            self.l.new(emission, self.grp.inputs["Emission"])
        self.grp.inputs["Gloss"].default_value = gloss
        return self.mat


# ---------------------------------------------------------------------------
# Material recipes
# ---------------------------------------------------------------------------

def _painted(name, c_dark, c_light, scale=1.5, contrast=(0.35, 0.65), coord="Object", emission=0.0,
             gloss=0.0, random_tint=0.0):
    """Two-tone soft noise: the basic 'painted' surface."""
    b = _MatBuilder(name)
    nz = b.noise(scale=scale, detail=1.5, roughness=0.45, coord_kind=coord)
    f = b.ramp(nz, [(contrast[0], (0, 0, 0, 1)), (contrast[1], (1, 1, 1, 1))])
    albedo = b.mix(c_dark, c_light, _bw(b, f))
    if random_tint:
        rnd = b.object_random()
        albedo = b.mix(albedo, b.mix(c_dark, c_light, 0.5), b.math("MULTIPLY", rnd, random_tint))
    return b.finish(albedo, emission=emission, gloss=gloss)


def _bw(b, color_socket):
    node = b.n.new("ShaderNodeRGBToBW")
    b.l.new(color_socket, node.inputs[0])
    return node.outputs[0]


def mat_grass_cap(name="M_Grass"):
    """Grass cap: bright top, darker green on the rounded lip; soft painterly patches."""
    b = _MatBuilder(name)
    nz = b.noise(scale=0.08, detail=2.0, roughness=0.5, coord_kind="Object")
    patches = b.ramp(nz, [(0.40, col("grass_top")), (0.62, col("grass_top_lt"))])
    small = b.noise(scale=0.9, detail=1.0, coord_kind="Object")
    top = b.mix(patches, col("grass_side"), _bw(b, b.ramp(small, [(0.7, (0, 0, 0, 1)), (0.9, (0.2, 0.2, 0.2, 1))])))
    nzv = b.normal_z()
    side_fac = b.ramp(nzv, [(0.55, (1, 1, 1, 1)), (0.85, (0, 0, 0, 1))])
    albedo = b.mix(top, col("grass_side"), _bw(b, side_fac))
    return b.finish(albedo)


def mat_cliff(name, c_mid, c_dark, c_light, band_scale=0.9):
    """Cliff/earth side: horizontal painted strata + darker base."""
    b = _MatBuilder(name)
    wave = b.n.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = band_scale
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 1.5
    wave.inputs["Detail Scale"].default_value = 0.6
    b.l.new(b.coord("Object"), wave.inputs["Vector"])
    bands = b.ramp(wave.outputs["Fac"], [(0.25, col(c_dark)), (0.55, col(c_mid)), (0.85, col(c_light))])
    nz = b.noise(scale=1.6, detail=1.0, coord_kind="Object")
    albedo = b.mix(bands, col(c_mid), _bw(b, b.ramp(nz, [(0.3, (0.0, 0, 0, 1)), (0.7, (0.5, 0.5, 0.5, 1))])))
    # darken toward the bottom of the cliff (world Z), soft
    wz = b.world_z()
    grad = b.math("MULTIPLY", b.math("ADD", wz, 6.0), 0.12, clamp=True)
    albedo = b.mix(b.mix(albedo, col(c_dark), 0.55), albedo, grad)
    return b.finish(albedo)


def mat_rock_cliff(name="M_Rock_Cliff", c_dark="#7A6A56", c_mid="#958570", c_mid2="#A49376", c_light="#C2B190",
                   c_crack="#56483A"):
    """Warm grey-brown rock face (grass_rock terraces: Maple Road stone pillars, arches, spires).

    Terrace bodies are baked in world space (object at the origin), so a plain Z-banded texture gives every
    stone the same strata and the bands line up from stone to stone like a stack of coins. Here:
    * the coordinate is offset per object (Object Info random) so neighbouring stones get different phases;
    * tall Voronoi cells (coordinates squashed in z) split each face into vertical blocks: their edges draw dark
      cracks, each block gets its own darkening and its own strata offset, so the bands jump across a crack;
    * the strata are domain-warped by noise and layered at three band scales (broad, medium, thin lines);
    * the foot of the face (Generated z) is darker and the top picks up a faint moss tint under the grass cap.
    """
    b = _MatBuilder(name)
    n, l = b.n, b.l

    def vmath(op, a, v):
        node = n.new("ShaderNodeVectorMath")
        node.operation = op
        for i, x in enumerate((a, v)):
            if isinstance(x, tuple):
                node.inputs[i].default_value = x
            else:
                l.new(x, node.inputs[i])
        return node.outputs["Vector"]

    def combine(xs, ys, zs):
        node = n.new("ShaderNodeCombineXYZ")
        for sock, v in zip(("X", "Y", "Z"), (xs, ys, zs)):
            if isinstance(v, (int, float)):
                node.inputs[sock].default_value = v
            else:
                l.new(v, node.inputs[sock])
        return node.outputs["Vector"]

    rnd = b.object_random()
    p = vmath("ADD", b.coord("Object"), combine(b.math("MULTIPLY", rnd, 53.1), b.math("MULTIPLY", rnd, 91.7),
                                                b.math("MULTIPLY", rnd, 2.9)))
    # vertical blocks: cells ~1.1 m wide and ~5 m tall
    blocks = vmath("MULTIPLY", p, (0.9, 0.9, 0.2))
    vc = n.new("ShaderNodeTexVoronoi")
    vc.feature = "F1"
    vc.inputs["Scale"].default_value = 1.0
    vc.inputs["Randomness"].default_value = 0.85
    l.new(blocks, vc.inputs["Vector"])
    cell = _bw(b, vc.outputs["Color"])
    ve = n.new("ShaderNodeTexVoronoi")
    ve.feature = "DISTANCE_TO_EDGE"
    ve.inputs["Scale"].default_value = 1.0
    ve.inputs["Randomness"].default_value = 0.85
    l.new(blocks, ve.inputs["Vector"])
    # domain warp + per-block strata offset
    wn = n.new("ShaderNodeTexNoise")
    wn.inputs["Scale"].default_value = 0.35
    wn.inputs["Detail"].default_value = 2.0
    wn.inputs["Roughness"].default_value = 0.5
    l.new(p, wn.inputs["Vector"])
    warp = vmath("MULTIPLY", vmath("SUBTRACT", wn.outputs["Color"], (0.5, 0.5, 0.5)), (0.8, 0.8, 1.1))
    pw = vmath("ADD", vmath("ADD", p, warp), combine(0.0, 0.0, b.math("MULTIPLY", cell, 1.7)))

    def bands(scale, distortion):
        w = n.new("ShaderNodeTexWave")
        w.wave_type = "BANDS"
        w.bands_direction = "Z"
        w.inputs["Scale"].default_value = scale
        w.inputs["Distortion"].default_value = distortion
        w.inputs["Detail"].default_value = 1.0
        w.inputs["Detail Scale"].default_value = 0.8
        l.new(pw, w.inputs["Vector"])
        return w.outputs["Fac"]

    broad = bands(0.21, 1.2)    # ~1.5 m strata
    medium = bands(0.55, 2.0)   # ~0.6 m
    thin = bands(1.35, 0.8)     # ~0.25 m lines
    albedo = b.ramp(broad, [(0.15, col(c_dark)), (0.42, col(c_mid)), (0.68, col(c_mid2)), (0.92, col(c_light))])
    albedo = b.mix(albedo, col(c_dark), _bw(b, b.ramp(medium, [(0.55, (0, 0, 0, 1)), (0.95, (0.3, 0.3, 0.3, 1))])))
    albedo = b.mix(albedo, col(c_light), _bw(b, b.ramp(medium, [(0.0, (0.18, 0.18, 0.18, 1)), (0.3, (0, 0, 0, 1))])))
    albedo = b.mix(albedo, col(c_crack), _bw(b, b.ramp(thin, [(0.82, (0, 0, 0, 1)), (0.97, (0.35, 0.35, 0.35, 1))])))
    # per-block tone and cracks
    albedo = b.mix(albedo, col(c_dark), b.math("MULTIPLY", cell, 0.22))
    crack = _bw(b, b.ramp(ve.outputs["Distance"], [(0.025, (1, 1, 1, 1)), (0.075, (0.25, 0.25, 0.25, 1)),
                                                   (0.16, (0, 0, 0, 1))]))
    albedo = b.mix(albedo, col(c_crack), crack)
    # soft painted breakup
    nz = b.noise(scale=1.4, detail=1.0, coord_kind="Object")
    albedo = b.mix(albedo, col(c_mid2), _bw(b, b.ramp(nz, [(0.35, (0, 0, 0, 1)), (0.7, (0.3, 0.3, 0.3, 1))])))
    # darker foot, faint moss under the cap (Generated z = 0..1 over the face)
    gz = b.separate(b.coord("Generated"))[2]
    albedo = b.mix(b.mix(albedo, col(c_crack), 0.35), albedo, b.math("MULTIPLY", gz, 3.5, clamp=True))
    moss = b.math("MULTIPLY", b.math("SUBTRACT", gz, 0.9), 1.6, clamp=True)
    albedo = b.mix(albedo, col("rock_moss"), b.math("MULTIPLY", moss, b.math("ADD", b.math("MULTIPLY", nz, 0.3), 0.05)))
    return b.finish(albedo)


def mat_cobble(name, a, bcol, ccol, mortar, scale=1.1):
    """Rounded cobblestones (Amherst / Southperry style): voronoi cells + dark mortar."""
    b = _MatBuilder(name)
    cell = b.voronoi_cell(scale)
    tint = b.ramp(_bw(b, cell), [(0.2, col(a)), (0.5, col(bcol)), (0.8, col(ccol))], interp="CONSTANT")
    edge = b.voronoi_edge(scale)
    mortar_fac = b.ramp(edge, [(0.035, (1, 1, 1, 1)), (0.09, (0, 0, 0, 1))])
    albedo = b.mix(tint, col(mortar), _bw(b, mortar_fac))
    nz = b.noise(scale=0.25, detail=1.0)
    albedo = b.mix(albedo, col(mortar), b.math("MULTIPLY", nz, 0.18))
    return b.finish(albedo)


def mat_wood(name, c_mid="wood", c_dark="wood_dk", c_light="wood_lt", grain_scale=3.0, axis="X"):
    b = _MatBuilder(name)
    wave = b.n.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = axis
    wave.inputs["Scale"].default_value = grain_scale
    wave.inputs["Distortion"].default_value = 3.0
    b.l.new(b.coord("Object"), wave.inputs["Vector"])
    albedo = b.ramp(wave.outputs["Fac"], [(0.2, col(c_dark)), (0.5, col(c_mid)), (0.9, col(c_light))])
    return b.finish(albedo)


def mat_gradient(name, c_bottom, c_top, z0=0.0, z1=1.0, noise_amt=0.15, coord="Generated", random_tint=0.0,
                 emission=0.0):
    """Vertical gradient over the object bounding box (Generated coords, 0..1)."""
    b = _MatBuilder(name)
    z = b.separate(b.coord(coord))[2]
    f = b.math("MULTIPLY", b.math("SUBTRACT", z, z0), 1.0 / max(1e-4, (z1 - z0)), clamp=True)
    if noise_amt:
        nz = b.noise(scale=1.2, detail=1.0, coord_kind=coord)
        f = b.math("ADD", f, b.math("MULTIPLY", b.math("SUBTRACT", nz, 0.5), noise_amt * 2), clamp=True)
    albedo = b.mix(c_bottom, c_top, f)
    if random_tint:
        rnd = b.object_random()
        albedo = b.mix(albedo, b.mix(albedo, col(c_top), 0.5), b.math("MULTIPLY", rnd, random_tint))
    return b.finish(albedo, emission=emission)


def mat_flat(name, c, emission=0.0, gloss=0.0):
    b = _MatBuilder(name)
    return b.finish(c, emission=emission, gloss=gloss)


def mat_spotted(name, c_base, c_spot, scale=2.2, threshold=0.18):
    """Mushroom-cap spots (Orange Mushroom house roofs etc.)."""
    b = _MatBuilder(name)
    v = b.n.new("ShaderNodeTexVoronoi")
    v.feature = "F1"
    v.inputs["Scale"].default_value = scale
    v.inputs["Randomness"].default_value = 0.7
    b.l.new(b.coord("Object"), v.inputs["Vector"])
    spot = b.ramp(v.outputs["Distance"], [(threshold - 0.02, (1, 1, 1, 1)), (threshold + 0.02, (0, 0, 0, 1))])
    z = b.separate(b.coord("Generated"))[2]
    base = b.mix(b.mix(c_base, "#000000", 0.22), c_base, b.math("MULTIPLY", z, 2.0, clamp=True))
    albedo = b.mix(base, col(c_spot), _bw(b, spot))
    return b.finish(albedo)


def mat_streaked(name, c_base, c_streak, scale=9.0):
    """Mushroom-cap streaks radiating from the top (classic yellow/red striped caps)."""
    b = _MatBuilder(name)
    sep = b.separate(b.coord("Object"))
    ang = b.math("ARCTAN2", sep[1], sep[0])
    wave = b.math("SINE", b.math("MULTIPLY", ang, scale))
    nz = b.noise(scale=3.0, detail=1.0)
    streak = b.ramp(b.math("ADD", wave, b.math("MULTIPLY", nz, 1.1)), [(0.7, (0, 0, 0, 1)), (0.85, (1, 1, 1, 1))])
    z = b.separate(b.coord("Generated"))[2]
    base = b.mix(b.mix(c_base, "#000000", 0.2), c_base, b.math("MULTIPLY", z, 2.0, clamp=True))
    albedo = b.mix(base, col(c_streak), b.math("MULTIPLY", _bw(b, streak), 0.42))
    return b.finish(albedo)


def mat_water(name="M_Water"):
    b = _MatBuilder(name)
    nz = b.noise(scale=0.12, detail=2.0, roughness=0.6, coord_kind="Object", distortion=0.8)
    base = b.ramp(nz, [(0.35, col("water_dk")), (0.55, col("water")), (0.72, col("water_lt"))])
    wav = b.n.new("ShaderNodeTexWave")
    wav.wave_type = "RINGS"
    wav.inputs["Scale"].default_value = 0.08
    wav.inputs["Distortion"].default_value = 12.0
    b.l.new(b.coord("Object"), wav.inputs["Vector"])
    glint = b.ramp(wav.outputs["Fac"], [(0.94, (0, 0, 0, 1)), (0.975, (1, 1, 1, 1))], interp="LINEAR")
    # depth gradient: turquoise shallows at the edges, deep blue in the middle (Generated = 0..1 over the surface)
    g = b.separate(b.coord("Generated"))
    dx = b.math("SUBTRACT", g[0], 0.5)
    dy = b.math("SUBTRACT", g[1], 0.5)
    rad = b.math("SQRT", b.math("ADD", b.math("MULTIPLY", dx, dx), b.math("MULTIPLY", dy, dy)))
    depth = b.ramp(rad, [(0.12, col("water_dk")), (0.34, col("water")), (0.5, col("water_shallow"))])
    base = b.mix(depth, base, 0.35)
    albedo = b.mix(base, col("foam"), b.math("MULTIPLY", _bw(b, glint), 0.28))
    return b.finish(albedo, gloss=0.12)


def mat_outline(name="M_Outline", c="#2B1D14"):
    """Inverted-hull ink line: only back faces of the shell render (backface culling)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = hex_to_linear(c)
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    mat.use_backface_culling = True
    try:
        mat.use_backface_culling_shadow = True
    except AttributeError:
        pass
    return mat


def mat_underside(name="M_Rock_Under"):
    """Floating-island underbelly: warm rock strata, lighter near the top, no absolute-height darkening."""
    b = _MatBuilder(name)
    wave = b.n.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = 0.06
    wave.inputs["Distortion"].default_value = 1.5
    wave.inputs["Detail"].default_value = 2.0
    b.l.new(b.coord("Object"), wave.inputs["Vector"])
    bands = b.ramp(wave.outputs["Fac"], [(0.2, col("rock_under_dk")), (0.55, col("rock_under")),
                                          (0.85, col("rock_under_lt"))])
    z = b.separate(b.coord("Generated"))[2]
    albedo = b.mix(b.mix(bands, col("dirt_dk"), 0.55), bands, b.math("POWER", z, 0.6))
    nz = b.noise(scale=0.03, detail=2.0)
    moss = _bw(b, b.ramp(nz, [(0.6, (0, 0, 0, 1)), (0.75, (1, 1, 1, 1))]))
    albedo = b.mix(albedo, col("rock_moss"), b.math("MULTIPLY", moss, 0.35))
    return b.finish(albedo)


def mat_waterfall(name="M_Waterfall"):
    """Vertical streaks of light/dark blue with white foam lines (reads as falling water)."""
    b = _MatBuilder(name)
    wave = b.n.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 2.5
    wave.inputs["Distortion"].default_value = 4.0
    b.l.new(b.coord("Object"), wave.inputs["Vector"])
    streak = b.ramp(wave.outputs["Fac"], [(0.2, col("water")), (0.6, col("water_lt")), (0.85, col("foam"))])
    return b.finish(streak, emission=0.25, gloss=0.1)


def mat_sea(name="M_Sea"):
    """Far-below sea: mostly self-lit so the island's huge shadow does not blot it."""
    b = _MatBuilder(name)
    nz = b.noise(scale=0.004, detail=2.0, roughness=0.6, coord_kind="Object", distortion=0.5)
    albedo = b.ramp(nz, [(0.35, col("sea_dk")), (0.65, col("sea"))])
    return b.finish(albedo, emission=0.85, gloss=0.0)


def mat_marker(name, c, emission=1.5):
    return mat_flat(name, c, emission=emission)


def mat_portal_glow(name="M_Portal_Glow", c_bottom="portal_core", c_top="portal_ring", strength=2.6, alpha=0.85):
    """Door-portal light column: emissive, brightest at the threshold and fading to fully transparent toward
    the top (Generated z over the mesh), so it marks the entry without hiding the door behind it. Bypasses
    MS_Shading (pure emission + transparency); put it on its own object with visible_shadow = False."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    n, l = nt.nodes, nt.links
    out = n.new("ShaderNodeOutputMaterial")
    tc = n.new("ShaderNodeTexCoord")
    sep = n.new("ShaderNodeSeparateXYZ")
    l.new(tc.outputs["Generated"], sep.inputs[0])
    inv = n.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.use_clamp = True
    inv.inputs[0].default_value = 1.0
    l.new(sep.outputs[2], inv.inputs[1])
    pw = n.new("ShaderNodeMath")
    pw.operation = "POWER"
    l.new(inv.outputs[0], pw.inputs[0])
    pw.inputs[1].default_value = 1.7
    fade = n.new("ShaderNodeMath")
    fade.operation = "MULTIPLY"
    fade.use_clamp = True
    l.new(pw.outputs[0], fade.inputs[0])
    fade.inputs[1].default_value = alpha
    cm = n.new("ShaderNodeMix")
    cm.data_type = "RGBA"
    cm.inputs["A"].default_value = col(c_bottom)
    cm.inputs["B"].default_value = col(c_top)
    l.new(sep.outputs[2], cm.inputs["Factor"])
    em = n.new("ShaderNodeEmission")
    l.new(cm.outputs["Result"], em.inputs["Color"])
    em.inputs["Strength"].default_value = strength
    tr = n.new("ShaderNodeBsdfTransparent")
    mix = n.new("ShaderNodeMixShader")
    l.new(fade.outputs[0], mix.inputs["Fac"])
    l.new(tr.outputs[0], mix.inputs[1])
    l.new(em.outputs[0], mix.inputs[2])
    l.new(mix.outputs[0], out.inputs["Surface"])
    for attr, val in (("surface_render_method", "BLENDED"), ("use_backface_culling", False),
                      ("use_transparent_shadow", True)):
        try:
            setattr(mat, attr, val)
        except (AttributeError, TypeError):
            pass
    return mat


def mat_hill(name="M_Hill"):
    """Rolling grass hill (plinth skirts, Mountain_Hill, Mountain_Peak_C): the ground grass painting (M_Grass
    patches and tint) so hills melt into the meadow instead of reading as olive domes; only steep faces
    (normal z < ~0.6) shade toward the darker grass side, the crest catches a little light, and each instance
    gets a slight random tint."""
    b = _MatBuilder(name)
    nz = b.noise(scale=0.08, detail=2.0, roughness=0.5, coord_kind="Object")
    patches = b.ramp(nz, [(0.40, col("grass_top")), (0.62, col("grass_top_lt"))])
    small = b.noise(scale=0.9, detail=1.0, coord_kind="Object")
    top = b.mix(patches, col("grass_side"), _bw(b, b.ramp(small, [(0.7, (0, 0, 0, 1)), (0.9, (0.15, 0.15, 0.15, 1))])))
    side_fac = b.ramp(b.normal_z(), [(0.32, (0.8, 0.8, 0.8, 1)), (0.68, (0, 0, 0, 1))])
    albedo = b.mix(top, col("grass_side"), _bw(b, side_fac))
    gz = b.separate(b.coord("Generated"))[2]
    albedo = b.mix(albedo, col("grass_top_lt"), b.math("MULTIPLY", b.math("SUBTRACT", gz, 0.7), 1.0, clamp=True))
    albedo = b.mix(albedo, col("grass_top"), b.math("MULTIPLY", b.object_random(), 0.25))
    return b.finish(albedo)


# Registry: name -> factory. Materials are created on first use and shared.
RECIPES = {
    "M_Grass": lambda: mat_grass_cap("M_Grass"),
    "M_Dirt_Cliff": lambda: mat_cliff("M_Dirt_Cliff", "dirt", "dirt_dk", "dirt_lt"),
    "M_Stone_Cliff": lambda: mat_cobble("M_Stone_Cliff", "cobble_a", "cobble_b", "cobble_c", "cobble_mortar", 0.9),
    "M_Sand_Cliff": lambda: mat_cobble("M_Sand_Cliff", "sand_a", "sand_b", "cobble_c", "sand_mortar", 0.9),
    "M_Cobble_Path": lambda: mat_cobble("M_Cobble_Path", "cobble_a", "cobble_c", "cobble_b", "cobble_mortar", 1.6),
    "M_Sand_Path": lambda: mat_cobble("M_Sand_Path", "sand_a", "beach", "sand_b", "sand_mortar", 1.4),
    "M_Path_Dirt": lambda: _painted("M_Path_Dirt", "path_dirt_dk", "path_dirt", scale=0.6),
    "M_Rock_Cliff": lambda: mat_rock_cliff("M_Rock_Cliff"),
    "M_Main_Road": lambda: _painted("M_Main_Road", "#E0C58C", "#F4E6BE", scale=0.35),
    "M_Beach": lambda: _painted("M_Beach", "sand_b", "beach", scale=0.3),
    "M_Rock": lambda: mat_gradient("M_Rock", "rock_dk", "rock", 0.0, 0.9, noise_amt=0.2, random_tint=0.3),
    "M_Rock_Moss": lambda: mat_gradient("M_Rock_Moss", "rock", "rock_moss", 0.55, 0.9, noise_amt=0.25),
    "M_Wood": lambda: mat_wood("M_Wood"),
    "M_Wood_Dark": lambda: mat_wood("M_Wood_Dark", "wood_dk", "#4A2E17", "wood", 2.0),
    "M_Plank": lambda: mat_wood("M_Plank", "plank", "wood", "wood_lt", 1.2, axis="Y"),
    "M_Bark": lambda: mat_wood("M_Bark", "bark", "bark_dk", "wood", 2.5, axis="Z"),
    "M_Plaster": lambda: _painted("M_Plaster", "plaster_dk", "plaster", scale=1.2),
    # soft painted near-white, slightly warm: Southperry's whitewashed stone (M_Plaster reads beige/khaki there)
    "M_Whitewash": lambda: _painted("M_Whitewash", "whitewash_dk", "whitewash", scale=0.9, contrast=(0.3, 0.7)),
    "M_StoneWall": lambda: mat_cobble("M_StoneWall", "stone_wall", "cobble_c", "plaster_dk", "rock_dk", 2.2),
    "M_Window": lambda: mat_flat("M_Window", "window", emission=0.35),
    "M_Door": lambda: mat_wood("M_Door", "door", "wood_dk", "wood", 4.0, axis="X"),
    "M_Metal": lambda: mat_flat("M_Metal", "metal", gloss=0.2),
    "M_Gold": lambda: mat_flat("M_Gold", "gold", gloss=0.25),
    "M_Rope": lambda: mat_flat("M_Rope", "rope"),
    "M_Cloth_White": lambda: _painted("M_Cloth_White", "#E2DAC8", "cloth_white", scale=1.0),
    "M_Cloth_Red": lambda: mat_flat("M_Cloth_Red", "cloth_red"),
    "M_Water": lambda: mat_water("M_Water"),
    "M_Foam": lambda: mat_flat("M_Foam", "foam", emission=0.15),
    "M_Leaf": lambda: mat_gradient("M_Leaf", "leaf_dk", "leaf_lt", 0.1, 0.95, noise_amt=0.18, random_tint=0.35),
    "M_Leaf_B": lambda: mat_gradient("M_Leaf_B", "leaf_b_dk", "leaf_b_lt", 0.1, 0.95, noise_amt=0.18, random_tint=0.35),
    "M_Leaf_Yellow": lambda: mat_gradient("M_Leaf_Yellow", "leaf_yellow_dk", "leaf_yellow", 0.1, 0.95, noise_amt=0.18,
                                          random_tint=0.3),
    "M_Leaf_Autumn": lambda: mat_gradient("M_Leaf_Autumn", "leaf_autumn_dk", "leaf_autumn", 0.1, 0.95, noise_amt=0.18),
    "M_Bush": lambda: mat_gradient("M_Bush", "grass_dark", "leaf_lt", 0.0, 1.0, noise_amt=0.15, random_tint=0.3),
    "M_MushStem": lambda: mat_gradient("M_MushStem", "mush_stem_dk", "mush_stem", 0.0, 1.0, noise_amt=0.05),
    "M_Tomato": lambda: mat_gradient("M_Tomato", "#A82418", "tomato", 0.0, 0.8, noise_amt=0.05),
    "M_Marker_Spawn": lambda: mat_marker("M_Marker_Spawn", "marker_spawn"),
    "M_Marker_NPC": lambda: mat_marker("M_Marker_NPC", "marker_npc"),
    "M_Marker_Route": lambda: mat_marker("M_Marker_Route", "marker_route"),
    "M_Portal_Core": lambda: mat_marker("M_Portal_Core", "portal_core", emission=1.6),
    "M_Portal_Ring": lambda: mat_marker("M_Portal_Ring", "portal_ring", emission=1.2),
    "M_Eye_Black": lambda: mat_flat("M_Eye_Black", "eye_black", gloss=0.3),
    "M_Eye_White": lambda: mat_flat("M_Eye_White", "eye_white"),
    "M_Skin": lambda: mat_flat("M_Skin", "skin"),
    "M_Outline": lambda: mat_outline("M_Outline"),
    "M_Mountain": lambda: mat_gradient("M_Mountain", "mountain_dk", "mountain_lt", 0.0, 1.0, noise_amt=0.22,
                                       random_tint=0.25),
    "M_Mountain_Rocky": lambda: mat_gradient("M_Mountain_Rocky", "mountain_dk", "rock", 0.35, 0.85, noise_amt=0.2),
    "M_Hill": lambda: mat_hill("M_Hill"),
    "M_Portal_Glow": lambda: mat_portal_glow("M_Portal_Glow"),
    "M_Cloud": lambda: mat_gradient("M_Cloud", "cloud_dk", "cloud", 0.1, 0.8, noise_amt=0.05, emission=0.35),
    "M_Rock_Under": lambda: mat_underside("M_Rock_Under"),
    "M_Waterfall": lambda: mat_waterfall("M_Waterfall"),
    "M_Sea": lambda: mat_sea("M_Sea"),
}


def get(name):
    """Return a shared material by name, creating it from its recipe if needed.

    Unknown names of the form ``M_Flat_<palettekey>`` / ``M_Spot_<base>_<spot>`` /
    ``M_Grad_<bottom>_<top>`` are generated on the fly so assets can request colors
    without registering a recipe.
    """
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    if name in RECIPES:
        return RECIPES[name]()
    if name.startswith("M_Flat_"):
        return mat_flat(name, name[len("M_Flat_"):])
    if name.startswith("M_Glow_"):
        return mat_flat(name, name[len("M_Glow_"):], emission=1.2)
    if name.startswith("M_Spot_"):
        base, spot = name[len("M_Spot_"):].split("__")
        return mat_spotted(name, base, spot)
    if name.startswith("M_Streak_"):
        base, streak = name[len("M_Streak_"):].split("__")
        return mat_streaked(name, base, streak)
    if name.startswith("M_Grad_"):
        bottom, top = name[len("M_Grad_"):].split("__")
        return mat_gradient(name, bottom, top, 0.0, 1.0, noise_amt=0.08)
    raise KeyError(f"Unknown material '{name}'")
