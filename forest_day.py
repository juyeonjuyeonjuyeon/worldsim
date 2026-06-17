import bpy
import random
import math
import mathutils

# --- 초기화 ---
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for mesh in bpy.data.meshes:
    bpy.data.meshes.remove(mesh)

# --- 재질 생성 헬퍼 ---
def make_mat(name, color, roughness=0.9):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return mat

# --- 나무 생성 ---
def make_tree(x, y, scale, seed):
    random.seed(seed)
    tree_objects = []

    trunk_h = 2.8 * scale
    trunk_mat = make_mat(f"Trunk_{seed}", (0.20, 0.12, 0.05, 1))

    # 기둥 (5단 테이퍼)
    for i in range(5):
        seg_h = trunk_h / 5
        z_ctr = i * seg_h + seg_h / 2
        r = 0.13 * scale * (1 - i * 0.14)
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=10, radius=r, depth=seg_h,
            location=(x, y, z_ctr)
        )
        obj = bpy.context.active_object
        obj.data.materials.append(trunk_mat)
        tree_objects.append(obj)

    # 가지 (4~6개)
    n_branches = random.randint(4, 6)
    branch_mat = make_mat(f"Branch_{seed}", (0.18, 0.10, 0.04, 1))
    for i in range(n_branches):
        b_z = trunk_h * random.uniform(0.35, 0.80)
        b_angle = random.uniform(35, 65)
        b_dir = random.uniform(0, 360)
        b_len = scale * random.uniform(0.9, 1.6)

        rad_a = math.radians(b_angle)
        rad_d = math.radians(b_dir)
        bx = x + math.sin(rad_a) * math.cos(rad_d) * b_len * 0.5
        by = y + math.sin(rad_a) * math.sin(rad_d) * b_len * 0.5
        bz = b_z + math.cos(rad_a) * b_len * 0.5

        bpy.ops.mesh.primitive_cylinder_add(
            vertices=6, radius=0.04 * scale, depth=b_len,
            location=(bx, by, bz)
        )
        branch = bpy.context.active_object
        branch.rotation_euler[1] = rad_a
        branch.rotation_euler[2] = rad_d
        branch.data.materials.append(branch_mat)
        tree_objects.append(branch)

    # 잎 클러스터 (10~16개 구체 흩뿌리기)
    n_clusters = random.randint(10, 16)
    crown_base = trunk_h * 0.40
    crown_h = trunk_h * 0.75

    for i in range(n_clusters):
        t = random.uniform(0, 1)
        spread = (1 - t * 0.45) * scale * 1.1
        angle = random.uniform(0, 360)

        cx = x + spread * math.cos(math.radians(angle)) * random.uniform(0.2, 1.0)
        cy = y + spread * math.sin(math.radians(angle)) * random.uniform(0.2, 1.0)
        cz = crown_base + t * crown_h + random.uniform(-0.15, 0.15) * scale

        cr = scale * random.uniform(0.28, 0.52)
        g = random.uniform(0.22, 0.38)
        leaf_mat = make_mat(f"Leaf_{seed}_{i}", (0.05, g, 0.04, 1))

        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=2, radius=cr,
            location=(cx, cy, cz)
        )
        cluster = bpy.context.active_object
        cluster.scale.z = random.uniform(0.65, 1.25)
        bpy.ops.object.transform_apply(scale=True)
        cluster.data.materials.append(leaf_mat)
        tree_objects.append(cluster)

    return tree_objects

# --- 지형 ---
bpy.ops.mesh.primitive_plane_add(size=50, location=(0, 0, 0))
terrain = bpy.context.active_object
terrain.name = "Terrain"

bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.subdivide(number_cuts=30)
bpy.ops.object.mode_set(mode='OBJECT')

displace = terrain.modifiers.new(name="Displace", type='DISPLACE')
noise_tex = bpy.data.textures.new("TerrainNoise", type='CLOUDS')
noise_tex.noise_scale = 3.0
displace.texture = noise_tex
displace.strength = 0.8
bpy.ops.object.modifier_apply(modifier="Displace")
terrain.data.materials.append(make_mat("Ground", (0.10, 0.22, 0.06, 1)))

# --- 나무 배치 ---
random.seed(7)
for _ in range(22):
    x = random.uniform(-19, 19)
    y = random.uniform(-19, 19)
    if abs(x) < 5 and abs(y) < 5:
        continue
    scale = random.uniform(0.7, 1.8)
    seed = random.randint(0, 9999)
    make_tree(x, y, scale, seed)

# --- 하늘 ---
world = bpy.data.worlds["World"]
world.use_nodes = True
nodes = world.node_tree.nodes
links = world.node_tree.links
for node in nodes:
    nodes.remove(node)

sky_tex = nodes.new("ShaderNodeTexSky")
sky_tex.sky_type = 'MULTIPLE_SCATTERING'
sky_tex.air_density = 1.0
sky_tex.aerosol_density = 1.0
sky_tex.ozone_density = 1.0

bg = nodes.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = 1.0
out = nodes.new("ShaderNodeOutputWorld")
links.new(sky_tex.outputs["Color"], bg.inputs["Color"])
links.new(bg.outputs["Background"], out.inputs["Surface"])

# --- 태양 ---
bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
sun = bpy.context.active_object
sun.name = "Sun"
sun.data.energy = 5.0
sun.data.angle = math.radians(0.53)

# --- 24시간 애니메이션 ---
scene = bpy.context.scene
scene.frame_start = 0
scene.frame_end = 240
MAX_ELEV = math.radians(60)

for frame in range(0, 241, 5):
    hour = frame / 10.0
    elevation = MAX_ELEV * math.sin(2 * math.pi * (hour / 24) - math.pi / 2)
    azimuth = math.radians(hour / 24 * 360)

    scene.frame_set(frame)
    sky_tex.sun_elevation = elevation
    sky_tex.sun_rotation = azimuth
    sky_tex.keyframe_insert(data_path="sun_elevation", frame=frame)
    sky_tex.keyframe_insert(data_path="sun_rotation", frame=frame)
    sun.rotation_euler[0] = math.pi / 2 - elevation
    sun.rotation_euler[2] = azimuth
    sun.keyframe_insert(data_path="rotation_euler", frame=frame)

scene.frame_set(60)

# --- 카메라 ---
bpy.ops.object.camera_add(location=(12, -14, 4))
cam = bpy.context.active_object
cam.name = "Camera"
cam.rotation_euler[0] = math.radians(78)
cam.rotation_euler[2] = math.radians(40)
cam.data.lens = 35
scene.camera = cam

# --- 렌더 설정 ---
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080

# --- 저장 ---
blend_path = r"C:\Users\kkjjy\Documents\WorldSim\WS_forest_day_v001.blend"
bpy.ops.wm.save_as_mainfile(filepath=blend_path)
print(f"저장 완료: {blend_path}")
