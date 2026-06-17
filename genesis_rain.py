"""
Genesis 연속 강우 시뮬레이션 - 3레이어 방식
한 씬에 높이 다른 얇은 슬랩 3개 배치:
  - low  (z=2m): 빠르게 착지
  - mid  (z=5m): 중간
  - high (z=8m): 천천히 착지
→ 항상 상중하 높이에 파티클 존재 = 연속 강우 효과
"""
import sys
import io
import os
import numpy as np

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

import genesis as gs

gs.init(backend=gs.cuda)   # 프로세스당 1회만 호출 가능

scene = gs.Scene(
    show_viewer=False,
    sim_options=gs.options.SimOptions(dt=0.003),
)

# 지면 (충돌 감지)
plane = scene.add_entity(gs.morphs.Plane())

# 레이어별 얇은 슬랩 (z_size=0.2 유지 → 파티클 수 원본과 동일)
# XY를 약간 분산시켜 레이어끼리 초기 충돌 방지
rain_low = scene.add_entity(
    material=gs.materials.SPH.Liquid(sampler='random', rho=1000.0, mu=0.001),
    morph=gs.morphs.Box(pos=( 0.0,  0.0, 2.0), size=(1.2, 1.2, 0.2)),
    surface=gs.surfaces.Default(color=(0.4, 0.75, 1.0, 0.85)),
)
rain_mid = scene.add_entity(
    material=gs.materials.SPH.Liquid(sampler='random', rho=1000.0, mu=0.001),
    morph=gs.morphs.Box(pos=( 0.0,  0.0, 5.0), size=(1.2, 1.2, 0.2)),
    surface=gs.surfaces.Default(color=(0.4, 0.75, 1.0, 0.85)),
)
rain_high = scene.add_entity(
    material=gs.materials.SPH.Liquid(sampler='random', rho=1000.0, mu=0.001),
    morph=gs.morphs.Box(pos=( 0.0,  0.0, 8.0), size=(1.2, 1.2, 0.2)),
    surface=gs.surfaces.Default(color=(0.4, 0.75, 1.0, 0.85)),
)

scene.build()

n_frames = 200
output_dir = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_genesis_rain_sim"
os.makedirs(output_dir, exist_ok=True)

print(f"3레이어 연속 강우 시뮬레이션 시작 ({n_frames}프레임)...")
all_positions = []

for frame in range(n_frames):
    scene.step()

    p_low  = rain_low.get_particles_pos().cpu().numpy()
    p_mid  = rain_mid.get_particles_pos().cpu().numpy()
    p_high = rain_high.get_particles_pos().cpu().numpy()

    # 세 레이어 합산 (프레임당 전체 파티클 하나의 배열로)
    combined = np.concatenate([p_low, p_mid, p_high], axis=0)
    all_positions.append(combined)

    if (frame + 1) % 40 == 0:
        # z>12 이상치 제외하고 통계 출력
        valid = combined[combined[:, 2] < 12.0]
        if len(valid) > 0:
            print(f"  {frame+1}/{n_frames} | 파티클: {len(combined)} "
                  f"| 유효 Z: {valid[:,2].min():.2f}~{valid[:,2].max():.2f}m")
        else:
            print(f"  {frame+1}/{n_frames} | 파티클: {len(combined)}")

arr = np.array(all_positions)   # (n_frames, N*3, 3)
save_path = os.path.join(output_dir, "rain_particles.npy")
np.save(save_path, arr)

print(f"\n완료: {save_path}")
print(f"형태: {arr.shape}  (프레임, 파티클수, XYZ)")
