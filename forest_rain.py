"""
WS_forest_rain v002
Genesis SPH 물리 데이터 → Blender Curve Shape Key 애니메이션
파티클 위치는 Genesis 실제 물리 계산값. 렌더는 Curve 튜브.
"""
import bpy
import numpy as np
import math
import random
import os

# =============================================
# Genesis 비 데이터 로드 + 전처리
# =============================================
data_path = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_genesis_rain_sim\rain_particles.npy"
rain_raw = np.load(data_path)           # (200, 108000, 3)
n_frames, n_total, _ = rain_raw.shape
print(f"Genesis 데이터: {n_frames}프레임, {n_total}파티클")

# 이상치 제거: z > 12m 파티클 마스크 (첫 프레임 기준)
z0 = rain_raw[0, :, 2]
valid_idx = np.where(z0 < 11.0)[0]

# 유효 파티클 중 3500개 서브샘플
n_rain = 3500
sample_idx = np.linspace(0, len(valid_idx) - 1, n_rain, dtype=int)
selected = valid_idx[sample_idx]
rain = rain_raw[:, selected, :]         # (200, 3500, 3)

# Genesis 좌표 → 숲 씬 스케일
# Genesis XY: -0.6 ~ 0.6m  →  Blender XY: -15 ~ 15m (배율 ×25)
rain[:, :, 0] *= 25.0
rain[:, :, 1] *= 25.0
# Z: Genesis 물리값 그대로 (0~10m)

print(f"서브샘플: {n_rain}개 | XY 배율: ×25 | Z 범위: {rain[0,:,2].min():.1f}~{rain[0,:,2].max():.1f}m")

# =============================================
# 씬 초기화
# =============================================
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for mesh in list(bpy.data.meshes):
    bpy.data.meshes.remove(mesh)
for mat in list(bpy.data.materials):
    bpy.data.materials.remove(mat)

# =============================================
# 재질 헬퍼
# =============================================
def make_mat(name, color, roughness=0.9, metallic=0.0, transmission=0.0, ior=1.45):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Transmission Weight"].default_value = transmission
    b.inputs["IOR"].default_value = ior
    return mat

# =============================================
# 지형 (젖은 땅)
# =============================================
bpy.ops.mesh.primitive_plane_add(size=50, location=(0, 0, 0))
terrain = bpy.context.active_object
terrain.name = "Terrain"
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.subdivide(number_cuts=30)
bpy.ops.object.mode_set(mode='OBJECT')
displace = terrain.modifiers.new("Displace", 'DISPLACE')
noise_tex = bpy.data.textures.new("TerrainNoise", type='CLOUDS')
noise_tex.noise_scale = 3.0
displace.texture = noise_tex
displace.strength = 0.8
bpy.ops.object.modifier_apply(modifier="Displace")
terrain.data.materials.append(
    make_mat("WetGround", (0.07, 0.16, 0.04, 1), roughness=0.55)
)

# =============================================
# 나무 22그루
# =============================================
def make_tree(x, y, scale, seed):
    random.seed(seed)
    trunk_h = 2.8 * scale
    trunk_mat = make_mat(f"Trunk_{seed}", (0.18, 0.11, 0.04, 1))
    for i in range(5):
        seg_h = trunk_h / 5
        r = 0.13 * scale * (1 - i * 0.14)
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=10, radius=r, depth=seg_h,
            location=(x, y, i * seg_h + seg_h / 2))
        bpy.context.active_object.data.materials.append(trunk_mat)
    branch_mat = make_mat(f"Branch_{seed}", (0.16, 0.09, 0.03, 1))
    for _ in range(random.randint(4, 6)):
        bz = trunk_h * random.uniform(0.35, 0.80)
        ba = random.uniform(35, 65)
        bd = random.uniform(0, 360)
        bl = scale * random.uniform(0.9, 1.6)
        ra, rd = math.radians(ba), math.radians(bd)
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=6, radius=0.04 * scale, depth=bl,
            location=(x + math.sin(ra)*math.cos(rd)*bl*0.5,
                      y + math.sin(ra)*math.sin(rd)*bl*0.5,
                      bz + math.cos(ra)*bl*0.5))
        b = bpy.context.active_object
        b.rotation_euler[1] = ra
        b.rotation_euler[2] = rd
        b.data.materials.append(branch_mat)
    crown_base = trunk_h * 0.40
    for _ in range(random.randint(10, 16)):
        t = random.uniform(0, 1)
        sp = (1 - t * 0.45) * scale * 1.1
        ag = random.uniform(0, 360)
        cx = x + sp * math.cos(math.radians(ag)) * random.uniform(0.2, 1.0)
        cy = y + sp * math.sin(math.radians(ag)) * random.uniform(0.2, 1.0)
        cz = crown_base + t * trunk_h * 0.75 + random.uniform(-0.15, 0.15) * scale
        cr = scale * random.uniform(0.28, 0.52)
        g = random.uniform(0.18, 0.30)
        lmat = make_mat(f"Leaf_{seed}_{_}", (0.04, g, 0.04, 1))
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=cr, location=(cx, cy, cz))
        cl = bpy.context.active_object
        cl.scale.z = random.uniform(0.65, 1.25)
        bpy.ops.object.transform_apply(scale=True)
        cl.data.materials.append(lmat)

