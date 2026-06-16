import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

import genesis as gs

# Genesis 초기화 (GPU)
gs.init(backend=gs.cuda)

# 씬 생성
scene = gs.Scene(show_viewer=False)

# 바닥
plane = scene.add_entity(gs.morphs.Plane())

# 물 입자 (SPH 유체)
liquid = scene.add_entity(
    material=gs.materials.SPH.Liquid(sampler='random'),
    morph=gs.morphs.Box(
        pos=(0, 0, 0.5),
        size=(0.4, 0.4, 0.4),
    ),
    surface=gs.surfaces.Default(color=(0.4, 0.7, 1.0, 1.0)),
)

# 빌드
scene.build()

# 10스텝 시뮬레이션
print("시뮬레이션 시작...")
for i in range(10):
    scene.step()
    print(f"  스텝 {i+1}/10 완료")

print("Genesis 물리 시뮬레이션 성공!")
