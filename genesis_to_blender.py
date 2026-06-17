import bpy
import numpy as np
import math
import os

# --- Genesis 파티클 데이터 로드 ---
data_path = r"C:\Users\kkjjy\Documents\WorldSim\output\rain_sim\rain_particles.npy"
particles = np.load(data_path)   # (120, 36000, 3)
n_frames, n_particles, _ = particles.shape
print(f"데이터 로드: {n_frames}프레임, {n_particles}파티클")

# --- 기존 씬 초기화 ---
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

# --- 파티클 표현: 프레임마다 메시 버텍스 위치 갱신 ---
# 빗방울 모양 기본 오브젝트 (아주 작은 구)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.012)
drop_template = bpy.context.active_object
drop_template.name = "RainDrop"

# 빗방울 재질
mat = bpy.data.materials.new("RainMat")
mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.5, 0.75, 1.0, 1.0)
bsdf.inputs["Roughness"].default_value = 0.0
bsdf.inputs["Transmission Weight"].default_value = 0.9   # 반투명
bsdf.inputs["IOR"].default_value = 1.33                  # 물 굴절률
drop_template.data.materials.append(mat)

# --- 파티클 시스템으로 인스턴싱 ---
# 빈 메시로 파티클 위치 표현 (버텍스 = 빗방울 위치)
bpy.ops.mesh.primitive_plane_add(size=0.001, location=(0, 0, -10))
particle_mesh_obj = bpy.context.active_object
particle_mesh_obj.name = "RainParticles"

# 파티클 시스템 추가
ps = particle_mesh_obj.modifiers.new("RainPS", 'PARTICLE_SYSTEM')
psys = particle_mesh_obj.particle_systems[0]
psys.settings.count = min(n_particles, 5000)   # 성능을 위해 5000개로 제한
psys.settings.emit_from = 'VERT'
psys.settings.lifetime = n_frames
psys.settings.object_align_factor = (0, 0, -1)

# --- 지면 (물이 쌓이는 곳) ---
bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"
gmat = bpy.data.materials.new("GroundMat")
gmat.use_nodes = True
bsdf_g = gmat.node_tree.nodes["Principled BSDF"]
bsdf_g.inputs["Base Color"].default_value = (0.08, 0.18, 0.05, 1)
bsdf_g.inputs["Roughness"].default_value = 0.85
ground.data.materials.append(gmat)

# --- 프레임별 파티클 위치를 메시 Shape Key로 애니메이션 ---
# (파티클 수를 줄여서 성능 최적화)
step = max(1, n_particles // 2000)   # 최대 2000개 샘플
sample_idx = np.arange(0, n_particles, step)[:2000]

# 포인트 클라우드 메시 생성
mesh = bpy.data.meshes.new("CloudMesh")
cloud_obj = bpy.data.objects.new("PointCloud", mesh)
bpy.context.collection.objects.link(cloud_obj)

# 첫 프레임 버텍스
first_frame_pos = particles[0][sample_idx]
verts = [tuple(p) for p in first_frame_pos]
mesh.from_pydata(verts, [], [])
mesh.update()

# Shape Keys로 프레임별 위치 애니메이션
cloud_obj.shape_key_add(name="Basis")

scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = n_frames

# 5프레임마다 Shape Key 추가 (성능 최적화)
for f in range(0, n_frames, 5):
    sk = cloud_obj.shape_key_add(name=f"Frame_{f:04d}")
    frame_pos = particles[f][sample_idx]
    for i, p in enumerate(frame_pos):
        sk.data[i].co = tuple(p)

    # 해당 프레임에 value=1, 나머지 0으로 키프레임
    scene.frame_set(f + 1)
    for key in cloud_obj.data.shape_keys.key_blocks[1:]:
        key.value = 0.0
        key.keyframe_insert("value")
    sk.value = 1.0
    sk.keyframe_insert("value")

print(f"애니메이션 완료: {n_frames}프레임")

# --- 하늘 (기존 숲 씬과 동일) ---
world = bpy.data.worlds["World"]
world.use_nodes = True
nodes = world.node_tree.nodes
links = world.node_tree.links
for node in nodes:
    nodes.remove(node)

sky_tex = nodes.new("ShaderNodeTexSky")
sky_tex.sky_type = 'MULTIPLE_SCATTERING'
sky_tex.sun_elevation = math.radians(25)   # 오전 시간대
sky_tex.sun_rotation = math.radians(120)
sky_tex.aerosol_density = 2.5              # 흐린 날씨 (비)
sky_tex.air_density = 1.0

bg = nodes.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = 0.6  # 흐린 날씨라 어둡게
out = nodes.new("ShaderNodeOutputWorld")
links.new(sky_tex.outputs["Color"], bg.inputs["Color"])
links.new(bg.outputs["Background"], out.inputs["Surface"])

# --- 태양 (흐린 날) ---
bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
sun = bpy.context.active_object
sun.name = "Sun"
sun.data.energy = 1.5   # 흐린 날씨라 약하게
sun.rotation_euler[0] = math.radians(65)
sun.rotation_euler[2] = math.radians(120)

# --- 카메라 ---
bpy.ops.object.camera_add(location=(3, -4, 2))
cam = bpy.context.active_object
cam.name = "Camera"
cam.rotation_euler[0] = math.radians(70)
cam.rotation_euler[2] = math.radians(40)
cam.data.lens = 50
scene.camera = cam

# --- 렌더 설정 ---
scene.render.engine = 'CYCLES'
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.image_settings.file_format = 'PNG'
scene.cycles.samples = 64
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

# --- 프레임 60 렌더링 (중간 시점) ---
output_path = r"C:\Users\kkjjy\Documents\WorldSim\output\rain_render.png"
scene.render.filepath = output_path
scene.frame_set(60)
bpy.ops.render.render(write_still=True)
print(f"렌더링 완료: {output_path}")

# --- .blend 저장 ---
bpy.ops.wm.save_as_mainfile(
    filepath=r"C:\Users\kkjjy\Documents\WorldSim\rain_world.blend"
)
print("씬 저장 완료")
