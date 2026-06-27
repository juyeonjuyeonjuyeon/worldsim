class_name WorldSimEnv
extends Node

const FIELD_HALF: float = 15.0

# 외부에서 읽는 출력값
var ground_wetness: float = 0.0
var ground_snow: float    = 0.0
var water_depth: float    = 0.0   # 실제 수위 (미터, 무제한)

var _ground_mesh: MeshInstance3D
var _ground_mat: ShaderMaterial
var _horizon_mat: StandardMaterial3D
var _ground_mist: MeshInstance3D
var _ground_mist_mat: StandardMaterial3D
var _snow_ground_mesh: MeshInstance3D
var _rain_particles: GPUParticles3D
var _snow_particles: GPUParticles3D
var _splash_particles: GPUParticles3D
var _ripple_emitters: Array  = []
var _leaf_mats: Array        = []
var _leaf_base_colors: Array = []
var _leaf_snow_caps: Array   = []
var _trunk_mats: Array       = []
var _tree_sway_pivots: Array = []
var _tree_sway_phase: Array  = []
var _tree_sway_freq: Array   = []
var _sway_time: float        = 0.0
var _puddle_nodes: Array     = []
var _puddle_max_r: Array     = []
var _puddle_mats: Array      = []
var _puddle_base_y: Array    = []
var _flood_plane: MeshInstance3D
var _flood_mat: ShaderMaterial
var _water_shader: Shader
var _puddle_shader: Shader
var _rain_shader_mat: ShaderMaterial
var _tree_splash_emitters: Array = []

# ── 빌드 ─────────────────────────────────────────────────────────────
func build() -> void:
	_build_ground()
	_build_snow_accumulation()
	_build_ground_mist()
	_build_trees()
	_build_puddles()
	_build_ripple_emitters()
	_build_flood_plane()
	_build_rain_snow()
	_build_splash()
	_build_tree_splash()
	_build_reflection_probe()

func _build_ground() -> void:
	_ground_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	plane.subdivide_width = 40
	plane.subdivide_depth = 40
	_ground_mesh.mesh = plane

	# 지형 굴곡 셰이더 — 버텍스를 사인파 조합으로 Y 변위, 법선 자동 계산
	var terrain_shader := Shader.new()
	terrain_shader.code = """
shader_type spatial;
uniform vec4 albedo    : source_color = vec4(0.16, 0.24, 0.08, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;

float terrain_h(vec2 xz) {
	return
		0.12 * sin(xz.x * 0.38 + 1.1) * cos(xz.y * 0.29 + 0.7) +
		0.08 * sin(xz.x * 0.71 + 2.3) * cos(xz.y * 0.55 + 1.8) +
		0.05 * cos(xz.x * 1.12 + 0.4) * sin(xz.y * 0.91 + 3.1);
}

void vertex() {
	float eps = 0.1;
	float h   = terrain_h(VERTEX.xz);
	float hx  = terrain_h(VERTEX.xz + vec2(eps, 0.0));
	float hz  = terrain_h(VERTEX.xz + vec2(0.0, eps));
	VERTEX.y += h;
	NORMAL = normalize(vec3(-(hx - h) / eps, 1.0, -(hz - h) / eps));
}

void fragment() {
	ALBEDO    = albedo.rgb;
	ROUGHNESS = roughness;
	SPECULAR  = 0.04;
}
"""
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = terrain_shader
	_ground_mat.set_shader_parameter("albedo",    Color(0.16, 0.24, 0.08))
	_ground_mat.set_shader_parameter("roughness", 0.85)
	_ground_mesh.material_override = _ground_mat
	add_child(_ground_mesh)

	# 지평선 평면 — 원거리 배경, 지형 변위 없이 평평, y=-0.30(지형 최저 -0.25m 아래)
	_horizon_mat = StandardMaterial3D.new()
	_horizon_mat.albedo_color      = Color(0.16, 0.24, 0.08)
	_horizon_mat.roughness         = 0.85
	_horizon_mat.metallic_specular = 0.04
	var horizon := MeshInstance3D.new()
	var hp := PlaneMesh.new()
	hp.size = Vector2(800, 800)
	horizon.mesh = hp
	horizon.position.y = -0.30
	horizon.material_override = _horizon_mat
	add_child(horizon)

func _build_snow_accumulation() -> void:
	_snow_ground_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(800, 0.5, 800)
	_snow_ground_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.94, 0.97)
	mat.roughness = 0.9
	mat.metallic_specular = 0.04
	_snow_ground_mesh.material_override = mat
	_snow_ground_mesh.visible = false
	add_child(_snow_ground_mesh)

func _build_ground_mist() -> void:
	_ground_mist = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(70.0, 3.0, 70.0)
	_ground_mist.mesh = box
	_ground_mist.position = Vector3(0, 1.5, 0)
	_ground_mist_mat = StandardMaterial3D.new()
	_ground_mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ground_mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ground_mist_mat.albedo_color = Color(0.6, 0.62, 0.65, 0.0)
	_ground_mist.material_override = _ground_mist_mat
	_ground_mist.visible = false
	add_child(_ground_mist)

