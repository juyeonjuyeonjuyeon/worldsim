"""
WS_forest_rain v012
사용자 피드백: "웅덩이가 평평한 색만 있는 도형이라 물처럼 안 보임,
지형의 파인 부분에 맞게 채워진 게 아니라 판떼기 같다" 수정.

웅덩이를 평평한 원판(단일 높이) 대신 지형 높이 그리드에서 실제 움푹한
부분(주변의 하위 25%)을 찾아 그 윤곽대로 격자 셀 블롭을 쌓아 만듦 ->
지형이 솟은 곳엔 묻히고 꺼진 곳엔 뜨던 문제 해결, 불규칙한 자연스러운
웅덩이 외곽선. 표면 재질에도 약한 잔물결 범프 추가(매끈한 플라스틱이
아니라 물처럼 보이게, 반사량은 유지해 이전의 백색 과다반사 문제 회피).

v011 기반 유지 (아래) + 위 웅덩이 지오메트리/재질 개선:
근본적 재설계: Genesis SPH 시뮬레이션을 와이드샷 낙하에서 완전히 제거.

**왜 바꿨나**: SPH는 "입자들이 서로 압력으로 밀어내는 유체"를 계산하는
도구인데, 실제로 떨어지는 빗방울들은 서로 유체역학적으로 상호작용하지
않음 — 각자 중력+공기저항만 받는 독립된 투사체임. v009/v010에서
SPH 안정성과 "진짜 입자간 상호작용"을 둘 다 잡으려 했지만(지터+stiffness
조합 5가지 테스트), 상호작용이 거의 0인 안정 구간과 폭주 구간 사이에
쓸 만한 중간지대가 없다는 걸 확인함. 근본 원인은 SPH로 푸는 문제 자체가
틀렸다는 것 — 입자-입자 상호작용이 실제로 의미 있는 건 "충돌해서 튀는
순간"(스플래시)뿐, 낙하 자체는 아님.

**새 방식**: 기상학의 실제 경험식 사용
- 마샬-팔머(Marshall-Palmer) 빗방울 크기 분포: N(D)=N0·exp(-ΛD)
- 건-킨저(Gunn-Kinzer) 종단속도 경험식(Atlas et al. 1973 근사):
  v_t = 9.65 - 10.3·exp(-0.6D), D는 mm
- 2차 공기저항 하의 낙하는 해석적으로 풀림: v(t)=v_t·tanh(gt/v_t),
  떨어진 거리=  (v_t²/g)·ln(cosh(gt/v_t)) — SPH 없이 GPU 시뮬레이션
  없이 numpy로 정확한 실제 물리값 계산. 큰 방울은 빠르게, 작은 방울은
  느리게 떨어지는 다양성이 "위상 트릭" 없이 자연스럽게 생김.

Genesis는 이제 클로즈업 스플래시(작은 영역, 빗방울 크기 입자)에만 사용
예정 (별도 단계). 지형/나무/하늘/웅덩이/지면습윤 시스템은 유지.
"""
import bpy
import numpy as np
import math
import random
import os

# =============================================
# 빗방울 물리 속성 생성 (실제 기상학 경험식, Genesis/SPH 불필요)
# =============================================
G = 9.81   # 중력가속도 m/s^2

RAIN_RATE_MM_HR = 20.0   # 강우강도 (보통~강한 비)
LAMBDA = 4.1 * RAIN_RATE_MM_HR ** -0.21   # 마샬-팔머 분포 파라미터 (mm^-1)

n_rain = 5000
np.random.seed(42)
_U = np.random.uniform(1e-6, 1.0, n_rain)
diam_mm = np.clip(-np.log(_U) / LAMBDA, 0.4, 6.0)   # 빗방울 직경(mm), 실측 범위로 클립
v_terminal = 9.65 - 10.3 * np.exp(-0.6 * diam_mm)    # 건-킨저 종단속도(m/s)

FIELD_HALF = 15.0
START_HEIGHT = 9.0   # 빗방울이 화면에 나타나기 시작하는 높이(m)

