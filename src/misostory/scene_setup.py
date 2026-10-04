"""Render settings, sky, sun and the isometric camera system."""

import math

import bpy
from mathutils import Vector

from . import core
from . import materials as M

# One camera language for the whole island.
ISO_PITCH = 40.0      # degrees below the horizon
ISO_YAW = -45.0       # camera looks toward world +X+Y (from the south-west)
CAM_DISTANCE = 400.0


def setup_render(res=(1920, 1080), samples=48, view="Standard", look="None"):
    scn = core.scene()
    scn.render.engine = "BLENDER_EEVEE"
    scn.render.resolution_x, scn.render.resolution_y = res
    scn.render.resolution_percentage = 100
    scn.render.film_transparent = False
    scn.eevee.taa_render_samples = samples
    scn.eevee.use_shadows = True
    scn.eevee.shadow_resolution_scale = 1.0
    scn.eevee.shadow_pool_size = "1024"
    scn.eevee.use_fast_gi = True
    scn.eevee.indirect_light_intensity = 0.55
    scn.eevee.use_raytracing = True
    try:
        scn.eevee.ray_tracing_options.resolution_scale = "2"
    except Exception:
        pass
    scn.view_settings.view_transform = view
    scn.view_settings.look = look
    scn.view_settings.exposure = 0.0
    scn.view_settings.gamma = 1.0
    scn.render.image_settings.file_format = "PNG"
    scn.render.image_settings.color_mode = "RGB"
    return scn


def setup_world(strength=0.4):
    """Sky: soft blue gradient for the camera, gentle sky fill for lighting."""
    scn = core.scene()
    w = bpy.data.worlds.get("W_MapleSky") or bpy.data.worlds.new("W_MapleSky")
    scn.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    n, l = nt.nodes, nt.links
    out = n.new("ShaderNodeOutputWorld")
    # lighting color (what surfaces receive)
    light_bg = n.new("ShaderNodeBackground")
    light_bg.inputs["Color"].default_value = M.hex_to_linear("#B9DCFF")
    light_bg.inputs["Strength"].default_value = 0.9 * strength
    # camera-visible sky gradient
    tc = n.new("ShaderNodeTexCoord")
    sep = n.new("ShaderNodeSeparateXYZ")
    l.new(tc.outputs["Window"], sep.inputs[0])
    ramp = n.new("ShaderNodeValToRGB")
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = 0.0, M.hex_to_linear("#E4F6FF")
    e[1].position, e[1].color = 1.0, M.hex_to_linear("#7CC8FF")
    l.new(sep.outputs[1], ramp.inputs["Fac"])
    cam_bg = n.new("ShaderNodeBackground")
    l.new(ramp.outputs["Color"], cam_bg.inputs["Color"])
    cam_bg.inputs["Strength"].default_value = 1.0
    lp = n.new("ShaderNodeLightPath")
    mix = n.new("ShaderNodeMixShader")
    l.new(lp.outputs["Is Camera Ray"], mix.inputs["Fac"])
    l.new(light_bg.outputs[0], mix.inputs[1])
    l.new(cam_bg.outputs[0], mix.inputs[2])
    l.new(mix.outputs[0], out.inputs["Surface"])
    return w


def setup_sun(energy=5.5, angle_deg=1.2, from_dir=(1.0, -0.72, 1.2), color="#FFF1D6", filter_radius=0.5):
    coll = core.get_collection("LIGHTING")
    for o in list(coll.objects):
        if o.type == "LIGHT":
            bpy.data.objects.remove(o)
    l = bpy.data.lights.new("Sun_Key", "SUN")
    l.energy = energy
    l.angle = math.radians(angle_deg)
    l.color = M.hex_to_linear(color)[:3]
    l.use_shadow = True
    l.shadow_filter_radius = filter_radius
    l.shadow_maximum_resolution = 0.02
    o = bpy.data.objects.new("Sun_Key", l)
    coll.objects.link(o)
    d = Vector(from_dir).normalized()
    o.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    o.location = d * 200
    return o


def iso_rotation(pitch=ISO_PITCH, yaw=ISO_YAW):
    return (math.radians(90 - pitch), 0.0, math.radians(yaw))


def make_camera(name, collection, target=(0, 0, 0), ortho_scale=40.0, pitch=ISO_PITCH, yaw=ISO_YAW):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cd = bpy.data.cameras.new(name)
        cam = bpy.data.objects.new(name, cd)
        collection.objects.link(cam)
    cd = cam.data
    cd.type = "ORTHO"
    cd.ortho_scale = ortho_scale
    cd.clip_start = 1.0
    cd.clip_end = 2000.0
    cam.rotation_euler = iso_rotation(pitch, yaw)
    look = _look_dir(cam)
    cam.location = Vector(target) - look * CAM_DISTANCE
    return cam


def _look_dir(cam):
    return (cam.rotation_euler.to_matrix() @ Vector((0, 0, -1))).normalized()


def fit_camera(cam, points, aspect=16 / 9, margin=1.08):
    """Center an ortho camera on 3D points and set ortho_scale to contain them."""
    rot = cam.rotation_euler.to_matrix()
    right = rot @ Vector((1, 0, 0))
    up = rot @ Vector((0, 1, 0))
    look = rot @ Vector((0, 0, -1))
    xs = [Vector(p).dot(right) for p in points]
    ys = [Vector(p).dot(up) for p in points]
    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    w = max(xs) - min(xs)
    h = max(ys) - min(ys)
    scale = max(w, h * aspect) * margin
    cam.data.ortho_scale = max(scale, 4.0)
    # pick a point on the center line; depth along look direction is irrelevant for ortho
    mean = sum((Vector(p) for p in points), Vector()) / len(points)
    depth = mean.dot(look)
    center = right * cx + up * cy + look * depth
    cam.location = center - look * CAM_DISTANCE
    return cam
