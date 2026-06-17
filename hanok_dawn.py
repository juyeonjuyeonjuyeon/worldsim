"""
WS_hanok_dawn v001
조선시대 한옥 새벽 씬

건축 물리 근거:
- 기와지붕: 점토 기와 (청회색), 무게 분산을 위한 곡선형 추녀
- 추녀들림: 처마 끝이 위로 들림 (하중 + 빗물 튀김 방지 + 미적)
- 기단: 지면 습기 차단 + 통풍을 위해 40~60cm 높임
- 기둥: 흘림기둥 (아래가 굵고 위로 갈수록 약간 좁아짐)
- 새벽 빛: 동쪽 지평선 주황/금색 + 하늘 짙은 청색
- 처마 아래 그림자: 깊은 처마가 만드는 특유의 그늘
- 마당: 다진 흙 또는 돌 박음 (조선 후기)
- 잣나무/소나무: 마당 한쪽에 배치
"""
import bpy
import math
import random
import os

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
# 재질 헬퍼
# =============================================
def make_mat(name, color, roughness=0.8, metallic=0.0, emission=(0,0,0,1), emit_str=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value  = roughness
    b.inputs["Metallic"].default_value   = metallic
    if emit_str > 0:
        b.inputs["Emission Color"].default_value    = emission
        b.inputs["Emission Strength"].default_value = emit_str
    return mat

# =============================================
# 마당 (흙 마당)
# =============================================
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
courtyard = bpy.context.active_object
courtyard.name = "Courtyard"
# 약간의 울퉁불퉁함 (옛 마당)
displace = courtyard.modifiers.new("Displace", 'DISPLACE')
noise = bpy.data.textures.new("CourtNoise", type='CLOUDS')
noise.noise_scale = 5.0
displace.texture = noise
displace.strength = 0.06
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.subdivide(number_cuts=20)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.modifier_apply(modifier="Displace")
courtyard.data.materials.append(
    make_mat("DirtGround", (0.42, 0.34, 0.22, 1), roughness=0.92)
)

# =============================================
# 한옥 본채: 기단 + 기둥 + 지붕
# 규모: 정면 3칸 (약 12m), 측면 2칸 (약 7m)
# =============================================
bldg_x  =  0.0    # 건물 중심 X
bldg_y  =  4.0    # 건물 중심 Y (마당 뒤쪽)
bldg_w  = 12.0    # 정면 폭
bldg_d  =  7.0    # 측면 깊이
bldg_h  =  3.8    # 기둥 높이 (처마 높이)
ridge_h =  5.8    # 용마루 높이
plat_h  =  0.55   # 기단 높이

# ─── 기단 (돌 받침) ───
bpy.ops.mesh.primitive_cube_add(
    size=1,
    location=(bldg_x, bldg_y, plat_h/2)
)
platform = bpy.context.active_object
platform.name = "Gidan"
platform.scale = (bldg_w/2 + 0.8, bldg_d/2 + 0.6, plat_h/2)
bpy.ops.object.transform_apply(scale=True)
platform.data.materials.append(
    make_mat("StoneGidan", (0.52, 0.50, 0.48, 1), roughness=0.80)
)

# ─── 마루 (나무 바닥) ───
bpy.ops.mesh.primitive_cube_add(
    size=1,
    location=(bldg_x, bldg_y, plat_h + 0.05)
)
floor = bpy.context.active_object
floor.name = "Maru"
floor.scale = (bldg_w/2, bldg_d/2, 0.05)
bpy.ops.object.transform_apply(scale=True)
floor.data.materials.append(
    make_mat("WoodMaru", (0.55, 0.38, 0.20, 1), roughness=0.35)
)

# ─── 기둥 (흘림기둥: 원통형) ───
# 정면 4개 + 후면 4개 = 8개
pillar_mat = make_mat("RedPillar", (0.58, 0.12, 0.05, 1), roughness=0.25)
col_h = bldg_h - plat_h
col_positions_x = [-bldg_w/2 + 0.5, -bldg_w/6, bldg_w/6, bldg_w/2 - 0.5]
col_positions_y = [bldg_y - bldg_d/2 + 0.5, bldg_y + bldg_d/2 - 0.5]

for px in col_positions_x:
    for py in col_positions_y:
        z_base = plat_h + col_h/2
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=16, radius=0.18, depth=col_h,
            location=(px, py, z_base)
        )
        col = bpy.context.active_object
        col.data.materials.append(pillar_mat)

