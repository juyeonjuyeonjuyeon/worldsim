"""
WS_forest_rain 실시간 관찰 도구 (forest_rain_live.py)

forest_rain.py(오프라인 Cycles 배치 렌더용)에 쓴 물리 코드를 그대로 재사용해,
Blender를 직접 열고 이 스크립트를 실행하면 EEVEE 실시간 뷰포트 + 오른쪽
사이드바("N"키) 슬라이더 패널로 날씨/시간대를 즉시 조절하며 관찰할 수 있음.

조절 가능: 비 유무/강도(mm/hr), 바람 유무/속도(m/s), 시간대(0~24시).
슬라이더를 옮기면 즉시 적용되고 뷰포트가 다시 그려짐 — 애니메이션을
재생하지 않아도 바로 반영됨.

한계(정직하게 밝힘):
- EEVEE는 실시간 래스터라이저라 Cycles 경로추적만큼 광원/볼륨 산란이
  정확하지 않음. 구름/안개 같은 볼륨은 보이지만 디테일이 Cycles보다 거칢.
- 최종 고품질 출력은 여전히 forest_rain.py(Cycles, 수십 분 소요)로 따로
  뽑아야 함 — 이 도구는 "보면서 값을 정하는" 용도.
- 실행 방법: Blender를 GUI로 직접 열고 (블렌더 파일은 새로 만들어도 됨),
  상단 'Scripting' 탭 → 이 파일을 열고 '▶ Run Script'(Alt+P) 클릭.
  3D 뷰포트에서 'N' 키를 누르면 오른쪽에 "WS Weather" 패널이 나타남.
"""
import bpy
import bmesh
import mathutils
import numpy as np
import math
import random

G = 9.81
FPS = 24.0
n_rain = 5000
FIELD_HALF = 15.0
START_HEIGHT = 9.0
GRID_N = 48
N_SIDES = 8
SPLASH_MAX = 300
STREAK_LEN = 0.40
SPLASH_WINDOW = 0.15
PUDDLE_GROWTH = 0.15
PUDDLE_DECAY = 0.004
RIPPLE_BOOST = 2.5
WETNESS_GROWTH_PER_SEC = 1.0 / 60.0    # 계속 비 오면 ~60초에 완전히 젖음
WETNESS_DECAY_PER_SEC  = 1.0 / 180.0   # 비 그치면 ~180초에 거의 마름
WIND_DIR_DEG = 30.0   # 바람 방향(고정, 세기/유무만 조절 대상)
WIND_DX = math.cos(math.radians(WIND_DIR_DEG))
WIND_DY = math.sin(math.radians(WIND_DIR_DEG))
CLOUD_DRIFT_AMP = 4.0

# ── 빗방울 크기/속도 분포 (forest_rain.py와 동일한 마샬-팔머/건-킨저 경험식) ──
def fall_distance(t, vt):
    return (vt ** 2 / G) * np.log(np.cosh(G * t / vt))

def fall_velocity(t, vt):
    return vt * np.tanh(G * t / vt)

def fall_duration(h, vt):
    A = np.exp(np.clip(h * G / vt ** 2, 0, 80))
    return (vt / G) * np.log(A + np.sqrt(np.maximum(A ** 2 - 1, 0)))

def lateral_drift(t, vt, wind_speed):
    tau = vt / G
    return wind_speed * (t - tau * (1.0 - np.exp(-t / tau)))

# =====================================================================
# 전역 상태 (PropertyGroup 콜백이 갱신, update_scene이 매 프레임/매 변경 읽음)
# =====================================================================
diam_mm = v_terminal = fall_dur = drop_phase = None
CYCLE_SEC = 7.0
x0 = y0 = ground_z = None
_height_grid = None
_gx = _gy = None
ground_wetness_level = 0.0

def ground_height_vec(xs, ys):
    ix = np.clip(np.searchsorted(_gx, xs), 0, GRID_N - 1)
    iy = np.clip(np.searchsorted(_gy, ys), 0, GRID_N - 1)
    return _height_grid[ix, iy]

def regenerate_rain_distribution(rain_rate):
    """강우강도가 바뀔 때만 호출 — 방울 크기/속도/낙하시간/주기를 다시 계산.
    착지 위치(x0,y0)는 강우강도와 무관(격자 배치)이라 그대로 둠."""
    global diam_mm, v_terminal, fall_dur, drop_phase, CYCLE_SEC
    rain_rate = max(rain_rate, 0.5)
    LAMBDA = 4.1 * rain_rate ** -0.21
    np.random.seed(42)
    _U = np.random.uniform(1e-6, 1.0, n_rain)
    diam_mm = np.clip(-np.log(_U) / LAMBDA, 0.4, 6.0)
    v_terminal = 9.65 - 10.3 * np.exp(-0.6 * diam_mm)
    drop_height = START_HEIGHT - ground_z
    fall_dur = fall_duration(drop_height, v_terminal)
    CYCLE_SEC = float(fall_dur.max()) * 1.15
    np.random.seed(99)
    drop_phase = np.random.uniform(0, CYCLE_SEC, n_rain)

