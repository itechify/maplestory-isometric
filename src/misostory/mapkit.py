"""MapCtx - the authoring API used by every map module.

A map is authored in LOCAL meters:
  * local +X = the original map's left->right progression (west -> east),
  * local +Y = depth (away from the camera side of the map),
  * local Z  = height above the map's base level (``base_z`` in world).
The world layout places each map with an origin and a yaw of 0 or -90 degrees; both
keep cliff faces that rise toward local +Y facing the isometric camera.

Rules of thumb for authors (see docs/AUTHORING.md):
  * build terrain first (terrace/ramp/stairs/bridge), then everything else is grounded
    automatically by raycast; ``place`` raises if nothing is under a point;
  * higher tiers sit further back (+Y) so their faces are visible;
  * keep walkable routes >= 2.5 m wide, ramps <= ~30 degrees, steps <= 0.35 m;
  * every exit gets ``portal(...)`` and every map gets at least one ``route(...)``.
"""

import json
import math

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from . import core, geo, kit
from . import layout as LY
from . import materials as M
from . import scene_setup
from .kit.creatures import MOB_ASSETS, register_npc

PLAYER_HEIGHT = core.PLAYER_HEIGHT  # 1.5 m chibi player

# The pale through-road (Maple Road / Rainbow Street main route) as one painted ribbon style, so the road reads as
# one continuous cream line across maps and trails:  m.path("Main_Road", pts, **MAIN_ROAD)
MAIN_ROAD = dict(mat="M_Main_Road", width=3.6)

# Gameplay-frame rule (gameplay_frame_check): the player proxy must project inside this band of the Gameplay
# camera's frame (u and v), and hunting maps need at least this many mob proxies inside the frame (0..1).
FRAME_BAND = (0.1, 0.9)
FRAME_MOBS_HUNTING = 2


