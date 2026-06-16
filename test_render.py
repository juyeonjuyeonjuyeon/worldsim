import bpy
import random
import math
import os

# --- 초기화 ---
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for mesh in bpy.data.meshes:
    bpy.data.meshes.remove(mesh)

# --- 출력 경로 ---
output_path = r"C:\Users\kkjjy\Documents\WorldSim\output\test_sunrise.png"
os.makedirs(os.path.dirname(output_path), exist_ok=True)

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

# --- 나무 생성 함수 ---
def make_tree(x, y, scale):
    # 기둥
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.08 * scale,
        depth=1.8 * scale,
        location=(x, y, 0.9 * scale)
    )
    trunk = bpy.context.active_object
    trunk_mat = bpy.data.materials.new(name=f"Trunk_{x:.1f}")
    trunk_mat.use_nodes = True
    trunk_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.22, 0.13, 0.04, 1)
    trunk.data.materials.append(trunk_mat)

    # 잎 (3단 원뿔로 자연스럽게)
    for i, (z_offset, radius) in enumerate([(1.8, 1.1), (2.4, 0.85), (3.0, 0.55)]):
        bpy.ops.mesh.primitive_cone_add(
            radius1=radius * scale,
            radius2=0,
            depth=1.0 * scale,
            location=(x, y, z_offset * scale)
        )
        leaves = bpy.context.active_object
        leaf_mat = bpy.data.materials.new(name=f"Leaf_{x:.1f}_{i}")
        leaf_mat.use_nodes = True
        # 일출 느낌 - 약간 따뜻한 초록
        g = random.uniform(0.28, 0.40)
        leaf_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, g, 0.04, 1)
        leaf_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
        leaves.data.materials.append(leaf_mat)

# --- 나무 배치 ---
random.seed(7)
for _ in range(30):
    x = random.uniform(-20, 20)
    y = random.uniform(-20, 20)
    # 카메라 시야 앞쪽 제외 (빈 공간 느낌)
    if abs(x) < 4 and abs(y) < 4:
        continue
    scale = random.uniform(0.7, 2.0)
    make_tree(x, y, scale)

# --- 하늘 / 대기 (Nishita - 실제 물리 기반) ---
world = bpy.data.worlds["World"]
world.use_nodes = True
nodes = world.node_tree.nodes
links = world.node_tree.links

for node in nodes:
    nodes.remove(node)

sky_tex = nodes.new("ShaderNodeTexSky")
sky_tex.sky_type = 'MULTIPLE_SCATTERING'   # Blender 5.1 물리 기반 대기 산란
sky_tex.sun_elevation = math.radians(6)    # 일출: 지평선 위 6도
sky_tex.sun_rotation = math.radians(120)   # 동쪽 방향
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
sun.data.energy = 4.0
sun.data.angle = math.radians(0.53)  # 실제 태양 각직경
sun.rotation_euler[0] = math.radians(84)   # 거의 수평 (일출)
sun.rotation_euler[2] = math.radians(120)  # 동쪽

# --- 카메라 ---
bpy.ops.object.camera_add(location=(12, -14, 4))
cam = bpy.context.active_object
cam.name = "Camera"
cam.rotation_euler[0] = math.radians(78)
cam.rotation_euler[2] = math.radians(40)
cam.data.lens = 35
bpy.context.scene.camera = cam

# --- 렌더 설정 ---
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = output_path

scene.cycles.samples = 128
scene.cycles.use_denoising = True

# GPU 활성화
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = 'CUDA'
    prefs.get_devices()
    for device in prefs.devices:
        device.use = True
    scene.cycles.device = 'GPU'
    print("GPU 렌더링 활성화")
except Exception as e:
    print(f"GPU 설정 실패, CPU로 진행: {e}")
    scene.cycles.device = 'CPU'

# --- 렌더링 ---
print("렌더링 시작...")
bpy.ops.render.render(write_still=True)
print(f"완료: {output_path}")