# =====================================================================
# 재질 헬퍼
# =====================================================================
def make_mat(name, color, roughness=0.9, metallic=0.0, transmission=0.0, ior=1.45):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Transmission Weight"].default_value = transmission
    b.inputs["IOR"].default_value = ior
    return mat

# =====================================================================
# 씬 빌드 (한 번만 실행)
# =====================================================================
_tree_mats = []
_tree_sway = []

def make_tree(x, y, scale, seed):
    random.seed(seed)
    trunk_h = 2.8 * scale
    trunk_mat = make_mat(f"Trunk_{seed}", (0.18, 0.11, 0.04, 1))
    _tree_mats.append((trunk_mat, 0.9))
    for i in range(5):
        seg_h = trunk_h / 5
        r = 0.13 * scale * (1 - i * 0.14)
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=10, radius=r, depth=seg_h,
            location=(x, y, i * seg_h + seg_h / 2))
        bpy.context.active_object.data.materials.append(trunk_mat)

    sway_pivot = bpy.data.objects.new(f"TreeSway_{seed}", None)
    sway_pivot.location = (x, y, trunk_h * 0.40)
    bpy.context.collection.objects.link(sway_pivot)

    branch_mat = make_mat(f"Branch_{seed}", (0.16, 0.09, 0.03, 1))
    _tree_mats.append((branch_mat, 0.9))
    for _ in range(random.randint(4, 6)):
        bz = trunk_h * random.uniform(0.35, 0.80)
        ba = random.uniform(35, 65)
        bd = random.uniform(0, 360)
        bl = scale * random.uniform(0.9, 1.6)
        ra, rd = math.radians(ba), math.radians(bd)
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=6, radius=0.04 * scale, depth=bl,
            location=(x + math.sin(ra) * math.cos(rd) * bl * 0.5,
                      y + math.sin(ra) * math.sin(rd) * bl * 0.5,
                      bz + math.cos(ra) * bl * 0.5))
        b = bpy.context.active_object
        b.rotation_euler[1] = ra
        b.rotation_euler[2] = rd
        b.data.materials.append(branch_mat)
        b.parent = sway_pivot
        b.matrix_parent_inverse = sway_pivot.matrix_world.inverted()

    crown_base = trunk_h * 0.40
    for _ in range(random.randint(10, 16)):
        t = random.uniform(0, 1)
        sp = (1 - t * 0.45) * scale * 1.1
        ag = random.uniform(0, 360)
        cx = x + sp * math.cos(math.radians(ag)) * random.uniform(0.2, 1.0)
        cy = y + sp * math.sin(math.radians(ag)) * random.uniform(0.2, 1.0)
        cz = crown_base + t * trunk_h * 0.75 + random.uniform(-0.15, 0.15) * scale
        cr = scale * random.uniform(0.28, 0.52)
        g = random.uniform(0.18, 0.30)
        lmat = make_mat(f"Leaf_{seed}_{_}", (0.04, g, 0.04, 1))
        _tree_mats.append((lmat, 0.9))
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=cr, location=(cx, cy, cz))
        cl = bpy.context.active_object
        cl.scale.z = random.uniform(0.65, 1.25)
        bpy.ops.object.transform_apply(scale=True)
        cl.data.materials.append(lmat)
        cl.parent = sway_pivot
        cl.matrix_parent_inverse = sway_pivot.matrix_world.inverted()

    n_cycles = random.randint(3, 7)
    amp = math.radians(5.0) / max(scale, 0.5)
    phase = random.uniform(0, 2 * math.pi)
    _tree_sway.append((sway_pivot, n_cycles, amp, phase))

