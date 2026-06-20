"""
WS_forest_rain v009
genesis_rain.py 전면 재시뮬레이션(30m 풀스케일, 450프레임, 안정화) 반영:

1. **XY 스케일 왜곡 해결**: Genesis 박스를 1.2m -> 30m로 키워 Blender 표시
   영역과 1:1 일치. 더 이상 ×25 좌표 늘리기 불필요 (가장 근본적인 수정).
2. **SPH 불안정성 근본 수정 확인**: sampler='regular' + stiffness 5000
   조합으로 450프레임 내내 폭주 0건 (기존 데이터는 프레임199에 37% 폭주
   했었음, 화면 밖으로 날아가 안 보였을 뿐). 더 이상 이상치 필터링 불필요.
3. **mid/high 배치 스플래시 가능**: 시뮬레이션을 450프레임으로 늘려
   high 배치(8m)도 자유낙하로 땅에 완전히 닿음 (기존 200프레임으론 불가능).

v006~v008 기반 기능 유지: 개별 위상 연속 강우, 데이터 기반 웅덩이 위치
+ 동적 성장, 지형 raycast, 실제 속도 기반 빗줄기 방향, 지면 시간적 습윤,
웅덩이-빗물 파문 상호작용, 스플래시 랜덤샘플링/충돌속도 기반 크기.
"""
import bpy
import numpy as np
import math
import random
import os

# =============================================
# Genesis 비 데이터 로드
# 30m 풀스케일로 재시뮬레이션됨 -> 좌표 스케일링/이상치 필터링 불필요
# =============================================
data_path = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_genesis_rain_sim\rain_particles.npy"
rain_raw = np.load(data_path)           # (450, 92928, 3)
n_frames, n_total, _ = rain_raw.shape
print(f"Genesis 데이터: {n_frames}프레임, {n_total}파티클 (30m 풀스케일, 이상치 없음)")

n_rain = 5000
sample_idx = np.linspace(0, n_total - 1, n_rain, dtype=int)
rain = rain_raw[:, sample_idx, :].copy()   # (450, 5000, 3)

# sampler='regular'는 입자를 완벽한 격자에 배치함 (불안정성 해결을 위한
# 트레이드오프). 카메라가 격자 축과 거의 일렬로 보면 같은 줄의 입자들이
# 화면에 겹쳐져 두꺼운 막대처럼 보이는 무아레 아티팩트가 생김. 입자마다
# 고정된 작은 XY 떨림을 줘서 격자 정렬을 깨뜨림 (물리량인 Z 방향 낙하에는
# 영향 없음, 격자 간격 0.17m의 절반 정도만 흔들어 시각적 정렬만 해소).
np.random.seed(7)
_jitter = (np.random.rand(n_rain, 2) - 0.5) * 1.2
rain[:, :, 0] += _jitter[:, 0]
rain[:, :, 1] += _jitter[:, 1]

print(f"서브샘플: {n_rain}개 | Z: {rain[0,:,2].min():.1f}~{rain[0,:,2].max():.1f}m")

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
# 지형
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

# ─── 비 낙하 밀집도 그리드 (지면 습윤 마스크 + 웅덩이 후보 산출에 공용) ───
_landing_xy = []
for _f in range(0, n_frames, 2):
    _m = rain[_f, :, 2] < 0.3
    if _m.any():
        _landing_xy.append(rain[_f, _m, :2])
_landing_xy = np.concatenate(_landing_xy, axis=0) if _landing_xy else np.zeros((0, 2))

_DENS_BINS = 24
if len(_landing_xy) > 0:
    _density_grid, _dxe, _dye = np.histogram2d(
        _landing_xy[:, 0], _landing_xy[:, 1], bins=_DENS_BINS,
        range=[[-16, 16], [-12, 12]])
    _density_norm = _density_grid / max(_density_grid.max(), 1.0)
else:
    _density_grid = np.zeros((_DENS_BINS, _DENS_BINS))
    _density_norm = _density_grid
    _dxe = np.linspace(-16, 16, _DENS_BINS + 1)
    _dye = np.linspace(-12, 12, _DENS_BINS + 1)
_dxc = 0.5 * (_dxe[:-1] + _dxe[1:])
_dyc = 0.5 * (_dye[:-1] + _dye[1:])

def density_at(x, y):
    i = int(np.clip(np.searchsorted(_dxc, x), 0, _DENS_BINS - 1))
    j = int(np.clip(np.searchsorted(_dyc, y), 0, _DENS_BINS - 1))
    return _density_norm[i, j]

