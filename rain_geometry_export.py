"""
실제 렌더링에 쓰인 WS_forest_rain_v015.blend를 직접 열어 그 안의 진짜 지형
객체로 raycast해서 사운드 합성용 데이터를 뽑음 — 별도 스크립트로 지형을
새로 만들면 미세한 차이가 생길 수 있어(원인 미확인, 작은 수치 차이) 실제
렌더와 100% 같은 지형/낙하시간을 보장하려고 저장된 blend를 그대로 사용.
"""
import bpy
import numpy as np
import math
import mathutils

bpy.ops.wm.open_mainfile(filepath=r"C:\Users\kkjjy\Documents\WorldSim\WS_forest_rain_v015.blend")

# 실제 forest_rain.py에서는 지형 높이 그리드를 raycast로 만들 때 나무/구름/
# 안개/비/웅덩이가 아직 생성되기 전이었음(스크립트 순서상 더 나중에 생성됨).
# 저장된 최종 blend에는 이미 다 들어있어서 raycast가 CloudLayer 등 다른
# 메시에 막힐 수 있음 -> Terrain/HorizonGround만 남기고 숨겨서 그때와
# 똑같은 조건으로 재현.
for _obj in bpy.data.objects:
    if _obj.name not in ("Terrain", "HorizonGround"):
        _obj.hide_viewport = True
bpy.context.view_layer.update()

G = 9.81
RAIN_RATE_MM_HR = 20.0
LAMBDA = 4.1 * RAIN_RATE_MM_HR ** -0.21

n_rain = 5000
np.random.seed(42)
_U = np.random.uniform(1e-6, 1.0, n_rain)
diam_mm = np.clip(-np.log(_U) / LAMBDA, 0.4, 6.0)
v_terminal = 9.65 - 10.3 * np.exp(-0.6 * diam_mm)

FIELD_HALF = 15.0
START_HEIGHT = 9.0

_grid_n = int(np.ceil(np.sqrt(n_rain)))
_cell = (2 * FIELD_HALF) / _grid_n
_gi, _gj = np.meshgrid(np.arange(_grid_n), np.arange(_grid_n), indexing='ij')
_gi = _gi.ravel()[:n_rain]
_gj = _gj.ravel()[:n_rain]
np.random.seed(43)
x0 = -FIELD_HALF + (_gi + np.random.uniform(0.1, 0.9, n_rain)) * _cell
y0 = -FIELD_HALF + (_gj + np.random.uniform(0.1, 0.9, n_rain)) * _cell

def fall_duration(h, vt):
    A = np.exp(np.clip(h * G / vt ** 2, 0, 80))
    return (vt / G) * np.log(A + np.sqrt(np.maximum(A ** 2 - 1, 0)))

# ── 저장된 blend 안의 실제 지형(+지평선)으로 raycast ──
depsgraph = bpy.context.evaluated_depsgraph_get()
_GRID_N = 48
_gx = np.linspace(-16, 16, _GRID_N)
_gy = np.linspace(-12, 12, _GRID_N)
_height_grid = np.zeros((_GRID_N, _GRID_N))
for _i, _x in enumerate(_gx):
    for _j, _y in enumerate(_gy):
        origin = mathutils.Vector((_x, _y, 50.0))
        direction = mathutils.Vector((0.0, 0.0, -1.0))
        ok, loc, nrm, idx, obj, mat = bpy.context.scene.ray_cast(depsgraph, origin, direction)
        _height_grid[_i, _j] = loc.z if ok else 0.0

def ground_height_vec(xs, ys):
    ix = np.clip(np.searchsorted(_gx, xs), 0, _GRID_N - 1)
    iy = np.clip(np.searchsorted(_gy, ys), 0, _GRID_N - 1)
    return _height_grid[ix, iy]

ground_z = ground_height_vec(x0, y0)
drop_height = START_HEIGHT - ground_z
fall_dur = fall_duration(drop_height, v_terminal)

CYCLE_SEC = float(fall_dur.max()) * 1.15
FPS = 24.0
np.random.seed(99)
drop_phase = np.random.uniform(0, CYCLE_SEC, n_rain)
n_frames = int(CYCLE_SEC * FPS)

# ── 웅덩이 위치/반경 — 실제 blend에 있는 WS_Puddle 객체 그대로 사용 ──
puddle_px, puddle_py, puddle_r = [], [], []
for obj in bpy.data.objects:
    if obj.name.startswith("WS_Puddle"):
        puddle_px.append(obj.location.x)
        puddle_py.append(obj.location.y)
        # 실제 렌더 마지막 프레임 기준 자란 반경 -> 1.3으로 나눠 원래 search_r(=r_max) 근사
        # (build_puddle_blob가 r_max*1.3을 검색반경으로 썼으므로 역산)
        local_max = max((v.co.x ** 2 + v.co.y ** 2) ** 0.5 for v in obj.data.vertices)
        puddle_r.append(local_max / 1.3 if local_max > 0 else 1.5)

np.savez(
    r"C:\Users\kkjjy\Documents\WorldSim\output\rain_sound_data.npz",
    x0=x0, y0=y0, diam_mm=diam_mm, v_terminal=v_terminal,
    fall_dur=fall_dur, drop_phase=drop_phase,
    CYCLE_SEC=CYCLE_SEC, FPS=FPS, n_frames=n_frames,
    puddle_px=np.array(puddle_px), puddle_py=np.array(puddle_py), puddle_r=np.array(puddle_r),
)
print(f"저장 완료: {n_rain}개 방울, 웅덩이 {len(puddle_px)}개, CYCLE_SEC={CYCLE_SEC:.3f}, n_frames={n_frames}")
