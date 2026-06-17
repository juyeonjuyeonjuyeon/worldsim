"""
WS_mars_sunset v001
화성 일몰 씬 – 실제 물리 기반

물리 근거:
- 화성 대기: 주로 CO₂, 기압 0.6 kPa (지구의 0.6%)
- 화성 일몰: Rayleigh 산란보다 먼지(적철석) 산란이 지배적
  → 낮엔 분홍/황갈색 하늘, 일몰엔 태양 주변만 파랗게 변함 (지구와 반대)
  → 파란 코로나: 크기 ~500nm 먼지 입자의 전방 산란(Mie scattering)
- 태양 겉보기 크기: 화성에서 0.35° (지구의 0.53°보다 작음)
- 중력: 3.72 m/s² (지구의 38%)
- 참고: Mars Curiosity/Perseverance 로버 실제 일몰 사진 색상값 반영

하늘 구현: Blender는 지구 대기 모델 내장 → 화성은 커스텀 sky shader 필요
ShaderNodeBackground + 방향 기반 그라디언트로 실제 화성 노을 색상 재현
"""
import bpy
import math
import random

# =============================================
# 씬 초기화
# =============================================
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for x in list(bpy.data.meshes):    bpy.data.meshes.remove(x)
for x in list(bpy.data.materials): bpy.data.materials.remove(x)
for x in list(bpy.data.curves):    bpy.data.curves.remove(x)

scene = bpy.context.scene

# =============================================
# 화성 하늘 – 커스텀 월드 셰이더
# 실제 색상 (Curiosity 로버 이미지 기반):
#   지평선 하늘:    (0.85, 0.68, 0.52) = 황갈색/살구색
#   상공:           (0.52, 0.40, 0.30) = 어두운 갈색
#   태양 주변 코로나: (0.25, 0.45, 0.80) = 파란색 (Mie 전방산란)
#   태양 원반:      (1.0, 0.95, 0.80)  = 흰빛 노란색 (화성에서 더 작고 흰색)
# =============================================
world = bpy.data.worlds["World"]
world.use_nodes = True
nt = world.node_tree
nodes = nt.nodes
links = nt.links
for n in list(nodes): nodes.remove(n)

# World 셰이더에서 실제 하늘 방향 벡터: ShaderNodeNewGeometry → Incoming
# Incoming = 카메라 레이 방향 (하늘을 향하는 단위 벡터)
# Z: +1=천정, 0=지평선, -1=지면 아래
geo  = nodes.new("ShaderNodeNewGeometry")
sep  = nodes.new("ShaderNodeSeparateXYZ")

# 태양 방향 벡터 (일몰: 고도각 5°, +X 방향이 동쪽)
sun_elev_rad = math.radians(5.0)
sun_dir_x = math.cos(sun_elev_rad)   # ~0.996
sun_dir_z = math.sin(sun_elev_rad)   # ~0.087

# 코로나 계산: dot(sky_incoming, sun_dir) → 태양 근접도
dot_node = nodes.new("ShaderNodeVectorMath")
dot_node.operation = 'DOT_PRODUCT'
sun_vec = nodes.new("ShaderNodeCombineXYZ")
sun_vec.inputs["X"].default_value = sun_dir_x
sun_vec.inputs["Y"].default_value = 0.0
sun_vec.inputs["Z"].default_value = sun_dir_z

# 고도 기반 그라디언트
# Incoming.Z: 지평선=0, 천정=1 → MapRange로 정규화
z_remap = nodes.new("ShaderNodeMapRange")
z_remap.inputs["From Min"].default_value = -0.2   # 지평선 조금 아래부터
z_remap.inputs["From Max"].default_value =  1.0   # 천정
z_remap.inputs["To Min"].default_value   =  0.0
z_remap.inputs["To Max"].default_value   =  1.0