# ─── 평방/창방 (기둥 위 가로 보) ───
beam_mat = make_mat("WoodBeam", (0.50, 0.32, 0.15, 1), roughness=0.40)
# 정면 보
bpy.ops.mesh.primitive_cube_add(
    size=1, location=(bldg_x, bldg_y - bldg_d/2 + 0.5, bldg_h - 0.12)
)
beam_f = bpy.context.active_object; beam_f.name = "BeamFront"
beam_f.scale = (bldg_w/2, 0.12, 0.12); bpy.ops.object.transform_apply(scale=True)
beam_f.data.materials.append(beam_mat)
# 후면 보
bpy.ops.mesh.primitive_cube_add(
    size=1, location=(bldg_x, bldg_y + bldg_d/2 - 0.5, bldg_h - 0.12)
)
beam_b = bpy.context.active_object; beam_b.name = "BeamBack"
beam_b.scale = (bldg_w/2, 0.12, 0.12); bpy.ops.object.transform_apply(scale=True)
beam_b.data.materials.append(beam_mat)
# 측면 보 (좌/우)
for sx in [-bldg_w/2 + 0.5, bldg_w/2 - 0.5]:
    bpy.ops.mesh.primitive_cube_add(
        size=1, location=(sx, bldg_y, bldg_h - 0.12)
    )
    beam_s = bpy.context.active_object
    beam_s.scale = (0.12, bldg_d/2 - 0.4, 0.12); bpy.ops.object.transform_apply(scale=True)
    beam_s.data.materials.append(beam_mat)

# ─── 기와지붕 (팔작지붕 근사) ───
# 용마루 + 내림마루 4개 + 처마선으로 구성
# 방법: 꼭짓점 수동 배치 → 메쉬 생성
import bmesh

roof_mat = make_mat("GiwaRoof", (0.22, 0.24, 0.26, 1), roughness=0.55)

