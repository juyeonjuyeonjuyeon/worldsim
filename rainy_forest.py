import bpy
import numpy as np
import math
import random
import os

# =============================================
# Genesis 비 데이터 로드 + 스케일 조정
# =============================================
rain_raw = np.load(r"C:\Users\kkjjy\Documents\WorldSim\output\rain_sim\rain_particles.npy")
n_frames, n_total, _ = rain_raw.shape  # (120, 36000, 3)

# 파티클 서브샘플링 (2000개로 줄이기)
n_rain = 2000
idx = np.linspace(0, n_total - 1, n_rain, dtype=int)
rain = rain_raw[:, idx, :]  # (120, 2000, 3)

# Genesis 좌표 → 숲 씬 스케일로 변환
# XY: 1.2m 범위 → 30m 범위로 확대
# Z: +4m 오프셋 (나무 높이 위에서 시작)
rain[:, :, 0] *= 20.0
rain[:, :, 1] *= 20.0
rain[:, :, 2] += 4.0

# =============================================
# 씬 초기화
# =============================================
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for d in bpy.data.meshes:
    bpy.data.meshes.remove(d)

# =============================================
# 재질 헬퍼
# =============================================
def make_mat(name, color, roughness=0.9, metallic=0.0, transmission=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Transmission Weight"].default_value = transmission
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

# 젖은 흙 재질 (비 온 뒤라 약간 반사)
wet_mat = make_mat("WetGround", (0.07, 0.16, 0.04, 1), roughness=0.55, metallic=0.0)
terrain.data.materials.append(wet_mat)

# =============================================
# 나무 생성
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
            location=(x, y, i * seg_h + seg_h / 2)
        )
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
                      bz + math.cos(ra)*bl*0.5)
        )
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
        g = random.uniform(0.18, 0.30)   # 비 온 날 - 어두운 초록
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
# Genesis 비 파티클 → Blender 애니메이션
# =============================================
# 빗방울 템플릿 (길쭉한 물방울 형태)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.04)
drop_tmpl = bpy.context.active_object
drop_tmpl.name = "RainDropTemplate"
drop_tmpl.scale = (0.35, 0.35, 1.0)
bpy.ops.object.transform_apply(scale=True)
drop_tmpl.data.materials.append(
    make_mat("DropMat", (0.5, 0.78, 1.0, 1), roughness=0.0, transmission=0.88)
)

# 포인트 클라우드 메시 (버텍스 = 빗방울 위치)
mesh = bpy.data.meshes.new("RainMesh")
rain_obj = bpy.data.objects.new("RainCloud", mesh)
bpy.context.collection.objects.link(rain_obj)

verts = [tuple(p) for p in rain[0]]
mesh.from_pydata(verts, [], [])
mesh.update()

# 버텍스 인스턴싱 (빗방울 템플릿을 각 버텍스에 배치)
rain_obj.instance_type = 'VERTS'
rain_obj.show_instancer_for_render = False
drop_tmpl.parent = rain_obj

# Shape Key로 프레임별 위치 애니메이션
rain_obj.shape_key_add(name="Basis")

scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = n_frames

print("Shape Key 애니메이션 생성 중...")
for f in range(0, n_frames, 4):    # 4프레임마다 키프레임
    sk = rain_obj.shape_key_add(name=f"F{f:03d}")
    for i, p in enumerate(rain[f]):
        sk.data[i].co = tuple(p)

    scene.frame_set(f + 1)
    for key in rain_obj.data.shape_keys.key_blocks[1:]:
        key.value = 0.0
        key.keyframe_insert("value")
    sk.value = 1.0
    sk.keyframe_insert("value")

print("완료!")

# =============================================
# 하늘 (비 오는 날)
# =============================================
world = bpy.data.worlds["World"]
world.use_nodes = True
nodes = world.node_tree.nodes
links = world.node_tree.links
for n in nodes:
    nodes.remove(n)

sky = nodes.new("ShaderNodeTexSky")
sky.sky_type = 'MULTIPLE_SCATTERING'
sky.sun_elevation = math.radians(20)
sky.sun_rotation = math.radians(100)
sky.air_density = 1.0
sky.aerosol_density = 4.0    # 빗날 - 습한 대기
sky.ozone_density = 1.0

bg = nodes.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = 0.5   # 흐린 날
out = nodes.new("ShaderNodeOutputWorld")
links.new(sky.outputs["Color"], bg.inputs["Color"])
links.new(bg.outputs["Background"], out.inputs["Surface"])

# =============================================
# 태양 (흐린 날)
# =============================================
bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
sun = bpy.context.active_object
sun.name = "Sun"
sun.data.energy = 1.2
sun.data.angle = math.radians(5)   # 확산광 (흐린 날)
sun.rotation_euler[0] = math.radians(70)
sun.rotation_euler[2] = math.radians(100)

# 전체적인 분위기를 위한 Area Light (하늘 빛 보완)
bpy.ops.object.light_add(type='AREA', location=(0, 0, 15))
sky_light = bpy.context.active_object
sky_light.name = "SkyLight"
sky_light.data.energy = 50
sky_light.data.size = 20
sky_light.data.color = (0.65, 0.78, 1.0)

# =============================================
# 카메라
# =============================================
bpy.ops.object.camera_add(location=(10, -13, 5))
cam = bpy.context.active_object
cam.name = "Camera"
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

try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = 'CUDA'
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    scene.cycles.device = 'GPU'
except:
    scene.cycles.device = 'CPU'

# 비 내리는 장면 중간 프레임 렌더링
output_path = r"C:\Users\kkjjy\Documents\WorldSim\output\rainy_forest.png"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
scene.render.filepath = output_path
scene.frame_set(50)   # 비가 한창 내리는 시점

print("렌더링 시작...")
bpy.ops.render.render(write_still=True)
print(f"완료: {output_path}")

# .blend 저장
bpy.ops.wm.save_as_mainfile(
    filepath=r"C:\Users\kkjjy\Documents\WorldSim\rainy_forest.blend"
)
print("씬 저장 완료")