class MapCtx:
    @classmethod
    def for_map(cls, mid, origins=None, ground_objs=()):
        """Context for a map placed by the world layout."""
        origins = origins or LY.resolve()
        lm = LY.MAPS[mid]
        meta = {"id": mid, "slug": lm["slug"], "name": lm["name"], "size": (lm["L"], lm["D"]), "kind": lm["kind"],
                "street": lm["street"]}
        ctx = cls(meta, origin=origins[mid], yaw=LY.world_yaw(mid))
        for o in ground_objs:
            ctx.ground.add(o)
        return ctx

    def __init__(self, meta, origin=(0.0, 0.0, 0.0), yaw=0.0):
        self.meta = meta
        self.map_id = meta["id"]
        self.slug = meta["slug"]
        self.name = meta["name"]
        self.size = meta["size"]  # (L, D) local meters
        self.origin = Vector(origin)
        self.yaw = yaw
        self._c = math.cos(math.radians(yaw))
        self._s = math.sin(math.radians(yaw))
        s = self.slug
        self.col_map = core.get_collection(f"MAPS/{s}")
        self.col_map["map_id"] = self.map_id
        self.col_map["map_name"] = self.name
        self.col_map["street"] = meta.get("street", "")
        self.col_map["kind"] = meta.get("kind", "field")
        self.col_terrain = core.get_collection(f"MAPS/{s}/{s}_Terrain")
        self.col_arch = core.get_collection(f"MAPS/{s}/{s}_Architecture")
        self.col_veg = core.get_collection(f"MAPS/{s}/{s}_Vegetation")
        self.col_props = core.get_collection(f"MAPS/{s}/{s}_Props")
        self.col_portals = core.get_collection(f"PORTALS/Portals_{s}")
        self.col_mobs = core.get_collection(f"MONSTER_PROXIES/Mobs_{s}")
        self.col_npcs = core.get_collection(f"CHARACTER_PROXIES/NPCs_{s}")
        self.col_cams = core.get_collection(f"CAMERAS/Cams_{s}")
        self.col_debug = core.get_collection(f"DEBUG/Debug_{s}")
        self.ground = core.GroundIndex()
        self.portals = []
        self.prop_zones = []  # (x, y, r) of placed props; scatter/mobs avoid them
        self.routes = []
        self.npcs = []
        self.spawns = []
        self.warnings = []  # exceptions that used to be swallowed (traversal.check_map reports them)
        self._player = None
        self._gameplay = None  # (fx, fy, scale) of the Gameplay camera, set by cameras()
        self._n = 0

    # ------------------------------------------------------------------
    # coordinates
    # ------------------------------------------------------------------
    def w(self, x, y, z=0.0):
        """Local (x, y, z) -> world Vector."""
        return Vector((self.origin.x + x * self._c - y * self._s,
                       self.origin.y + x * self._s + y * self._c,
                       self.origin.z + z))

    def wxy(self, x, y):
        v = self.w(x, y)
        return (v.x, v.y)

    def wpoly(self, poly):
        return [self.wxy(x, y) for x, y in poly]

    def wyaw(self, rot):
        return rot + self.yaw

    # ------------------------------------------------------------------
    # layout / topology
    # ------------------------------------------------------------------
    def anchor(self, name):
        """Local (x, y, z) of an edge portal fixed by the world layout."""
        return LY.MAPS[self.map_id]["anchors"][name]

    def link_target(self, portal_name):
        for child, ca, parent, pa, _g, _b in LY.LINKS:
            if child == self.map_id and ca == portal_name:
                return parent, pa
            if parent == self.map_id and pa == portal_name:
                return child, ca
        for mid, pn, interior, ipn in LY.DOOR_LINKS:
            if mid == self.map_id and pn == portal_name:
                return interior, ipn
            if interior == self.map_id and ipn == portal_name:
                return mid, pn
        raise KeyError(f"[{self.slug}] portal '{portal_name}' has no link in layout.LINKS / DOOR_LINKS")

    def edge_portal(self, name, rot=None, offset=(0.0, 0.0)):
        """Place the layout-anchored edge portal (target looked up from the link table)."""
        x, y, z = self.anchor(name)
        x += offset[0]
        y += offset[1]
        to_map, to_portal = self.link_target(name)
        if rot is None:
            L, D = self.size
            # face along the walking direction through the portal: decided by the nearest edge
            rot = 90.0 if min(x, L - x) < min(y, D - y) else 0.0
        return self.portal(name, x, y, to_map, to_portal, kind="edge", rot=rot)

    def door_portal(self, name, x, y, rot=0.0, z=None):
        to_map, to_portal = self.link_target(name)
        return self.portal(name, x, y, to_map, to_portal, kind="door", rot=rot, z=z)

    def view_dir(self):
        """Local (x, y) direction the isometric camera looks along for this map.

        Faces whose local normal points against this vector are visible to the camera.
        """
        import math as _m
        c, s_ = _m.cos(_m.radians(-self.yaw)), _m.sin(_m.radians(-self.yaw))
        vx, vy = 0.70710678, 0.70710678
        return (vx * c - vy * s_, vx * s_ + vy * c)

    def face_point(self, x, y, dx, dy, max_dist=12.0, drop=0.5, step=0.1):
        """March from (x, y) along (dx, dy) until the ground drops by > drop.

        Returns (ex, ey, z_top, z_below): the last point on the upper surface (the cliff
        edge), its height, and the ground height just past the edge. None if no edge.
        """
        import math as _m
        L = _m.hypot(dx, dy) or 1.0
        dx, dy = dx / L, dy / L
        z0 = self.ground_z(x, y)
        if z0 is None:
            return None
        t = 0.0
        while t < max_dist:
            t += step
            z = self.ground_z(x + dx * t, y + dy * t)
            if z is None or z0 - z > drop:
                ex, ey = x + dx * (t - step), y + dy * (t - step)
                return (ex, ey, z0, z)
            z0 = max(z0, z) if abs(z - z0) < drop else z0
        return None

    def _name(self, base):
        return f"{self.slug}_{base}"

    def add_ground(self, obj):
        self.ground.add(obj)
        return obj

    def collider(self, name, boxes=(), cylinders=()):
        """Invisible walkable collision geometry (interiors: perches, lids, humps under a visual prop).

        boxes: list of (x0, y0, z0, x1, y1, z1) in local meters (note: z0 before x1, unlike kit
        interior.solid). cylinders: optional list of (cx, cy, r, z0, z1). The mesh joins the ground index
        (walkable for traversal and grounding), never renders, is tagged obj["collider"] = True and lives
        in the map's <slug>_Collision collection. Returns the object.
        """
        mb = geo.MeshBuilder()
        for (x0, y0, z0, x1, y1, z1) in boxes:
            x0, x1 = min(x0, x1), max(x0, x1)
            y0, y1 = min(y0, y1), max(y0, y1)
            z0, z1 = min(z0, z1), max(z0, z1)
            mb.box((x1 - x0, y1 - y0, z1 - z0), loc=self.w((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
                   rot=(0, 0, self.yaw), mat="M_Rock")
        for (cx, cy, r, z0, z1) in cylinders:
            z0, z1 = min(z0, z1), max(z0, z1)
            mb.cyl(r, z1 - z0, loc=self.w(cx, cy, z0), rot=(0, 0, self.yaw), mat="M_Rock", verts=16)
        if not mb.bm.faces:
            raise ValueError(f"[{self.slug}] collider('{name}'): no boxes or cylinders given")
        coll = core.get_collection(f"MAPS/{self.slug}/{self.slug}_Collision", hide_render=True)
        obj = mb.build(self._name(name), coll, smooth=False)
        obj["collider"] = True
        obj.hide_render = True
        obj.visible_camera = False
        obj.visible_shadow = False
        obj.display_type = "WIRE"
        self.ground.add(obj)
        return obj

    # ------------------------------------------------------------------
    # terrain
    # ------------------------------------------------------------------
    def terrace(self, name, outline, top, bottom=None, style="grass_dirt", collection=None, walkable=True, **kw):
        """Platform/terrace from a local outline. top/bottom are local heights."""
        bottom = (top - 3.0) if bottom is None else bottom
        coll = collection or self.col_terrain
        objs = geo.terrace(self._name(name), self.wpoly(outline), self.origin.z + top, self.origin.z + bottom,
                           coll, style=style, seed=core.stable_hash(name), **kw)
        if walkable:
            for o in objs:
                if o.name.endswith("_Cap") or "_Cap_" in o.name:
                    self.ground.add(o)
        return objs

    def ramp(self, name, p0, p1, width, style="grass_dirt", bottom=None, blend=True, **kw):
        a = self.w(*p0)
        b = self.w(*p1)
        bot = None if bottom is None else self.origin.z + bottom
        obj = geo.ramp(self._name(name), a, b, width, self.col_terrain, style=style, bottom=bot,
                       ground_index=self.ground, **kw)
        top_mat = kw.get("top_mat", "M_Path_Dirt")
        if blend and top_mat and top_mat != "M_Grass" and style.startswith("grass"):
            # dirt ribbons carry the trail onto the terraces at both ends. Each starts on the ramp surface at
            # the ramp's full width (same material: the overlap is invisible), covers the flat end plate and
            # the cap lip band the ramp tucks under, then narrows and rounds off on the terrace - one
            # continuous outline instead of a notched step where ramp, blend and cap meet.
            import math as _m
            dx, dy = p1[0] - p0[0], p1[1] - p0[1]
            L = _m.hypot(dx, dy) or 1.0
            ux, uy = dx / L, dy / L
            ext = kw.get("extend", 0.6)
            run_in = min(1.2, 0.35 * L)  # how far the blend reaches back over the ramp surface
            out = ext + 1.1              # how far past the ramp end it runs onto the terrace
            span = run_in + out
            full = (run_in + ext) / span  # fraction of the ribbon kept at the full ramp width

            def narrowing(t, t0=full):
                if t <= t0:
                    return 1.0
                v = min(1.0, (t - t0) / max(1e-6, 1.0 - t0))
                return 1.0 - 0.15 * v * v * (3 - 2 * v)

            bw = max(0.6, width - 0.08)
            try:
                self.path(name + "_BlendTop", [(p1[0] - ux * run_in, p1[1] - uy * run_in),
                                               (p1[0] + ux * out, p1[1] + uy * out)],
                          width=bw, smooth_iters=0, edge_wobble=0.03, width_fn=narrowing, end_taper=0.75,
                          mat=top_mat)
                self.path(name + "_BlendFoot", [(p0[0] + ux * run_in, p0[1] + uy * run_in),
                                                (p0[0] - ux * out, p0[1] - uy * out)],
                          width=bw, smooth_iters=0, edge_wobble=0.03, width_fn=narrowing, end_taper=0.75,
                          mat=top_mat)
            except Exception as e:  # noqa: BLE001 - visual only, but recorded (build_report traversal.exceptions)
                self.warnings.append(f"ramp {name}: blend ribbon failed: {e!r}")
        return obj

    def stairs(self, name, p0, p1, width, mat="M_Plank", side_mat="M_Wood_Dark", fit_edge=False, **kw):
        """Steps from p0 (bottom) to p1 (top). fit_edge=True slides the whole flight (run and heights kept)
        along its climb direction so the top tread sits just inside the upper cap's real, wobbled edge
        (the most protruding of three samples across the width): no lower tread ends up under the cap lip.
        """
        if fit_edge:
            p0, p1 = self._fit_flight(p0, p1, width, kw.get("step_h", 0.28))
        return geo.stairs(self._name(name), self.w(*p0), self.w(*p1), width, self.col_terrain, mat=mat,
                          side_mat=side_mat, ground_index=self.ground, **kw)

    def _fit_flight(self, p0, p1, width, step_h):
        """Shift a flight so its top tread overlaps the upper cap edge by 0.1 m (see stairs(fit_edge=True))."""
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        run = math.hypot(dx, dy)
        if run < 1e-6:
            return p0, p1
        cx, cy = dx / run, dy / run
        n = max(2, int(round(abs(p1[2] - p0[2]) / step_h)))
        depth = run / n
        # start the search on the upper cap: a little past p1 if p1 itself is short of the edge
        start = None
        for back in (1.5, 0.8, 0.0, 2.5):
            sx, sy = p1[0] + cx * back, p1[1] + cy * back
            z = self.ground_z(sx, sy, z_from=p1[2] + 0.6)
            if z is not None and abs(z - p1[2]) < 0.3:
                start = (sx, sy)
                break
        if start is None:
            return p0, p1
        best = None
        for off in (-0.5 * width, 0.0, 0.5 * width):
            sx, sy = start[0] - cy * off, start[1] + cx * off
            e = self.face_point(sx, sy, -cx, -cy)
            if e is None:
                continue
            proj = e[0] * cx + e[1] * cy  # the most protruding edge sample wins
            if best is None or proj < best:
                best = proj
        if best is None:
            return p0, p1
        t = best - (p1[0] * cx + p1[1] * cy) + depth - 0.1
        return ((p0[0] + cx * t, p0[1] + cy * t, p0[2]), (p1[0] + cx * t, p1[1] + cy * t, p1[2]))

    def deck(self, name, outline, top, post_bottom=None, mat="M_Plank", posts=True, rail=False):
        """Wooden walkway/platform on posts (local outline, local top height)."""
        mb = geo.MeshBuilder()
        wp = self.wpoly(outline)
        z = self.origin.z + top
        mb.prism(wp, z - 0.25, z, mat=mat, bevel=0.04, segs=1)
        if posts:
            pb = self.origin.z + (top - 4.0 if post_bottom is None else post_bottom)
            for (x, y) in geo.resample(geo.ensure_ccw(wp), 2.6):
                mb.cyl(0.16, z - 0.2 - pb, loc=(x, y, pb), mat="M_Wood_Dark", verts=8)
        obj = mb.build(self._name(name), self.col_terrain, smooth=False)
        self.ground.add(obj)
        if rail:
            self.rail(name + "_Rail", outline, top)
        return obj

    def rail(self, name, pts, top, closed=True, height=0.9, mat="M_Wood"):
        mb = geo.MeshBuilder()
        wpts = [self.w(x, y, top) for x, y in pts]
        n = len(wpts)
        rng_ = range(n) if closed else range(n - 1)
        for i in rng_:
            a = wpts[i]
            b = wpts[(i + 1) % n]
            d = b - a
            L = d.length
            yaw = math.degrees(math.atan2(d.y, d.x))
            mid = (a + b) / 2
            mb.box((L, 0.1, 0.12), loc=(mid.x, mid.y, a.z + height), rot=(0, 0, yaw), mat=mat)
            for k in range(int(L // 1.5) + 1):
                p = a.lerp(b, k * 1.5 / max(L, 1e-3))
                mb.box((0.12, 0.12, height), loc=(p.x, p.y, a.z + height / 2), mat=mat)
        return mb.build(self._name(name), self.col_arch, smooth=False)

    def bridge(self, name, p0, p1, width=2.6, rope=True, sag=0.35):
        """Plank bridge with rope rails between two local points (x, y, z)."""
        a = self.w(*p0)
        b = self.w(*p1)
        d = b - a
        d2 = Vector((d.x, d.y, 0))
        L = d2.length
        d2.normalize()
        nrm = Vector((-d2.y, d2.x, 0))
        yaw = math.degrees(math.atan2(d2.y, d2.x))
        n = max(4, int(L / 0.55))
        mb = geo.MeshBuilder()
        for i in range(n + 1):
            t = i / n
            p = a.lerp(b, t)
            p.z -= math.sin(math.pi * t) * sag
            pitch = math.degrees(math.atan2(d.z, L))
            mb.box((0.48, width, 0.14), loc=(p.x, p.y, p.z - 0.07), rot=(0, -pitch, yaw), mat="M_Plank", bevel=0.02,
                   segs=1)
        if rope:
            for side in (-1, 1):
                for end in (a, b):
                    q = end + nrm * side * (width / 2 + 0.1)
                    mb.cyl(0.12, 1.3, loc=(q.x, q.y, q.z - 0.3), mat="M_Wood_Dark", verts=8)
                prev = None
                for i in range(n + 1):
                    t = i / n
                    p = a.lerp(b, t) + nrm * side * (width / 2 + 0.1)
                    p.z += 0.95 - math.sin(math.pi * t) * (sag + 0.15)
                    if prev is not None:
                        seg = p - prev
                        mid = (p + prev) / 2
                        sl = seg.length
                        pitch = math.degrees(math.atan2(seg.z, Vector((seg.x, seg.y)).length))
                        mb.box((sl + 0.02, 0.06, 0.06), loc=mid, rot=(0, -pitch, yaw), mat="M_Rope")
                    prev = p
        obj = mb.build(self._name(name), self.col_terrain, smooth=False)
        self.ground.add(obj)
        return obj

    def ladder(self, name, x, y, z0, z1, facing=0.0, kind="ladder", descend_only=False):
        """Ladder or knotted rope from local height z0 to z1 at (x, y).

        facing: yaw (deg, local) of the direction a climber faces (toward the wall).
        Default 0 = facing local +X... use 90 for a wall at +Y (most common).
        """
        p = self.w(x, y, z0)
        h = z1 - z0
        yaw = math.radians(self.wyaw(facing))
        mb = geo.MeshBuilder()
        if kind == "ladder":
            fx, fy = math.cos(yaw), math.sin(yaw)
            sx, sy = -fy, fx
            for side in (-1, 1):
                q = Vector((p.x + sx * side * 0.38, p.y + sy * side * 0.38, p.z))
                mb.box((0.12, 0.12, h + 0.6), loc=(q.x, q.y, p.z + (h + 0.6) / 2), rot=(0, 0, math.degrees(yaw)),
                       mat="M_Wood", bevel=0.03, segs=1)
            k = 0
            z = 0.3
            while z < h + 0.4:
                mb.box((0.08, 0.8, 0.08), loc=(p.x, p.y, p.z + z), rot=(0, 0, math.degrees(yaw)), mat="M_Wood_Dark")
                z += 0.38
                k += 1
        outline = []
        if kind != "ladder":  # knotted rope tied to a stake on the cap (or a leafy vine), hung plumb down the face
            vine = kind == "vine" or bool(descend_only)
            outline = self._hanging_strand(mb, x, y, z0, z1, facing, vine, descend_only)
            # traversal reads a climbable's position from its bounding-box centre: two loose (never rendered)
            # vertices mirror the off-centre strand/stake so that centre stays exactly at (x, y)
            w0 = self.w(x, y)
            vs = [v.co for v in mb.bm.verts]
            lo_x, hi_x = min(v.x for v in vs), max(v.x for v in vs)
            lo_y, hi_y = min(v.y for v in vs), max(v.y for v in vs)
            zm = (min(v.z for v in vs) + max(v.z for v in vs)) / 2
            mb.bm.verts.new((2 * w0.x - hi_x, 2 * w0.y - hi_y, zm))
            mb.bm.verts.new((2 * w0.x - lo_x, 2 * w0.y - lo_y, zm))
        if outline:
            # ink line: an inverted hull (built as geometry, not a SOLIDIFY modifier, so the bounding box - the
            # climb position - is the same evaluated or not): consistent normals first, then turn the shell inside out
            bmesh.ops.recalc_face_normals(mb.bm, faces=list(mb.bm.faces))
            for f in outline:
                f.normal_flip()
        obj = mb.build(self._name(name), self.col_arch, smooth=kind != "ladder", sharp_angle=60,
                       recalc_normals=not outline)
        obj["climbable"] = kind
        obj["climb_z0"] = self.origin.z + z0
        obj["climb_z1"] = self.origin.z + z1
        obj["descend_only"] = bool(descend_only)  # e.g. vines hanging into a pit: no foot landing required
        return obj

    def _climb_lip(self, x, y, z1, facing):
        """Find the upper cap beside a hanging rope: (dir, t_lip, t_stake, z_stake) in local coords, or None.

        The inward direction is the mean of the probe directions that land on the cap 0.7 m out (so a rope
        under a straight lip drapes straight back, whatever `facing` says); farther caps are found by
        marching out up to 2 m, the facing direction first."""

        def on_cap(t, d):
            g = self.ground_z(x + d[0] * t, y + d[1] * t, z_from=z1 + 0.6)
            return g is not None and abs(g - z1) < 0.25

        sx = sy = 0.0
        for k in range(16):
            a = math.radians(facing + 22.5 * k)
            if on_cap(0.7, (math.cos(a), math.sin(a))):
                sx += math.cos(a)
                sy += math.sin(a)
        d = None
        if math.hypot(sx, sy) > 0.5:
            d = (sx / math.hypot(sx, sy), sy / math.hypot(sx, sy))
        else:
            for t in [0.05 * i for i in range(1, 41)]:
                for da in (0, 45, -45, 90, -90, 135, -135, 180):
                    a = math.radians(facing + da)
                    if on_cap(t, (math.cos(a), math.sin(a))):
                        d = (math.cos(a), math.sin(a))
                        break
                if d is not None:
                    break
        if d is None:
            return None
        t_lip = next((t for t in [0.05 * i for i in range(0, 41)] if on_cap(t, d)), None)
        if t_lip is None:
            return None
        for back in (0.55, 0.45, 0.35, 0.25):
            ts = t_lip + back
            g = self.ground_z(x + d[0] * ts, y + d[1] * ts, z_from=z1 + 0.6)
            if g is not None and abs(g - z1) < 0.3:
                return d, t_lip, ts, g
        return d, t_lip, None, z1

    @staticmethod
    def _smooth3(pts, iterations=2):
        """Open-polyline Chaikin smoothing in 3D (keeps both end points)."""
        pts = [Vector(p) for p in pts]
        for _ in range(iterations):
            out = [pts[0]]
            for a, b in zip(pts, pts[1:]):
                out += [a.lerp(b, 0.25), a.lerp(b, 0.75)]
            out.append(pts[-1])
            pts = out
        return pts

    def _face_bvh(self, x, y, reach, z0, z1):
        """BVH (world) of the solid terrain/architecture meshes near local (x, y): terrace bodies and caps, stairs,
        decks, embedded cliff stones - no grass fringes, ribbons' flat tops still included, no climbables."""
        w0 = self.w(x, y)
        zlo, zhi = self.origin.z + z0 - 0.5, self.origin.z + z1 + 1.0
        verts, polys = [], []

        def add(me, mw):
            off = len(verts)
            verts.extend(mw @ v.co for v in me.vertices)
            polys.extend([off + i for i in p.vertices] for p in me.polygons)

        def near(cs):
            return (min(c.x for c in cs) <= w0.x + reach and max(c.x for c in cs) >= w0.x - reach and
                    min(c.y for c in cs) <= w0.y + reach and max(c.y for c in cs) >= w0.y - reach and
                    min(c.z for c in cs) <= zhi and max(c.z for c in cs) >= zlo)

        for coll in (self.col_terrain, self.col_arch):
            for ob in coll.objects:
                if "climbable" in ob.keys() or "_Fringe" in ob.name:
                    continue
                mw = core.GroundIndex.object_world_matrix(ob)
                if ob.type == "MESH":
                    if near([mw @ Vector(c) for c in ob.bound_box]):
                        add(ob.data, mw)
                elif ob.instance_type == "COLLECTION" and ob.instance_collection is not None:
                    for src in ob.instance_collection.all_objects:
                        if src.type == "MESH":
                            sm = mw @ src.matrix_basis
                            if near([sm @ Vector(c) for c in src.bound_box]):
                                add(src.data, sm)
        return BVHTree.FromPolygons(verts, polys) if polys else None

    def _hit(self, bvh, x, y, z, d, dist):
        """Distance along local horizontal direction d from local (x, y, z) to the first front-facing surface."""
        if bvh is None:
            return None
        o = self.w(x, y, z)
        dw = self.w(x + d[0], y + d[1]) - self.w(x, y)
        dw = Vector((dw.x, dw.y, 0.0)).normalized()
        hit = bvh.ray_cast(o, dw, dist)
        if hit[0] is None or hit[1].dot(dw) > 0:
            return None
        return hit[3]

    def _hanging_strand(self, mb, x, y, z0, z1, facing, vine, descend_only):
        """Geometry of a climbable rope or vine (local x, y, z0..z1) into MeshBuilder mb (world coords).

        Rope: a chunky plumb hemp strand with darker knot bands every ~0.4 m, hung within ~0.13 m of the cliff face
        below the upper cap's lip (found by horizontal probes toward the cap); it ends at the lip edge in a dark
        whipping knot (nothing curls up and over the lip) and a flat peg sits on the cap just behind the lip. Vine: a twisted green strand with leaf
        clusters, hung the same way from a leafy clump on the cap. The climb position the validator reads is still
        (x, y): ladder() mirrors the bounding box. Returns the ink-outline faces (ropes) for ladder() to flip."""
        fa = math.radians(facing)
        fl = (math.cos(fa), math.sin(fa))      # local direction toward the wall (when no cap is found)
        sl = (-fl[1], fl[0])                   # local sideways
        wyaw = self.wyaw(facing)
        rope_mat, rr = ("M_Flat_leaf_dk", 0.045) if vine else ("M_Rope", 0.11)
        band_mat = "M_Wood_Dark"   # knot bands (maps that recolour ropes swap M_Rope / M_Wood_Dark by name)
        r = core.rng(self.slug, x, y, "strand")
        anchor = self._climb_lip(x, y, z1, facing)
        outline = []

        def W(t, z, d, lat=0.0):  # local point t along d from (x, y), lat sideways, at height z -> world
            return self.w(x + d[0] * t + sl[0] * lat, y + d[1] * t + sl[1] * lat, z)

        if anchor is None:
            d = fl
            sl = (-d[1], d[0])
            s, foot, z_top = 0.0, z0, z1 + 0.25
            path = [W(0.0, z0 + rr + (z_top - z0 - rr) * i / 12, d) for i in range(13)]
            col_top = z_top
            lip_info = None
        else:
            d, t_lip, ts, gs = anchor
            sl = (-d[1], d[0])
            reach = t_lip + 1.6
            bvh = self._face_bvh(x, y, reach, z0, z1)
            # the face below the lip: the most protruding of several horizontal probes toward the cap
            hs = []
            zz = z0 + 0.3
            while zz < z1 - 0.55:
                hs.append(zz)
                zz += 0.3
            if not hs:
                hs = [(z0 + z1) / 2 - 0.1]
            face = [self._hit(bvh, x - d[0] * 0.05, y - d[1] * 0.05, h, d, reach) for h in hs]
            face = [f - 0.05 for f in face if f is not None]
            face_t = min(face) if face else None
            # the outer edge of the cap lip (rounded slab: probe its thickness)
            lips = [self._hit(bvh, x - d[0] * 0.05, y - d[1] * 0.05, z1 - dz, d, reach) for dz in (0.06, 0.15, 0.24)]
            lips = [v - 0.05 for v in lips if v is not None]
            lip_t = min([t_lip] + lips)
            # strand: plumb, its surface ~4.5 cm off the face (centre <= 0.12 m from it for the rope)
            s = 0.0
            if face_t is not None:
                s = max(-0.4, face_t - (rr + 0.045))
            zf_from = min(0.6, max(0.15, (z1 - z0) * 0.4))
            foot = None
            for k in (1.0, 0.6, 0.3, 0.0):
                g = self.ground_z(x + d[0] * s * k, y + d[1] * s * k, z_from=z0 + zf_from)
                if g is not None and abs(g - z0) <= 0.35:
                    s, foot = s * k, g
                    break
            if foot is None:
                s, foot = 0.0, z0
            # the underside of the cap overhang above the strand (if the strand hangs under the lip)
            # does the strand hang under the cap's overhang? (an upward probe meets the cap underside and the cap top
            # is right above it). Then the strand runs up into the cap slab (hidden) and the visible rope comes over
            # the lip edge - no hook out and around the lip; in front of the lip it rises to the edge and drapes over
            tucked = False
            if bvh is not None and s > lip_t - rr:
                up = bvh.ray_cast(W(s, foot + 0.3, d), Vector((0.0, 0.0, 1.0)), z1 + 0.5 - foot)
                top_here = self.ground_z(x + d[0] * s, y + d[1] * s, z_from=z1 + 0.6)
                tucked = (up[0] is not None and z1 - 0.8 < up[0].z - self.origin.z < z1 + 0.05 and
                          top_here is not None and abs(top_here - z1) < 0.3)
            col_top = max(z1 - (0.25 if tucked else 0.14), foot + 0.3)
            n = max(4, int(math.ceil((col_top - foot) / 0.25)))
            path = [W(s, foot + rr + (col_top - foot - rr) * i / n, d) for i in range(n + 1)]
            lip_info = (d, t_lip, ts, gs, lip_t, tucked)
        # ----- over the lip and onto the cap
        cap_pts = []
        if lip_info is not None:
            d, t_lip, ts, gs, lip_t, tucked = lip_info
            lip_g = self.ground_z(x + d[0] * (lip_t + 0.08), y + d[1] * (lip_t + 0.08), z_from=z1 + 0.6)
            lip_g = z1 if lip_g is None or abs(lip_g - z1) > 0.3 else lip_g
            cap_t = ts if ts is not None else lip_t + 0.3
            g_mid = self.ground_z(x + d[0] * (lip_t + cap_t) / 2, y + d[1] * (lip_t + cap_t) / 2, z_from=z1 + 0.6)
            g_mid = lip_g if g_mid is None or abs(g_mid - z1) > 0.3 else g_mid
            lat = r.uniform(-0.05, 0.05)
            bend = []
            if not tucked:  # rises in front of the lip: up to the edge, then over it
                bend.append(W(min(s, lip_t - rr * 0.5) + 0.01, z1 - 0.04, d))
            bend.append(W(lip_t + 0.03, lip_g + rr * 0.9, d))
            bend.append(W((lip_t + cap_t) / 2, g_mid + rr * 0.9, d, lat))
            if vine:
                bend.append(W(cap_t + 0.05, gs + 0.12, d))
            elif ts is not None:
                bend.append(W(cap_t - 0.07, gs + 0.11, d))
            else:
                bend.append(W(cap_t, gs + rr * 0.9, d))
            if vine:
                keep = max(1, len(path) - 2)
                smooth = self._smooth3(path[keep - 1:] + bend, 3)
                full = path[:keep - 1] + smooth
            else:  # rope: plumb all the way, ending at the lip edge (nothing curls up and over it)
                full = path + ([] if tucked else [W(min(s, lip_t - rr * 0.5) + 0.01, z1 - 0.04, d)])
            cap_pts = bend
        else:
            full = path
        # ----- the strand
        if vine:
            mb.tube(full, rr, mat=rope_mat, sides=8, caps=True)
            helix = []
            m_ = len(full)
            for i in range(m_):
                a = 2 * math.pi * i * 0.35
                c = full[i]
                helix.append(c + Vector((math.cos(a) * 0.05, math.sin(a) * 0.05, 0.0)))
            mb.tube(helix, 0.026, mat=rope_mat, sides=6, caps=True)
            # leaf clusters alternating left/right up the hanging part
            base = path[0]
            top_z = path[-1].z
            dwx, dwy = (self.w(x + sl[0], y + sl[1]) - self.w(x, y)).xy
            fwx, fwy = (self.w(x + d[0], y + d[1]) - self.w(x, y)).xy
            z, k = 0.18, 0
            while base.z + z < top_z - 0.05:
                side = 1 if k % 2 else -1
                for j in range(2 if k % 3 == 0 else 1):
                    lr = r.uniform(0.11, 0.16) * (1.25 if j else 1.0)
                    off = 0.1 + 0.06 * j
                    q = Vector((base.x + dwx * side * off - fwx * 0.03, base.y + dwy * side * off - fwy * 0.03,
                                base.z + z + (0.07 if j else 0.0)))
                    mb.sphere(lr, loc=q, scale=(1.15, 0.55, 0.8), rot=(0, r.uniform(-25, 25), wyaw + 90 * side),
                              mat="M_Leaf", subdiv=1, lumpy=0.15, seed=k * 3 + j)
                z += 0.3 + r.uniform(-0.04, 0.04)
                k += 1
            mb.sphere(0.13, loc=path[0], scale=(0.9, 0.9, 1.2), mat="M_Leaf", subdiv=1, lumpy=0.2, seed=7)
            if lip_info is not None:
                d, t_lip, ts, gs, lip_t, _tucked = lip_info
                cap_t = ts if ts is not None else lip_t + 0.3
                for j, (ox, oy, rad) in enumerate(((0.0, 0.0, 0.3), (0.2, 0.16, 0.22), (-0.18, 0.12, 0.2),
                                                   (0.06, -0.2, 0.18))):
                    mb.sphere(rad, loc=W(cap_t + 0.12 + oy, gs + rad * 0.45, d, ox), scale=(1.0, 1.0, 0.75),
                              mat="M_Leaf", subdiv=2, lumpy=0.25, seed=11 + j, flatten_bottom=0.4)
                for j, p in enumerate(cap_pts[-4:-1]):  # a few leaves along the draped part
                    mb.sphere(0.12, loc=p + Vector((0.0, 0.0, 0.03)), scale=(1.15, 0.55, 0.7), rot=(0, 0, wyaw + 90),
                              mat="M_Leaf", subdiv=1, lumpy=0.15, seed=21 + j)
            return outline
        mb.tube(full, rr, mat=rope_mat, sides=8, caps=True)
        outline += mb.tube(full, rr + 0.016, mat="M_Outline", sides=8, caps=True)
        # darker knot bands every ~0.4 m up the plumb part
        base = path[0]
        z = 0.32
        while base.z + z < path[-1].z - 0.12:
            mb.cyl(rr * 1.32, 0.075, loc=(base.x, base.y, base.z + z - 0.0375), mat=band_mat, verts=8)
            z += 0.4
        # a dark whipping knot where the rope ends at the lip
        top = full[-1]
        mb.cyl(rr * 1.5, 0.12, loc=(top.x, top.y, top.z - 0.1), mat=band_mat, verts=8)
        if lip_info is not None:
            d, t_lip, ts, gs, lip_t, _tucked = lip_info
            # a flat peg just behind the lip (no more than ~0.1 m proud of the cap): the rope reads as tied, not posted
            peg_t = (ts if ts is not None else lip_t + 0.3)
            pg = self.ground_z(x + d[0] * peg_t, y + d[1] * peg_t, z_from=z1 + 0.6)
            pg = z1 if pg is None or abs(pg - z1) > 0.3 else pg
            mb.cyl(0.07, 0.11, loc=self.w(x + d[0] * peg_t, y + d[1] * peg_t, pg - 0.03), mat="M_Wood_Dark", verts=8)
        return outline

    def path(self, name, pts, width=2.6, mat="M_Path_Dirt", **kw):
        return geo.path_ribbon(self._name(name), self.wpoly(pts), width, self.col_terrain, self.ground, mat=mat,
                               **kw)

    def water(self, name, outline, level, foam=True):
        objs = [geo.flat_poly(self._name(name), self.wpoly(outline), self.origin.z + level, self.col_terrain,
                              "M_Water")]
        if foam:
            objs.append(geo.foam_ring(self._name(name + "_Foam"), self.wpoly(outline), self.origin.z + level + 0.02,
                                      -0.5, self.col_terrain))
        return objs

    def room(self, x0, y0, x1, y1, wall_h=4.2, floor_mat="M_Plank", wall_mat="M_Plaster", trim_mat="M_Wood_Dark",
             windows=(), back_door=None, floor_z=0.0, thickness=0.35, beams=True):
        """Cutaway interior room (floor + back wall at y1 + side walls at x0/x1, open toward the camera).

        windows: list of (wall, center, z_center, width, height) with wall in {"back", "left", "right"}.
        back_door: (x_center, width, height) cut into the back wall (visual only).
        Returns the floor object (walkable).
        """
        mb = geo.MeshBuilder()
        z = self.origin.z + floor_z
        # floor slab (walkable)
        floor = geo.MeshBuilder()
        floor.prism(self.wpoly(geo.rect(x0, y0, x1, y1)), z - 0.5, z, mat=floor_mat, bevel=0.05, segs=1)
        fobj = floor.build(self._name("Room_Floor"), self.col_terrain, smooth=False)
        self.ground.add(fobj)

        def wall(name, a, b):
            (ax, ay), (bx, by) = a, b
            import math as _m
            L = _m.hypot(bx - ax, by - ay)
            yaw = _m.degrees(_m.atan2(by - ay, bx - ax))
            # split the wall around openings along its length
            ops = [w for w in windows if w[0] == name]
            if name == "back" and back_door:
                ops = ops + [("back", back_door[0], back_door[2] / 2, back_door[1], back_door[2])]
            cuts = sorted((c - x0 if name == "back" else c - y0, wdt, zc, hgt) for (_w, c, zc, wdt, hgt) in ops)
            segs = []
            t = 0.0
            for c, wdt, zc, hgt in cuts:
                segs.append((t, c - wdt / 2, 0.0, wall_h))
                if zc - hgt / 2 > 0.01:
                    segs.append((c - wdt / 2, c + wdt / 2, 0.0, zc - hgt / 2))
                segs.append((c - wdt / 2, c + wdt / 2, zc + hgt / 2, wall_h))
                t = c + wdt / 2
            segs.append((t, L, 0.0, wall_h))
            for (s0, s1, h0, h1) in segs:
                if s1 - s0 < 0.02 or h1 - h0 < 0.02:
                    continue
                mid = (s0 + s1) / 2
                px = ax + (bx - ax) * mid / L
                py = ay + (by - ay) * mid / L
                w = self.w(px, py, floor_z + (h0 + h1) / 2)
                mb.box((s1 - s0, thickness, h1 - h0), loc=w, rot=(0, 0, self.wyaw(yaw)), mat=wall_mat)
            # trim along the top and bottom
            for zz in (0.12, wall_h - 0.1):
                mid = 0.5
                w = self.w(ax + (bx - ax) * mid, ay + (by - ay) * mid, floor_z + zz)
                mb.box((L + 0.1, thickness + 0.12, 0.22), loc=w, rot=(0, 0, self.wyaw(yaw)), mat=trim_mat)
            for (_w, c, zc, wdt, hgt) in [w for w in windows if w[0] == name]:
                off = c - (x0 if name == "back" else y0)
                px = ax + (bx - ax) * off / L
                py = ay + (by - ay) * off / L
                w = self.w(px, py, floor_z + zc)
                mb.box((wdt, thickness * 0.3, hgt), loc=w, rot=(0, 0, self.wyaw(yaw)), mat="M_Window")
                mb.box((wdt + 0.25, thickness + 0.1, 0.12), loc=self.w(px, py, floor_z + zc - hgt / 2), rot=(0, 0, self.wyaw(yaw)),
                       mat=trim_mat)

        wall("back", (x0, y1), (x1, y1))
        wall("left", (x0, y0), (x0, y1))
        wall("right", (x1, y0), (x1, y1))
        if beams:
            for k in range(1, 4):
                bx = x0 + (x1 - x0) * k / 4
                w = self.w(bx, (y0 + y1) / 2 + (y1 - y0) * 0.25, floor_z + wall_h - 0.2)
                mb.box((0.3, (y1 - y0) * 0.5, 0.3), loc=w, rot=(0, 0, self.wyaw(0)), mat=trim_mat)
        mb.build(self._name("Room_Walls"), self.col_arch, smooth=False)
        return fobj

    # ------------------------------------------------------------------
    # dressing
    # ------------------------------------------------------------------
    def ground_z(self, x, y, z_from=None):
        wv = self.w(x, y)
        zf = 400.0 if z_from is None else self.origin.z + z_from
        z, _n = self.ground.raycast_down(wv.x, wv.y, z_from=zf)
        return None if z is None else z - self.origin.z

    def place(self, asset_name, x, y, rot=0.0, scale=1.0, z=None, name=None, collection=None, z_from=None,
              sink=0.04, tilt=(0.0, 0.0), required=True):
        """Instance an asset at local (x, y). z is found by raycast unless given (local)."""
        if z is None:
            z = self.ground_z(x, y, z_from=z_from)
            if z is None:
                if required:
                    raise ValueError(f"[{self.slug}] place('{asset_name}', {x:.1f}, {y:.1f}): no ground under point")
                return None
            z -= sink
        coll = collection or self._default_collection(asset_name)
        wv = self.w(x, y, z)
        fp = kit.REGISTRY.get(asset_name, {}).get("footprint", 1.0)
        if fp >= 1.0 and kit.REGISTRY.get(asset_name, {}).get("category") not in ("Markers", "Monsters", "Characters"):
            sc = max(scale) if isinstance(scale, (tuple, list)) else scale
            self.prop_zones.append((x, y, fp * 0.5 * sc))
        return kit.instance(asset_name, coll, (wv.x, wv.y, wv.z), rot_z=self.wyaw(rot), scale=scale,
                            obj_name=self._name(name or asset_name), tilt=tilt)

    def _default_collection(self, asset_name):
        cat = kit.REGISTRY.get(asset_name, {}).get("category", "Props")
        if cat == "Architecture":
            return self.col_arch
        if cat in ("Trees", "Foliage"):
            return self.col_veg
        return self.col_props

    def scatter(self, assets, area, count, seed=0, min_dist=1.5, scale=(0.85, 1.15), avoid=(), rot=None,
                max_slope=0.85, collection=None, z_band=None, avoid_props=True):
        """Scatter assets in a local polygon (or (cx, cy, r) circle), skipping no-ground and avoid zones.

        avoid: list of polygons or (cx, cy, r) circles (local). z_band: (zmin, zmax) local height filter.
        """
        r = core.rng(self.slug, seed, str(assets))
        if isinstance(area, tuple) and len(area) == 3 and not isinstance(area[0], tuple):
            cx, cy, rad = area
            poly = geo.ellipse(cx, cy, rad, rad, 20)
        else:
            poly = area
        x0, y0, x1, y1 = geo.poly_bbox(poly)
        placed = []
        tries = 0
        assets = list(assets) if isinstance(assets, (list, tuple)) else [assets]
        while len(placed) < count and tries < count * 40:
            tries += 1
            x = r.uniform(x0, x1)
            y = r.uniform(y0, y1)
            if not geo.point_in_poly(x, y, poly):
                continue
            if any(_in_zone(x, y, a) for a in avoid):
                continue
            if avoid_props and any((x - px) ** 2 + (y - py) ** 2 < (pr + 0.35) ** 2 for px, py, pr in self.prop_zones):
                continue
            if any((x - px) ** 2 + (y - py) ** 2 < min_dist ** 2 for px, py in placed):
                continue
            wv = self.w(x, y)
            z, nrm = self.ground.raycast_down(wv.x, wv.y)
            if z is None or (nrm is not None and nrm.z < max_slope):
                continue
            zl = z - self.origin.z
            if z_band and not (z_band[0] <= zl <= z_band[1]):
                continue
            a = r.choice(assets)
            s = r.uniform(*scale)
            rr = r.uniform(0, 360) if rot is None else rot
            ob = self.place(a, x, y, rot=rr, scale=s, z=zl - 0.04, collection=collection)
            if ob is not None:
                ob["scattered"] = True  # only scattered clutter may be auto-cleared from routes
            placed.append((x, y))
        return placed

    def row(self, asset_name, p0, p1, spacing, rot=None, jitter=0.0, seed=0, scale=1.0):
        """Place assets along a local line (fences use rot = line direction)."""
        a = Vector(p0)
        b = Vector(p1)
        d = b - a
        L = d.length
        n = max(1, int(L // spacing))
        ang = math.degrees(math.atan2(d.y, d.x)) if rot is None else rot
        r = core.rng(self.slug, seed, asset_name)
        out = []
        for i in range(n + (0 if rot is None and asset_name.startswith("Fence") else 1)):
            p = a.lerp(b, i / n) if n else a
            out.append(self.place(asset_name, p.x + r.uniform(-jitter, jitter), p.y + r.uniform(-jitter, jitter),
                                  rot=ang, scale=scale, required=False))
        return out

    def fence(self, pts, asset_name="Fence_Wood_Seg"):
        out = []
        for i in range(len(pts) - 1):
            a = Vector(pts[i])
            b = Vector(pts[i + 1])
            d = b - a
            L = d.length
            n = max(1, int(round(L / 2.0)))
            ang = math.degrees(math.atan2(d.y, d.x))
            for k in range(n):
                p = a.lerp(b, k / n)
                sc = (L / n) / 2.0
                out.append(self.place(asset_name, p.x, p.y, rot=ang, scale=(sc, 1, 1), required=False))
        return out

    # ------------------------------------------------------------------
    # gameplay
    # ------------------------------------------------------------------
    def portal(self, name, x, y, to_map, to_portal, kind="edge", rot=0.0, z=None):
        """An exit. kind: edge (map transition), door (building interior), inner (in-map portal)."""
        arrival_only = (self.map_id, name) in LY.ONE_WAY
        asset_name = "Portal_Door" if kind == "door" else ("Portal_Arrival" if arrival_only else "Portal_Swirl")
        obj = self.place(asset_name, x, y, rot=rot, z=z, name=f"Portal_{name}", collection=self.col_portals,
                         sink=0.0)
        obj["map_id"] = self.map_id
        obj["portal_name"] = name
        obj["to_map"] = to_map
        obj["to_portal"] = to_portal
        obj["portal_kind"] = kind
        obj["one_way_arrival"] = arrival_only
        lz = obj.location.z - self.origin.z
        self.portals.append({"name": name, "x": x, "y": y, "z": lz, "to_map": to_map, "to_portal": to_portal,
                             "kind": kind, "world": list(obj.location)})
        return obj

    def npc(self, npc_name, x, y, rot=0.0, npc_id=None, role="", **override):
        """Place an NPC proxy. Appearance comes from misostory/npcs.py (override with chibi kwargs)."""
        from . import npcs
        spec = npcs.spec(npc_name) if npc_name in npcs.NPCS else {}
        spec.update(override)
        if npc_name in npcs.NPCS:
            nid, nrole = npcs.info(npc_name)
            npc_id = npc_id or nid
            role = role or nrole
        asset_name = register_npc(npc_name.replace(" ", ""), **spec)
        obj = self.place(asset_name, x, y, rot=rot, name=f"NPC_{npc_name.replace(' ', '')}",
                         collection=self.col_npcs, sink=0.0)
        obj["npc_name"] = npc_name
        obj["npc_id"] = npc_id or 0
        obj["role"] = role
        b = self.place("NPC_Beacon", x, y, z=obj.location.z - self.origin.z + 2.0, name=f"Beacon_{npc_name}",
                       collection=self.col_debug, rot=45)
        self.npcs.append({"name": npc_name, "x": x, "y": y, "id": npc_id})
        return obj

    def mobs(self, mob_name, area, count, seed=0, min_dist=2.2, avoid=(), z_band=None):
        """Spawn representative monster proxies in an area + debug spawn rings."""
        asset_name = MOB_ASSETS[mob_name]
        r = core.rng(self.slug, "mob", mob_name, seed)
        pts = self.scatter([asset_name], area, count, seed=seed, min_dist=min_dist, scale=(0.95, 1.05),
                           avoid=avoid, collection=self.col_mobs, z_band=z_band)
        for (x, y) in pts:
            self.place("Spawn_Ring", x, y, collection=self.col_debug, required=False, sink=-0.02,
                       scale=1.0 + r.uniform(0, 0.2))
        self.spawns.append({"mob": mob_name, "count": len(pts), "points": pts})
        return pts

    def player(self, x, y, rot=0.0):
        """The player scale reference (one per map). It must stand inside the Gameplay frame: see
        gameplay_frame_check() and the PLAYER_IN_FRAME line printed by scripts/build_map.py."""
        obj = self.place("Player_Proxy", x, y, rot=rot, name="Player_Proxy",
                         collection=core.get_collection("CHARACTER_PROXIES/Player"), sink=0.0)
        self._player = obj
        return obj

    def route(self, name, pts, z_from=None, one_way=False):
        """Declare a traversal route (local xy polyline), walked in both directions by the validator.

        one_way=True: the route is only walked forward (e.g. it includes a jump-down drop).
        """
        self.routes.append({"name": name, "pts": [list(p) for p in pts], "one_way": bool(one_way)})
        # debug ribbon
        wpts = []
        for x, y in geo.resample(pts, 0.8, closed=False):
            z = self.ground_z(x, y, z_from=z_from)
            wv = self.w(x, y, (z if z is not None else 0) + 0.12)
            wpts.append(wv)
        if len(wpts) >= 2:
            cu = bpy.data.curves.new(self._name(f"Route_{name}"), "CURVE")
            cu.dimensions = "3D"
            cu.bevel_depth = 0.08
            sp = cu.splines.new("POLY")
            sp.points.add(len(wpts) - 1)
            for p, v in zip(sp.points, wpts):
                p.co = (v.x, v.y, v.z, 1)
            ob = bpy.data.objects.new(core.unique_name(self._name(f"Route_{name}")), cu)
            cu.materials.append(M.get("M_Marker_Route"))
            self.col_debug.objects.link(ob)
        return wpts

    def label(self, text, x, y, z=6.0, size=3.0):
        cu = bpy.data.curves.new(self._name("Label"), "FONT")
        cu.body = text
        cu.size = size
        cu.align_x = "CENTER"
        cu.extrude = 0.08
        ob = bpy.data.objects.new(core.unique_name(self._name("Label")), cu)
        wv = self.w(x, y, z)
        ob.location = wv
        ob.rotation_euler = (math.radians(50), 0, math.radians(-45))
        cu.materials.append(M.get("M_Marker_NPC"))
        self.col_debug.objects.link(ob)
        return ob

    def cameras(self, focus=None, gameplay_scale=30.0, extra_height=10.0, overview_margin=1.04, overview_extra=None):
        """Create the overview + gameplay cameras for this map (one isometric camera language).

        overview_extra: optional list of local boxes (x0, y0, x1, y1) - or (x0, y0, x1, y1, z0, z1) - merged into
        the exterior Overview fit, for landmarks that overhang the footprint (a moored ship, a bowsprit). Without
        z0/z1 the box spans the height of the map geometry overlapping it. build.py passes the map module's
        OVERVIEW_EXTRA constant here when it defines one.
        """
        L, D = self.size
        zs = []
        for o in self.ground.objects:
            zs += [(o.matrix_world @ Vector(c)).z for c in o.bound_box]
        zmax = (max(zs) - self.origin.z) if zs else 6.0
        ztop = min(zmax + extra_height, 40)
        pts = [self.w(x, y, z) for x in (0, L) for y in (0, D) for z in (0, ztop)]
        margin = overview_margin
        if self.meta.get("kind") == "interior":
            # interiors: frame the room itself (its built bounding box) + 15 %, not footprint + sky headroom
            room = self._built_bbox_points((self.col_terrain, self.col_arch))
            if room:
                pts, margin = room, 1.15
        elif overview_extra:
            pts += self._overview_extra_points(overview_extra, ztop)
        cam = scene_setup.make_camera(f"CAM_{self.slug}_Overview", self.col_cams)
        scene_setup.fit_camera(cam, pts, margin=margin)
        fx, fy = focus if focus else (L * 0.5, D * 0.4)
        fz = self.ground_z(fx, fy) or 0.0
        cam2 = scene_setup.make_camera(f"CAM_{self.slug}_Gameplay", self.col_cams, target=self.w(fx, fy, fz + 1.0),
                                       ortho_scale=gameplay_scale)
        self._gameplay = (fx, fy, gameplay_scale)
        return cam, cam2

    def _local(self, v):
        """World Vector -> local (x, y, z)."""
        dx, dy = v.x - self.origin.x, v.y - self.origin.y
        return (dx * self._c + dy * self._s, -dx * self._s + dy * self._c, v.z - self.origin.z)

    def _world_bboxes(self, colls):
        """World-space bounding-box corners (8 Vectors) of every mesh and collection instance in colls."""
        out = []
        for coll in colls:
            for ob in coll.all_objects:
                mw = core.GroundIndex.object_world_matrix(ob)
                if ob.type == "MESH":
                    out.append([mw @ Vector(c) for c in ob.bound_box])
                elif ob.instance_type == "COLLECTION" and ob.instance_collection is not None:
                    cs = []
                    for src in ob.instance_collection.all_objects:
                        if src.type == "MESH":
                            sm = mw @ core.GroundIndex.object_world_matrix(src)
                            cs += [sm @ Vector(c) for c in src.bound_box]
                    if cs:
                        out.append(cs)
        return out

    def _overview_extra_points(self, boxes, ztop):
        """World fit points for overview_extra boxes (see cameras)."""
        pts = []
        boxes = list(boxes)
        geo_boxes = []
        if any(len(b) == 4 for b in boxes):
            for cs in self._world_bboxes((self.col_terrain, self.col_arch, self.col_props, self.col_veg)):
                loc = [self._local(c) for c in cs]
                geo_boxes.append((min(p[0] for p in loc), min(p[1] for p in loc), max(p[0] for p in loc),
                                  max(p[1] for p in loc), min(p[2] for p in loc), max(p[2] for p in loc)))
        for b in boxes:
            if len(b) == 6:
                x0, y0, x1, y1, z0, z1 = b
            elif len(b) == 4:
                x0, y0, x1, y1 = b
                zz = [(g[4], g[5]) for g in geo_boxes
                      if g[0] <= max(x0, x1) and g[2] >= min(x0, x1) and g[1] <= max(y0, y1) and g[3] >= min(y0, y1)]
                z0 = min([z[0] for z in zz] + [0.0])
                z1 = min(max([z[1] for z in zz] + [4.0]), ztop)
            else:
                raise ValueError(f"[{self.slug}] OVERVIEW_EXTRA box {b!r}: use (x0, y0, x1, y1) or "
                                 f"(x0, y0, x1, y1, z0, z1)")
            pts += [self.w(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
        return pts

    def gameplay_frame_check(self):
        """Are the scale references inside the representative Gameplay render?

        Projects the Player_Proxy (m.player; its origin, i.e. the feet) and the mob proxies (m.mobs) through
        CAM_<slug>_Gameplay with bpy_extras.object_utils.world_to_camera_view at the scene's render resolution
        (16:9 in every build path). Rule: exterior maps need a Player_Proxy with FRAME_BAND[0] <= u, v <=
        FRAME_BAND[1] and z > 0 (in front of the camera); maps of kind "hunting" also need at least
        FRAME_MOBS_HUNTING mob proxies inside 0..1; interiors report the player but never fail on it.
        Returns {"ok", "player", "player_uv", "mobs_in_frame", "mobs_required", "issues", ...}. build.py stores
        it in build_report maps.<id>.gameplay_frame; scripts/build_map.py prints it as PLAYER_IN_FRAME.
        """
        from bpy_extras.object_utils import world_to_camera_view
        kind = self.meta.get("kind", "field")
        interior = kind == "interior"
        need_mobs = FRAME_MOBS_HUNTING if kind == "hunting" else 0
        cam_name = f"CAM_{self.slug}_Gameplay"
        out = {"ok": True, "player": False, "player_uv": None, "mobs_in_frame": 0, "mobs_required": need_mobs,
               "issues": [], "camera": cam_name, "kind": kind, "player_local": None, "mobs_total": 0,
               "focus": None if self._gameplay is None else [round(self._gameplay[0], 2),
                                                             round(self._gameplay[1], 2)],
               "scale": None if self._gameplay is None else self._gameplay[2]}
        cam = bpy.data.objects.get(cam_name)
        if cam is None:
            out["ok"] = False
            out["issues"].append(f"no {cam_name} camera (MapCtx.cameras() was not run)")
            return out
        scn = bpy.context.scene
        # a camera created during this build has a stale matrix_world (no depsgraph update yet): set it from its
        # location/rotation so world_to_camera_view projects through the real view
        cam.matrix_world = core.GroundIndex.object_world_matrix(cam)

        def project(ob):
            v = world_to_camera_view(scn, cam, core.GroundIndex.object_world_matrix(ob).translation)
            return v.x, v.y, v.z

        player = self._player
        try:
            if player is not None and bpy.data.objects.get(player.name) is not player:
                player = None
        except ReferenceError:
            player = None
        if player is None:  # placed some other way (m.place("Player_Proxy", ...))
            coll = bpy.data.collections.get("Player")
            cands = [o for o in (coll.all_objects if coll else bpy.data.objects)
                     if o.get("asset") == "Player_Proxy" and o.name.startswith(f"{self.slug}_")]
            player = cands[0] if cands else None
        lo, hi = FRAME_BAND
        hint = ""
        if self._gameplay is not None:
            hint = (f"; move m.player onto a route point near GAMEPLAY_FOCUS ({self._gameplay[0]:.1f}, "
                    f"{self._gameplay[1]:.1f}) or shift GAMEPLAY_FOCUS/GAMEPLAY_SCALE")
        if player is None:
            if not interior:
                out["ok"] = False
                out["issues"].append("no Player_Proxy: call m.player(x, y, rot) once" + hint)
        else:
            u, v, z = project(player)
            lx, ly, _lz = self._local(core.GroundIndex.object_world_matrix(player).translation)
            out["player_uv"] = [round(u, 3), round(v, 3)]
            out["player_local"] = [round(lx, 2), round(ly, 2)]
            out["player"] = bool(lo <= u <= hi and lo <= v <= hi and z > 0)
            if not out["player"] and not interior:
                out["ok"] = False
                out["issues"].append(f"Player_Proxy at local ({lx:.1f}, {ly:.1f}) projects to u={u:.2f} v={v:.2f} in "
                                     f"{cam_name}; it must be inside {lo}..{hi} on both axes" + hint)
        mobs = [o for o in self.col_mobs.objects if o.instance_type == "COLLECTION"]
        out["mobs_total"] = len(mobs)
        n_in = 0
        for ob in mobs:
            u, v, z = project(ob)
            if 0.0 <= u <= 1.0 and 0.0 <= v <= 1.0 and z > 0:
                n_in += 1
        out["mobs_in_frame"] = n_in
        if n_in < need_mobs:
            out["ok"] = False
            out["issues"].append(f"only {n_in} of {len(mobs)} mob proxies inside {cam_name} (hunting maps need >= "
                                 f"{need_mobs}): aim GAMEPLAY_FOCUS at a spawn area or add m.mobs there")
        return out

    def _built_bbox_points(self, colls, per_object=1500):
        """World vertex positions of the mesh objects in colls (subsampled; no depsgraph needed).

        fit_camera projects them onto the view plane, so the frame hugs the built geometry (object
        bound_boxes overshoot on sliced domes and cut-away shells)."""
        pts = []
        for coll in colls:
            for ob in coll.all_objects:
                if ob.type != "MESH" or ob.get("collider") or ob.hide_render:
                    continue
                mw = core.GroundIndex.object_world_matrix(ob)
                vs = ob.data.vertices
                step = max(1, len(vs) // per_object)
                pts.extend(mw @ vs[i].co for i in range(0, len(vs), step))
        return pts

    def finalize(self):
        """Store metadata for validation/manifest generation."""
        self.col_map["portals_json"] = json.dumps(self.portals)
        self.col_map["routes_json"] = json.dumps(self.routes)
        self.col_map["npcs_json"] = json.dumps(self.npcs)
        self.col_map["spawns_json"] = json.dumps([{k: v for k, v in s.items() if k != "points"} for s in self.spawns])
        self.col_map["origin"] = list(self.origin)
        self.col_map["yaw"] = self.yaw
        self.col_map["size"] = list(self.size)


def _in_zone(x, y, zone):
    if isinstance(zone, tuple) and len(zone) == 3 and not isinstance(zone[0], tuple):
        cx, cy, r = zone
        return (x - cx) ** 2 + (y - cy) ** 2 < r * r
    return geo.point_in_poly(x, y, zone)