def build_puddle_blob(px, py, search_r, water_depth=0.06):
    i_lo = max(0, np.searchsorted(_gx, px - search_r) - 1)
    i_hi = min(GRID_N, np.searchsorted(_gx, px + search_r) + 1)
    j_lo = max(0, np.searchsorted(_gy, py - search_r) - 1)
    j_hi = min(GRID_N, np.searchsorted(_gy, py + search_r) + 1)
    local = _height_grid[i_lo:i_hi, j_lo:j_hi]
    if local.size < 4:
        return None, 0.0
    water_level = float(np.percentile(local, 25)) + water_depth
    cell_w = _gx[1] - _gx[0]
    cell_h = _gy[1] - _gy[0]
    bm = bmesh.new()
    for i in range(i_lo, i_hi):
        for j in range(j_lo, j_hi):
            gxv, gyv = _gx[i], _gy[j]
            if (gxv - px) ** 2 + (gyv - py) ** 2 > search_r ** 2:
                continue
            if _height_grid[i, j] >= water_level:
                continue
            cx, cy = gxv - px, gyv - py
            v1 = bm.verts.new((cx - cell_w / 2, cy - cell_h / 2, 0.0))
            v2 = bm.verts.new((cx + cell_w / 2, cy - cell_h / 2, 0.0))
            v3 = bm.verts.new((cx + cell_w / 2, cy + cell_h / 2, 0.0))
            v4 = bm.verts.new((cx - cell_w / 2, cy + cell_h / 2, 0.0))
            bm.faces.new((v1, v2, v3, v4))
    if len(bm.faces) == 0:
        bm.free()
        return None, water_level
    mesh = bpy.data.meshes.new("WS_PuddleBlob")
    bm.to_mesh(mesh)
    bm.free()
    return mesh, water_level

_state = {}

