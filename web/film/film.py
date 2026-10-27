# The film's pictures, path traced: the room scene.html exports (scene.glb), each frame as it plans it (plan.json: the
# camera, the phone, which place's light, what each screen shows), rendered by Cycles and denoised. record.mjs runs it:
#   blender -b -P web/film/film.py -- <out/film> <frames, e.g. 0-1140 or 150,420,600> [samples]
# The words and the lines between the machines go over these afterwards (scene.html?overlay=1).
import json
import math
import os
import sys
import time

import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index('--') + 1:]
OUT = args[0]
spec = args[1]
SAMPLES = int(args[2]) if len(args) > 2 else 128
plan = json.load(open(os.path.join(OUT, 'cycles', 'plan.json')))
if '-' in spec:
    a, b = spec.split('-')
    FRAMES = range(int(a), min(int(b), len(plan)))
else:
    FRAMES = [int(x) for x in spec.split(',')]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, 'cycles', 'scene.glb'))
scene = bpy.context.scene

# ---- Cycles on the GPU, denoised ----
scene.render.engine = 'CYCLES'
prefs = bpy.context.preferences.addons['cycles'].preferences
prefs.compute_device_type = 'METAL'
prefs.get_devices()
for d in prefs.devices:
    d.use = True
scene.cycles.device = 'GPU'
scene.cycles.samples = SAMPLES
scene.cycles.use_adaptive_sampling = True
scene.cycles.adaptive_threshold = 0.015
scene.cycles.use_denoising = True
scene.cycles.denoiser = 'OPENIMAGEDENOISE'
scene.cycles.max_bounces = 8
# The scene stays on the GPU from frame to frame: only what moves is sent again.
scene.render.use_persistent_data = True
scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
for vt in ('Khronos PBR Neutral', 'AgX', 'Filmic'):
    try:
        scene.view_settings.view_transform = vt
        break
    except TypeError:
        pass

# ---- The world: the room's light at the desk, the station's on the train ----
world = bpy.data.worlds.new('world')
scene.world = world
world.use_nodes = True
wn = world.node_tree.nodes
wl = world.node_tree.links
wn.clear()
coord = wn.new('ShaderNodeTexCoord')
mapping = wn.new('ShaderNodeMapping')
env = wn.new('ShaderNodeTexEnvironment')
bg = wn.new('ShaderNodeBackground')
outw = wn.new('ShaderNodeOutputWorld')
wl.new(coord.outputs['Generated'], mapping.inputs['Vector'])
wl.new(mapping.outputs['Vector'], env.inputs['Vector'])
wl.new(env.outputs['Color'], bg.inputs['Color'])
wl.new(bg.outputs['Background'], outw.inputs['Surface'])
HDR = {
    'office': bpy.data.images.load(os.path.join(OUT, 'assets', 'office.hdr')),
    'metro': bpy.data.images.load(os.path.join(OUT, 'assets', 'metro.hdr')),
}

# A window's light from the left, soft.
sun_data = bpy.data.lights.new('sun', 'SUN')
sun_data.energy = 6.5
sun_data.angle = math.radians(1.5)
sun_data.color = (1.0, 0.95, 0.88)
sun = bpy.data.objects.new('sun', sun_data)
scene.collection.objects.link(sun)
# three's (x, y, z), y up, as Blender's (x, -z, y), z up.
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
sun_from = (C @ Vector((-4.2, 3.0, 1.2, 1))).to_3d()
sun.rotation_euler = (-sun_from).to_track_quat('-Z', 'Y').to_euler()

# ---- The camera ----
cam_data = bpy.data.cameras.new('camera')
cam_data.sensor_fit = 'VERTICAL'
cam_data.sensor_height = 24
cam = bpy.data.objects.new('camera', cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

# ---- The screens: each a picture lit by itself, under a little gloss ----
screens = {}
for mat in list(bpy.data.materials):
    if not mat.name.startswith('screen_'):
        continue
    key = mat.name[len('screen_'):]
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    uv = nt.nodes.new('ShaderNodeTexCoord')
    flip = nt.nodes.new('ShaderNodeMapping')
    # (the pictures' rows run the other way from the way scene.html laid them on)
    flip.inputs['Scale'].default_value = (1, -1, 1)
    flip.inputs['Location'].default_value = (0, 1, 0)
    img = nt.nodes.new('ShaderNodeTexImage')
    img.interpolation = 'Cubic'
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = (0, 0, 0, 1)
    bsdf.inputs['Roughness'].default_value = 0.22
    # Glass that reflects a little, not enough to wash the picture out.
    bsdf.inputs['Coat Weight'].default_value = 0.06
    bsdf.inputs['Specular IOR Level'].default_value = 0.25
    bsdf.inputs['Emission Strength'].default_value = 1.0
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    nt.links.new(uv.outputs['UV'], flip.inputs['Vector'])
    nt.links.new(flip.outputs['Vector'], img.inputs['Vector'])
    nt.links.new(img.outputs['Color'], bsdf.inputs['Emission Color'])
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    screens[key] = img

phone = bpy.data.objects.get('phone')


def matrix(a):
    """three's matrix (column by column) as Blender's."""
    return Matrix([a[i::4] for i in range(4)])


loaded = {}


def picture(path):
    if path in loaded:
        return loaded[path]
    img = bpy.data.images.load(os.path.join(OUT, path))
    loaded[path] = img
    # Only what this frame shows stays in memory.
    while len(loaded) > 12:
        old = next(iter(loaded))
        bpy.data.images.remove(loaded.pop(old))
    return img


os.makedirs(os.path.join(OUT, 'cycles', 'frames'), exist_ok=True)
for f in FRAMES:
    fr = plan[f]
    cam.matrix_world = C @ matrix(fr['camera'])
    cam_data.lens = (cam_data.sensor_height / 2) / math.tan(math.radians(fr['fov']) / 2)
    cam_data.clip_start = 0.01
    blur = fr['blur']
    cam_data.dof.use_dof = blur > 0.0005
    cam_data.dof.focus_distance = fr['focus']
    cam_data.dof.aperture_fstop = 1.8 if blur > 0.005 else 4.0
    if phone:
        phone.matrix_world = C @ matrix(fr['phone']) @ C.inverted()
    place = 'metro' if fr['train'] else 'office'
    env.image = HDR[place]
    bg.inputs['Strength'].default_value = 1.0 if fr['train'] else 0.9
    mapping.inputs['Rotation'].default_value = (0, 0, -(1.2 + fr['s'] * 0.02) if fr['train'] else 0)
    for key, node in screens.items():
        if key in fr['screens']:
            node.image = picture(fr['screens'][key])
    scene.render.filepath = os.path.join(OUT, 'cycles', 'frames', f'{f:05d}.png')
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    print(f'film.py: frame {f} done in {time.time() - t0:.1f} s', flush=True)
