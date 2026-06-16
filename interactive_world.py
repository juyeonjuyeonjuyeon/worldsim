import bpy
import random
import math
import os

# --- 초기화 ---
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for mesh in bpy.data.meshes:
    bpy.data.meshes.remove(mesh)

# --- 지형 ---
bpy.ops.mesh.primitive_plane_add(size=50, location=(0, 0, 0))
terrain = bpy.context.active_object
terrain.name = "Terrain"

bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.subdivide(number_cuts=30)
bpy.ops.object.mode_set(mode='OBJECT')

displace = terrain.modifiers.new(name="Displace", type='DISPLACE')
noise_tex = bpy.data.textures.new("TerrainNoise", type='CLOUDS')
noise_tex.noise_scale = 3.0
displace.texture = noise_tex
displace.strength = 0.8
bpy.ops.object.modifier_apply(modifier="Displace")

ground_mat = bpy.data.materials.new(name="Ground")
ground_mat.use_nodes = True
bsdf = ground_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.10, 0.22, 0.06, 1)
bsdf.inputs["Roughness"].default_value = 1.0
terrain.data.materials.append(ground_mat)

# --- 나무 ---
def make_tree(x, y, scale):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.08 * scale, depth=1.8 * scale,
        location=(x, y, 0.9 * scale)
    )
    trunk = bpy.context.active_object
    trunk_mat = bpy.data.materials.new(name=f"Trunk_{x:.0f}{y:.0f}")
    trunk_mat.use_nodes = True
    trunk_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.22, 0.13, 0.04, 1)
    trunk.data.materials.append(trunk_mat)

    for z_offset, radius in [(1.8, 1.1), (2.4, 0.85), (3.0, 0.55)]:
        bpy.ops.mesh.primitive_cone_add(
            radius1=radius * scale, radius2=0, depth=1.0 * scale,
            location=(x, y, z_offset * scale)
        )
        leaves = bpy.context.active_object
        leaf_mat = bpy.data.materials.new(name=f"Leaf_{x:.0f}{y:.0f}{z_offset}")
        leaf_mat.use_nodes = True
        g = random.uniform(0.28, 0.40)
        leaf_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, g, 0.04, 1)
        leaves.data.materials.append(leaf_mat)

random.seed(7)
for _ in range(30):
    x = random.uniform(-20, 20)
    y = random.uniform(-20, 20)
    if abs(x) < 4 and abs(y) < 4:
        continue
    scale = random.uniform(0.7, 2.0)
    make_tree(x, y, scale)

# --- 하늘 ---
world = bpy.data.worlds["World"]
world.use_nodes = True
nodes = world.node_tree.nodes
links = world.node_tree.links
for node in nodes:
    nodes.remove(node)

sky_tex = nodes.new("ShaderNodeTexSky")
sky_tex.sky_type = 'MULTIPLE_SCATTERING'
sky_tex.air_density = 1.0
sky_tex.aerosol_density = 1.0
sky_tex.ozone_density = 1.0

bg = nodes.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = 1.0
out = nodes.new("ShaderNodeOutputWorld")
links.new(sky_tex.outputs["Color"], bg.inputs["Color"])
links.new(bg.outputs["Background"], out.inputs["Surface"])

# --- 태양 ---
bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
sun = bpy.context.active_object
sun.name = "Sun"
sun.data.energy = 5.0
sun.data.angle = math.radians(0.53)

# --- 24시간 애니메이션 (240프레임 = 24시간, 1프레임 = 6분) ---
scene = bpy.context.scene
scene.frame_start = 0
scene.frame_end = 240

MAX_ELEVATION = math.radians(60)  # 최대 태양 고도 (위도 기준 약 한국)

for frame in range(0, 241, 5):
    hour = frame / 10.0  # 0~24시

    # 태양 고도: 사인파 (새벽 6시 일출, 낮 12시 최고, 저녁 6시 일몰)
    elevation = MAX_ELEVATION * math.sin(2 * math.pi * (hour / 24) - math.pi / 2)

    # 태양 방위각: 동→남→서 (동쪽에서 시작)
    azimuth = math.radians(hour / 24 * 360)

    scene.frame_set(frame)

    # 하늘 텍스처 키프레임
    sky_tex.sun_elevation = elevation
    sky_tex.sun_rotation = azimuth
    sky_tex.keyframe_insert(data_path="sun_elevation", frame=frame)
    sky_tex.keyframe_insert(data_path="sun_rotation", frame=frame)

    # 태양 램프 키프레임
    sun.rotation_euler[0] = math.pi / 2 - elevation
    sun.rotation_euler[2] = azimuth
    sun.keyframe_insert(data_path="rotation_euler", frame=frame)

# 시작 프레임을 일출(60 = 오전 6시)로 설정
scene.frame_set(60)

# --- 카메라 ---
bpy.ops.object.camera_add(location=(12, -14, 4))
cam = bpy.context.active_object
cam.name = "Camera"
cam.rotation_euler[0] = math.radians(78)
cam.rotation_euler[2] = math.radians(40)
cam.data.lens = 35
scene.camera = cam

# --- 렌더러: EEVEE (실시간 뷰포트용) ---
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080

# --- .blend 저장 ---
blend_path = r"C:\Users\kkjjy\Documents\WorldSim\forest_world.blend"
bpy.ops.wm.save_as_mainfile(filepath=blend_path)
print(f"저장 완료: {blend_path}")