def build_scene():
    global x0, y0, ground_z, _height_grid, _gx, _gy

    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for mesh in list(bpy.data.meshes): bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials): bpy.data.materials.remove(mat)
    for crv in list(bpy.data.curves): bpy.data.curves.remove(crv)
    _tree_mats.clear()
    _tree_sway.clear()

    # ── 빗방울 착지 격자 (지터드 그리드, 강우강도와 무관) ──
    grid_n = int(np.ceil(np.sqrt(n_rain)))
    cell = (2 * FIELD_HALF) / grid_n
    gi, gj = np.meshgrid(np.arange(grid_n), np.arange(grid_n), indexing='ij')
    gi = gi.ravel()[:n_rain]
    gj = gj.ravel()[:n_rain]
    np.random.seed(43)
    x0 = -FIELD_HALF + (gi + np.random.uniform(0.1, 0.9, n_rain)) * cell
    y0 = -FIELD_HALF + (gj + np.random.uniform(0.1, 0.9, n_rain)) * cell

    # ── 지형 ──
    bpy.ops.mesh.primitive_plane_add(size=50, location=(0, 0, 0))
    terrain = bpy.context.active_object
    terrain.name = "Terrain"
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.subdivide(number_cuts=30)
    bpy.ops.object.mode_set(mode='OBJECT')
    displace = terrain.modifiers.new("Displace", 'DISPLACE')
    noise_tex = bpy.data.textures.new("TerrainNoise", type='CLOUDS')
    noise_tex.noise_scale = 3.0
    displace.texture = noise_tex
    displace.strength = 0.8
    bpy.ops.object.modifier_apply(modifier="Displace")

    bpy.ops.mesh.primitive_plane_add(size=800, location=(0, 0, -0.05))
    horizon_ground = bpy.context.active_object
    horizon_ground.name = "HorizonGround"
    horizon_ground.data.materials.append(
        make_mat("HorizonGround", (0.09, 0.16, 0.07, 1), roughness=0.6))

    # ── 지형 높이 그리드 (raycast) ──
    depsgraph = bpy.context.evaluated_depsgraph_get()
    _gx = np.linspace(-16, 16, GRID_N)
    _gy = np.linspace(-12, 12, GRID_N)
    _height_grid = np.zeros((GRID_N, GRID_N))
    for i, gxv in enumerate(_gx):
        for j, gyv in enumerate(_gy):
            origin = mathutils.Vector((gxv, gyv, 50.0))
            direction = mathutils.Vector((0.0, 0.0, -1.0))
            ok, loc, nrm, idx, obj, mat = bpy.context.scene.ray_cast(depsgraph, origin, direction)
            _height_grid[i, j] = loc.z if ok else 0.0
    ground_z = ground_height_vec(x0, y0)

    # ── 밀집도 그리드(웅덩이/습윤 마스크 위치 산출용, 강우강도와 무관) ──
    DENS_BINS = 24
    density_grid, dxe, dye = np.histogram2d(
        x0, y0, bins=DENS_BINS, range=[[-16, 16], [-12, 12]])
    dxc = 0.5 * (dxe[:-1] + dxe[1:])
    dyc = 0.5 * (dye[:-1] + dye[1:])

    def density_at(x, y):
        i = int(np.clip(np.searchsorted(dxc, x), 0, DENS_BINS - 1))
        j = int(np.clip(np.searchsorted(dyc, y), 0, DENS_BINS - 1))
        return density_grid[i, j] / max(density_grid.max(), 1.0)

    wet_attr = terrain.data.color_attributes.new(name="WetnessMask", type='FLOAT_COLOR', domain='POINT')
    for v in terrain.data.vertices:
        w = density_at(v.co.x, v.co.y)
        wet_attr.data[v.index].color = (w, w, w, 1.0)

    dry_color = (0.16, 0.24, 0.08, 1.0)
    wet_color = (0.05, 0.13, 0.03, 1.0)
    ground_mat = bpy.data.materials.new("WetGround")
    ground_mat.use_nodes = True
    gnt = ground_mat.node_tree
    gnodes, glinks = gnt.nodes, gnt.links
    gbsdf = gnodes["Principled BSDF"]
    gbsdf.inputs["Metallic"].default_value = 0.0
    vcol = gnodes.new("ShaderNodeVertexColor")
    vcol.layer_name = "WetnessMask"
    sep = gnodes.new("ShaderNodeSeparateColor")
    glinks.new(vcol.outputs["Color"], sep.inputs["Color"])
    densitymap = gnodes.new("ShaderNodeMapRange")
    densitymap.inputs["From Min"].default_value = 0.0
    densitymap.inputs["From Max"].default_value = 1.0
    densitymap.inputs["To Min"].default_value = 0.5
    densitymap.inputs["To Max"].default_value = 1.0
    glinks.new(sep.outputs["Red"], densitymap.inputs["Value"])
    ground_wetness_value = gnodes.new("ShaderNodeValue")
    ground_wetness_value.outputs[0].default_value = 0.0
    ground_wetness_value.label = "GlobalWetnessRamp"
    wmul = gnodes.new("ShaderNodeMath")
    wmul.operation = 'MULTIPLY'
    glinks.new(densitymap.outputs["Result"], wmul.inputs[0])
    glinks.new(ground_wetness_value.outputs[0], wmul.inputs[1])
    mixcol = gnodes.new("ShaderNodeMixRGB")
    mixcol.inputs["Color1"].default_value = dry_color
    mixcol.inputs["Color2"].default_value = wet_color
    glinks.new(wmul.outputs[0], mixcol.inputs["Fac"])
    glinks.new(mixcol.outputs["Color"], gbsdf.inputs["Base Color"])
    roughmap = gnodes.new("ShaderNodeMapRange")
    roughmap.inputs["From Min"].default_value = 0.0
    roughmap.inputs["From Max"].default_value = 1.0
    roughmap.inputs["To Min"].default_value = 0.85
    roughmap.inputs["To Max"].default_value = 0.40
    glinks.new(wmul.outputs[0], roughmap.inputs["Value"])
    glinks.new(roughmap.outputs["Result"], gbsdf.inputs["Roughness"])
    terrain.data.materials.append(ground_mat)

    # ── 웅덩이 후보 (밀집도 기반, 강우강도와 무관 — 위치는 고정) ──
    puddle_mat = make_mat("Puddle", (0.03, 0.06, 0.08, 1), roughness=0.18, ior=1.333)
    pn = puddle_mat.node_tree.nodes.new("ShaderNodeTexNoise")
    pn.inputs["Scale"].default_value = 18.0
    pn.inputs["Detail"].default_value = 3.0
    pbump = puddle_mat.node_tree.nodes.new("ShaderNodeBump")
    pbump.inputs["Strength"].default_value = 0.25
    pbsdf = puddle_mat.node_tree.nodes["Principled BSDF"]
    puddle_mat.node_tree.links.new(pn.outputs["Fac"], pbump.inputs["Height"])
    puddle_mat.node_tree.links.new(pbump.outputs["Normal"], pbsdf.inputs["Normal"])

    n_puddles = 8
    order = np.argsort(density_grid.ravel())[::-1]
    min_sep = 3.0
    centers = []
    for flat in order:
        i, j = np.unravel_index(flat, density_grid.shape)
        if density_grid[i, j] <= 0:
            break
        cx, cy = dxc[i], dyc[j]
        if all((cx - px) ** 2 + (cy - py) ** 2 > min_sep ** 2 for px, py, _ in centers):
            centers.append((cx, cy, density_grid[i, j]))
        if len(centers) >= n_puddles:
            break
    max_density = max((c[2] for c in centers), default=1.0)

    puddle_objs, puddle_max_r, puddle_centers_list = [], [], []
    for px, py, density in centers:
        r_max = 1.2 + 1.8 * (density / max_density)
        blob_mesh, water_level = build_puddle_blob(px, py, r_max * 1.3)
        if blob_mesh is None:
            continue
        p = bpy.data.objects.new("WS_Puddle", blob_mesh)
        p.location = (px, py, water_level)
        p.scale = (0.001, 0.001, 1.0)
        bpy.context.collection.objects.link(p)
        p.data.materials.append(puddle_mat)
        puddle_objs.append(p)
        puddle_max_r.append(r_max)
        puddle_centers_list.append((px, py))
    puddle_max_r = np.array(puddle_max_r) if puddle_max_r else np.zeros(0)
    puddle_centers_arr = np.array(puddle_centers_list) if puddle_centers_list else np.zeros((0, 2))
    puddle_wetness = np.zeros(len(puddle_objs))

    # ── 나무 ──
    random.seed(7)
    for _ in range(22):
        x = random.uniform(-19, 19)
        y = random.uniform(-19, 19)
        if abs(x) < 5 and abs(y) < 5:
            continue
        make_tree(x, y, random.uniform(0.7, 1.8), random.randint(0, 9999))

    # ── 비/스플래시 ──
    rain_curve = bpy.data.curves.new("WS_RainCurve", type='CURVE')
    rain_curve.dimensions = '3D'
    rain_curve.bevel_depth = 0.004
    rain_curve.bevel_resolution = 1
    rain_curve.use_fill_caps = True
    for i in range(n_rain):
        sp = rain_curve.splines.new('POLY')
        sp.points.add(1)
        sp.points[0].co = (x0[i], y0[i], START_HEIGHT, 1.0)
        sp.points[1].co = (x0[i], y0[i], START_HEIGHT + STREAK_LEN, 1.0)
    rain_obj = bpy.data.objects.new("WS_Rain", rain_curve)
    bpy.context.collection.objects.link(rain_obj)
    rain_mat = bpy.data.materials.new("WaterStreak")
    rain_mat.use_nodes = True
    b = rain_mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.78, 0.87, 1.0, 1.0)
    b.inputs["Roughness"].default_value = 0.05
    b.inputs["Transmission Weight"].default_value = 0.85
    b.inputs["IOR"].default_value = 1.333
    b.inputs["Emission Color"].default_value = (0.78, 0.87, 1.0, 1.0)
    b.inputs["Emission Strength"].default_value = 0.15
    rain_obj.data.materials.append(rain_mat)

    splash_mesh = bpy.data.meshes.new("WS_SplashMesh")
    splash_verts, splash_faces = [], []
    for s in range(SPLASH_MAX):
        base_idx = len(splash_verts)
        for k in range(N_SIDES):
            ang = 2 * math.pi * k / N_SIDES
            splash_verts.append((math.cos(ang) * 0.001, math.sin(ang) * 0.001, -100.0))
        splash_faces.append(list(range(base_idx, base_idx + N_SIDES)))
    splash_mesh.from_pydata(splash_verts, [], splash_faces)
    splash_mesh.update()
    splash_obj = bpy.data.objects.new("WS_Splash", splash_mesh)
    bpy.context.collection.objects.link(splash_obj)
    splash_mat = bpy.data.materials.new("SplashRing")
    splash_mat.use_nodes = True
    bs = splash_mat.node_tree.nodes["Principled BSDF"]
    bs.inputs["Base Color"].default_value = (0.40, 0.52, 0.62, 1.0)
    bs.inputs["Roughness"].default_value = 0.6
    bs.inputs["Emission Color"].default_value = (0.40, 0.52, 0.62, 1.0)
    bs.inputs["Emission Strength"].default_value = 0.04
    splash_obj.data.materials.append(splash_mat)

    # ── 하늘/월드 ──
    world = bpy.data.worlds["World"]
    world.use_nodes = True
    wn, wl = world.node_tree.nodes, world.node_tree.links
    for n in list(wn): wn.remove(n)
    sky = wn.new("ShaderNodeTexSky")
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_elevation = math.radians(18)
    sky.sun_rotation = math.radians(100)
    sky.air_density = 1.0
    sky.aerosol_density = 5.5
    sky.ozone_density = 1.0
    bg = wn.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 0.45
    out_w = wn.new("ShaderNodeOutputWorld")
    wl.new(sky.outputs["Color"], bg.inputs["Color"])
    wl.new(bg.outputs["Background"], out_w.inputs["Surface"])

    # ── 조명 ──
    bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
    sun = bpy.context.active_object
    sun.data.energy = 0.4
    sun.data.angle = math.radians(20)
    sun.rotation_euler[0] = math.radians(70)
    sun.rotation_euler[2] = math.radians(100)

    bpy.ops.object.light_add(type='AREA', location=(0, 0, 15))
    sl = bpy.context.active_object
    sl.data.energy = 90
    sl.data.size = 20
    sl.data.color = (0.60, 0.72, 1.0)

    # ── 구름(흐름) ──
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 20))
    cloud_obj = bpy.context.active_object
    cloud_obj.name = "CloudLayer"
    cloud_obj.scale = (140, 140, 16)
    bpy.ops.object.transform_apply(scale=True)
    cloud_mat = bpy.data.materials.new("CloudVolume")
    cloud_mat.use_nodes = True
    cnodes, clinks = cloud_mat.node_tree.nodes, cloud_mat.node_tree.links
    for n in list(cnodes): cnodes.remove(n)
    ctexcoord = cnodes.new("ShaderNodeTexCoord")
    cloud_mapping = cnodes.new("ShaderNodeMapping")
    clinks.new(ctexcoord.outputs["Object"], cloud_mapping.inputs["Vector"])
    ctex = cnodes.new("ShaderNodeTexNoise")
    ctex.inputs["Scale"].default_value = 2.5
    ctex.inputs["Detail"].default_value = 4.0
    clinks.new(cloud_mapping.outputs["Vector"], ctex.inputs["Vector"])
    cmap = cnodes.new("ShaderNodeMapRange")
    cmap.inputs["From Min"].default_value = 0.35
    cmap.inputs["From Max"].default_value = 0.65
    cmap.inputs["To Min"].default_value = 0.0
    cmap.inputs["To Max"].default_value = 1.0
    cmap.clamp = True
    cvol = cnodes.new("ShaderNodeVolumePrincipled")
    cvol.inputs["Color"].default_value = (0.75, 0.76, 0.78, 1.0)
    cmul = cnodes.new("ShaderNodeMath")
    cmul.operation = 'MULTIPLY'
    cmul.inputs[1].default_value = 0.10
    cout = cnodes.new("ShaderNodeOutputMaterial")
    clinks.new(ctex.outputs["Fac"], cmap.inputs["Value"])
    clinks.new(cmap.outputs["Result"], cmul.inputs[0])
    clinks.new(cmul.outputs["Value"], cvol.inputs["Density"])
    clinks.new(cvol.outputs["Volume"], cout.inputs["Volume"])
    cloud_obj.data.materials.append(cloud_mat)

    # ── 지면 실안개 ──
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 1.25))
    mist_obj = bpy.context.active_object
    mist_obj.name = "GroundMist"
    mist_obj.scale = (200, 200, 2.5)
    bpy.ops.object.transform_apply(scale=True)
    mist_mat = bpy.data.materials.new("GroundMistVolume")
    mist_mat.use_nodes = True
    mnodes, mlinks = mist_mat.node_tree.nodes, mist_mat.node_tree.links
    for n in list(mnodes): mnodes.remove(n)
    mvol = mnodes.new("ShaderNodeVolumePrincipled")
    mvol.inputs["Color"].default_value = (0.82, 0.85, 0.86, 1.0)
    mvol.inputs["Density"].default_value = 0.012
    mout = mnodes.new("ShaderNodeOutputMaterial")
    mlinks.new(mvol.outputs["Volume"], mout.inputs["Volume"])
    mist_obj.data.materials.append(mist_mat)

    # ── 카메라 ──
    bpy.ops.object.camera_add(location=(8, -16, 6.5))
    cam = bpy.context.active_object
    cam.rotation_euler[0] = math.radians(84)
    cam.rotation_euler[2] = math.radians(38)
    cam.data.lens = 35
    bpy.context.scene.camera = cam

    _state.update(dict(
        rain_obj=rain_obj, splash_obj=splash_obj,
        puddle_objs=puddle_objs, puddle_max_r=puddle_max_r,
        puddle_centers=puddle_centers_arr, puddle_wetness=puddle_wetness,
        ground_wetness_value=ground_wetness_value,
        sky=sky, bg=bg, sun=sun, sl=sl, cloud_mapping=cloud_mapping,
    ))

