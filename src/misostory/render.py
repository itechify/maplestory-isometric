"""Rendering helpers with a cross-process GPU slot lock.

Several Blender processes (e.g. parallel map-authoring agents) may render at once on
one GPU. ``gpu_slot()`` caps concurrent renders at MAX_SLOTS using lock files.
"""

import contextlib
import os
import tempfile
import time

import bpy

from . import core

MAX_SLOTS = int(os.environ.get("MISO_RENDER_SLOTS", "3"))
LOCK_DIR = os.path.join(tempfile.gettempdir(), "misostory_render_slots")
STALE_SECONDS = 900


@contextlib.contextmanager
def gpu_slot(timeout=3600):
    os.makedirs(LOCK_DIR, exist_ok=True)
    t0 = time.time()
    held = None
    while held is None:
        for i in range(MAX_SLOTS):
            p = os.path.join(LOCK_DIR, f"slot{i}.lock")
            try:
                if os.path.exists(p) and time.time() - os.path.getmtime(p) > STALE_SECONDS:
                    os.remove(p)
                fd = os.open(p, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                os.write(fd, str(os.getpid()).encode())
                os.close(fd)
                held = p
                break
            except (FileExistsError, PermissionError):
                continue
        if held is None:
            if time.time() - t0 > timeout:
                raise TimeoutError("No free render slot")
            time.sleep(2.0)
    try:
        yield
    finally:
        try:
            os.remove(held)
        except OSError:
            pass


def render_camera(cam_name, path, debug=False, res=None, samples=None):
    scn = core.scene()
    cam = bpy.data.objects.get(cam_name)
    if cam is None:
        raise KeyError(f"camera {cam_name} not found")
    scn.camera = cam
    dbg = bpy.data.collections.get("DEBUG")
    if dbg is not None:
        dbg.hide_render = not debug
    labels = bpy.data.collections.get("Debug_MapLabels")
    if labels is not None:  # big island labels only in island/region shots
        labels.hide_render = not (debug and (cam_name.startswith("CAM_Island") or cam_name.startswith("CAM_Region")))
    if res:
        scn.render.resolution_x, scn.render.resolution_y = res
    if samples:
        scn.eevee.taa_render_samples = samples
    scn.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with gpu_slot():
        bpy.ops.render.render(write_still=True)
    return path


def map_cameras(slug):
    return [o.name for o in bpy.data.objects if o.type == "CAMERA" and o.name.startswith(f"CAM_{slug}_")]