elev_ramp = nodes.new("ShaderNodeValToRGB")
elev_ramp.color_ramp.interpolation = 'LINEAR'
elev_ramp.color_ramp.elements[0].position = 0.0
elev_ramp.color_ramp.elements[0].color    = (0.88, 0.70, 0.52, 1.0)  # 지평선: 황갈
elev_ramp.color_ramp.elements[1].position = 1.0
elev_ramp.color_ramp.elements[1].color    = (0.38, 0.26, 0.18, 1.0)  # 상공: 짙은 갈색
elev_ramp.color_ramp.elements.new(0.12)
elev_ramp.color_ramp.elements[1].color    = (0.92, 0.76, 0.58, 1.0)  # 지평선 위 밝은 띠

# 태양 코로나 (파란 Mie 전방산란 효과)
corona_ramp = nodes.new("ShaderNodeValToRGB")
corona_ramp.color_ramp.interpolation = 'EASE'
corona_ramp.color_ramp.elements[0].position = 0.0
corona_ramp.color_ramp.elements[0].color    = (0.0, 0.0, 0.0, 1.0)
corona_ramp.color_ramp.elements[1].position = 1.0
corona_ramp.color_ramp.elements[1].color    = (0.0, 0.0, 0.0, 1.0)
corona_ramp.color_ramp.elements.new(0.88)
corona_ramp.color_ramp.elements[2].color    = (0.10, 0.25, 0.65, 1.0)  # 파란 코로나
corona_ramp.color_ramp.elements.new(0.98)
corona_ramp.color_ramp.elements[3].color    = (0.92, 0.90, 0.80, 1.0)  # 태양 원반

# 하늘색 = 고도 그라디언트 + 코로나 오버레이
mix_sky = nodes.new("ShaderNodeMixRGB")
mix_sky.blend_type = 'ADD'
mix_sky.inputs["Fac"].default_value = 1.0

bg = nodes.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = 1.2

out_w = nodes.new("ShaderNodeOutputWorld")

# 연결: Incoming → 고도(Z) + 코로나(dot)
links.new(geo.outputs["Incoming"],    sep.inputs["Vector"])
links.new(sep.outputs["Z"],           z_remap.inputs["Value"])
links.new(z_remap.outputs["Result"],  elev_ramp.inputs["Fac"])

links.new(geo.outputs["Incoming"],    dot_node.inputs[0])
links.new(sun_vec.outputs["Vector"],  dot_node.inputs[1])
links.new(dot_node.outputs["Value"],  corona_ramp.inputs["Fac"])

links.new(elev_ramp.outputs["Color"],  mix_sky.inputs["Color1"])
links.new(corona_ramp.outputs["Color"],mix_sky.inputs["Color2"])
links.new(mix_sky.outputs["Color"],    bg.inputs["Color"])
links.new(bg.outputs["Background"],    out_w.inputs["Surface"])

# =============================================
# 태양 (화성에서 더 작고 흰색)
# 겉보기 크기: 0.35° (지구 0.53°의 66%)
# =============================================
bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
sun = bpy.context.active_object
sun.name = "MarsSun"
sun.data.energy = 590          # W/m² (화성 태양상수 ≈ 590, 지구 1361)
sun.data.angle  = math.radians(0.35)   # 화성에서 태양 겉보기 크기
sun.rotation_euler[0] = math.radians(90 - 5.0)   # 고도 5° (일몰)
sun.rotation_euler[2] = math.radians(0)            # 동쪽
sun.data.color = (1.0, 0.96, 0.88)    # 화성 태양: 약간 흰빛 (먼지 필터 후)

# 앰비언트: 화성 하늘의 산란광 (적색 기조)
bpy.ops.object.light_add(type='AREA', location=(0, 0, 20))
amb = bpy.context.active_object
amb.data.energy = 120
amb.data.size   = 30
amb.data.color  = (0.85, 0.62, 0.45)   # 황갈색 환경광 (지표 반사 포함)

