"""
WS_forest_rain v006
v005 기반 + 개별 위상 연속 강우:
파티클마다 랜덤 위상을 부여해 시간 이동 (중력 낙하는 시간 이동에 불변 →
"언제 떨어지기 시작했는지"만 다른 것은 물리적으로 동등). 동기화된 점프 없이
무한 루프 가능. v005에서 확인된 "시간이 지나며 비가 옅어지는" 문제 해결.
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
# 웅덩이 (정적 물 고임 – 어두운 청록, 매트)
# 진단 결과: 재질 자체는 정상이지만 반지름 0.4~1.4m가 카메라에서
# 너무 작고 멀어 안티에일리어싱에 묻혀 안 보임 → 크기를 키움
# =============================================
puddle_mat = make_mat("Puddle", (0.03, 0.06, 0.08, 1), roughness=0.9,
                      transmission=0.0, ior=1.333)
random.seed(42)
for _ in range(8):
    px = random.uniform(-14, 14)
    py = random.uniform(-10, 10)
    r  = random.uniform(1.4, 3.0)   # 0.4~1.4 → 1.4~3.0 (확실히 보이게)
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

# ─── 비 Curve (얇고 투명한 빗줄기 – 글로우 튜브 아님) ───
rain_curve = bpy.data.curves.new("WS_RainCurve", type='CURVE')
rain_curve.dimensions    = '3D'
rain_curve.bevel_depth   = 0.004   # 4mm (10mm → 대폭 축소)
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
b.inputs["Base Color"].default_value          = (0.78, 0.87, 1.0, 1.0)
b.inputs["Roughness"].default_value           = 0.05
b.inputs["Transmission Weight"].default_value = 0.85   # 0.55 → 더 투명한 유리/물 느낌
b.inputs["IOR"].default_value                = 1.333
b.inputs["Emission Color"].default_value      = (0.78, 0.87, 1.0, 1.0)
b.inputs["Emission Strength"].default_value   = 0.15    # 0.5 → 글로우 대폭 약화
rain_obj.data.materials.append(rain_mat)

# ─── 스플래시 (지면 충돌 – 채워진 원판 메쉬, Curve 윤곽선 아님) ───
# 8각형 N-gon 면으로 채워진 작은 원판 → 실제 물방울 튀김처럼 보임
splash_mesh = bpy.data.meshes.new("WS_SplashMesh")
splash_verts = []
splash_faces = []
N_SIDES = 8
for s in range(splash_max):
    base_idx = len(splash_verts)
    for k in range(N_SIDES):
        ang = 2 * math.pi * k / N_SIDES
        splash_verts.append((math.cos(ang) * 0.001, math.sin(ang) * 0.001, -100.0))
    splash_faces.append(list(range(base_idx, base_idx + N_SIDES)))
splash_mesh.from_pydata(splash_verts, [], splash_faces)
splash_mesh.update()

splash_obj = bpy.data.objects.new("WS_Splash", splash_mesh)
bpy.context.collection.objects.link(splash_obj)

splash_mat = bpy.data.materials.new("SplashRing")
splash_mat.use_nodes = True
bs = splash_mat.node_tree.nodes["Principled BSDF"]
bs.inputs["Base Color"].default_value          = (0.40, 0.52, 0.62, 1.0)
bs.inputs["Roughness"].default_value           = 0.6
bs.inputs["Transmission Weight"].default_value = 0.0
bs.inputs["Emission Color"].default_value      = (0.40, 0.52, 0.62, 1.0)
bs.inputs["Emission Strength"].default_value   = 0.04
splash_obj.data.materials.append(splash_mat)

# ─── 프레임 핸들러 ───
# 연속 강우: 파티클마다 개별 랜덤 위상(phase)을 부여해 시간 이동
# 중력 낙하는 시간 이동에 불변이므로, "언제 떨어지기 시작했는지"를
# 파티클마다 다르게 주는 것은 실제로 각자 다른 순간에 낙하를 시작한
# 빗방울들이 동시에 존재하는 것과 물리적으로 동등함.
# v004의 반반 오프셋과 달리 5000개가 각자 다른 시점에 리셋되므로
# 동기화된 점프가 보이지 않음 → 무한 루프 가능
np.random.seed(123)
_phase       = np.random.randint(0, n_frames, size=n_rain)
_particle_ix = np.arange(n_rain)

_rain_data   = rain
_n_frames    = n_frames
_n_rain      = n_rain
_slen        = streak_len
_wtilt       = wind_tilt
_rain_obj    = rain_obj
_splash_obj  = splash_obj
_splash_max  = splash_max
_splash_r    = 0.55
_n_sides     = N_SIDES

def update_scene(scene):
    f = (scene.frame_current - 1) % _n_frames   # 무한 루프
    idx = (f + _phase) % _n_frames               # 파티클별 개별 시간 이동
    pts = _rain_data[idx, _particle_ix, :]        # (n_rain, 3) 팬시 인덱싱

    # 비 Curve 업데이트 (풍각도 포함)
    rain_splines = _rain_obj.data.splines
    nr = min(_n_rain, len(rain_splines))
    for i in range(nr):
        x, y, z = pts[i]
        rain_splines[i].points[0].co = (x,                    y, z,           1.0)
        rain_splines[i].points[1].co = (x - _wtilt * _slen,   y, z + _slen,   1.0)
    _rain_obj.data.update_tag()

    # 스플래시 메쉬 업데이트: z < 30cm 파티클 위치에 채워진 원판 표시
    near = pts[pts[:, 2] < 0.30]
    verts = _splash_obj.data.vertices
    ns = min(_splash_max, len(verts) // _n_sides)
    for i in range(ns):
        base = i * _n_sides
        if i < len(near):
            x, y = near[i, 0], near[i, 1]
            for k in range(_n_sides):
                ang = 2 * math.pi * k / _n_sides
                verts[base + k].co = (x + math.cos(ang) * _splash_r,
                                       y + math.sin(ang) * _splash_r,
                                       0.07)
        else:
            for k in range(_n_sides):
                verts[base + k].co = (0, 0, -100.0)
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
preview_path = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v006_preview.png"
os.makedirs(os.path.dirname(preview_path), exist_ok=True)
scene.render.filepath = preview_path
scene.frame_set(60)
print("프리뷰 렌더링 (프레임 60, 시각 결함 수정판)...")
bpy.ops.render.render(write_still=True)
print(f"프리뷰 저장: {preview_path}")

# =============================================
# 200프레임 PNG 시퀀스 렌더링
# 매 프레임 scene.frame_set() → 핸들러 → Curve 갱신 보장
# =============================================
frame_dir = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v006"
os.makedirs(frame_dir, exist_ok=True)

print(f"\n200프레임 애니메이션 렌더링 시작 (단순 순차 재생)...")
for f in range(1, n_frames + 1):
    scene.frame_set(f)   # frame_change_post 핸들러 실행
    out = os.path.join(frame_dir, f"WS_forest_rain_v006_{f:04d}.png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    if f % 20 == 0 or f == 1:
        print(f"  {f}/{n_frames} 완료")

print(f"\nPNG 시퀀스 완료: {frame_dir}")

# =============================================
# .blend 저장
# =============================================
bpy.ops.wm.save_as_mainfile(
    filepath=r"C:\Users\kkjjy\Documents\WorldSim\WS_forest_rain_v006.blend"
)
print("씬 저장: WS_forest_rain_v006.blend")
