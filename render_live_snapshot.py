"""
forest_rain_live.py 수정사항(지면 경계선 제거, 강수강도별 비 양/크기) 확인용
헤드리스 스냅샷 — Blender 5.1에서:
  blender --background --python render_live_snapshot.py
로 실행하면 output/WS_forest_rain_live_check.png 를 만듦.

사운드 동기화 버그 수정·천둥 신뢰성 개선·카메라 플라이 모드는 실시간 GUI
상호작용(오디오 재생, 모달 입력)이라 정지 이미지 한 장으로는 증명이 안 됨 —
이 스냅샷은 "눈으로 바로 보이는" 두 가지(지면 이음새, 비 양/크기)만 확인.
"""
import bpy
import os

_SCRIPT_DIR = r"C:\Users\kkjjy\Documents\WorldSim"
with open(os.path.join(_SCRIPT_DIR, "forest_rain_live.py"), encoding="utf-8") as f:
    exec(compile(f.read(), "forest_rain_live.py", "exec"), globals())

scene = bpy.context.scene
scene.frame_set(120)  # 5초 지점 — 비가 충분히 떨어지고 스플래시도 보일 시점
update_scene(scene)

scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.filepath = os.path.join(_SCRIPT_DIR, "output", "WS_forest_rain_live_check.png")
scene.render.image_settings.file_format = 'PNG'
os.makedirs(os.path.join(_SCRIPT_DIR, "output"), exist_ok=True)
bpy.ops.render.render(write_still=True)
print("저장 완료:", scene.render.filepath)
