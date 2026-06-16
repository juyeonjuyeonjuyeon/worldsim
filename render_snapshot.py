import bpy
import sys

# 인자로 출력 파일명 받기 (없으면 기본값)
output_file = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else r"C:\Users\kkjjy\Documents\WorldSim\output\snapshot.png"

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = output_file

scene.cycles.samples = 128
scene.cycles.use_denoising = True

try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = 'CUDA'
    prefs.get_devices()
    for device in prefs.devices:
        device.use = True
    scene.cycles.device = 'GPU'
except:
    scene.cycles.device = 'CPU'

bpy.ops.render.render(write_still=True)
print(f"저장: {output_file}")
