"""
PNG 시퀀스 → mp4 변환 (v003 전용, Blender VSE)
blender --background --python make_video_v003.py
"""
import bpy, os

frame_dir = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v003"
n_frames  = 200
fps       = 24
output    = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_forest_rain_v003.mp4"
prefix    = "WS_forest_rain_v003"

first = os.path.join(frame_dir, f"{prefix}_0001.png")
if not os.path.exists(first):
    print(f"오류: 프레임 없음 - {first}"); exit(1)

actual = [f for f in os.listdir(frame_dir) if f.endswith(".png") and prefix in f]
print(f"발견된 프레임: {len(actual)}개")

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

scene = bpy.context.scene
scene.frame_start = 1; scene.frame_end = n_frames; scene.render.fps = fps

if not scene.sequence_editor: scene.sequence_editor_create()
seq = scene.sequence_editor
for s in list(seq.sequences): seq.sequences.remove(s)

strip = seq.sequences.new_image(name="Seq", filepath=first, channel=1, frame_start=1)
strip.directory = frame_dir + "\\"
for i in range(n_frames):
    fname = f"{prefix}_{i+1:04d}.png"
    if i < len(strip.elements): strip.elements[i].filename = fname
strip.frame_final_duration = n_frames

scene.render.image_settings.file_format = 'FFMPEG'
scene.render.ffmpeg.format = 'MPEG4'
scene.render.ffmpeg.codec = 'H264'
scene.render.ffmpeg.constant_rate_factor = 'MEDIUM'
scene.render.ffmpeg.audio_codec = 'NONE'
scene.render.resolution_x = 1920; scene.render.resolution_y = 1080
scene.render.filepath = output

print(f"영상 합치기: {output}")
bpy.ops.render.render(animation=True)
print(f"완료: {output}")