# 순수 균등 난수로 XY를 뽑으면 통계적으로 우연한 클러스터가 생김
# (직접 확인: 반경 0.4m 안 평균 2.8개여야 할 입자가 실제로 11개 뭉친 곳 발견 ->
# 카메라가 얕은 각도라 그 위치의 여러 높이 빗방울들이 겹쳐 보여 흰 막대처럼
# 보이는 v009와 동일한 원인의 아티팩트 재발). 지터드 그리드(각 셀에 정확히
# 1개, 셀 내부에서만 무작위)로 바꿔 최소 간격을 보장 -> 군집 원천 차단,
# 그러면서도 완벽한 격자가 아니라 시각적으로 자연스러움.
_grid_n = int(np.ceil(np.sqrt(n_rain)))
_cell = (2 * FIELD_HALF) / _grid_n
_gi, _gj = np.meshgrid(np.arange(_grid_n), np.arange(_grid_n), indexing='ij')
_gi = _gi.ravel()[:n_rain]
_gj = _gj.ravel()[:n_rain]
np.random.seed(43)
x0 = -FIELD_HALF + (_gi + np.random.uniform(0.1, 0.9, n_rain)) * _cell
y0 = -FIELD_HALF + (_gj + np.random.uniform(0.1, 0.9, n_rain)) * _cell

print(f"빗방울 {n_rain}개 생성 (강우강도 {RAIN_RATE_MM_HR}mm/hr)")
print(f"직경: {diam_mm.min():.1f}~{diam_mm.max():.1f}mm | "
      f"종단속도: {v_terminal.min():.1f}~{v_terminal.max():.1f}m/s")

def fall_distance(t, vt):
    """2차 공기저항 하 t초 동안 낙하한 거리 (해석적 정확해)"""
    return (vt ** 2 / G) * np.log(np.cosh(G * t / vt))

def fall_velocity(t, vt):
    """t초 시점의 속도 (해석적 정확해, t->inf 에서 vt로 수렴)"""
    return vt * np.tanh(G * t / vt)

def fall_duration(h, vt):
    """높이 h를 낙하하는 데 걸리는 시간 (위 공식의 역함수, 폐형 해)"""
    A = np.exp(np.clip(h * G / vt ** 2, 0, 80))   # exp 오버플로 방지
    return (vt / G) * np.log(A + np.sqrt(np.maximum(A ** 2 - 1, 0)))

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
# 새 모델은 빗방울이 수직으로만 낙하(횡방향 힘 없음)하므로 착지 위치가
# 곧 출발 위치(x0,y0)와 같음 — 시계열 스캔 없이 바로 밀집도 계산 가능.
_landing_xy = np.stack([x0, y0], axis=1)

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

# ─── 빗방울별 낙하시간 계산 (지형 굴곡 반영, 해석적 정확해) ───
ground_z = ground_height_vec(x0, y0)
drop_height = START_HEIGHT - ground_z
fall_dur = fall_duration(drop_height, v_terminal)
print(f"낙하시간: {fall_dur.min():.2f}~{fall_dur.max():.2f}s "
      f"(작은 방울일수록 느리게 떨어져 오래 걸림)")

# 연속 강우 순환 주기: 가장 느린 방울이 다 떨어지는 시간 + 여유
CYCLE_SEC = float(fall_dur.max()) * 1.15
FPS = 24.0
np.random.seed(99)
drop_phase = np.random.uniform(0, CYCLE_SEC, n_rain)   # 각 방울의 독립적 시작 시각

# =============================================
# 웅덩이 (어두운 청록, 매트)
# 실제 비 낙하 데이터 기반 배치: 위에서 계산한 밀집도 그리드(_density_grid)를
# 재사용해 가장 비가 많이 떨어지는 지점을 웅덩이 후보로 산출.
# 크기는 밀집도에 비례, 처음엔 거의 안 보이다 비가 쌓이며 점차 자람.
# =============================================
puddle_mat = make_mat("Puddle", (0.03, 0.06, 0.08, 1), roughness=0.9,
                      transmission=0.0, ior=1.333)
# 완전히 평평한 표면은 "판떼기" 같아 보임 -> 약한 잔물결 범프로 표면에
# 미세한 변화를 줘서 매끈한 플라스틱이 아니라 물처럼 보이게 함.
# (이전 시도에서 범프+높은 반사를 같이 올리면 하늘을 그대로 비춰
# 하얗게 뜨는 문제가 있었으므로 roughness는 그대로 유지, 범프만 추가)
_pn = puddle_mat.node_tree.nodes.new("ShaderNodeTexNoise")
_pn.inputs["Scale"].default_value = 18.0
_pn.inputs["Detail"].default_value = 3.0
_pbump = puddle_mat.node_tree.nodes.new("ShaderNodeBump")
_pbump.inputs["Strength"].default_value = 0.25
_pbsdf = puddle_mat.node_tree.nodes["Principled BSDF"]
puddle_mat.node_tree.links.new(_pn.outputs["Fac"], _pbump.inputs["Height"])
puddle_mat.node_tree.links.new(_pbump.outputs["Normal"], _pbsdf.inputs["Normal"])

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

