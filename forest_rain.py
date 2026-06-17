import bpy
import math
import random
import os

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
# 비 - Curve 오브젝트 (보장된 렌더링)
# 파티클 시뮬레이션 없이 직접 3D 빗줄기 생성
# =============================================
random.seed(42)
n_drops = 3500

curve_data = bpy.data.curves.new("RainCurve", type='CURVE')
curve_data.dimensions = '3D'
curve_data.bevel_depth = 0.005       # 빗방울 두께 5mm
curve_data.bevel_resolution = 1      # 낮은 폴리곤 (성능)
curve_data.use_fill_caps = True      # 양 끝 마감

for i in range(n_drops):
    x = random.uniform(-21, 21)
    y = random.uniform(-21, 21)
    z_top = random.uniform(0.8, 13.0)        # 지면 위 ~ 높은 곳까지 분포
    length = random.uniform(0.20, 0.55)      # 빗줄기 길이
    tilt_x = random.uniform(-0.04, 0.02)    # 바람에 의한 기울기 (왼쪽으로 약간)
    tilt_y = random.uniform(-0.02, 0.02)

    spline = curve_data.splines.new('POLY')
    spline.points.add(1)                     # 2포인트 = 직선 빗줄기
    spline.points[0].co = (x, y, z_top, 1)
    spline.points[1].co = (x + tilt_x, y + tilt_y, z_top - length, 1)

rain_obj = bpy.data.objects.new("Rain", curve_data)
bpy.context.collection.objects.link(rain_obj)

# 빗방울 재질 (반투명 파란빛 물)
rain_mat = bpy.data.materials.new("RainMat")
rain_mat.use_nodes = True
bsdf = rain_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.82, 0.92, 1.0, 1.0)
bsdf.inputs["Roughness"].default_value = 0.03
bsdf.inputs["Metallic"].default_value = 0.0
bsdf.inputs["Transmission Weight"].default_value = 0.70
bsdf.inputs["IOR"].default_value = 1.333
rain_obj.data.materials.append(rain_mat)

print(f"비 줄기 생성 완료: {n_drops}개")

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
sky.aerosol_density = 4.0
sky.ozone_density = 1.0

bg = nodes.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = 0.5
out = nodes.new("ShaderNodeOutputWorld")
links.new(sky.outputs["Color"], bg.inputs["Color"])
links.new(bg.outputs["Background"], out.inputs["Surface"])

# =============================================
# 조명
# =============================================
bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
sun = bpy.context.active_object
sun.name = "Sun"
sun.data.energy = 1.2
sun.data.angle = math.radians(5)
sun.rotation_euler[0] = math.radians(70)
sun.rotation_euler[2] = math.radians(100)

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
bpy.context.scene.camera = cam

# =============================================
# 렌더 설정
# =============================================
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.image_settings.file_format = 'PNG'
scene.cycles.samples = 128
scene.cycles.use_denoising = True
scene.frame_start = 1
scene.frame_end = 120

# 모션 블러: 빗줄기를 더 사실적으로 (정적 씬이라도 Cycles motion blur 효과)
scene.render.use_motion_blur = True
scene.render.motion_blur_shutter = 0.5

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

print("렌더링 시작...")
bpy.ops.render.render(write_still=True)
print(f"완료: {output_path}")

bpy.ops.wm.save_as_mainfile(
    filepath=r"C:\Users\kkjjy\Documents\WorldSim\WS_forest_rain_v001.blend"
)
print("씬 저장 완료")