def make_hipped_roof(cx, cy, w, d, eave_h, ridge_h, overhang=1.8):
    """
    팔작지붕(Hipped roof):
    - 전후면: 삼각형 박공 + 경사면
    - 좌우면: 경사면
    - 처마 오버행: 기둥 바깥으로 돌출
    - 추녀들림: 네 모서리가 위로 들림
    """
    ow = w/2 + overhang
    od = d/2 + overhang
    upturn = 0.35   # 추녀들림 높이 (모서리가 올라가는 양)
    ridge_w = w * 0.55   # 용마루 길이

    # 지붕 꼭짓점 정의
    # 모서리 처마 (추녀, 위로 들림)
    corners = [
        (-ow, cy - od, eave_h + upturn),  # 앞왼쪽
        ( ow, cy - od, eave_h + upturn),  # 앞오른쪽
        ( ow, cy + od, eave_h + upturn),  # 뒤오른쪽
        (-ow, cy + od, eave_h + upturn),  # 뒤왼쪽
    ]
    # 처마 중간 (추녀 사이, 약간 낮음)
    mid_eave = [
        (0,        cy - od, eave_h),       # 앞 중앙
        ( ow,      cy,      eave_h),       # 오른쪽 중앙
        (0,        cy + od, eave_h),       # 뒤 중앙
        (-ow,      cy,      eave_h),       # 왼쪽 중앙
    ]
    # 용마루 (ridge)
    ridge = [
        (-ridge_w/2 + cx, cy, ridge_h),   # 용마루 왼쪽 끝
        ( ridge_w/2 + cx, cy, ridge_h),   # 용마루 오른쪽 끝
    ]

    mesh = bpy.data.meshes.new("HanokRoof")
    bm = bmesh.new()

    # 모든 꼭짓점 추가
    cv = [bm.verts.new(co) for co in corners]   # 0-3: 모서리
    mv = [bm.verts.new(co) for co in mid_eave]  # 4-7: 처마 중간
    rv = [bm.verts.new(co) for co in ridge]     # 8-9: 용마루

    bm.verts.ensure_lookup_table()

    # 앞면: 모서리(0) - 처마앞(4) - 모서리(1) - 용마루왼(8) - 용마루오(9)
    bm.faces.new([cv[0], mv[0], cv[1], rv[1], rv[0]])
    # 오른면: 모서리(1) - 처마오(5) - 모서리(2) - 용마루오(9)
    bm.faces.new([cv[1], mv[1], cv[2], rv[1]])
    # 뒷면: 모서리(2) - 처마뒤(6) - 모서리(3) - 용마루왼(8) - 용마루오(9)
    bm.faces.new([cv[2], mv[2], cv[3], rv[0], rv[1]])
    # 왼면: 모서리(3) - 처마왼(7) - 모서리(0) - 용마루왼(8)
    bm.faces.new([cv[3], mv[3], cv[0], rv[0]])

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj = bpy.data.objects.new("HanokRoof", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(roof_mat)

    # 기와 질감: 법선 맵 효과를 위한 Displace 모디파이어
    disp = obj.modifiers.new("TileDisplace", 'DISPLACE')
    tile_tex = bpy.data.textures.new("GiwaTile", type='STUCCI')
    tile_tex.noise_scale = 0.15
    tile_tex.stucci_type = 'WALL_IN'
    disp.texture = tile_tex
    disp.strength = 0.03
    disp.texture_coords = 'LOCAL'

    return obj

make_hipped_roof(bldg_x, bldg_y, bldg_w, bldg_d,
                 eave_h=bldg_h, ridge_h=ridge_h)

# ─── 담장 (돌담) ───
wall_mat = make_mat("StoneWall", (0.55, 0.52, 0.47, 1), roughness=0.85)
# 앞 담장 (문 있는 쪽)
for wx in [-14, 14]:
    bpy.ops.mesh.primitive_cube_add(size=1, location=(wx * 0.85, -15, 1.2))
    wobj = bpy.context.active_object
    wobj.scale = (2.5, 0.35, 1.2); bpy.ops.object.transform_apply(scale=True)
    wobj.data.materials.append(wall_mat)
# 옆 담장
for wy in [-1, 1]:
    bpy.ops.mesh.primitive_cube_add(size=1, location=(wy*20, 0, 1.2))
    wobj = bpy.context.active_object
    wobj.scale = (0.35, 15, 1.2); bpy.ops.object.transform_apply(scale=True)
    wobj.data.materials.append(wall_mat)

# ─── 솟을대문 (정문) ───
gate_mat = make_mat("WoodGate", (0.48, 0.30, 0.12, 1), roughness=0.45)
# 문 기둥 2개
for gx in [-2.0, 2.0]:
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.22, depth=4.5,
                                        location=(gx, -15, 2.25))
    bpy.context.active_object.data.materials.append(gate_mat)
# 문 상부 지붕 (간략화)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -15, 4.2))
gate_roof = bpy.context.active_object
gate_roof.scale = (2.8, 0.4, 0.25); bpy.ops.object.transform_apply(scale=True)
gate_roof.data.materials.append(roof_mat)

# ─── 소나무 (마당 한쪽) ───
pine_trunk_mat = make_mat("PineTrunk", (0.35, 0.22, 0.10, 1), roughness=0.80)
pine_leaf_mat  = make_mat("PineLeaf",  (0.06, 0.22, 0.08, 1), roughness=0.75)
random.seed(5)
for tree_i, (tx, ty) in enumerate([(-16, -8), (14, -10), (-14, 10)]):
    trunk_h = random.uniform(4.5, 7.0)
    for i in range(6):
        seg_h = trunk_h / 6
        r = 0.14 * (1 - i * 0.10)
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=r, depth=seg_h,
            location=(tx, ty, i * seg_h + seg_h/2))
        bpy.context.active_object.data.materials.append(pine_trunk_mat)
    # 솔잎 클러스터 (납작한 구 여러 개)
    for _ in range(8):
        cz = trunk_h * random.uniform(0.4, 1.0)
        cr = random.uniform(0.6, 1.4)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=cr,
            location=(tx + random.uniform(-1,1), ty + random.uniform(-1,1), cz))
        pn = bpy.context.active_object
        pn.scale.z = 0.5
        bpy.ops.object.transform_apply(scale=True)
        pn.data.materials.append(pine_leaf_mat)