import bmesh

def build_puddle_blob(px, py, search_r, water_depth=0.06):
    """지형 높이 그리드에서 search_r 반경 내 가장 낮은 25% 영역을 찾아
    그 모양대로(격자 셀 단위 블롭) 평평한 수면 메쉬를 만든다.
    평평한 원판을 굴곡진 지형 위에 얹으면 "판떼기"처럼 떠 보이거나
    파묻히는 문제가 있었음 — 실제 움푹한 부분의 윤곽을 따라 채움.
    반환: (메쉬, 절대 수면높이) 또는 (None, 0) — 움푹한 곳 없으면."""
    i_lo = max(0, np.searchsorted(_gx, px - search_r) - 1)
    i_hi = min(_GRID_N, np.searchsorted(_gx, px + search_r) + 1)
    j_lo = max(0, np.searchsorted(_gy, py - search_r) - 1)
    j_hi = min(_GRID_N, np.searchsorted(_gy, py + search_r) + 1)
    local = _height_grid[i_lo:i_hi, j_lo:j_hi]
    if local.size < 4:
        return None, 0.0
    water_level = float(np.percentile(local, 25)) + water_depth
    cell_w = _gx[1] - _gx[0]
    cell_h = _gy[1] - _gy[0]

    bm = bmesh.new()
    for i in range(i_lo, i_hi):
        for j in range(j_lo, j_hi):
            gxv, gyv = _gx[i], _gy[j]
            if (gxv - px) ** 2 + (gyv - py) ** 2 > search_r ** 2:
                continue
            if _height_grid[i, j] >= water_level:
                continue
            cx, cy = gxv - px, gyv - py
            v1 = bm.verts.new((cx - cell_w / 2, cy - cell_h / 2, 0.0))
            v2 = bm.verts.new((cx + cell_w / 2, cy - cell_h / 2, 0.0))
            v3 = bm.verts.new((cx + cell_w / 2, cy + cell_h / 2, 0.0))
            v4 = bm.verts.new((cx - cell_w / 2, cy + cell_h / 2, 0.0))
            bm.faces.new((v1, v2, v3, v4))
    if len(bm.faces) == 0:
        bm.free()
        return None, water_level
    mesh = bpy.data.meshes.new("WS_PuddleBlob")
    bm.to_mesh(mesh)
    bm.free()
    return mesh, water_level

# 웅덩이를 동적으로 키우기 위해 블롭 메쉬를 만들고 object.scale로 매 프레임
# 크기를 조절 (Z스케일은 항상 1.0 — 수면은 늘 평평, XY만 줄여서 시작 시
# 거의 안 보이게 하고 비가 쌓이며 점차 자라남, 프레임 핸들러에서 갱신).
puddle_objs    = []
puddle_max_r   = []
puddle_centers = []
for px, py, density in _centers:
    r_max = 1.2 + 1.8 * (density / _max_density)   # 최종 크기 (밀집도에 비례)
    blob_mesh, water_level = build_puddle_blob(px, py, r_max * 1.3)
    if blob_mesh is None:
        continue   # 이 근처에 물이 고일 움푹한 곳이 없으면 웅덩이 생략
    p = bpy.data.objects.new("WS_Puddle", blob_mesh)
    p.location = (px, py, water_level)
    p.scale = (0.001, 0.001, 1.0)   # 시작 시 거의 안 보임
    bpy.context.collection.objects.link(p)
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
    sp = rain_curve.splines.new('POLY')
    sp.points.add(1)
    sp.points[0].co = (x0[i], y0[i], START_HEIGHT, 1.0)
    sp.points[1].co = (x0[i], y0[i], START_HEIGHT + streak_len, 1.0)   # 초기값, 핸들러가 즉시 갱신

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
# 연속 강우: 각 빗방울이 실제로 독립된 순간(drop_phase)에 낙하를 "시작"함.
# 이건 더 이상 시각적 트릭이 아니라 진짜 기상학적 사실 그대로임 — 실제
# 빗방울들도 다 같은 시각에 한꺼번에 응결되어 떨어지는 게 아니라 각자
# 다른 순간에 구름에서 떨어지기 시작함. CYCLE_SEC 주기로 무한 반복되고,
# 큰 방울은 빠르게(짧은 fall_dur), 작은 방울은 느리게(긴 fall_dur)
# 떨어지는 진짜 물리적 다양성이 자연 발생함 (위상 트릭으로 흉내낸 게 아님).
_rain_obj    = rain_obj
_splash_obj  = splash_obj
_splash_max  = splash_max
_n_sides     = N_SIDES
_slen        = streak_len
_SPLASH_WINDOW = 0.15   # 착지 후 스플래시가 보이는 시간(초)