func _make_tree(x: float, z: float, scale_: float, seed_: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var trunk_h: float = 2.8 * scale_
	var th: float = _terrain_height(x, z)
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.10 * scale_
	cyl.bottom_radius = 0.14 * scale_
	cyl.height = trunk_h
	trunk.mesh = cyl
	trunk.position = Vector3(x, trunk_h * 0.5 + th, z)
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.18, 0.11, 0.04)
	trunk_mat.roughness = 0.9
	trunk.material_override = trunk_mat
	add_child(trunk)
	_trunk_mats.append(trunk_mat)

	var n_leaves: int = rng.randi_range(8, 13)
	var crown_base: float = trunk_h * 0.55
	var pivot := Node3D.new()
	pivot.position = Vector3(x, crown_base + th, z)
	add_child(pivot)
	_tree_sway_pivots.append(pivot)
	_tree_sway_phase.append(rng.randf_range(0.0, TAU))
	_tree_sway_freq.append(rng.randf_range(0.3, 0.6))

	for i in range(n_leaves):
		var t: float = float(i) / float(n_leaves)
		var sp: float = (1.0 - t * 0.4) * scale_ * 1.1
		var ang: float = rng.randf_range(0.0, TAU)
		var cx: float = sp * cos(ang) * rng.randf_range(0.2, 1.0)
		var cz: float = sp * sin(ang) * rng.randf_range(0.2, 1.0)
		var cy: float = t * trunk_h * 0.7 + rng.randf_range(-0.1, 0.1) * scale_
		var cr: float = scale_ * rng.randf_range(0.30, 0.55)
		var g: float = rng.randf_range(0.18, 0.30)
		var leaf := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = cr
		sph.height = cr * 2.0
		leaf.mesh = sph
		leaf.position = Vector3(cx, cy, cz)
		var leaf_color := Color(0.04, g, 0.04)
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = leaf_color
		lmat.roughness = 0.9
		leaf.material_override = lmat
		pivot.add_child(leaf)
		_leaf_mats.append(lmat)
		_leaf_base_colors.append(leaf_color)

		var snow_cap := MeshInstance3D.new()
		var cap_cyl := CylinderMesh.new()
		cap_cyl.top_radius = cr * 0.65
		cap_cyl.bottom_radius = cr * 0.80
		cap_cyl.height = cr * 0.45
		cap_cyl.rings = 1
		snow_cap.mesh = cap_cyl
		snow_cap.position = Vector3(0, cr * 0.72, 0)
		var cap_mat := StandardMaterial3D.new()
		cap_mat.albedo_color = Color(0.92, 0.94, 0.97)
		cap_mat.roughness = 0.9
		cap_mat.metallic_specular = 0.04
		snow_cap.material_override = cap_mat
		snow_cap.visible = false
		leaf.add_child(snow_cap)
		_leaf_snow_caps.append(snow_cap)

func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(22):
		var x: float = rng.randf_range(-19, 19)
		var z: float = rng.randf_range(-19, 19)
		if abs(x) < 5 and abs(z) < 5:
			continue
		_make_tree(x, z, rng.randf_range(0.7, 1.8), rng.randi())

func _build_puddles() -> void:
	# 웅덩이·범람에 공통으로 쓰는 물 셰이더
	_water_shader = Shader.new()
	_water_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float sky_brightness : hint_range(0.0, 2.0) = 1.0;