random.seed(7)
for _ in range(22):
    x = random.uniform(-19, 19)
    y = random.uniform(-19, 19)
    if abs(x) < 5 and abs(y) < 5:
        continue
    make_tree(x, y, random.uniform(0.7, 1.8), random.randint(0, 9999))

# =============================================
# Genesis 비 파티클 → Curve + Shape Key 애니메이션
# 렌더에서 확실히 보이는 방식 (Cycles Curve = 3D 튜브)
# 파티클 위치는 Genesis 물리 계산값
# =============================================
streak_len = 0.35   # 빗방울 길이 (m)
RENDER_FRAME = 80   # Genesis 시뮬 프레임 80 = 낙하 중간 시점

# Genesis 프레임 80 위치로 정적 Curve 생성 (애니메이션은 .blend GUI에서)
# → Shape Key 블렌딩 오류 없이 렌더에서 확실히 보임
curve_data = bpy.data.curves.new("WS_RainCurve", type='CURVE')
curve_data.dimensions = '3D'
curve_data.bevel_depth = 0.012       # 12mm 두께
curve_data.bevel_resolution = 1
curve_data.use_fill_caps = True

pts = rain[RENDER_FRAME]   # (3500, 3) - Genesis 물리 위치
for i in range(n_rain):
    x, y, z = pts[i]
    sp = curve_data.splines.new('POLY')
    sp.points.add(1)
    sp.points[0].co = (x, y, z, 1.0)
    sp.points[1].co = (x, y, z - streak_len, 1.0)

rain_obj = bpy.data.objects.new("WS_Rain", curve_data)
bpy.context.collection.objects.link(rain_obj)

# 물 재질: 약한 발광 추가 → 배경 상관없이 보임
rain_mat = bpy.data.materials.new("WaterDrop")
rain_mat.use_nodes = True
b = rain_mat.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value         = (0.85, 0.93, 1.0, 1.0)
b.inputs["Roughness"].default_value          = 0.03
b.inputs["Transmission Weight"].default_value = 0.60
b.inputs["IOR"].default_value               = 1.333
b.inputs["Emission Color"].default_value     = (0.85, 0.93, 1.0, 1.0)
b.inputs["Emission Strength"].default_value  = 0.4   # 약한 빛 → 가시성 확보
rain_obj.data.materials.append(rain_mat)

scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = n_frames
print(f"Genesis 프레임 {RENDER_FRAME} 위치로 Curve 생성 완료: {n_rain}개 빗줄기")

# =============================================
# 하늘 (비 오는 날)
# =============================================
world = bpy.data.worlds["World"]
world.use_nodes = True
wn = world.node_tree.nodes
wl = world.node_tree.links
for n in wn:
    wn.remove(n)
sky = wn.new("ShaderNodeTexSky")
sky.sky_type = 'MULTIPLE_SCATTERING'
sky.sun_elevation = math.radians(20)
sky.sun_rotation = math.radians(100)
sky.air_density = 1.0
sky.aerosol_density = 4.0
sky.ozone_density = 1.0
bg = wn.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = 0.5
out_w = wn.new("ShaderNodeOutputWorld")
wl.new(sky.outputs["Color"], bg.inputs["Color"])
wl.new(bg.outputs["Background"], out_w.inputs["Surface"])

# =============================================
# 조명
# =============================================
bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
sun = bpy.context.active_object
sun.data.energy = 1.2
sun.data.angle = math.radians(5)
sun.rotation_euler[0] = math.radians(70)
sun.rotation_euler[2] = math.radians(100)

bpy.ops.object.light_add(type='AREA', location=(0, 0, 15))
sl = bpy.context.active_object
sl.data.energy = 50
sl.data.size = 20
sl.data.color = (0.65, 0.78, 1.0)

# =============================================
# 카메라
# =============================================
bpy.ops.object.camera_add(location=(10, -13, 5))
cam = bpy.context.active_object
cam.rotation_euler[0] = math.radians(75)
cam.rotation_euler[2] = math.radians(38)
cam.data.lens = 35
scene.camera = cam

# =============================================
# 렌더 설정
# =============================================
scene.render.engine = 'CYCLES'
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.image_settings.file_format = 'PNG'
scene.cycles.samples = 128
scene.cycles.use_denoising = True
scene.render.use_motion_blur = True
scene.render.motion_blur_shutter = 0.4

try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = 'CUDA'
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    scene.cycles.device = 'GPU'
except:
    scene.cycles.device = 'CPU'

output_path = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v001.png"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
scene.render.filepath = output_path
scene.frame_set(1)

print("렌더링 시작 (Genesis SPH 물리 기반)...")
bpy.ops.render.render(write_still=True)
print(f"완료: {output_path}")

bpy.ops.wm.save_as_mainfile(
    filepath=r"C:\Users\kkjjy\Documents\WorldSim\WS_forest_rain_v001.blend"
)
print("씬 저장 완료")
