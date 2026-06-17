"""
WS_forest_rain v003
Genesis SPH 물리 기반 비 애니메이션 + 지면 스플래시 + 200프레임 영상 렌더링
개선: 비 밀도 5000개, 풍각도, 지면 충돌 스플래시 링, 웅덩이, PNG 시퀀스 출력
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

z0 = rain_raw[0, :, 2]
valid_idx = np.where(z0 < 11.0)[0]

n_rain = 5000   # 3500 → 5000 (더 촘촘한 비)
sample_idx = np.linspace(0, len(valid_idx) - 1, n_rain, dtype=int)
selected = valid_idx[sample_idx]
rain = rain_raw[:, selected, :]         # (200, 5000, 3)
rain[:, :, 0] *= 25.0
rain[:, :, 1] *= 25.0

print(f"서브샘플: {n_rain}개 | XY ×25 | Z: {rain[0,:,2].min():.1f}~{rain[0,:,2].max():.1f}m")

# =============================================
# 씬 초기화
# =============================================
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for mesh in list(bpy.data.meshes):   bpy.data.meshes.remove(mesh)
for mat  in list(bpy.data.materials): bpy.data.materials.remove(mat)
for crv  in list(bpy.data.curves):   bpy.data.curves.remove(crv)

# =============================================
# 재질 헬퍼
# =============================================
def make_mat(name, color, roughness=0.9, metallic=0.0, transmission=0.0, ior=1.45):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value  = roughness
    b.inputs["Metallic"].default_value   = metallic
    b.inputs["Transmission Weight"].default_value = transmission
    b.inputs["IOR"].default_value        = ior
    return mat

# =============================================
# 지형 (젖은 땅 – 더 짙고 반사)
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
    make_mat("WetGround", (0.05, 0.13, 0.03, 1), roughness=0.40)
)

# =============================================
# 웅덩이 (정적 물 고임 – 지면에 납작한 반사 원)
# =============================================
puddle_mat = make_mat("Puddle", (0.55, 0.65, 0.80, 1), roughness=0.05,
                      transmission=0.20, ior=1.333)
random.seed(42)
for _ in range(12):
    px = random.uniform(-18, 18)
    py = random.uniform(-18, 18)
    r  = random.uniform(0.4, 1.4)
    bpy.ops.mesh.primitive_circle_add(vertices=32, radius=r,
                                      fill_type='NGON', location=(px, py, 0.06))
    p = bpy.context.active_object
    p.scale.z = 0.01   # 납작하게
    bpy.ops.object.transform_apply(scale=True)
    p.data.materials.append(puddle_mat)

# =============================================
# 나무 22그루
# =============================================
def make_tree(x, y, scale, seed):
    random.seed(seed)
    trunk_h   = 2.8 * scale
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
        t  = random.uniform(0, 1)
        sp = (1 - t * 0.45) * scale * 1.1
        ag = random.uniform(0, 360)
        cx = x + sp * math.cos(math.radians(ag)) * random.uniform(0.2, 1.0)
        cy = y + sp * math.sin(math.radians(ag)) * random.uniform(0.2, 1.0)
        cz = crown_base + t * trunk_h * 0.75 + random.uniform(-0.15, 0.15) * scale
        cr = scale * random.uniform(0.28, 0.52)
        g  = random.uniform(0.18, 0.30)
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
# 비 Curve (메인) + 스플래시 Curve
# 핸들러에서 매 프레임 Genesis 위치 직접 기록
# =============================================
streak_len  = 0.40   # 빗줄기 길이 (m)
wind_tilt   = 0.12   # 수평 기울기 비율 (풍각도)
splash_max  = 300    # 동시 스플래시 링 최대 개수

# ─── 비 Curve ───
rain_curve = bpy.data.curves.new("WS_RainCurve", type='CURVE')
rain_curve.dimensions    = '3D'
rain_curve.bevel_depth   = 0.010   # 10mm
rain_curve.bevel_resolution = 1
rain_curve.use_fill_caps = True

for i in range(n_rain):
    x, y, z = rain[0, i]
    sp = rain_curve.splines.new('POLY')
    sp.points.add(1)
    sp.points[0].co = (x, y, z, 1.0)
    sp.points[1].co = (x - wind_tilt * streak_len, y, z + streak_len, 1.0)

rain_obj = bpy.data.objects.new("WS_Rain", rain_curve)
bpy.context.collection.objects.link(rain_obj)

rain_mat = bpy.data.materials.new("WaterStreak")
rain_mat.use_nodes = True
b = rain_mat.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value          = (0.85, 0.93, 1.0, 1.0)
b.inputs["Roughness"].default_value           = 0.03
b.inputs["Transmission Weight"].default_value = 0.55
b.inputs["IOR"].default_value                = 1.333
b.inputs["Emission Color"].default_value      = (0.85, 0.93, 1.0, 1.0)
b.inputs["Emission Strength"].default_value   = 0.5
rain_obj.data.materials.append(rain_mat)

# ─── 스플래시 Curve (지면 충돌 링) ───
# 다이아몬드형 4점 폴리 스플라인 → bevel → 작은 원호처럼 보임
splash_curve = bpy.data.curves.new("WS_SplashCurve", type='CURVE')
splash_curve.dimensions  = '3D'
splash_curve.bevel_depth = 0.006
splash_curve.bevel_resolution = 1

for i in range(splash_max):
    sp = splash_curve.splines.new('POLY')
    sp.points.add(3)
    sp.use_cyclic_u = True
    for j, (dx, dy) in enumerate([(1,0),(0,1),(-1,0),(0,-1)]):
        sp.points[j].co = (dx * 0.001, dy * 0.001, -100.0, 1.0)  # 초기: 지하에 숨김

splash_obj = bpy.data.objects.new("WS_Splash", splash_curve)
bpy.context.collection.objects.link(splash_obj)

splash_mat = bpy.data.materials.new("SplashRing")
splash_mat.use_nodes = True
bs = splash_mat.node_tree.nodes["Principled BSDF"]
bs.inputs["Base Color"].default_value          = (0.75, 0.88, 1.0, 1.0)
bs.inputs["Roughness"].default_value           = 0.05
bs.inputs["Emission Color"].default_value      = (0.75, 0.88, 1.0, 1.0)
bs.inputs["Emission Strength"].default_value   = 0.6
splash_obj.data.materials.append(splash_mat)

# ─── 프레임 핸들러 ───
_rain_data   = rain
_n_frames    = n_frames
_n_rain      = n_rain
_slen        = streak_len
_wtilt       = wind_tilt
_rain_obj    = rain_obj
_splash_obj  = splash_obj
_splash_max  = splash_max
_splash_r    = 1.2   # 스플래시 반지름 (Blender 단위, XY 이미 ×25)

def update_scene(scene):
    f = max(0, min(scene.frame_current - 1, _n_frames - 1))
    pts = _rain_data[f]

    # 비 Curve 업데이트 (풍각도 포함)
    rain_splines = _rain_obj.data.splines
    nr = min(_n_rain, len(rain_splines))
    for i in range(nr):
        x, y, z = pts[i]
        rain_splines[i].points[0].co = (x,                    y, z,           1.0)
        rain_splines[i].points[1].co = (x - _wtilt * _slen,   y, z + _slen,   1.0)
    _rain_obj.data.update_tag()

    # 스플래시 Curve 업데이트 (지면 근접 파티클 → 링)
    near = pts[pts[:, 2] < 0.35]   # z < 35cm 파티클
    splash_splines = _splash_obj.data.splines
    ns = min(_splash_max, len(splash_splines))
    for i in range(ns):
        if i < len(near):
            x, y = near[i, 0], near[i, 1]
            r = _splash_r
            splash_splines[i].points[0].co = ( r+x,   y,  0.08, 1.0)
            splash_splines[i].points[1].co = (  x,  r+y,  0.08, 1.0)
            splash_splines[i].points[2].co = (-r+x,   y,  0.08, 1.0)
            splash_splines[i].points[3].co = (  x, -r+y,  0.08, 1.0)
        else:
            for j in range(4):
                splash_splines[i].points[j].co = (0, 0, -100.0, 1.0)
    _splash_obj.data.update_tag()

bpy.app.handlers.frame_change_post.append(update_scene)

scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end   = n_frames

# 핸들러 즉시 실행 (현재 프레임 반영)
update_scene(scene)
print("프레임 핸들러 등록 완료")

# =============================================
# 하늘 (흐린 비오는 날)
# =============================================
world = bpy.data.worlds["World"]
world.use_nodes = True
wn = world.node_tree.nodes
wl = world.node_tree.links
for n in list(wn): wn.remove(n)
sky = wn.new("ShaderNodeTexSky")
sky.sky_type        = 'MULTIPLE_SCATTERING'
sky.sun_elevation   = math.radians(18)
sky.sun_rotation    = math.radians(100)
sky.air_density     = 1.0
sky.aerosol_density = 5.5   # 흐린 날 더 짙은 대기
sky.ozone_density   = 1.0
bg  = wn.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = 0.45
out_w = wn.new("ShaderNodeOutputWorld")
wl.new(sky.outputs["Color"], bg.inputs["Color"])
wl.new(bg.outputs["Background"], out_w.inputs["Surface"])

# =============================================
# 조명
# =============================================
bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
sun = bpy.context.active_object
sun.data.energy = 1.0
sun.data.angle  = math.radians(5)
sun.rotation_euler[0] = math.radians(70)
sun.rotation_euler[2] = math.radians(100)

bpy.ops.object.light_add(type='AREA', location=(0, 0, 15))
sl = bpy.context.active_object
sl.data.energy = 60
sl.data.size   = 20
sl.data.color  = (0.60, 0.72, 1.0)

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
scene.cycles.samples      = 64    # 애니메이션용 – 속도/품질 균형
scene.cycles.use_denoising = True
scene.render.use_motion_blur = False  # Python 핸들러 방식에서 모션 블러 비활성

try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = 'CUDA'
    prefs.get_devices()
    for d in prefs.devices: d.use = True
    scene.cycles.device = 'GPU'
except:
    scene.cycles.device = 'CPU'

# =============================================
# 프리뷰 렌더 (프레임 60) – 애니메이션 전 품질 확인
# =============================================
preview_path = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v003_preview.png"
os.makedirs(os.path.dirname(preview_path), exist_ok=True)
scene.render.filepath = preview_path
scene.frame_set(60)
print("프리뷰 렌더링 (프레임 60)...")
bpy.ops.render.render(write_still=True)
print(f"프리뷰 저장: {preview_path}")

# =============================================
# 200프레임 PNG 시퀀스 렌더링
# 매 프레임 scene.frame_set() → 핸들러 → Curve 갱신 보장
# =============================================
frame_dir = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v003"
os.makedirs(frame_dir, exist_ok=True)

print(f"\n200프레임 애니메이션 렌더링 시작...")
for f in range(1, n_frames + 1):
    scene.frame_set(f)   # frame_change_post 핸들러 실행
    out = os.path.join(frame_dir, f"WS_forest_rain_v003_{f:04d}.png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    if f % 20 == 0 or f == 1:
        print(f"  {f}/{n_frames} 완료")

print(f"\n PNG 시퀀스 완료: {frame_dir}")

# =============================================
# .blend 저장
# =============================================
bpy.ops.wm.save_as_mainfile(
    filepath=r"C:\Users\kkjjy\Documents\WorldSim\WS_forest_rain_v003.blend"
)
print("씬 저장: WS_forest_rain_v003.blend")
