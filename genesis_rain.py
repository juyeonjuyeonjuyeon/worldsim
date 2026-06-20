"""
Genesis 연속 강우 시뮬레이션 - 3레이어 방식 (v2: 안정성 수정 + 풀스케일)

v1 대비 핵심 수정:
1. **불안정성 근본 수정**: sampler='random' -> 'regular'
   기존 npy를 직접 분석한 결과, "정상" 데이터도 시간이 지날수록 입자가
   폭주했음 (프레임 199에 37% 폭주, 단 화면 밖으로 날아가 안 보였을 뿐).
   원인은 'random' 샘플러가 초기 입자를 불균일/겹치게 배치해 SPH 압력이
   폭주한 것. 'regular'(균일 격자) 샘플러로 교체 + stiffness 50000->5000
   으로 200스텝 검증 결과 폭주 0건.
2. **스케일 왜곡 해결**: 박스 크기 1.2m -> 30m (Blender 표시 영역과 동일)
   더 이상 XY를 25배로 늘릴 필요 없음 (forest_rain.py에서 스케일 팩터 제거).
   particle_size를 0.02 -> 0.17로 키워 입자 수는 비슷하게 유지.
3. **시뮬레이션 길이 확장**: 200 -> 450프레임. high 레이어(8m)가 자유낙하로
   땅에 닿으려면 약 426스텝(1.28초) 필요 -> mid/high도 스플래시 발생 가능.

mujoco DLL이 Windows Smart App Control에 차단되어 Genesis import 자체가
실패하는 문제: RigidEntity/MJCF 기능은 전혀 안 쓰므로 가짜 모듈로 스텁
처리해서 import만 통과시킴 (실제 mujoco는 로드 안 됨, 보안 정책 자체는
그대로 유지됨). 사용자 명시적 승인 후 적용.
"""
import sys
import io
import os
import types

_mujoco_stub = types.ModuleType("mujoco")
_mujoco_stub.__file__ = "<mujoco-stub>"
_mujoco_stub.__path__ = []
def _stub_getattr(name):
    raise AttributeError(f"mujoco.{name} 사용 불가 (스텁 모듈 - RigidEntity/MJCF 미사용)")
_mujoco_stub.__getattr__ = _stub_getattr
sys.modules['mujoco'] = _mujoco_stub

import numpy as np

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

import genesis as gs

gs.init(backend=gs.cuda)   # 프로세스당 1회만 호출 가능

scene = gs.Scene(
    show_viewer=False,
    sim_options=gs.options.SimOptions(dt=0.003),
    sph_options=gs.options.SPHOptions(particle_size=0.17),
)

# 지면 (충돌 감지)
plane = scene.add_entity(gs.morphs.Plane())

# 레이어별 슬랩: 30m x 30m (Blender 표시 영역과 1:1, 스케일 왜곡 없음)
# regular 샘플러 + stiffness 5000 = 200스텝 검증 결과 폭주 0건 (안정)
SPH_KW = dict(sampler='regular', rho=1000.0, mu=0.001, stiffness=5000.0)
rain_low = scene.add_entity(
    material=gs.materials.SPH.Liquid(**SPH_KW),
    morph=gs.morphs.Box(pos=(0.0, 0.0, 2.0), size=(30.0, 30.0, 0.2)),
    surface=gs.surfaces.Default(color=(0.4, 0.75, 1.0, 0.85)),
)
rain_mid = scene.add_entity(
    material=gs.materials.SPH.Liquid(**SPH_KW),
    morph=gs.morphs.Box(pos=(0.0, 0.0, 5.0), size=(30.0, 30.0, 0.2)),
    surface=gs.surfaces.Default(color=(0.4, 0.75, 1.0, 0.85)),
)
rain_high = scene.add_entity(
    material=gs.materials.SPH.Liquid(**SPH_KW),
    morph=gs.morphs.Box(pos=(0.0, 0.0, 8.0), size=(30.0, 30.0, 0.2)),
    surface=gs.surfaces.Default(color=(0.4, 0.75, 1.0, 0.85)),
)

scene.build()

n_frames = 450   # high 레이어(8m)가 땅에 닿는 데 필요한 ~426스텝 + 여유
output_dir = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_genesis_rain_sim"
os.makedirs(output_dir, exist_ok=True)

print(f"3레이어 연속 강우 시뮬레이션 시작 ({n_frames}프레임, 30m 풀스케일)...")
all_positions = []

for frame in range(n_frames):
    scene.step()

    p_low  = rain_low.get_particles_pos().cpu().numpy()
    p_mid  = rain_mid.get_particles_pos().cpu().numpy()
    p_high = rain_high.get_particles_pos().cpu().numpy()

    combined = np.concatenate([p_low, p_mid, p_high], axis=0)
    all_positions.append(combined)

    if (frame + 1) % 40 == 0:
        n_exploded = np.sum((np.abs(combined[:, 0]) > 15.5) |
                             (np.abs(combined[:, 1]) > 15.5) |
                             (combined[:, 2] > 10.0) | (combined[:, 2] < -0.5))
        print(f"  {frame+1}/{n_frames} | 파티클: {len(combined)} "
              f"| Z: {combined[:,2].min():.2f}~{combined[:,2].max():.2f}m "
              f"| 폭주: {n_exploded}개")

arr = np.array(all_positions)   # (n_frames, N*3, 3)
save_path = os.path.join(output_dir, "rain_particles.npy")
np.save(save_path, arr)

print(f"\n완료: {save_path}")
print(f"형태: {arr.shape}  (프레임, 파티클수, XYZ)")
print(f"파일 크기: {os.path.getsize(save_path) / 1024 / 1024:.0f} MB")