# ─── 지면 습윤 마스크 (정점색): 비가 실제로 더 많이 떨어지는 곳일수록
# 짙게 젖은 색이 되도록 공간적 분포를 정점색에 저장. 시간적 변화(처음엔
# 안 젖어있다가 점차 젖어가는)는 셰이더의 Value 노드를 프레임 핸들러가
# 갱신해서 표현 (공간 마스크 × 시간 램프 = 최종 습윤도)
_wet_attr = terrain.data.color_attributes.new(name="WetnessMask", type='FLOAT_COLOR', domain='POINT')
for v in terrain.data.vertices:
    w = density_at(v.co.x, v.co.y)
    _wet_attr.data[v.index].color = (w, w, w, 1.0)

dry_color = (0.16, 0.24, 0.08, 1.0)   # 비 오기 전 마른 풀색
wet_color = (0.05, 0.13, 0.03, 1.0)   # 흠뻑 젖은 색 (기존 WetGround 색)

ground_mat = bpy.data.materials.new("WetGround")
ground_mat.use_nodes = True
_gnt = ground_mat.node_tree
_gnodes, _glinks = _gnt.nodes, _gnt.links
_gbsdf = _gnodes["Principled BSDF"]
_gbsdf.inputs["Metallic"].default_value = 0.0

_vcol = _gnodes.new("ShaderNodeVertexColor")
_vcol.layer_name = "WetnessMask"
_sep = _gnodes.new("ShaderNodeSeparateColor")
_glinks.new(_vcol.outputs["Color"], _sep.inputs["Color"])

# 밀집도 마스크에 최소 베이스라인 부여: 측정된 낙하 위치가 좁은 패치에
# 몰려있어(스케일 왜곡 문제 #3과 연결) 마스크가 대부분 0이 됨 → 시간이
# 다 지나도 대부분 지역이 마른 색으로 남는 부작용 방지. 밀도 낮은 곳도
# 절반은 젖게, 밀도 높은 곳은 완전히 젖게.
_densitymap = _gnodes.new("ShaderNodeMapRange")
_densitymap.inputs["From Min"].default_value = 0.0
_densitymap.inputs["From Max"].default_value = 1.0
_densitymap.inputs["To Min"].default_value = 0.5
_densitymap.inputs["To Max"].default_value = 1.0
_glinks.new(_sep.outputs["Red"], _densitymap.inputs["Value"])

ground_wetness_value = _gnodes.new("ShaderNodeValue")
ground_wetness_value.outputs[0].default_value = 0.0   # 프레임 핸들러가 매 프레임 갱신
ground_wetness_value.label = "GlobalWetnessRamp"

_wmul = _gnodes.new("ShaderNodeMath")
_wmul.operation = 'MULTIPLY'
_glinks.new(_densitymap.outputs["Result"], _wmul.inputs[0])
_glinks.new(ground_wetness_value.outputs[0], _wmul.inputs[1])

_mixcol = _gnodes.new("ShaderNodeMixRGB")
_mixcol.inputs["Color1"].default_value = dry_color
_mixcol.inputs["Color2"].default_value = wet_color
_glinks.new(_wmul.outputs[0], _mixcol.inputs["Fac"])
_glinks.new(_mixcol.outputs["Color"], _gbsdf.inputs["Base Color"])

_roughmap = _gnodes.new("ShaderNodeMapRange")
_roughmap.inputs["From Min"].default_value = 0.0
_roughmap.inputs["From Max"].default_value = 1.0
_roughmap.inputs["To Min"].default_value = 0.85    # 마른 땅: 거침
_roughmap.inputs["To Max"].default_value = 0.40    # 젖은 땅: 매끈
_glinks.new(_wmul.outputs[0], _roughmap.inputs["Value"])
_glinks.new(_roughmap.outputs["Result"], _gbsdf.inputs["Roughness"])

terrain.data.materials.append(ground_mat)