# =============================================
# 화성 지형
# 특징: 붉은 현무암 + 적철석 먼지 + 바위 흩뿌림
# 화성 표면 색: RGB(0.65, 0.30, 0.15) 정도
# =============================================
bpy.ops.mesh.primitive_plane_add(size=100, location=(0, 0, 0))
terrain = bpy.context.active_object
terrain.name = "MarsTerrain"
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.subdivide(number_cuts=40)
bpy.ops.object.mode_set(mode='OBJECT')

# 지형 변위: 화성의 완만한 구릉 (에올리스 지역 같은 평탄한 지형)
displace = terrain.modifiers.new("Displace", 'DISPLACE')
noise_tex = bpy.data.textures.new("MarsNoise", type='CLOUDS')
noise_tex.noise_scale = 8.0    # 큰 지형 특성
displace.texture = noise_tex
displace.strength = 1.2
bpy.ops.object.modifier_apply(modifier="Displace")

# 화성 지면 재질
mars_ground_mat = bpy.data.materials.new("MarsGround")
mars_ground_mat.use_nodes = True
mg = mars_ground_mat.node_tree.nodes["Principled BSDF"]
mg.inputs["Base Color"].default_value = (0.62, 0.28, 0.12, 1.0)   # 붉은 현무암
mg.inputs["Roughness"].default_value  = 0.92                       # 매우 거친 먼지 표면
mg.inputs["Metallic"].default_value   = 0.0
terrain.data.materials.append(mars_ground_mat)

# =============================================
# 화성 바위 (랜덤 배치 30개)
# 형태: 불규칙한 각진 블록 (풍화된 현무암)
# =============================================
rock_mat = bpy.data.materials.new("MarsRock")
rock_mat.use_nodes = True
rk = rock_mat.node_tree.nodes["Principled BSDF"]
rk.inputs["Base Color"].default_value = (0.45, 0.22, 0.10, 1.0)   # 짙은 현무암
rk.inputs["Roughness"].default_value  = 0.85

random.seed(13)
for _ in range(30):
    rx = random.uniform(-35, 35)
    ry = random.uniform(-35, 35)
    rz = random.uniform(0.1, 0.5)   # 지면 위 살짝
    rs = random.uniform(0.3, 2.5)   # 크기 0.3~2.5m
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=rs,
                                          location=(rx, ry, rz))
    rock = bpy.context.active_object
    # 불규칙한 모양: 비균일 스케일
    rock.scale = (random.uniform(0.6, 1.4),
                  random.uniform(0.6, 1.4),
                  random.uniform(0.3, 0.8))   # 납작하게
    bpy.ops.object.transform_apply(scale=True)
    rock.data.materials.append(rock_mat)

# =============================================
# 카메라: 지평선을 바라보는 저각도
# 일몰 방향(+X)을 향해 배치
# =============================================
bpy.ops.object.camera_add(location=(-15, -8, 2.5))
cam = bpy.context.active_object
cam.name = "MarsCamera"
cam.rotation_euler[0] = math.radians(88)    # 거의 수평
cam.rotation_euler[1] = 0
cam.rotation_euler[2] = math.radians(60)    # 일몰 방향 향함
cam.data.lens = 28                           # 광각 (화성의 광활한 느낌)
scene.camera = cam

# =============================================
# 렌더 설정
# =============================================
scene.render.engine = 'CYCLES'
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.image_settings.file_format = 'PNG'
scene.cycles.samples = 128
scene.cycles.use_denoising = True

try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = 'CUDA'
    prefs.get_devices()
    for d in prefs.devices: d.use = True
    scene.cycles.device = 'GPU'
except:
    scene.cycles.device = 'CPU'

import os
output_path = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_mars_sunset_v001.png"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
scene.render.filepath = output_path

print("화성 일몰 렌더링 중...")
bpy.ops.render.render(write_still=True)
print(f"완료: {output_path}")

bpy.ops.wm.save_as_mainfile(
    filepath=r"C:\Users\kkjjy\Documents\WorldSim\WS_mars_sunset_v001.blend"
)
print("씬 저장 완료")