uniform float alpha_mult     : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	float cosA   = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - cosA, 3.0);
	vec3 deep    = vec3(0.01, 0.04, 0.10) * sky_brightness;
	vec3 refl    = vec3(0.42, 0.57, 0.78) * sky_brightness;
	vec3 col     = mix(deep, refl, fresnel * 0.65 + 0.05);
	// 빗방울 4개가 웅덩이 내 서로 다른 위치에 떨어짐 (황금비 각도 분산)
	float ripple = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 c   = vec2(0.5) + vec2(sin(fi * 1.618 + 0.5), cos(fi * 2.094 + 1.2)) * 0.20;
		float d  = length(UV - c) * 2.2;
		float t  = fract(TIME * 0.75 + fi * 0.25);
		// r=0.06에서 시작 → 점이 아닌 링 모양으로 태어남
		float r  = 0.06 + t * 0.84;
		float w  = 0.055;
		float rg = smoothstep(r - w, r, d) * smoothstep(r + w * 0.35, r, d);
		ripple  += rg * (1.0 - t) * 1.2;
	}
	col += vec3(clamp(ripple * rain_intensity * 0.42, 0.0, 0.45));
	// UV 중심에서 0.5 이상이면 원 바깥 → 투명(사각형 모서리 제거)
	float circ = 1.0 - smoothstep(0.47, 0.50, length(UV - vec2(0.5)));
	ALBEDO    = col;
	ROUGHNESS = 0.02;
	SPECULAR  = 0.95;
	ALPHA     = clamp((0.72 + fresnel * 0.22) * alpha_mult, 0.0, 1.0) * circ;
}
"""
	# 웅덩이 셰이더 — SCREEN_TEXTURE 반사로 하늘·나무가 실제로 비침
	# blend_mix 투명 패스에서 렌더링 → SCREEN_TEXTURE에 하늘·불투명 오브젝트 포함됨
	# 바람 uniform으로 수면 법선 교란 및 파문 위상 이동 구현
	_puddle_shader = Shader.new()
	_puddle_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float sky_brightness : hint_range(0.0, 2.0) = 1.0;
uniform vec2  wind_dir_xz = vec2(0.0, 0.0);
uniform float wind_speed  = 0.0;

void fragment() {
	// 원형 마스크
	float circ = 1.0 - smoothstep(0.47, 0.50, length(UV - vec2(0.5)));

	// 월드 위치 및 카메라 방향
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_cam    = normalize(CAMERA_POSITION_WORLD - world_pos);

	// 바람으로 인한 수면 법선 교란
	float wsp  = wind_speed * 0.016;
	vec2  surf = UV * vec2(9.0, 7.0) + wind_dir_xz * TIME * wind_speed * 0.12;
	float wn   = sin(surf.x + TIME * 1.4) * cos(surf.y + TIME * 1.1);
	vec3 water_n = normalize(vec3(-wn * wsp * wind_dir_xz.x, 1.0, -wn * wsp * wind_dir_xz.y));

	// 프레넬
	float cosA    = clamp(dot(to_cam, water_n), 0.0, 1.0);
	float fresnel = pow(1.0 - cosA, 2.5);

	// 반사 방향을 스크린 UV로 투영 (하늘·나무가 SCREEN_TEXTURE에 포함)
	vec3 refl_dir = reflect(-to_cam, water_n);
	vec4 rc = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos + refl_dir * 80.0, 1.0);
	vec2 refl_uv = (rc.w > 0.001) ? rc.xy / rc.w * 0.5 + 0.5 : SCREEN_UV;

	// 바람에 의한 반사 UV 교란 (파도가 반사상을 흔듦)
	float wd = wind_speed * 0.004;
	refl_uv += vec2(sin(UV.x * 14.0 + TIME * 2.2) * wd,
	                cos(UV.y * 11.0 + TIME * 1.9) * wd);
	refl_uv = clamp(refl_uv, 0.001, 0.999);
	vec3 screen_refl = texture(SCREEN_TEXTURE, refl_uv).rgb;

	// 수심색 + 화면 반사 합성 (최소 25% 반사로 수직에서도 하늘 보임)
	vec3 deep = vec3(0.01, 0.04, 0.10) * sky_brightness;
	float refl_str = clamp(fresnel * 0.70 + 0.25, 0.0, 0.92);
	vec3 col = mix(deep, screen_refl, refl_str);

	// 빗방울 파문 (바람 방향으로 위상 이동)
	float ripple   = 0.0;
	float w_phase  = wind_speed * 0.35;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 c   = vec2(0.5) + vec2(
			sin(fi * 1.618 + 0.5 + wind_dir_xz.x * TIME * w_phase),
			cos(fi * 2.094 + 1.2 + wind_dir_xz.y * TIME * w_phase)) * 0.20;
		float d  = length(UV - c) * 2.2;
		float t  = fract(TIME * 0.75 + fi * 0.25);
		float r  = 0.06 + t * 0.84;
		float w  = 0.055;
		float rg = smoothstep(r - w, r, d) * smoothstep(r + w * 0.35, r, d);
		ripple  += rg * (1.0 - t) * 1.2;
	}
	col += vec3(clamp(ripple * rain_intensity * 0.25, 0.0, 0.40));

	ALBEDO    = col;
	ROUGHNESS = 0.02;
	SPECULAR  = 0.95;
	METALLIC  = 0.0;
	ALPHA     = clamp(0.90 + fresnel * 0.08, 0.0, 1.0) * circ;
}
"""
	var low_pts := _find_low_points(8, 3.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in range(low_pts.size()):
		var lp: Vector3 = low_pts[i]
		var r: float = rng.randf_range(0.8, 2.4)
		var p := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(2.0, 2.0)
		p.mesh = plane
		p.position = Vector3(lp.x, lp.y + 0.002, lp.z)
		p.scale = Vector3(0.001, 1.0, 0.001)
		var pmat := ShaderMaterial.new()
		pmat.shader = _puddle_shader
		pmat.set_shader_parameter("rain_intensity", 0.0)
		pmat.set_shader_parameter("sky_brightness", 1.0)
		pmat.set_shader_parameter("wind_dir_xz", Vector2(0.0, 0.0))
		pmat.set_shader_parameter("wind_speed",  0.0)
		p.material_override = pmat
		add_child(p)
		_puddle_nodes.append(p)
		_puddle_max_r.append(r)
		_puddle_mats.append(pmat)
		_puddle_base_y.append(lp.y)

func _build_ripple_emitters() -> void:
	# 파동 링 공유 리소스
	var ring_shader := Shader.new()
	ring_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
varying float v_alpha;
void vertex() { v_alpha = COLOR.a; }
void fragment() {
	float d    = length(UV - vec2(0.5)) * 2.0;
	float ring = smoothstep(0.38, 0.52, d) * smoothstep(0.82, 0.68, d);
	ALBEDO = vec3(0.82, 0.91, 1.0);
	ALPHA  = ring * v_alpha;
}
"""
	var ring_smat := ShaderMaterial.new()
	ring_smat.shader = ring_shader
	var rmesh := PlaneMesh.new()
	rmesh.size     = Vector2(0.38, 0.38)
	rmesh.material = ring_smat
	var sc := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.05))
	curve.add_point(Vector2(1.0, 1.0))
	sc.curve = curve
	var rg := Gradient.new()
	rg.set_color(0, Color(0.82, 0.91, 1.0, 0.5))
	rg.set_color(1, Color(0.82, 0.91, 1.0, 0.0))
	var rramp := GradientTexture1D.new()
	rramp.gradient = rg
	# 웅덩이마다 전용 에미터 생성
	for pnode in _puddle_nodes:
		var pn: MeshInstance3D = pnode as MeshInstance3D
		var re := GPUParticles3D.new()
		re.amount   = 12
		re.lifetime = 0.9
		re.position = Vector3(pn.position.x, pn.position.y + 0.001, pn.position.z)
		re.emitting = false
		var rmat := ParticleProcessMaterial.new()
		rmat.emission_shape       = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		rmat.emission_box_extents = Vector3(0.001, 0.001, 0.001)
		rmat.direction            = Vector3(0, 1, 0)
		rmat.spread               = 0.0
		rmat.gravity              = Vector3.ZERO
		rmat.initial_velocity_min = 0.0
		rmat.initial_velocity_max = 0.0
		rmat.scale_min            = 1.0
		rmat.scale_max            = 1.0
		rmat.scale_curve          = sc
		rmat.color_ramp           = rramp
		re.process_material = rmat
		re.draw_pass_1      = rmesh
		add_child(re)
		_ripple_emitters.append(re)

func _build_flood_plane() -> void:
	_flood_plane = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(800, 800)
	_flood_plane.mesh = plane
	_flood_plane.position = Vector3(0, 0.009, 0)
	_flood_mat = ShaderMaterial.new()
	_flood_mat.shader = _water_shader
	_flood_mat.set_shader_parameter("rain_intensity", 0.0)
	_flood_mat.set_shader_parameter("sky_brightness", 1.0)
	_flood_mat.set_shader_parameter("alpha_mult", 0.0)
	_flood_plane.material_override = _flood_mat
	_flood_plane.visible = false
	add_child(_flood_plane)

func _build_rain_snow() -> void:
	_rain_particles = _make_precip_particles(false)
	# 파티클이 y=18에서 y=0까지 낙하 + 바람 drift → AABB가 emission box(y=18)만 커버하면
	# 수평 시점에서 파티클 시스템 전체가 frustum-cull 됨. 25m 여유를 추가해 방지.
	_rain_particles.extra_cull_margin = 25.0
	add_child(_rain_particles)
	_snow_particles = _make_precip_particles(true)
	_snow_particles.extra_cull_margin = 25.0
	add_child(_snow_particles)

func _build_splash() -> void:
	# ── 튀는 물방울 ──────────────────────────────────────────────────────
	_splash_particles = GPUParticles3D.new()
	_splash_particles.amount   = 500
	_splash_particles.lifetime = 0.45
	_splash_particles.position = Vector3(0, 0.02, 0)
	_splash_particles.emitting = false

	var smat := ParticleProcessMaterial.new()
	smat.emission_shape      = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	smat.emission_box_extents = Vector3(FIELD_HALF, 0.01, FIELD_HALF)
	smat.direction            = Vector3(0, 1, 0)
	smat.spread               = 68.0
	smat.gravity              = Vector3(0, -9.8, 0)
	smat.initial_velocity_min = 0.6
	smat.initial_velocity_max = 2.2
	smat.scale_min            = 0.3
	smat.scale_max            = 0.8
	var sg := Gradient.new()
	sg.set_color(0, Color(0.82, 0.91, 1.0, 0.75))
	sg.set_color(1, Color(0.82, 0.91, 1.0, 0.0))
	var sramp := GradientTexture1D.new()
	sramp.gradient = sg
	smat.color_ramp = sramp
	_splash_particles.process_material = smat

	# SphereMesh — 구는 방향과 무관하게 항상 같은 실루엣, edge-on 문제 없음
	var smesh := SphereMesh.new()
	smesh.radius = 0.015
	smesh.height = 0.03
	var spmat := StandardMaterial3D.new()
	spmat.shading_mode             = BaseMaterial3D.SHADING_MODE_UNSHADED
	spmat.albedo_color             = Color(0.82, 0.91, 1.0)
	spmat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA
	spmat.depth_draw_mode          = BaseMaterial3D.DEPTH_DRAW_DISABLED
	spmat.vertex_color_use_as_albedo = true
	smesh.material = spmat
	_splash_particles.draw_pass_1 = smesh
	add_child(_splash_particles)



func _build_tree_splash() -> void:
	var cg := Gradient.new()
	cg.set_color(0, Color(0.72, 0.85, 1.0, 0.8))
	cg.set_color(1, Color(0.72, 0.85, 1.0, 0.0))
	var cramp := GradientTexture1D.new()
	cramp.gradient = cg
	var cmesh := SphereMesh.new()
	cmesh.radius = 0.025
	cmesh.height = 0.050
	var cpmat := StandardMaterial3D.new()
	cpmat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	cpmat.albedo_color               = Color(0.72, 0.85, 1.0)
	cpmat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	cpmat.depth_draw_mode            = BaseMaterial3D.DEPTH_DRAW_DISABLED
	cpmat.vertex_color_use_as_albedo = true
	cmesh.material = cpmat
	for pivot in _tree_sway_pivots:
		var emitter := GPUParticles3D.new()
		emitter.amount   = 25
		emitter.lifetime = 1.1
		emitter.position = (pivot as Node3D).position + Vector3(0, 1.2, 0)
		emitter.emitting = false
		var cmat := ParticleProcessMaterial.new()
		cmat.emission_shape       = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		cmat.emission_box_extents = Vector3(2.0, 1.5, 2.0)
		cmat.direction            = Vector3(0, -1, 0)
		cmat.spread               = 14.0
		cmat.gravity              = Vector3(0, -5.5, 0)
		cmat.initial_velocity_min = 0.1
		cmat.initial_velocity_max = 0.5
		cmat.scale_min            = 0.35
		cmat.scale_max            = 0.85
		cmat.color_ramp           = cramp
		emitter.process_material  = cmat
		emitter.draw_pass_1       = cmesh
		add_child(emitter)
		_tree_splash_emitters.append(emitter)

func _make_precip_particles(is_snow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 2000 if not is_snow else 1200
	p.lifetime = 3.5 if not is_snow else 8.0
	p.position = Vector3(0, 18, 0)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(FIELD_HALF, 0.1, FIELD_HALF)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 6.0 if not is_snow else 25.0
	mat.angle_min = -8.0 if not is_snow else -40.0
	mat.angle_max = 8.0 if not is_snow else 40.0
	mat.gravity = Vector3(0, -9.0 if not is_snow else -1.2, 0)
	mat.initial_velocity_min = 0.3 if not is_snow else 0.1
	mat.initial_velocity_max = 1.2 if not is_snow else 0.5
	mat.scale_min = 0.7 if not is_snow else 0.5
	mat.scale_max = 1.4 if not is_snow else 1.8
	p.process_material = mat
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not is_snow:
		# 뷰 공간에 낙하 방향을 투영해 카메라 상하 각도에 무관하게 빗줄기 방향 유지
		# - 수평 시야: 세로 빗줄기  - 위 볼 때: 점/원  - 아래 볼 때: 짧은 흔적
		var qmesh := QuadMesh.new()
		qmesh.size = Vector2(0.028, 0.62)  # 실제 빗방울 비율: 폭 2.8cm, 길이 62cm (낙하속도에 의한 잔상)
		var rain_shader := Shader.new()
		rain_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
// 바람 포함 실제 낙하 방향 (월드 공간, 정규화됨) — GDScript에서 매 프레임 갱신
uniform vec3 fall_dir = vec3(0.0, -1.0, 0.0);
void vertex() {
	// 파티클 중심 → 뷰 공간
	vec4 center_view = VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	// 바람 포함 낙하 방향을 뷰 공간으로 변환
	vec3 fall_view  = normalize(mat3(VIEW_MATRIX) * fall_dir);
	// 수직 방향과 수직인 가로 축 (특이점 방지: fall이 ±Z에 가까우면 Y 기준 사용)
	vec3 up_ref     = abs(fall_view.z) < 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	vec3 right_view = normalize(cross(fall_view, up_ref));
	// 파티클 스케일 반영
	float s = length(MODEL_MATRIX[0].xyz);
	// VERTEX.x → 가로(right), VERTEX.y → 낙하 방향(fall)
	vec3 offset = right_view * VERTEX.x * s + fall_view * VERTEX.y * s;
	POSITION = PROJECTION_MATRIX * (center_view + vec4(offset, 0.0));
}
void fragment() {
	// 가우시안 단면: 실제 빗방울의 원형 단면을 수직 투영한 형태
	// 가운데 불투명, 가장자리로 갈수록 투명 (선명한 경계선 없음)
	float cx    = UV.x - 0.5;
	float gauss = exp(-cx * cx * 30.0);
	// 양 끝 소멸: 빗방울 위아래 끝이 공기 속으로 흐릿하게 소멸
	float fade  = smoothstep(0.0, 0.10, UV.y) * smoothstep(1.0, 0.90, UV.y);
	// Mie 전방산란: 빛이 물방울을 통과할 때 청백색으로 산란됨
	ALBEDO = vec3(0.80, 0.90, 1.0);
	// 단일 빗방울은 매우 투명 — 여러 방울이 겹쳐 비의 밀도감이 생김
	ALPHA  = gauss * fade * 0.40 * COLOR.a;
}
"""
		var rain_smat := ShaderMaterial.new()
		rain_smat.shader = rain_shader
		_rain_shader_mat = rain_smat
		qmesh.material = rain_smat
		p.draw_pass_1  = qmesh
	else:
		# 눈송이 — BILLBOARD_ENABLED로 모든 카메라 방향에서 항상 면이 보임
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3(0.06, 0.04, 0.06)
		pmat.albedo_color   = Color(0.95, 0.96, 0.98, 0.85)
		pmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		bmesh.material = pmat
		p.draw_pass_1  = bmesh
	return p

# ── 갱신 ─────────────────────────────────────────────────────────────
func update(
	weather_type: String,
	rain_rate: float,
	wind_speed: float,
	wind_direction: float,
	wind_enabled: bool,
	cloud_props: Dictionary,
	sim_month: int,
	sky_brightness: float,
	sky_overcast: float,
	rain_streak_scale: float,
	snow_size_scale: float,
	delta: float
) -> void:
	var is_rain: bool = weather_type == "RAIN"
	var is_snow: bool = weather_type == "SNOW"
	_rain_particles.emitting = is_rain
	_snow_particles.emitting = is_snow

	var wind_amt: float = wind_speed if wind_enabled else 0.0

	# 바람 방향 벡터 (나침반 각도 → X/Z)
	var wind_dir_rad: float = deg_to_rad(wind_direction)
	var wind_x: float = sin(wind_dir_rad) * wind_amt
	var wind_z: float = cos(wind_dir_rad) * wind_amt

	# 비/눈 파티클 바람 흩날림
	var rain_pmat: ParticleProcessMaterial = _rain_particles.process_material as ParticleProcessMaterial
	var rain_gravity := Vector3(wind_x * 0.6, -9.0, wind_z * 0.6)
	rain_pmat.gravity = rain_gravity
	# 빗줄기 시각 방향을 실제 낙하 방향과 일치시킴 (바람 없으면 수직, 바람 있으면 기울어짐)
	if _rain_shader_mat:
		_rain_shader_mat.set_shader_parameter("fall_dir", rain_gravity.normalized())
	var snow_pmat: ParticleProcessMaterial = _snow_particles.process_material as ParticleProcessMaterial
	snow_pmat.gravity = Vector3(wind_x * 1.1, -1.2, wind_z * 1.1)

	# 강수강도 → 입자 양·크기 (rate=0이면 파티클 없음)
	var rain_frac: float = 0.0 if rain_rate <= 0.0 else clampf(pow(rain_rate / 50.0, 0.21), 0.15, 1.0)
	_rain_particles.amount_ratio = rain_frac
	# 강도에 따른 물리적 크기 변화: 강한 비일수록 빗방울이 크고 낙하속도가 빨라 잔상이 길어짐
	var rain_size: float = (0.7 + 0.5 * rain_frac) * rain_streak_scale
	rain_pmat.scale_min = rain_size * 0.75
	rain_pmat.scale_max = rain_size * 1.35
	var snow_frac: float = clampf(rain_rate / 30.0, 0.1, 1.0)
	_snow_particles.amount_ratio = snow_frac
	var snow_size: float = (0.6 + 0.8 * snow_frac) * snow_size_scale
	snow_pmat.scale_min = snow_size * 0.7
	snow_pmat.scale_max = snow_size * 1.5

	# 스플래시 / 파문 — 비가 닿는 지면에서 튀어오르는 물방울 + 퍼지는 링
	var splash_pmat: ParticleProcessMaterial = _splash_particles.process_material as ParticleProcessMaterial
	_splash_particles.emitting    = is_rain
	_splash_particles.amount_ratio = rain_frac
	splash_pmat.gravity = Vector3(wind_x * 0.35, -9.8, wind_z * 0.35)
	for emitter in _tree_splash_emitters:
		(emitter as GPUParticles3D).emitting     = is_rain
		(emitter as GPUParticles3D).amount_ratio = rain_frac

	# 지면 젖음/눈 축적
	# 강우강도에 비례한 포화 속도: 50mm/hr 폭우 → 5분(300s), 20mm/hr → 12.5분, 2.5mm/hr → ~1.5시간
	# 계절별 눈 녹음: 겨울(12~2월)=1시간, 초봄·늦가을=30분, 봄·가을=20분, 여름=10분
	var snow_melt: float
	match sim_month:
		12, 1, 2: snow_melt = 1.0 / 3600.0
		3, 11:    snow_melt = 1.0 / 1800.0
		4, 10:    snow_melt = 1.0 / 1200.0
		_:        snow_melt = 1.0 / 600.0
	if is_rain:
		var wet_rate: float = (rain_rate / 50.0) / 300.0
		ground_wetness = clampf(ground_wetness + delta * wet_rate, 0.0, 1.0)
		# 비는 눈을 계절 속도의 6배로 녹임 (잠열 + 수온)
		ground_snow    = clampf(ground_snow - delta * snow_melt * 6.0, 0.0, 1.0)
	elif is_snow:
		# rain_rate 비례 쌓임: 10mm/hr → 300s 포화, 폭설(50mm) → 60s, 약한 눈(2mm) → 1500s
		var snow_rate: float = clampf(rain_rate / 10.0, 0.5, 5.0) / 300.0
		ground_snow    = clampf(ground_snow + delta * snow_rate, 0.0, 1.0)
		ground_wetness = clampf(ground_wetness - delta / 3600.0, 0.0, 1.0)
	else:
		ground_wetness = clampf(ground_wetness - delta / 3600.0, 0.0, 1.0)
		ground_snow    = clampf(ground_snow - delta * snow_melt, 0.0, 1.0)

	# 지면 색
	var dry_color  := Color(0.16, 0.24, 0.08)
	var wet_color  := Color(0.05, 0.13, 0.03)
	var snow_color := Color(0.92, 0.94, 0.97)
	var c: Color = dry_color.lerp(wet_color, ground_wetness).lerp(snow_color, ground_snow)
	_ground_mat.set_shader_parameter("albedo",    c)
	_ground_mat.set_shader_parameter("roughness", lerp(0.85, 0.3, ground_wetness))
	_horizon_mat.albedo_color = c
	_horizon_mat.roughness    = lerp(0.85, 0.3, ground_wetness)

	# 나뭇잎 계절 색 + 젖음 효과
	var wet: float = ground_wetness * (1.0 - ground_snow)
	var season_tint: Color = _seasonal_leaf_tint(sim_month)
	for i in range(_leaf_mats.size()):
		var base: Color = _leaf_base_colors[i]
		var seasonal := Color(
			clampf(base.r * season_tint.r, 0.0, 1.0),
			clampf(base.g * season_tint.g, 0.0, 1.0),
			clampf(base.b * season_tint.b, 0.0, 1.0))
		var m: StandardMaterial3D = _leaf_mats[i]
		var leaf_col: Color = seasonal.lerp(snow_color, ground_snow)
		m.albedo_color = leaf_col.darkened(wet * 0.38)
		m.roughness    = lerp(0.9, 0.22, wet * 0.8)

	# 나무 줄기 젖음 효과
	var trunk_dry := Color(0.18, 0.11, 0.04)
	for tmat in _trunk_mats:
		var tm: StandardMaterial3D = tmat as StandardMaterial3D
		tm.albedo_color = trunk_dry.darkened(wet * 0.45)
		tm.roughness    = lerp(0.9, 0.30, wet * 0.8)

	# 나뭇잎 눈 캡
	for cap in _leaf_snow_caps:
		cap.visible = ground_snow > 0.02
		if cap.visible:
			cap.scale.y = clampf(ground_snow, 0.05, 1.0)

	# 눈더미 메쉬
	_snow_ground_mesh.visible = ground_snow > 0.12
	if _snow_ground_mesh.visible:
		var t: float = clampf((ground_snow - 0.12) / 0.88, 0.0, 1.0)
		_snow_ground_mesh.scale.y = t
		_snow_ground_mesh.position.y = 0.25 * t

	# 수위 누적 — 지구 물리: 50mm/hr 폭우 30분 → 1m, 배수 2시간/m
	if is_rain:
		water_depth += delta * rain_rate / (50.0 * 1800.0)
	else:
		water_depth = maxf(0.0, water_depth - delta / 7200.0)

	# 웅덩이 — 크기는 ground_wetness 기반, 수위는 water_depth 기반
	var rain_int: float = rain_frac if is_rain else 0.0
	for i in range(_puddle_nodes.size()):
		var node: MeshInstance3D = _puddle_nodes[i]
		var max_r: float = _puddle_max_r[i]
		var visible_r: float = maxf(0.001, pow(wet, 0.6) * max_r * 4.0)
		node.scale    = Vector3(visible_r, 1.0, visible_r)
		node.position.y = _puddle_base_y[i] + 0.002
		var pmat: ShaderMaterial = _puddle_mats[i] as ShaderMaterial
		pmat.set_shader_parameter("rain_intensity", rain_int)
		pmat.set_shader_parameter("sky_brightness", sky_brightness)
		pmat.set_shader_parameter("wind_dir_xz", Vector2(sin(wind_dir_rad), cos(wind_dir_rad)))
		pmat.set_shader_parameter("wind_speed",  wind_amt)
		# 파동 에미터 — 웅덩이 원 안에서만 링 발생 (UV 0.47 마스크 기준 94%)
		var re: GPUParticles3D = _ripple_emitters[i] as GPUParticles3D
		re.position.y = _puddle_base_y[i] + 0.003
		var re_pmat: ParticleProcessMaterial = re.process_material as ParticleProcessMaterial
		var puddle_r: float = visible_r * 0.94
		re_pmat.emission_box_extents = Vector3(puddle_r, 0.001, puddle_r)
		re.emitting     = is_rain and wet > 0.05
		re.amount_ratio = rain_frac
	# 범람 평면 — 수위가 1mm 이상이면 출현, 5cm에서 완전 불투명, y좌표 = 실제 수위
	_flood_plane.position.y = maxf(0.002, water_depth)
	var surface_alpha: float = clampf(water_depth / 0.05, 0.0, 1.0)
	_flood_plane.visible = water_depth > 0.001
	if _flood_plane.visible:
		_flood_mat.set_shader_parameter("alpha_mult",     surface_alpha * 0.85)
		_flood_mat.set_shader_parameter("rain_intensity", rain_int)
		_flood_mat.set_shader_parameter("sky_brightness", sky_brightness)

	# 지면 실안개
	var fog_amt: float = 0.0
	if is_rain:
		fog_amt = lerp(0.015, 0.05, sky_overcast)
	elif is_snow:
		fog_amt = lerp(0.02, 0.07, sky_overcast)
	elif weather_type == "OVERCAST":
		fog_amt = 0.02
	_ground_mist.visible = fog_amt > 0.0
	if _ground_mist.visible:
		var mist_c: Color = Color(0.6, 0.62, 0.65) * sky_brightness
		_ground_mist_mat.albedo_color = Color(mist_c.r, mist_c.g, mist_c.b, clampf(fog_amt * 9.0, 0.0, 0.85))

	_update_tree_sway(wind_amt, wind_dir_rad, delta)

func _update_tree_sway(wind_amt: float, wind_dir_rad: float, delta: float) -> void:
	_sway_time += delta
	# 0-12 m/s 전 범위 선형 스케일 (6 m/s 이하에선 기존과 동일, 폭풍은 더 크게)
	var wind_factor: float = clampf(wind_amt / 12.0, 0.0, 1.0)
	var max_angle: float   = deg_to_rad(20.0) * wind_factor
	for i in range(_tree_sway_pivots.size()):
		var pivot: Node3D = _tree_sway_pivots[i]
		var phase: float  = _tree_sway_phase[i]
		var freq: float   = _tree_sway_freq[i]
		var angle: float  = sin(_sway_time * freq * TAU + phase) * max_angle
		# 나침반 방향에 맞게 기울어짐: 0°=+Z, 90°=+X, 180°=-Z, 270°=-X
		pivot.rotation = Vector3(
			angle * cos(wind_dir_rad),
			0.0,
			-angle * sin(wind_dir_rad)
		)

static func _terrain_height(x: float, z: float) -> float:
	return (
		0.12 * sin(x * 0.38 + 1.1) * cos(z * 0.29 + 0.7) +
		0.08 * sin(x * 0.71 + 2.3) * cos(z * 0.55 + 1.8) +
		0.05 * cos(x * 1.12 + 0.4) * sin(z * 0.91 + 3.1)
	)

func _find_low_points(count: int, min_sep: float) -> Array:
	var step := 0.8
	var candidates: Array = []
	var ix: float = -12.0
	while ix <= 12.0:
		var iz: float = -12.0
		while iz <= 12.0:
			candidates.append(Vector3(ix, _terrain_height(ix, iz), iz))
			iz += step
		ix += step
	candidates.sort_custom(func(a, b): return a.y < b.y)
	var chosen: Array = []
	for c in candidates:
		if chosen.size() >= count:
			break
		var ok := true
		for p in chosen:
			if Vector2(c.x - p.x, c.z - p.z).length() < min_sep:
				ok = false
				break
		if ok:
			chosen.append(c)
	return chosen

func _build_reflection_probe() -> void:
	# ReflectionProbe: 씬 전체(별·달·구름 포함)를 cubemap으로 캡처
	# UPDATE_ALWAYS = 매 프레임 갱신 → 별/구름 등 투명 오브젝트도 반사에 포함
	# SCREEN_TEXTURE에 잡히지 않는 투명 오브젝트 반사를 보완
	var probe := ReflectionProbe.new()
	probe.update_mode    = ReflectionProbe.UPDATE_ALWAYS
	probe.intensity      = 1.0
	probe.max_distance   = 80.0
	probe.extents        = Vector3(22.0, 18.0, 22.0)
	probe.position       = Vector3(0.0, 4.0, 0.0)
	probe.box_projection = false
	probe.interior       = false
	add_child(probe)

static func _seasonal_leaf_tint(month: int) -> Color:
	match month:
		3, 4:       return Color(0.85, 1.05, 0.55)
		5, 6, 7, 8: return Color(0.70, 1.00, 0.50)
		9, 10:      return Color(1.80, 0.75, 0.12)
		11:         return Color(1.20, 0.55, 0.10)
		12, 1, 2:   return Color(0.55, 0.40, 0.28)
		_:          return Color(0.70, 1.00, 0.50)