# =====================================================================
# 시간대(0~24시) -> 조명/하늘 (단순화된 모델, 위도/계절 미반영 근사)
# =====================================================================
def apply_time_of_day(hour):
    sky, bg, sun, sl = _state["sky"], _state["bg"], _state["sun"], _state["sl"]
    elevation_deg = 60.0 * math.sin(math.radians((hour - 6) / 12.0 * 180.0))
    elevation_deg = max(-90.0, min(60.0, elevation_deg))
    daylight = max(0.0, math.sin(math.radians(max(elevation_deg, 0.0))))

    sky.sun_elevation = math.radians(elevation_deg)
    sun.rotation_euler[0] = math.radians(90.0 - elevation_deg)

    if elevation_deg < 8.0:
        warm = max(0.0, 1.0 - elevation_deg / 8.0)
    else:
        warm = 0.0
    sun_color = (1.0 - warm * 0.0, 1.0 - warm * 0.40, 1.0 - warm * 0.70)
    sun.data.color = sun_color

    night_floor = 0.02
    sun.data.energy = 0.4 * daylight
    sl.data.energy = 90.0 * max(daylight, night_floor)
    sl.data.color = (0.60, 0.72, 1.0) if daylight > 0.05 else (0.55, 0.62, 0.85)
    bg.inputs["Strength"].default_value = 0.45 * max(daylight, night_floor * 1.5)

