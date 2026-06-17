"""
PNG 시퀀스 → mp4 변환 (ffmpeg 방식)
사용법: python make_video.py  OR  blender --background --python make_video.py

버전별 설정만 바꾸면 재사용 가능.
"""
import subprocess
import os
import glob

FFMPEG = r"C:\Users\kkjjy\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-8.1.1-full_build\bin\ffmpeg.exe"

VERSION   = "v004"
FPS       = 24
CRF       = 18      # 품질 (낮을수록 고품질, 18=고품질, 23=기본)
PREFIX    = f"WS_forest_rain_{VERSION}"
FRAME_DIR = rf"C:\Users\kkjjy\Documents\WorldSim\output\{PREFIX}"
OUTPUT    = rf"C:\Users\kkjjy\Documents\WorldSim\output\{PREFIX}.mp4"

# 프레임 존재 확인
first = os.path.join(FRAME_DIR, f"{PREFIX}_0001.png")
if not os.path.exists(first):
    print(f"오류: 프레임 없음 - {first}")
    exit(1)

frames = glob.glob(os.path.join(FRAME_DIR, f"{PREFIX}_*.png"))
print(f"발견 프레임: {len(frames)}개")

# ffmpeg 실행
pattern = os.path.join(FRAME_DIR, f"{PREFIX}_%04d.png")
cmd = [
    FFMPEG, "-y",
    "-framerate", str(FPS),
    "-i", pattern,
    "-c:v", "libx264",
    "-pix_fmt", "yuv420p",
    "-crf", str(CRF),
    OUTPUT
]

print(f"변환 중: {OUTPUT}")
result = subprocess.run(cmd, capture_output=True, text=True)
if result.returncode == 0:
    size_mb = os.path.getsize(OUTPUT) / 1024 / 1024
    print(f"완료: {OUTPUT}  ({size_mb:.1f} MB)")
else:
    print("ffmpeg 오류:")
    print(result.stderr[-500:])