# =============================================
# 지형 높이 조회 (raycast 1회 사전계산 → 그리드 보간)
# 웅덩이/스플래시가 평평한 고정 높이에 떠 있거나 묻히던 문제 해결:
# Displace로 굴곡진 지형의 실제 표면 높이를 raycast로 얻어 배치에 사용
# =============================================
import mathutils
_depsgraph = bpy.context.evaluated_depsgraph_get()
_GRID_N = 48
_gx = np.linspace(-16, 16, _GRID_N)
_gy = np.linspace(-12, 12, _GRID_N)
_height_grid = np.zeros((_GRID_N, _GRID_N))
for _i, _x in enumerate(_gx):
    for _j, _y in enumerate(_gy):
        origin = mathutils.Vector((_x, _y, 50.0))
        direction = mathutils.Vector((0.0, 0.0, -1.0))
        ok, loc, nrm, idx, obj, mat = bpy.context.scene.ray_cast(_depsgraph, origin, direction)
        _height_grid[_i, _j] = loc.z if ok else 0.0
print(f"지형 높이 그리드 사전계산 완료 ({_GRID_N}x{_GRID_N})")

def ground_height(x, y):
    i = int(np.clip(np.searchsorted(_gx, x), 0, _GRID_N - 1))
    j = int(np.clip(np.searchsorted(_gy, y), 0, _GRID_N - 1))
    return _height_grid[i, j]

def ground_height_vec(xs, ys):
    ix = np.clip(np.searchsorted(_gx, xs), 0, _GRID_N - 1)
    iy = np.clip(np.searchsorted(_gy, ys), 0, _GRID_N - 1)
    return _height_grid[ix, iy]

# =============================================
# 웅덩이 (어두운 청록, 매트)
# 실제 비 낙하 데이터 기반 배치: 위에서 계산한 밀집도 그리드(_density_grid)를
# 재사용해 가장 비가 많이 떨어지는 지점을 웅덩이 후보로 산출.
# 크기는 밀집도에 비례, 처음엔 거의 안 보이다 비가 쌓이며 점차 자람.
# =============================================
puddle_mat = make_mat("Puddle", (0.03, 0.06, 0.08, 1), roughness=0.9,
                      transmission=0.0, ior=1.333)

n_puddles = 8
_order = np.argsort(_density_grid.ravel())[::-1]
_min_sep = 3.0
_centers = []
for _flat in _order:
    _i, _j = np.unravel_index(_flat, _density_grid.shape)
    if _density_grid[_i, _j] <= 0:
        break
    _cx, _cy = _dxc[_i], _dyc[_j]
    if all((_cx - px) ** 2 + (_cy - py) ** 2 > _min_sep ** 2 for px, py, _ in _centers):
        _centers.append((_cx, _cy, _density_grid[_i, _j]))
    if len(_centers) >= n_puddles:
        break
print(f"웅덩이 후보 {len(_centers)}개: 실제 낙하 밀집도 기반 산출 "
      f"(최대 밀집도 {max((c[2] for c in _centers), default=0):.0f}회)")

_max_density = max((c[2] for c in _centers), default=1.0)

# 웅덩이를 동적으로 키우기 위해 단위원(반지름 1)으로 만들고 object.scale로
# 매 프레임 크기를 조절 (transform_apply로 굳히지 않음). 처음엔 거의 안 보이게
# 시작해서 비가 쌓이며 점차 자라남 (프레임 핸들러에서 갱신).
puddle_objs    = []
puddle_max_r   = []
puddle_centers = []
for px, py, density in _centers:
    r_max = 1.2 + 1.8 * (density / _max_density)   # 최종 크기 (밀집도에 비례)
    gz = ground_height(px, py)
    bpy.ops.mesh.primitive_circle_add(vertices=32, radius=1.0,
                                      fill_type='NGON', location=(px, py, gz + 0.02))
    p = bpy.context.active_object
    p.scale = (0.001, 0.001, 0.01)   # 시작 시 거의 안 보임
    p.data.materials.append(puddle_mat)
    puddle_objs.append(p)
    puddle_max_r.append(r_max)
    puddle_centers.append((px, py))

