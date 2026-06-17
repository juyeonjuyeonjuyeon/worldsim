"""
PNG 시퀀스 → mp4 변환 (Blender VSE 방식)
forest_rain.py 렌더 완료 후 실행:
  blender --background --python make_video.py
"""
import bpy
import os

frame_dir = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v004"
n_frames  = 200
fps       = 24
output    = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v004.mp4"

# 파일 존재 확인
first = os.path.join(frame_dir, "WS_forest_rain_v004_0001.png")
if not os.path.exists(first):
    print(f"오류: 프레임 파일 없음 - {first}")
    exit(1)

actual_frames = [f for f in os.listdir(frame_dir)
                 if f.endswith(".png") and "v003_" in f]
print(f"발견된 프레임: {len(actual_frames)}개")

# 씬 초기화 (렌더 전용 씬)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end   = n_frames
scene.render.fps  = fps

# VSE 설정
if not scene.sequence_editor:
    scene.sequence_editor_create()
seq = scene.sequence_editor

# 이미 있는 스트립 삭제
for s in list(seq.sequences_all):
    seq.sequences.remove(s)

# 이미지 시퀀스 스트립 추가
strip = seq.sequences.new_image(
    name="RainSeq",
    filepath=os.path.join(frame_dir, "WS_forest_rain_v004_0001.png"),
    channel=1,
    frame_start=1
)
strip.directory = frame_dir + "\\"
for i in range(n_frames):
    fname = f"WS_forest_rain_v004_{i+1:04d}.png"
    if i < len(strip.elements):
        strip.elements[i].filename = fname
    else:
        strip.elements.append(fname)
strip.frame_final_duration = n_frames

print(f"스트립 길이: {strip.frame_final_duration}프레임")

# 렌더 출력: FFMPEG (Blender 내장)
scene.render.image_settings.file_format = 'FFMPEG'
scene.render.ffmpeg.format             = 'MPEG4'
scene.render.ffmpeg.codec              = 'H264'
scene.render.ffmpeg.constant_rate_factor = 'MEDIUM'
scene.render.ffmpeg.audio_codec        = 'NONE'
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.filepath = output

print(f"영상 합치기 중: {output}")
bpy.ops.render.render(animation=True)
print(f"완료: {output}")