# =====================================================================
# 프레임/파라미터 갱신
# =====================================================================
def update_scene(scene):
    global ground_wetness_level
    w = scene.ws_weather
    wind_speed = w.wind_speed if w.wind_enabled else 0.0
    rain_on = w.rain_enabled

    t = (scene.frame_current - 1) / FPS

    rain_obj, splash_obj = _state["rain_obj"], _state["splash_obj"]
    rain_obj.hide_viewport = rain_obj.hide_render = not rain_on
    splash_obj.hide_viewport = splash_obj.hide_render = not rain_on

    hits_per_puddle = np.zeros(len(_state["puddle_objs"]))

    if rain_on:
        local_t = (t + drop_phase) % CYCLE_SEC
        falling = local_t < fall_dur
        t_eff = np.where(falling, local_t, fall_dur)
        fallen = fall_distance(t_eff, v_terminal)
        drift = lateral_drift(t_eff, v_terminal, wind_speed)
        z = np.where(falling, START_HEIGHT - fallen, ground_z)
        x = x0 + drift * WIND_DX
        y = y0 + drift * WIND_DY
        speed = np.where(falling, fall_velocity(t_eff, v_terminal), 0.0)
        tau = v_terminal / G
        wind_now = np.where(falling, wind_speed * (1.0 - np.exp(-t_eff / tau)), 0.0)
        vx, vy, vz = wind_now * WIND_DX, wind_now * WIND_DY, speed
        vmag = np.sqrt(vx ** 2 + vy ** 2 + vz ** 2)
        vmag_safe = np.where(vmag < 1e-6, 1.0, vmag)
        vis_len = np.clip(STREAK_LEN * (vmag / 4.0), STREAK_LEN * 0.3, STREAK_LEN * 2.0)
        tail_x = x - (vx / vmag_safe) * vis_len
        tail_y = y - (vy / vmag_safe) * vis_len
        tail_z = z + (vz / vmag_safe) * vis_len

        rain_splines = rain_obj.data.splines
        nr = min(n_rain, len(rain_splines))
        for i in range(nr):
            if falling[i]:
                rain_splines[i].points[0].co = (x[i], y[i], z[i], 1.0)
                rain_splines[i].points[1].co = (tail_x[i], tail_y[i], tail_z[i], 1.0)
            else:
                rain_splines[i].points[0].co = (0, 0, -100.0, 1.0)
                rain_splines[i].points[1].co = (0, 0, -100.0, 1.0)
        rain_obj.data.update_tag()

        since_landing = local_t - fall_dur
        splashing = (since_landing >= 0) & (since_landing < SPLASH_WINDOW)
        near = np.stack([x[splashing], y[splashing], z[splashing]], axis=1)
        near_speed = v_terminal[splashing]
        if len(near) > SPLASH_MAX:
            sel = np.random.choice(len(near), SPLASH_MAX, replace=False)
            near, near_speed = near[sel], near_speed[sel]
        radii = np.clip(0.3 + near_speed * 0.12, 0.3, 1.3)
        gz = ground_height_vec(near[:, 0], near[:, 1]) if len(near) else np.zeros(0)

        n_pud = len(_state["puddle_objs"])
        pc, pmr = _state["puddle_centers"], _state["puddle_max_r"]
        if n_pud > 0 and len(near) > 0:
            dx = near[:, 0:1] - pc[:, 0][None, :]
            dy = near[:, 1:2] - pc[:, 1][None, :]
            dist2 = dx ** 2 + dy ** 2
            inside_catchment = dist2 < (pmr[None, :] ** 2)
            hits_per_puddle = inside_catchment.sum(axis=0)
            cur_r = pmr * _state["puddle_wetness"]
            inside_current = dist2 < (cur_r[None, :] ** 2)
            in_any_puddle = inside_current.any(axis=1)
            radii[in_any_puddle] *= RIPPLE_BOOST

        verts = splash_obj.data.vertices
        ns = min(SPLASH_MAX, len(verts) // N_SIDES)
        n_active = len(near)
        for i in range(ns):
            base = i * N_SIDES
            if i < n_active:
                px, py = near[i, 0], near[i, 1]
                r = radii[i]
                pz = gz[i] + 0.02
                for k in range(N_SIDES):
                    ang = 2 * math.pi * k / N_SIDES
                    verts[base + k].co = (px + math.cos(ang) * r, py + math.sin(ang) * r, pz)
            else:
                for k in range(N_SIDES):
                    verts[base + k].co = (0, 0, -100.0)
        splash_obj.data.update_tag()

        ground_wetness_level = min(1.0, ground_wetness_level + WETNESS_GROWTH_PER_SEC / FPS)
    else:
        ground_wetness_level = max(0.0, ground_wetness_level - WETNESS_DECAY_PER_SEC / FPS)

    pw = _state["puddle_wetness"]
    for pi in range(len(_state["puddle_objs"])):
        if hits_per_puddle[pi] > 0:
            pw[pi] = min(1.0, pw[pi] + PUDDLE_GROWTH * hits_per_puddle[pi])
        else:
            pw[pi] = max(0.0, pw[pi] - PUDDLE_DECAY)
        s = max(0.001, pw[pi]) * _state["puddle_max_r"][pi]
        _state["puddle_objs"][pi].scale = (s, s, 1.0)

    _state["ground_wetness_value"].outputs[0].default_value = ground_wetness_level
    for mat, dry_r in _tree_mats:
        mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = (
            dry_r - ground_wetness_level * (dry_r - 0.25))

    cloud_drift = CLOUD_DRIFT_AMP * math.sin(2 * math.pi * t / max(CYCLE_SEC, 1.0))
    _state["cloud_mapping"].inputs["Location"].default_value = (
        cloud_drift * WIND_DX, cloud_drift * WIND_DY, 0.0)

    for pivot, n_cycles, amp, phase in _tree_sway:
        wind_factor = min(1.0, wind_speed / 1.6)
        angle = amp * wind_factor * math.sin(2 * math.pi * n_cycles * t / max(CYCLE_SEC, 1.0) + phase)
        pivot.rotation_euler[0] = -angle * WIND_DY
        pivot.rotation_euler[1] = angle * WIND_DX

    apply_time_of_day(w.time_of_day)

def refresh(scene):
    update_scene(scene)
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type == 'VIEW_3D':
                area.tag_redraw()

# =====================================================================
# UI: PropertyGroup + Panel
# =====================================================================
def _on_rain_rate_change(self, context):
    regenerate_rain_distribution(self.rain_rate)
    refresh(context.scene)

def _on_other_change(self, context):
    refresh(context.scene)

class WS_WeatherProps(bpy.types.PropertyGroup):
    rain_enabled: bpy.props.BoolProperty(name="비", default=True, update=_on_other_change)
    rain_rate: bpy.props.FloatProperty(
        name="강우강도 (mm/hr)", default=20.0, min=0.5, max=60.0, update=_on_rain_rate_change)
    wind_enabled: bpy.props.BoolProperty(name="바람", default=True, update=_on_other_change)
    wind_speed: bpy.props.FloatProperty(
        name="바람 속도 (m/s)", default=1.6, min=0.0, max=12.0, update=_on_other_change)
    time_of_day: bpy.props.FloatProperty(
        name="시간 (시)", default=12.0, min=0.0, max=24.0, update=_on_other_change)

class WS_PT_WeatherPanel(bpy.types.Panel):
    bl_label = "WS Weather"
    bl_idname = "WS_PT_weather_panel"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "WS Weather"

    def draw(self, context):
        w = context.scene.ws_weather
        col = self.layout.column()
        col.prop(w, "rain_enabled")
        col.prop(w, "rain_rate")
        col.separator()
        col.prop(w, "wind_enabled")
        col.prop(w, "wind_speed")
        col.separator()
        col.prop(w, "time_of_day")

_classes = (WS_WeatherProps, WS_PT_WeatherPanel)

def register():
    for c in _classes:
        bpy.utils.register_class(c)
    bpy.types.Scene.ws_weather = bpy.props.PointerProperty(type=WS_WeatherProps)

def unregister():
    del bpy.types.Scene.ws_weather
    for c in reversed(_classes):
        bpy.utils.unregister_class(c)

# =====================================================================
# 실행
# =====================================================================
for c in _classes:
    try:
        bpy.utils.unregister_class(c)
    except Exception:
        pass
try:
    del bpy.types.Scene.ws_weather
except Exception:
    pass
register()

build_scene()
regenerate_rain_distribution(20.0)

scene = bpy.context.scene
scene.ws_weather.rain_rate = 20.0
scene.frame_start = 1
scene.frame_end = 9999
scene.render.engine = 'BLENDER_EEVEE'
scene.eevee.use_raytracing = True

if bpy.context.screen:   # --background 모드(화면 없음)에서도 안전하게 동작
    for area in bpy.context.screen.areas:
        if area.type == 'VIEW_3D':
            for space in area.spaces:
                if space.type == 'VIEW_3D':
                    space.shading.type = 'RENDERED'

bpy.app.handlers.frame_change_post.clear()
bpy.app.handlers.frame_change_post.append(update_scene)
refresh(scene)

print("=" * 60)
print("WS Weather 실시간 도구 준비 완료.")
print("3D 뷰포트에서 'N' 키 -> 오른쪽 'WS Weather' 탭에서 조절.")
print("=" * 60)
