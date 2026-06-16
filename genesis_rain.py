import sys
import io
import os
import numpy as np

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

import genesis as gs

gs.init(backend=gs.cuda)

scene = gs.Scene(
    show_viewer=False,
    sim_options=gs.options.SimOptions(dt=0.003),  # SPH 안정 타임스텝
)

# 바닥
plane = scene.add_entity(gs.morphs.Plane())

# 빗물 (높은 곳에서 아래로 떨어지는 물 덩어리)
rain = scene.add_entity(
    material=gs.materials.SPH.Liquid(
        sampler='random',
        rho=1000.0,   # 물 밀도 (kg/m³)
        mu=0.001,     # 점성
    ),
    morph=gs.morphs.Box(
        pos=(0.0, 0.0, 2.5),   # 지면 위 2.5m
        size=(1.2, 1.2, 0.2),  # 넓게 퍼진 빗방울 영역
    ),
    surface=gs.surfaces.Default(color=(0.4, 0.75, 1.0, 0.85)),
)

scene.build()

# 시뮬레이션 실행 + 프레임별 파티클 위치 저장
n_frames = 120   # 약 2초 분량
output_dir = r"C:\Users\kkjjy\Documents\WorldSim\output\rain_sim"
os.makedirs(output_dir, exist_ok=True)

print(f"비 시뮬레이션 시작 ({n_frames}프레임)...")
all_positions = []

for frame in range(n_frames):
    scene.step()
    pos = rain.get_particles_pos()    # (N, 3) 파티클 위치
    pos_np = pos.cpu().numpy()
    all_positions.append(pos_np)

    if (frame + 1) % 20 == 0:
        print(f"  {frame+1}/{n_frames} 완료 | 파티클 수: {len(pos_np)}")

# numpy 배열로 저장
all_positions = np.array(all_positions)   # (frames, N, 3)
save_path = os.path.join(output_dir, "rain_particles.npy")
np.save(save_path, all_positions)

print(f"\n완료! 저장: {save_path}")
print(f"데이터 형태: {all_positions.shape}  (프레임, 파티클수, XYZ)")