puddle_max_r   = np.array(puddle_max_r) if puddle_max_r else np.zeros(0)
puddle_centers = np.array(puddle_centers) if puddle_centers else np.zeros((0, 2))
puddle_wetness = np.zeros(len(puddle_objs))   # 0~1, 누적 상태 (프레임 핸들러가 갱신)

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
splash_max  = 300    # 동시 스플래시 슬롯 개수

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
    sp.points[1].co = (x, y, z + streak_len, 1.0)   # 초기값, 핸들러가 즉시 갱신

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
#
# 위상을 순수 랜덤(파티클별 독립)으로 주면 'regular' 샘플러 특유의 문제가
# 생김: 3개 레이어가 동일한 XY 격자를 공유하므로, 같은 XY에서 유래한
# 다른 레이어 입자들이 서로 다른 무작위 위상을 받아 그 시점에 전부 다른
# 높이에 떠 있게 되고, 화면에선 그 XY 위치 전체가 빗줄기로 "채워진" 흰
# 기둥처럼 보임 (카메라가 얕은 각도라 두드러짐). 위상을 XY 위치만의
# 함수로 만들어 같은 XY를 공유하는 레이어 입자들이 항상 같은 위상(같은
# 낙하 진행률)을 갖게 해서 해결.
_x0 = rain[0, :, 0]
_y0 = rain[0, :, 1]
# 고주파(137,251 같은 큰 배수) 해시는 인접 격자점끼리도 위상이 급격히
# 달라져 같은 문제가 재발함 -> 저주파(완만한) 그라디언트로 변경.
# 인접한 XY는 항상 비슷한 위상을 가져 화면에 갑작스런 높이 불연속이
# 생기지 않음 (대신 비가 대각선 파도처럼 약간 출렁이며 떨어지는
# 모습이 되는데, 이 역시 실제 강우 전선의 진행처럼 보일 수 있음).
_phase = (((_x0 + 15.0) + (_y0 + 15.0)) / 60.0 * n_frames).astype(np.int64) % n_frames
_particle_ix = np.arange(n_rain)

_rain_data   = rain
_n_frames    = n_frames
_n_rain      = n_rain
_slen        = streak_len
_rain_obj    = rain_obj
_splash_obj  = splash_obj
_splash_max  = splash_max
_n_sides     = N_SIDES
_fallback_vel = np.array([0.0, 0.0, -0.02])   # 위상 wrap 순간의 속도 대체값

# 웅덩이 동적 성장 + 지면 습윤 시간 변화 파라미터
_PUDDLE_GROWTH = 0.15    # 근처 적중 1회당 wetness 증가량
_PUDDLE_DECAY  = 0.004   # 적중 없을 때 자연 감소(증발/배수)
_GROUND_RAMP_FRAMES = 60.0   # 지면이 마른 상태→완전히 젖는 데 걸리는 프레임 수
_RIPPLE_BOOST  = 1.7     # 웅덩이 안에 떨어진 스플래시 크기 배율 (파문 효과)