# 웅덩이 동적 성장 + 지면 습윤 시간 변화 파라미터
_PUDDLE_GROWTH = 0.15    # 근처 적중 1회당 wetness 증가량
_PUDDLE_DECAY  = 0.004   # 적중 없을 때 자연 감소(증발/배수)
_GROUND_RAMP_FRAMES = 60.0   # 지면이 마른 상태→완전히 젖는 데 걸리는 프레임 수
_RIPPLE_BOOST  = 2.5     # 웅덩이 안에 떨어진 스플래시 크기 배율

def update_scene(scene):
    t = (scene.frame_current - 1) / FPS          # 렌더 경과 시간(초), 무한 루프 없이 그대로 증가
    local_t = (t + drop_phase) % CYCLE_SEC        # 빗방울별 독립 주기 (실제 기상학적 다양성)

    falling = local_t < fall_dur
    fallen = fall_distance(np.where(falling, local_t, fall_dur), v_terminal)
    z = np.where(falling, START_HEIGHT - fallen, ground_z)
    speed = np.where(falling, fall_velocity(np.where(falling, local_t, fall_dur), v_terminal), 0.0)

    # 빗줄기 꼬리: 순수 수직 낙하(바람 없음)이므로 꼬리는 항상 위쪽,
    # 길이는 속도에 비례해 늘어남(빠른 방울일수록 길게 - 모션블러 대신
    # 실제 속도 기반 시각적 신호)
    vis_len = np.clip(_slen * (speed / 4.0), _slen * 0.3, _slen * 2.0)
    tail_z = z + vis_len

    # 비 Curve 업데이트: 떨어지는 중인 방울만 보이고, 착지한 방울은 숨김
    rain_splines = _rain_obj.data.splines
    nr = min(n_rain, len(rain_splines))
    for i in range(nr):
        if falling[i]:
            rain_splines[i].points[0].co = (x0[i], y0[i], z[i], 1.0)
            rain_splines[i].points[1].co = (x0[i], y0[i], tail_z[i], 1.0)
        else:
            rain_splines[i].points[0].co = (0, 0, -100.0, 1.0)
            rain_splines[i].points[1].co = (0, 0, -100.0, 1.0)
    _rain_obj.data.update_tag()

    # 스플래시: 착지 직후(_SPLASH_WINDOW초) 동안만 표시, 충돌속도(=종단속도)
    # 기반 크기 — 실제 운동량에 비례하는 진짜 물리값
    since_landing = local_t - fall_dur
    splashing = (since_landing >= 0) & (since_landing < _SPLASH_WINDOW)
    near = np.stack([x0[splashing], y0[splashing], z[splashing]], axis=1)
    near_speed = v_terminal[splashing]
    if len(near) > _splash_max:
        sel = np.random.choice(len(near), _splash_max, replace=False)
        near = near[sel]
        near_speed = near_speed[sel]
    radii = np.clip(0.3 + near_speed * 0.12, 0.3, 1.3)
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
        puddle_objs[pi].scale = (s, s, 1.0)   # 블롭 메쉬는 이미 평평(Z=0) -> Z스케일 항상 1

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

# 더 이상 시뮬레이션 길이에 묶이지 않음 (분석적 물리 계산, 길이 제약 없음).
# CYCLE_SEC 안에서 빗방울들이 자연스럽게 순환하므로 임의 길이로 렌더 가능.
n_frames = int(CYCLE_SEC * FPS)   # 한 순환 주기 전체를 렌더 (루프 길이와 일치)

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
preview_path = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v012_preview.png"
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
frame_dir = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v012"
os.makedirs(frame_dir, exist_ok=True)

print(f"\n{n_frames}프레임 애니메이션 렌더링 시작...")
for f in range(1, n_frames + 1):
    scene.frame_set(f)   # frame_change_post 핸들러 실행
    out = os.path.join(frame_dir, f"WS_forest_rain_v012_{f:04d}.png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    if f % 20 == 0 or f == 1:
        print(f"  {f}/{n_frames} 완료")

print(f"\nPNG 시퀀스 완료: {frame_dir}")

# =============================================
# .blend 저장
# =============================================
bpy.ops.wm.save_as_mainfile(
    filepath=r"C:\Users\kkjjy\Documents\WorldSim\WS_forest_rain_v012.blend"
)
print("씬 저장: WS_forest_rain_v012.blend")