# ─── 장독대 (옹기항아리 3개) ───
jang_mat = make_mat("Onggi", (0.30, 0.18, 0.10, 1), roughness=0.70)
for ji, jpos in enumerate([(6, -6, 0.5), (7.5, -5.5, 0.45), (5, -5, 0.55)]):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=16, ring_count=8, radius=jpos[2],
        location=(jpos[0], jpos[1], jpos[2])
    )
    jobj = bpy.context.active_object
    jobj.scale.z = 1.2; bpy.ops.object.transform_apply(scale=True)
    jobj.data.materials.append(jang_mat)

# =============================================
# 새벽 하늘 (동쪽 지평선 주황, 서쪽/상공 짙은 청색)
# 물리 근거: 일출 전 박명(薄明) – 태양이 지평선 아래 5~10°
# Rayleigh 산란: 짧은 파장(파란빛) 전파 > 긴 파장
# 지평선 근처: 대기 경로 길어짐 → 황/주황 투과
# =============================================
world = bpy.data.worlds["World"]
world.use_nodes = True
wn = world.node_tree.nodes
wl = world.node_tree.links
for n in list(wn): wn.remove(n)

sky = wn.new("ShaderNodeTexSky")
sky.sky_type        = 'MULTIPLE_SCATTERING'
sky.sun_elevation   = math.radians(-3)    # 태양이 지평선 아래 3° (새벽 박명)
sky.sun_rotation    = math.radians(90)    # 동쪽 (일출 방향)
sky.air_density     = 1.0
sky.aerosol_density = 2.5
sky.ozone_density   = 1.0

bg  = wn.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = 0.30   # 어두운 새벽
out_w = wn.new("ShaderNodeOutputWorld")
wl.new(sky.outputs["Color"], bg.inputs["Color"])
wl.new(bg.outputs["Background"], out_w.inputs["Surface"])

# =============================================
# 조명: 새벽빛
# =============================================
# 동쪽 주광 (태양 직전의 박명 빛 – 주황/금색)
bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
dawn_sun = bpy.context.active_object
dawn_sun.name = "DawnLight"
dawn_sun.data.energy = 0.6     # 약한 새벽빛
dawn_sun.data.angle  = math.radians(5)
dawn_sun.data.color  = (1.0, 0.72, 0.42)   # 주황/금색
dawn_sun.rotation_euler[0] = math.radians(88)   # 거의 수평
dawn_sun.rotation_euler[2] = math.radians(90)   # 동쪽

# 하늘 앰비언트 (파란 새벽빛 – 서쪽 하늘 반사)
bpy.ops.object.light_add(type='AREA', location=(0, 0, 20))
sky_amb = bpy.context.active_object
sky_amb.data.energy = 25
sky_amb.data.size   = 25
sky_amb.data.color  = (0.42, 0.56, 0.90)   # 서늘한 청색 (새벽 하늘)

# 종이 등불 (건물 처마 아래) – 새벽 한옥의 따뜻한 빛
bpy.ops.object.light_add(type='POINT', location=(bldg_x, bldg_y - bldg_d/2 + 1.5, bldg_h - 0.8))
lantern = bpy.context.active_object
lantern.name = "HanjiLantern"
lantern.data.energy = 80
lantern.data.color  = (1.0, 0.82, 0.52)   # 한지 등불: 따뜻한 노란빛
lantern.data.shadow_soft_size = 0.15

# =============================================
# 카메라: 솟을대문에서 본채를 바라보는 시점
# 처마 아래 그림자 보이도록 앙각 25°
# =============================================
bpy.ops.object.camera_add(location=(-8, -22, 3.5))
cam = bpy.context.active_object
cam.name = "HanokCamera"
cam.rotation_euler[0] = math.radians(78)
cam.rotation_euler[1] = 0.0
cam.rotation_euler[2] = math.radians(25)
cam.data.lens = 35
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

output_path = r"C:\Users\kkjjy\Documents\WorldSim\output\WS_hanok_dawn_v001.png"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
scene.render.filepath = output_path

print("한옥 새벽 씬 렌더링 중...")
bpy.ops.render.render(write_still=True)
print(f"완료: {output_path}")

bpy.ops.wm.save_as_mainfile(
    filepath=r"C:\Users\kkjjy\Documents\WorldSim\WS_hanok_dawn_v001.blend"
)
print("씬 저장 완료")