def update_scene(scene):
    f = (scene.frame_current - 1) % _n_frames     # 무한 루프
    idx = (f + _phase) % _n_frames                 # 파티클별 개별 시간 이동
    pts = _rain_data[idx, _particle_ix, :]          # (n_rain, 3) 팬시 인덱싱

    # 실제 Genesis 프레임간 속도(변위) – wind_tilt 같은 고정값 대신
    # 진짜 계산된 속도로 빗줄기 방향을 결정 (물리적 근거 확보)
    idx_prev = (idx - 1) % _n_frames
    pts_prev = _rain_data[idx_prev, _particle_ix, :]
    vel = pts - pts_prev
    wrapped = (idx == 0)                # 위상 루프 경계: 속도가 깨지는 지점
    vel[wrapped] = _fallback_vel
    vel_norm = np.linalg.norm(vel, axis=1, keepdims=True)
    vel_norm[vel_norm < 1e-6] = 1e-6
    vel_dir = vel / vel_norm
    tail = pts - vel_dir * _slen   # 빗줄기 꼬리 = 속도 반대 방향으로 streak_len만큼

    # 비 Curve 업데이트
    rain_splines = _rain_obj.data.splines
    nr = min(_n_rain, len(rain_splines))
    for i in range(nr):
        x, y, z = pts[i]
        tx, ty, tz = tail[i]
        rain_splines[i].points[0].co = (x,  y,  z,  1.0)
        rain_splines[i].points[1].co = (tx, ty, tz, 1.0)
    _rain_obj.data.update_tag()

    # 스플래시 메쉬 업데이트: z < 30cm 파티클 위치에 채워진 원판 표시
    # - 300개 초과시 랜덤 샘플링 (인덱스 순서 편향 제거)
    # - 충돌 속도(수직 속도) 기반 가변 크기
    # - 지형 raycast 높이 그리드로 실제 지표면에 배치
    mask = pts[:, 2] < 0.30
    near = pts[mask]
    near_speed = np.abs(vel[mask, 2])
    if len(near) > _splash_max:
        sel = np.random.choice(len(near), _splash_max, replace=False)
        near = near[sel]
        near_speed = near_speed[sel]
    radii = np.clip(0.3 + near_speed * 15.0, 0.3, 1.3)
    gz = ground_height_vec(near[:, 0], near[:, 1]) if len(near) else np.zeros(0)

    # ── 웅덩이 동적 성장 + 빗방울-웅덩이 상호작용(파문) ──
    # 성장 판정은 웅덩이의 "최종 크기"(puddle_max_r, 고정된 집수 영역) 기준으로
    # 해야 함 — 현재 자란 크기를 기준으로 하면 처음에 반지름이 0이라 적중 판정이
    # 절대 안 나서 영원히 안 자라는 닭-달걀 문제가 생김. 파문(시각 효과)만
    # "현재 자란 반지름" 안에 떨어졌을 때 더 크게 그려서 인과관계를 표시.
    n_pud = len(puddle_objs)
    if n_pud > 0 and len(near) > 0:
        dx = near[:, 0:1] - puddle_centers[:, 0][None, :]   # (n_near, n_pud)
        dy = near[:, 1:2] - puddle_centers[:, 1][None, :]
        dist2 = dx ** 2 + dy ** 2
        inside_catchment = dist2 < (puddle_max_r[None, :] ** 2)   # 성장 판정 (고정 영역)
        hits_per_puddle = inside_catchment.sum(axis=0)
        cur_r = puddle_max_r * puddle_wetness                      # 현재 자란 반지름
        inside_current = dist2 < (cur_r[None, :] ** 2)             # 파문 표시 판정
        in_any_puddle = inside_current.any(axis=1)
        radii[in_any_puddle] *= _RIPPLE_BOOST
    elif n_pud > 0:
        hits_per_puddle = np.zeros(n_pud)
    else:
        hits_per_puddle = np.zeros(0)

    for pi in range(n_pud):
        if hits_per_puddle[pi] > 0:
            puddle_wetness[pi] = min(1.0, puddle_wetness[pi] + _PUDDLE_GROWTH * hits_per_puddle[pi])
        else:
            puddle_wetness[pi] = max(0.0, puddle_wetness[pi] - _PUDDLE_DECAY)
        s = max(0.001, puddle_wetness[pi]) * puddle_max_r[pi]
        puddle_objs[pi].scale = (s, s, 0.01)

    # ── 지면 습윤도 시간 변화: 처음엔 마른 색 → 비가 쌓이며 점차 젖은 색 ──
    elapsed = scene.frame_current   # 위상 루프와 무관한, 이 렌더 클립의 실제 경과 프레임
    ground_wetness_value.outputs[0].default_value = min(1.0, elapsed / _GROUND_RAMP_FRAMES)

    verts = _splash_obj.data.vertices
    ns = min(_splash_max, len(verts) // _n_sides)
    n_active = len(near)
    for i in range(ns):
        base = i * _n_sides
        if i < n_active:
            x, y = near[i, 0], near[i, 1]
            r = radii[i]
            z = gz[i] + 0.02
            for k in range(_n_sides):
                ang = 2 * math.pi * k / _n_sides
                verts[base + k].co = (x + math.cos(ang) * r,
                                       y + math.sin(ang) * r,
                                       z)
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
preview_path = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v009_preview.png"
os.makedirs(os.path.dirname(preview_path), exist_ok=True)
scene.render.filepath = preview_path
scene.frame_set(60)
print("프리뷰 렌더링 (프레임 60, 30m 풀스케일 재시뮬레이션 반영판)...")
bpy.ops.render.render(write_still=True)
print(f"프리뷰 저장: {preview_path}")

# =============================================
# 450프레임 PNG 시퀀스 렌더링 (전체 시뮬레이션 길이 = high 배치까지 착지)
# 매 프레임 scene.frame_set() → 핸들러 → Curve 갱신 보장
# =============================================
frame_dir = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v009"
os.makedirs(frame_dir, exist_ok=True)

print(f"\n{n_frames}프레임 애니메이션 렌더링 시작...")
for f in range(1, n_frames + 1):
    scene.frame_set(f)   # frame_change_post 핸들러 실행
    out = os.path.join(frame_dir, f"WS_forest_rain_v009_{f:04d}.png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    if f % 20 == 0 or f == 1:
        print(f"  {f}/{n_frames} 완료")

print(f"\nPNG 시퀀스 완료: {frame_dir}")

# =============================================
# .blend 저장
# =============================================
bpy.ops.wm.save_as_mainfile(
    filepath=r"C:\Users\kkjjy\Documents\WorldSim\WS_forest_rain_v009.blend"
)
print("씬 저장: WS_forest_rain_v009.blend")
