class_name WorldSimSky
extends Node

const STARLIGHT_FLOOR_LUX: float = 0.0008

# 별자리 선분 [ra1°, dec1°, ra2°, dec2°] — J2000.0 좌표
const CONST_SEGS: Array = [
	# 큰곰자리 (Ursa Major / Big Dipper)
	[165.93,61.75,165.46,56.38],[165.46,56.38,178.46,53.69],
	[178.46,53.69,183.86,57.03],[183.86,57.03,165.93,61.75],
	[183.86,57.03,193.51,55.96],[193.51,55.96,200.98,54.93],[200.98,54.93,206.89,49.31],
	# 작은곰자리 (Ursa Minor / Little Dipper)
	[37.95,89.26,263.05,86.59],[263.05,86.59,251.49,82.04],
	[251.49,82.04,236.02,77.79],[236.02,77.79,244.38,75.76],
	[244.38,75.76,222.68,74.16],[222.68,74.16,230.18,71.83],[230.18,71.83,244.38,75.76],
	# 카시오페이아 (Cassiopeia, W)
	[28.60,63.67,21.45,60.24],[21.45,60.24,14.18,60.72],
	[14.18,60.72,10.13,56.54],[10.13,56.54,2.29,59.15],
	# 페르세우스 (Perseus)
	[51.08,49.86,49.80,53.50],[51.08,49.86,51.79,47.71],
	[51.79,47.71,57.85,40.01],[57.85,40.01,58.53,31.88],
	[51.08,49.86,42.68,55.90],[51.08,49.86,47.04,40.96],
	# 마차부자리 (Auriga)
	[79.17,45.99,89.88,44.95],[89.88,44.95,90.18,37.21],
	[90.18,37.21,74.25,33.17],[74.25,33.17,75.49,43.82],[75.49,43.82,79.17,45.99],
	# 오리온자리 (Orion) ★
	[83.78,9.93,88.79,7.41],[83.78,9.93,81.28,6.35],
	[88.79,7.41,84.05,-1.20],[81.28,6.35,83.00,-0.30],
	[83.00,-0.30,84.05,-1.20],[84.05,-1.20,85.19,-1.94],
	[85.19,-1.94,86.94,-9.67],[86.94,-9.67,78.63,-8.20],[83.00,-0.30,78.63,-8.20],
	# 황소자리 (Taurus)
	[68.98,16.51,81.57,28.61],[68.98,16.51,84.41,21.14],
	[68.98,16.51,65.73,17.54],[65.73,17.54,56.87,24.11],
	# 쌍둥이자리 (Gemini)
	[113.65,31.89,116.33,28.03],[113.65,31.89,100.98,25.13],
	[100.98,25.13,92.61,22.51],[116.33,28.03,110.03,21.98],
	[110.03,21.98,105.45,20.57],[105.45,20.57,92.61,22.51],[92.61,22.51,99.43,16.40],
	# 큰개자리 (Canis Major, Sirius)
	[101.29,-16.72,95.68,-17.96],[101.29,-16.72,104.66,-28.97],
	[104.66,-28.97,107.10,-26.39],[107.10,-26.39,111.02,-29.30],
	# 사자자리 (Leo)
	[152.09,11.97,152.65,16.76],[152.65,16.76,154.99,19.84],
	[154.99,19.84,154.17,23.42],[154.17,23.42,146.46,23.77],
	[152.09,11.97,168.56,15.43],[168.56,15.43,177.26,14.57],
	[168.53,20.52,168.56,15.43],[168.53,20.52,154.99,19.84],
	# 처녀자리 (Virgo)
	[201.30,-11.16,204.97,-0.60],[204.97,-0.60,190.41,-1.45],
	[190.41,-1.45,177.67,1.76],[190.41,-1.45,186.74,-0.66],
	[186.74,-0.66,193.90,3.40],[193.90,3.40,195.54,10.96],
	# 목동자리 (Boötes, Arcturus)
	[213.92,19.18,208.67,18.40],[213.92,19.18,221.25,27.07],
	[221.25,27.07,214.68,38.31],[214.68,38.31,218.02,40.39],
	[218.02,40.39,221.25,33.31],[221.25,33.31,221.25,27.07],
	# 헤르쿨레스 (Hercules, Keystone)
	[247.55,21.49,246.36,19.15],[246.36,19.15,248.49,24.84],
	[248.49,24.84,253.32,30.93],[253.32,30.93,250.73,31.60],
	[250.73,31.60,250.19,38.92],[250.19,38.92,255.08,36.81],
	[255.08,36.81,253.32,30.93],[247.55,21.49,248.49,24.84],
	# 전갈자리 (Scorpius) ★
	[238.85,-26.11,240.08,-22.62],[240.08,-22.62,241.36,-19.81],
	[240.08,-22.62,245.30,-25.59],[245.30,-25.59,247.35,-26.43],
	[247.35,-26.43,247.55,-28.22],[247.55,-28.22,252.54,-34.29],
	[252.54,-34.29,253.08,-38.05],[253.08,-38.05,253.08,-42.36],
	[253.08,-42.36,254.03,-43.24],[254.03,-43.24,263.40,-37.10],
	[263.40,-37.10,265.62,-39.03],[263.40,-37.10,264.33,-43.00],
	# 궁수자리 (Sagittarius, Teapot)
	[271.45,-25.42,275.25,-29.83],[275.25,-29.83,276.99,-34.38],
	[276.99,-34.38,285.66,-29.88],[285.66,-29.88,283.82,-26.30],
	[283.82,-26.30,290.97,-27.67],[271.45,-25.42,271.45,-30.42],
	[271.45,-30.42,275.25,-29.83],[283.82,-26.30,271.45,-25.42],
	# 거문고자리 (Lyra, Vega)
	[279.23,38.78,282.52,33.36],[279.23,38.78,284.74,32.69],
	[282.52,33.36,284.74,32.69],[281.20,36.90,282.52,33.36],[281.20,36.90,279.23,38.78],
	# 백조자리 (Cygnus, Northern Cross)
	[310.36,45.28,305.56,40.26],[305.56,40.26,292.68,27.96],
	[299.08,45.13,305.56,40.26],[305.56,40.26,311.55,33.97],
	# 독수리자리 (Aquila, Altair)
	[296.56,10.61,297.70,8.87],[297.70,8.87,298.83,6.41],
	[286.35,13.86,296.56,10.61],[297.70,8.87,296.10,3.11],[296.10,3.11,296.67,-4.88],
	# 페가수스 (Pegasus, Great Square)
	[346.19,28.08,346.19,15.18],[346.19,15.18,3.31,15.18],
	[3.31,15.18,2.10,29.09],[2.10,29.09,346.19,28.08],
	[346.19,28.08,335.56,33.17],[346.19,15.18,323.49,9.83],
]

# 외부에서 읽는 출력값
var sky_brightness_safe: float     = 1.0
var sky_overcast_amt_current: float = 0.0
var cloud_tau_current: float        = 0.0

var show_constellations: bool = false  # UI 토글로 제어

var _sun_light: DirectionalLight3D
var _moon_light: DirectionalLight3D
var _moon_mesh: MeshInstance3D
var _moon_shader_mat: ShaderMaterial
var _sun_mesh: MeshInstance3D
var _sun_shader_mat: ShaderMaterial
var _world_env: WorldEnvironment
var _sky_mat: ProceduralSkyMaterial
var _stars_mm: MultiMeshInstance3D
var _planet_mm: MultiMeshInstance3D    # 금성·목성 (2 인스턴스)
var _const_mesh: ImmediateMesh         # 별자리 선분
var _const_mesh_inst: MeshInstance3D
var _cloud_mesh: MeshInstance3D
var _cloud_shader_mat: ShaderMaterial
var _bolt_mesh: ImmediateMesh          # 번개 볼트 선분
var _bolt_inst: MeshInstance3D
var _bolt_mat:  ShaderMaterial
var _bolt_segs: Array      = []        # [[Vector3, Vector3], ...] 세그먼트 목록
var _prev_lightning: float = 0.0      # 섬광 상승 엣지 감지용
var _bolt_az: float        = 0.0      # 현재 볼트 방위각 (도)
var _star_data: Array = []
var _current_exposure: float = 1.0  # 노출 스무딩 상태 (프레임 간 급격한 변화 방지)

# ── 빌드 ─────────────────────────────────────────────────────────────
func build() -> void:
	_load_star_catalog()
	_build_sky_and_lights()
	_build_stars()
	_build_planets()
	_build_constellations()
	_build_clouds()
	_build_bolt()

func _load_star_catalog() -> void:
	var f := FileAccess.open("res://stars.json", FileAccess.READ)
	if f == null:
		push_warning("stars.json을 못 찾음 — 별 없이 진행")
		return
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_ARRAY:
		_star_data = parsed

func _build_sky_and_lights() -> void:
	_world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = _sky_mat
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	# 화면 공간 반사 — 웅덩이에 나무·하늘 투영 구현 (Forward+ 전용)
	env.ssr_enabled         = true
	env.ssr_max_steps       = 56
	env.ssr_fade_in         = 0.15
	env.ssr_fade_out        = 2.0
	env.ssr_depth_tolerance = 0.2
	_world_env.environment = env
	add_child(_world_env)

	_sun_light = DirectionalLight3D.new()
	_sun_light.light_energy = 1.0
	_sun_light.shadow_enabled = true
	add_child(_sun_light)

	_moon_light = DirectionalLight3D.new()
	_moon_light.light_energy = 0.0
	_moon_light.light_color = Color(0.75, 0.82, 1.0)
	_moon_light.shadow_enabled = false
	add_child(_moon_light)

	_moon_mesh = MeshInstance3D.new()
	var msph := SphereMesh.new()
	msph.radius = 0.46
	msph.height = 0.92
	_moon_mesh.mesh = msph
	_moon_shader_mat = ShaderMaterial.new()
	var moon_shader := Shader.new()
	moon_shader.code = """
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_never;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 lit_color : source_color = vec3(1.0, 0.98, 0.92);
uniform float brightness : hint_range(0.0, 10.0) = 2.0;
uniform float exposure_safe : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_fade   : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz);
}

void fragment() {
	float ndotl = dot(normalize(world_normal), normalize(sun_dir));
	float lit = smoothstep(-0.08, 0.08, ndotl);
	vec3 dark_col   = vec3(0.008, 0.013, 0.028) * exposure_safe;
	vec3 bright_col = lit_color * brightness * exposure_safe;
	// 구름을 통과할수록 달빛이 파랗고 희게 산란됨
	vec3 cloud_white = vec3(0.78, 0.82, 0.98) * exposure_safe;
	bright_col = mix(bright_col, cloud_white, (1.0 - cloud_fade) * 0.8);
	vec3 col = mix(dark_col, bright_col, lit) * cloud_fade;
	ALBEDO   = col;
	// EMISSION 제거 — unshaded+blend_mix에서 EMISSION은 ALPHA=0이어도 기록됨
	// ALBEDO만 두면 ALPHA=lit*cloud_fade로 어두운 면이 완전 투명 처리됨
	ALPHA = lit * cloud_fade;
}
"""
	_moon_shader_mat.shader = moon_shader
	_moon_shader_mat.set_shader_parameter("sun_dir", Vector3(0, 1, 0))
	_moon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_moon_mesh.material_override = _moon_shader_mat
	add_child(_moon_mesh)

	# 태양 원반 — 뷰 공간 빌보드 쿼드, 거리 100m, 실제 태양 시각도 ~0.53° 재현
	# 빌보드 정점 셰이더로 항상 카메라를 향함. blend_add로 하늘 색에 합산.
	_sun_mesh = MeshInstance3D.new()
	var sun_quad := QuadMesh.new()
	sun_quad.size = Vector2(0.9, 0.9)
	_sun_mesh.mesh = sun_quad
	var sun_shader := Shader.new()
	sun_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.80);
uniform float cloud_fade : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// 뷰 공간에서 billboard — 회전 없이 카메라 정면으로 위치 오프셋만 적용
	vec4 center_view = VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	POSITION = PROJECTION_MATRIX * (center_view + vec4(VERTEX.xy, 0.0, 0.0));
}

void fragment() {
	float d     = length(UV - vec2(0.5)) * 2.0;
	// 원반: quad 안쪽 82% 영역이 실제 태양 원반, 0.9m quad에서 시각도 ~0.47°
	float disc  = 1.0 - smoothstep(0.82, 0.96, d);
	// 코로나 글로우: 빠르게 감쇠해 과도한 bloom 방지
	float glow  = exp(-d * 4.5) * 0.18;
	ALBEDO = sun_color;
	ALPHA  = clamp((disc * 0.75 + glow) * cloud_fade, 0.0, 0.82);
}
"""
	_sun_shader_mat = ShaderMaterial.new()
	_sun_shader_mat.shader = sun_shader
	_sun_shader_mat.set_shader_parameter("sun_color",  Vector3(1.0, 0.95, 0.80))
	_sun_shader_mat.set_shader_parameter("cloud_fade", 1.0)
	_sun_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sun_mesh.material_override = _sun_shader_mat
	add_child(_sun_mesh)

func _build_stars() -> void:
	_stars_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors       = true   # per-star 밝기를 인스턴스 color.a 에 인코딩
	mm.use_custom_data  = false
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = max(_star_data.size(), 1)
	_stars_mm.multimesh = mm

	# 초기값: 전부 투명 — 가시성은 _update_stars()에서 매 프레임 계산
	for i in range(_star_data.size()):
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0.0, -2000.0, 0.0)))

	# 가우시안 PSF 셰이더 — 실제 별의 회절·대기산란 패턴 재현
	# blend_add: 별이 겹쳐도 자연스럽게 합산 (물리적으로 올바름)
	var star_shader := Shader.new()
	star_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float global_brightness : hint_range(0.0, 8.0) = 0.0;
varying vec4 star_col;

void vertex() {
\t// use_colors=true 인스턴스 색상 전달
\tstar_col = COLOR;
\t// 뷰 공간 빌보드 — 인스턴스 스케일 보존하면서 항상 카메라 정면
\tfloat s = length(MODEL_MATRIX[0]);
\tMODELVIEW_MATRIX = VIEW_MATRIX * mat4(
\t\tINV_VIEW_MATRIX[0] * s,
\t\tINV_VIEW_MATRIX[1] * s,
\t\tINV_VIEW_MATRIX[2] * s,
\t\tMODEL_MATRIX[3]);
}

void fragment() {
\tvec2 uv = UV - vec2(0.5);
\tfloat d2 = dot(uv, uv) * 4.0;
\t// 이중 가우시안: 밝은 핵(core) + 넓은 광환(halo) — 대기 PSF 재현
\tfloat core = exp(-d2 * 18.0);
\tfloat halo = exp(-d2 * 3.0) * 0.35;
\tALBEDO = star_col.rgb;
\tALPHA  = clamp((core + halo) * global_brightness * star_col.a, 0.0, 1.0);
}
"""
	var smat := ShaderMaterial.new()
	smat.shader = star_shader
	smat.set_shader_parameter("global_brightness", 0.0)
	_stars_mm.material_override = smat
	add_child(_stars_mm)

## 행성 순서(인덱스 고정): 수성0 금성1 화성2 목성3 토성4 천왕성5 해왕성6
const PLANETS: Array = ["mercury","venus","mars","jupiter","saturn","uranus","neptune"]
## 행성별 고유 색 (RGB) — 실제 반사 스펙트럼 기반
const PLANET_COLORS: Array = [
	Color(0.88, 0.83, 0.80),   # 수성 — 회백
	Color(1.00, 0.97, 0.88),   # 금성 — 따뜻한 흰
	Color(1.00, 0.60, 0.40),   # 화성 — 주황적
	Color(0.97, 0.92, 0.80),   # 목성 — 연한 황백
	Color(1.00, 0.93, 0.68),   # 토성 — 황금
	Color(0.68, 0.92, 1.00),   # 천왕성 — 청록
	Color(0.40, 0.60, 1.00),   # 해왕성 — 파랑
]

func _build_planets() -> void:
	_planet_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors       = true
	mm.use_custom_data  = false
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = PLANETS.size()
	for idx in range(PLANETS.size()):
		mm.set_instance_color(idx, Color(PLANET_COLORS[idx].r, PLANET_COLORS[idx].g, PLANET_COLORS[idx].b, 0.0))
		mm.set_instance_transform(idx, Transform3D(Basis(), Vector3(0.0, -2000.0, 0.0)))
	_planet_mm.multimesh = mm
	# 별과 동일한 가우시안 PSF 셰이더 재사용
	var psmat := _stars_mm.material_override.duplicate() as ShaderMaterial
	psmat.set_shader_parameter("global_brightness", 0.0)
	_planet_mm.material_override = psmat
	add_child(_planet_mm)

func _build_constellations() -> void:
	_const_mesh = ImmediateMesh.new()
	_const_mesh_inst = MeshInstance3D.new()
	_const_mesh_inst.mesh = _const_mesh
	var line_shader := Shader.new()
	line_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform float line_alpha : hint_range(0.0, 1.0) = 0.0;
void fragment() {
\tALBEDO = vec3(0.55, 0.68, 1.0);
\tALPHA  = line_alpha;
}
"""
	var lmat := ShaderMaterial.new()
	lmat.shader = line_shader
	lmat.set_shader_parameter("line_alpha", 0.0)
	_const_mesh_inst.material_override = lmat
	_const_mesh_inst.visible = false
	add_child(_const_mesh_inst)

func _build_clouds() -> void:
	_cloud_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)   # 넓힘 — 고고도 권운도 지평선 근처까지 커버
	_cloud_mesh.mesh = plane
	_cloud_mesh.position = Vector3(0, 20, 0)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;
uniform float coverage     : hint_range(0.0, 1.0)  = 0.4;
uniform float density      : hint_range(0.0, 1.0)  = 0.5;
uniform float noise_scale  : hint_range(0.5, 30.0) = 6.0;
uniform float softness     : hint_range(0.02, 0.6) = 0.25;
uniform float warp_str     : hint_range(0.0, 1.0)  = 0.4;
uniform float stretch_ratio: hint_range(1.0, 8.0)  = 1.0;
uniform vec2  drift        = vec2(0.0, 0.0);
uniform vec2  stretch_dir  = vec2(0.0, 1.0);
uniform vec3  cloud_base   : source_color = vec3(0.85, 0.86, 0.88);
uniform float brightness   : hint_range(0.0, 2.0)  = 1.0;
uniform vec3  sun_dir      = vec3(0.0, 1.0, 0.0);
uniform vec3  sun_color    : source_color = vec3(1.0, 0.95, 0.80);

// sin() 기반 해시의 격자무늬 문제 해결 — fract 곱 해시
float hash2(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}
// C² 퀸틱 보간 Value Noise — 경계 아티팩트 없음
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(
		mix(hash2(i),               hash2(i + vec2(1.0, 0.0)), u.x),
		mix(hash2(i + vec2(0.0,1.0)), hash2(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}
// 5옥타브 FBM — 각 레이어 주파수 2.13×, 진폭 0.5×
float fbm5(vec2 p) {
	float v = 0.0, a = 0.5;
	v += a * vnoise(p); p = p * 2.13 + vec2(1.70, 9.20); a *= 0.5;
	v += a * vnoise(p); p = p * 2.13 + vec2(8.30, 2.80); a *= 0.5;
	v += a * vnoise(p); p = p * 2.13 + vec2(3.10, 7.40); a *= 0.5;
	v += a * vnoise(p); p = p * 2.13 + vec2(5.90, 4.60); a *= 0.5;
	v += a * vnoise(p);
	return v;
}
void fragment() {
	vec2 uv_base = UV * noise_scale + drift;
	// 이방성 UV 변환 — 바람 방향으로 노이즈 특징 늘이기 (권운 실·줄기 모양)
	// sd 방향 성분을 stretch_ratio로 나눔 → 그 방향으로 특징이 stretch_ratio배 길어짐
	vec2 sd      = normalize(stretch_dir + vec2(0.0001, 0.0));
	vec2 perp    = vec2(-sd.y, sd.x);
	float par_c  = dot(uv_base, sd);
	float perp_c = dot(uv_base, perp);
	vec2 uv      = sd * (par_c / stretch_ratio) + perp * perp_c;
	// 도메인 워핑: 저주파 노이즈로 UV 교란 → 구름 윤곽 자연스러움
	vec2 warp = vec2(
		fbm5(uv * 0.42 + vec2(0.00, 0.00)),
		fbm5(uv * 0.42 + vec2(5.20, 1.30))
	) * 2.0 - 1.0;
	float n = fbm5(uv + warp_str * warp);
	float a = smoothstep(1.0 - coverage, 1.0 - coverage + softness, n) * density;
	// 태양 고도 (0=지평선, 1=천정)
	float sun_up = clamp(sun_dir.y, 0.0, 1.0);
	// 가장자리 계수: alpha 낮은 곳(얇은 부분)일수록 1
	float thin   = clamp(1.0 - a / max(density, 0.01), 0.0, 1.0);
	// 구름 바닥 음영 — density×2 로 누적운(적운) 아래면 확실히 어둡게
	// 권운(density≈0.05): shadow≈0.95(거의 흰색), 적운(0.28): ≈0.69, 난층운(1.0): ≈0.45
	float shadow = mix(1.0, 0.45, clamp(density * 2.0, 0.0, 1.0) * sqrt(clamp(a, 0.0, 1.0)));
	vec3  col    = cloud_base * shadow;
	// 실버 라이닝: 얇은 가장자리에서 태양빛 투과 → 따뜻하고 밝은 테두리
	col = mix(col, sun_color * 1.6, thin * sun_up * 0.55);
	ALBEDO = col * brightness;
	ALPHA  = a;
}
"""
	_cloud_shader_mat = ShaderMaterial.new()
	_cloud_shader_mat.shader = shader
	_cloud_shader_mat.set_shader_parameter("coverage",      0.4)
	_cloud_shader_mat.set_shader_parameter("density",       0.5)
	_cloud_shader_mat.set_shader_parameter("warp_str",      0.4)
	_cloud_shader_mat.set_shader_parameter("stretch_ratio", 1.0)
	_cloud_shader_mat.set_shader_parameter("stretch_dir",   Vector2(0.0, 1.0))
	_cloud_shader_mat.set_shader_parameter("sun_dir",       Vector3(0.0, 1.0, 0.0))
	_cloud_shader_mat.set_shader_parameter("sun_color",     Color(1.0, 0.95, 0.80))
	_cloud_mesh.material_override = _cloud_shader_mat
	add_child(_cloud_mesh)

# ── 갱신 ─────────────────────────────────────────────────────────────
func update(
	sun_altaz: Vector2,
	moon: Dictionary,
	cloud_props: Dictionary,
	weather_type: String,
	wind_speed: float,
	wind_direction: float,
	wind_enabled: bool,
	lightning_flash: float,
	lightning_bolt_dist_km: float,
	dt: Dictionary,
	hour_utc: float,
	latitude: float,
	longitude: float,
	delta: float
) -> void:
	_update_sky_and_lights(sun_altaz, moon, cloud_props, lightning_flash, delta)
	_update_stars(dt, hour_utc, latitude, longitude, cloud_props)
	_update_planets(dt, hour_utc, latitude, longitude, cloud_props)
	_update_constellations(dt, hour_utc, latitude, longitude, cloud_props)
	_update_bolt(lightning_flash, lightning_bolt_dist_km)
	_update_cloud_visual(cloud_props, weather_type, wind_speed, wind_direction, wind_enabled, sun_altaz, delta)

func _update_sky_and_lights(sun_altaz: Vector2, moon: Dictionary, cloud_props: Dictionary, lightning_flash: float, delta: float) -> void:
	var elevation: float = sun_altaz.x
	var azimuth: float   = sun_altaz.y
	var sun_dir: Vector3 = _altaz_to_dir(elevation, azimuth)
	_sun_light.global_transform = Transform3D(Basis.looking_at(-sun_dir, Vector3.UP), Vector3.ZERO)

	var moon_alt: float   = moon["alt"]
	var moon_az: float    = moon["az"]
	var moon_illum: float = moon["illum"]
	var moon_dir: Vector3 = _altaz_to_dir(moon_alt, moon_az)
	_moon_light.global_transform = Transform3D(Basis.looking_at(-moon_dir, Vector3.UP), Vector3.ZERO)
	_moon_mesh.position = moon_dir * 100.0
	_moon_mesh.visible  = moon_alt > 0.0
	_moon_shader_mat.set_shader_parameter("sun_dir", sun_dir)
	# 달 고도에 따른 색: 지평선 근처=오렌지(대기 산란), 상공=청백
	var moon_warm: float = clampf(1.0 - moon_alt / 18.0, 0.0, 1.0)
	var moon_lit_c := Vector3(1.0, lerp(0.98, 0.62, moon_warm * 0.65), lerp(0.92, 0.28, moon_warm * 0.65))
	_moon_shader_mat.set_shader_parameter("lit_color", moon_lit_c)
	# DirectionalLight 색도 동일 규칙으로 갱신 (build()의 고정값 대체)
	# 지평선 = 오렌지황(0.95, 0.75, 0.55), 상공 = 청백(0.75, 0.82, 1.00)
	var moon_hz: float = clampf(1.0 - moon_alt / 15.0, 0.0, 1.0)
	_moon_light.light_color = Color(
		lerp(0.75, 0.95, moon_hz),
		lerp(0.82, 0.75, moon_hz),
		lerp(1.00, 0.55, moon_hz)
	)

	# 태양 원반 위치/색 업데이트 — sun_color 계산 전에 먼저 위치 설정
	_sun_mesh.position = sun_dir * 100.0
	_sun_mesh.visible  = elevation > -3.0

	var warm: float        = clampf(1.0 - elevation / 20.0, 0.0, 1.0)
	var night_blend: float = clampf(-elevation / 6.0, 0.0, 1.0)
	var white   := Color(1, 1, 1)
	var orange  := Color(1.0, 0.6, 0.3)
	var moonlt  := Color(0.65, 0.72, 0.95)
	var sun_color: Color = white.lerp(orange, warm).lerp(moonlt, night_blend)
	# 구름/흐림이면 직사광 색이 중성 회백색으로 수렴 (파장별 산란 균일화)
	var cloud_grey_amt: float = 1.0 - exp(-(cloud_props["tau"] as float) / 12.0)
	sun_color = sun_color.lerp(Color(0.93, 0.93, 0.94), cloud_grey_amt * (1.0 - night_blend))
	_sun_light.light_color = sun_color

	# 태양 원반 색을 DirectionalLight 색과 동기화 (지평선=주황, 상공=흰색)
	_sun_shader_mat.set_shader_parameter("sun_color", Vector3(sun_color.r, sun_color.g, sun_color.b))

	var sun_lux: float  = _sun_illuminance(elevation)
	var moon_lux: float = 0.0
	if moon_alt > 0.0:
		moon_lux = 0.27 * moon_illum * sin(deg_to_rad(moon_alt))
	var total_lux: float = sun_lux + moon_lux + STARLIGHT_FLOOR_LUX

	var exposure_ev: float = _exposure_for_lux(total_lux)
	if lightning_flash > 0.01:
		exposure_ev = lerp(exposure_ev, 0.0, lightning_flash)
	# FP16 HDR 버퍼 최솟값(6e-5) 대비 tonemap 보정 상한 = 2^4 = 16×
	# 이 이상은 FP16 양자화 오차가 증폭되어 분홍/초록 노이즈로 나타남
	# 낮→밤 급전환 방지: delta 기반 부드러운 스무딩 적용
	const EV_MAX: float = 4.0
	var target_exp: float = clampf(pow(2.0, exposure_ev), 0.5, pow(2.0, EV_MAX))
	_current_exposure = lerp(_current_exposure, target_exp, clampf(delta * 2.0, 0.0, 1.0))
	var exposure_mult: float = _current_exposure
	_sun_light.light_energy  = min(clampf(sun_lux / 100000.0 * 3.0, 0.0, 6.0), 6.0 / exposure_mult)
	# 달 에너지: 위상에 정확히 비례 (이중 min 제거 — 보름달 vs 반달 밝기 구분)
	# 지평선 근처(8° 미만)이거나 위상 40% 미만이면 그림자 비활성
	_moon_light.light_energy = clampf(moon_lux / 0.27 * 0.6, 0.0, 0.6) / exposure_mult * exp(-(cloud_props["tau"] as float))
	_moon_light.shadow_enabled = moon_alt > 8.0 and moon_illum > 0.40

	sky_brightness_safe = min(1.0, 1.0 / exposure_mult)
	_moon_shader_mat.set_shader_parameter("exposure_safe", sky_brightness_safe)

	var sky_night_blend: float = clampf((-elevation - 6.0) / 12.0, 0.0, 1.0)
	var day_top     := Color(0.35, 0.55, 0.95) * sky_brightness_safe
	var sunset_top  := Color(0.45, 0.35, 0.55) * sky_brightness_safe
	# FP16 최솟값(6e-5) 이상으로 설정 — 극소 값은 FP16 양자화 노이즈 유발
	# 달 위상/고도에 따라 밤하늘 전체 밝기 조정 (보름달 = 2.5배)
	# tonemap ×16 후 달 없는 밤 ≈ (0.030, 0.035, 0.057) = 실제 어두운 남색
	var moon_sky_factor: float = 1.0 + clampf(moon_lux / 0.27, 0.0, 1.0) * 1.5
	var night_top := Color(0.00190 * moon_sky_factor, 0.00218 * moon_sky_factor, 0.00358 * moon_sky_factor)
	var top: Color   = day_top.lerp(sunset_top, warm * (1.0 - sky_night_blend)).lerp(night_top, sky_night_blend)
	var day_horizon    := Color(0.75, 0.80, 0.90) * sky_brightness_safe
	var sunset_horizon := Color(1.0, 0.55, 0.30) * sky_brightness_safe
	# 지평선은 상단보다 약간 더 어둡게 (실제 밤 지평선은 대기 소광으로 더 어두움)
	var night_horizon  := Color(0.00080 * moon_sky_factor, 0.00085 * moon_sky_factor, 0.00140 * moon_sky_factor)
	var horizon: Color  = day_horizon.lerp(sunset_horizon, warm * (1.0 - sky_night_blend)).lerp(night_horizon, sky_night_blend)

	var cloud_tau: float = cloud_props["tau"]
	cloud_tau_current = cloud_tau
	var direct_transmittance: float = exp(-cloud_tau)
	var sky_overcast_amt: float = 1.0 - exp(-cloud_tau / 12.0)
	sky_overcast_amt_current = sky_overcast_amt
	# 달/태양 메시: 구름이 두꺼울수록 점점 흐려지다 사라짐
	var moon_cloud_fade: float = clampf(1.0 - sky_overcast_amt * 1.2, 0.0, 1.0)
	_moon_shader_mat.set_shader_parameter("cloud_fade", moon_cloud_fade)
	_moon_mesh.visible = moon_alt > 0.0 and moon_cloud_fade > 0.01
	# 태양은 얇은 구름에서도 어느 정도 보임 (달보다 밝아서)
	var sun_cloud_fade: float = clampf(1.0 - sky_overcast_amt * 0.85, 0.0, 1.0)
	_sun_shader_mat.set_shader_parameter("cloud_fade", sun_cloud_fade)
	var overcast_grey: Color = Color(0.42, 0.44, 0.47) * sky_brightness_safe
	top     = top.lerp(overcast_grey,    sky_overcast_amt * (1.0 - sky_night_blend))
	horizon = horizon.lerp(overcast_grey, sky_overcast_amt * (1.0 - sky_night_blend))
	top.a = 1.0; horizon.a = 1.0
	_sky_mat.sky_top_color      = top
	_sky_mat.sky_horizon_color  = horizon
	_sky_mat.ground_horizon_color = horizon
	var ground_bottom: Color    = Color(0.05, 0.05, 0.05) * sky_brightness_safe
	ground_bottom.a = 1.0
	_sky_mat.ground_bottom_color = ground_bottom

	_sun_light.light_energy *= direct_transmittance
	_world_env.environment.tonemap_exposure = exposure_mult

	var sat: float = clampf((log(max(total_lux, 1e-5)) / log(10.0) + 2.0) / (log(400.0) / log(10.0) + 2.0), 0.0, 1.0)
	_world_env.environment.adjustment_enabled    = true
	_world_env.environment.adjustment_saturation = lerp(0.15, 1.0, sat)

	if lightning_flash > 0.01:
		var fi: float = lightning_flash
		_sky_mat.sky_top_color     = _sky_mat.sky_top_color.lerp(Color(0.75, 0.80, 0.95), fi)
		_sky_mat.sky_horizon_color = _sky_mat.sky_horizon_color.lerp(Color(0.85, 0.87, 0.95), fi)
		_world_env.environment.tonemap_exposure = lerp(_world_env.environment.tonemap_exposure, 1.0, fi)

func _update_stars(dt: Dictionary, hour_utc: float, latitude: float, longitude: float, cloud_props: Dictionary) -> void:
	if _star_data.is_empty():
		return
	var sun_elev: float  = Astronomy.sun_altaz(dt["year"], dt["month"], dt["day"], hour_utc, latitude, longitude).x
	var cloud_block: float = cloud_props["okta"]
	# 태양이 지평선 위면 어떤 별도 보이지 않음 — 위치 계산 생략
	if sun_elev > 0.0:
		_stars_mm.visible = false
		return
	_stars_mm.visible = true
	var smat: ShaderMaterial = _stars_mm.material_override as ShaderMaterial
	# 구름은 모든 별에 동일하게 적용 — 박명 페이드는 per-star 인스턴스 색상에서 처리
	smat.set_shader_parameter("global_brightness", 4.0 * max(0.0, 1.0 - cloud_block))
	var jd: float = Astronomy.julian_day(dt["year"], dt["month"], dt["day"], hour_utc)
	var g: float  = Astronomy.gmst_deg(jd)
	var mm := _stars_mm.multimesh
	var radius: float = 400.0
	for i in range(_star_data.size()):
		var star: Dictionary = _star_data[i]
		var mag: float = star["mag"]
		# 등급별 박명 역치 — 밝은 별일수록 하늘 배경 대비가 높아 일찍 보임
		# mag -1.5(시리우스): 태양 -4°에서 보이기 시작
		# mag  5.0(5등성):    태양 -14°에서 보이기 시작
		var appear_elev: float = lerp(-4.0, -14.0, (mag + 1.5) / 6.5)
		# 태양이 appear_elev+2° → appear_elev 로 낮아지는 2° 구간에서 부드럽게 페이드인
		var twilight: float = clampf((sun_elev - appear_elev - 2.0) / -2.0, 0.0, 1.0)
		# 포그손 밝기 × 박명 가시도 → instance color.a 에 인코딩
		var pogson_b: float = clampf(pow(10.0, -mag * 0.40), 0.0, 1.0)
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, pogson_b * twilight))
		var altaz: Vector2 = Astronomy.radec_to_altaz(star["ra"], star["dec"], g, latitude, longitude)
		var dir: Vector3   = _altaz_to_dir(altaz.x, altaz.y)
		# 포그손 법칙 기반 로그 크기: 5등급차 = 100배 밝기, 크기는 밝기의 0.18승에 비례
		var scale_: float  = clampf(0.45 * pow(10.0, -0.18 * mag), 0.10, 3.0)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(scale_, scale_, scale_)), dir * radius))

func _update_planets(dt: Dictionary, hour_utc: float, latitude: float, longitude: float, cloud_props: Dictionary) -> void:
	var sun_elev: float  = Astronomy.sun_altaz(dt["year"], dt["month"], dt["day"], hour_utc, latitude, longitude).x
	var cloud_block: float = cloud_props["okta"]
	var psmat: ShaderMaterial = _planet_mm.material_override as ShaderMaterial
	# 행성은 태양 고도 +3° 이하에서 표시 (금성은 낮에도 보이는 경우 있어 기준을 완화)
	if sun_elev > 3.0:
		psmat.set_shader_parameter("global_brightness", 0.0)
		return
	psmat.set_shader_parameter("global_brightness", 4.0 * max(0.0, 1.0 - cloud_block))
	var mm := _planet_mm.multimesh
	var radius: float = 398.0  # 별(400)보다 약간 앞에 — 행성이 별 앞에 겹쳐 그려짐
	for idx in range(PLANETS.size()):
		var pname: String = PLANETS[idx]
		var pc: Color = PLANET_COLORS[idx]
		var ps: Dictionary = Astronomy.planet_state(pname, dt["year"], dt["month"], dt["day"], hour_utc, latitude, longitude)
		if ps.is_empty():
			mm.set_instance_color(idx, Color(pc.r, pc.g, pc.b, 0.0))
			mm.set_instance_transform(idx, Transform3D(Basis(), Vector3(0.0, -2000.0, 0.0)))
			continue
		var mag: float = ps["mag"]
		# 등급별 박명 역치 (금성은 -4.5등 → 태양 +3°에서도 보임, 외행성 공식과 동일 구조)
		var appear_elev: float = lerp(-4.0, -14.0, (mag + 1.5) / 6.5)
		var twilight: float    = clampf((sun_elev - appear_elev - 2.0) / -2.0, 0.0, 1.0)
		var pogson_b: float    = clampf(pow(10.0, -mag * 0.40), 0.0, 1.0)
		mm.set_instance_color(idx, Color(pc.r, pc.g, pc.b, pogson_b * twilight))
		var dir: Vector3   = _altaz_to_dir(ps["alt"], ps["az"])
		var scale_: float  = clampf(0.45 * pow(10.0, -0.18 * mag), 0.10, 3.5)
		mm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3(scale_, scale_, scale_)), dir * radius))

func _update_constellations(dt: Dictionary, hour_utc: float, latitude: float, longitude: float, cloud_props: Dictionary) -> void:
	var sun_elev: float  = Astronomy.sun_altaz(dt["year"], dt["month"], dt["day"], hour_utc, latitude, longitude).x
	var night_blend: float = clampf(-sun_elev / 6.0, 0.0, 1.0)
	var cloud_block: float = cloud_props["okta"]
	var star_vis: float    = night_blend * (1.0 - cloud_block)
	var lmat: ShaderMaterial = _const_mesh_inst.material_override as ShaderMaterial
	# 별자리는 별이 보일 때만, 그리고 토글 ON일 때만 표시
	if not show_constellations or star_vis < 0.05:
		_const_mesh_inst.visible = false
		return
	_const_mesh_inst.visible = true
	lmat.set_shader_parameter("line_alpha", clampf(star_vis * 0.45, 0.0, 0.45))
	var jd: float = Astronomy.julian_day(dt["year"], dt["month"], dt["day"], hour_utc)
	var g: float  = Astronomy.gmst_deg(jd)
	var radius: float = 395.0  # 별(400)보다 살짝 안쪽
	_const_mesh.clear_surfaces()
	_const_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for seg in CONST_SEGS:
		var a1: Vector2 = Astronomy.radec_to_altaz(seg[0], seg[1], g, latitude, longitude)
		var a2: Vector2 = Astronomy.radec_to_altaz(seg[2], seg[3], g, latitude, longitude)
		_const_mesh.surface_add_vertex(_altaz_to_dir(a1.x, a1.y) * radius)
		_const_mesh.surface_add_vertex(_altaz_to_dir(a2.x, a2.y) * radius)
	_const_mesh.surface_end()

func _update_cloud_visual(cloud_props: Dictionary, weather_type: String, wind_speed: float, wind_direction: float, wind_enabled: bool, sun_altaz: Vector2, delta: float) -> void:
	# 운형별 실제 물리 파라미터
	# Y 고도: 권운 8km→250m, 적운 1km→60m, 층운·난층운 500m→22~28m
	# scale: 4000m 평면에서 구름 1개 크기 = 4000/scale m
	#   권운 scale=1.5 → 2667m 큰 줄기, 적운 scale=4 → 1000m 뭉게구름, 층운/비 scale=2~2.5 → 넓은 덩어리
	# stretch: 바람 방향으로 이방성 늘이기 — 권운(4×=실 모양), 나머지(1×=등방)
	# warp: 도메인 워핑 강도 — 권운(낮음=직선 얼음결정), 적란운(높음=격렬한 대류)
	var shape_presets := {
		"CLEAR":    {"visible": false, "y":  20.0, "scale": 6.0,  "soft": 0.25, "warp": 0.40, "stretch": 1.0, "base": Color(0.95, 0.95, 0.96)},
		"CIRRUS":   {"visible": true,  "y": 250.0, "scale": 1.5,  "soft": 0.38, "warp": 0.08, "stretch": 4.0, "base": Color(0.96, 0.97, 1.00)},
		"CUMULUS":  {"visible": true,  "y":  60.0, "scale": 4.0,  "soft": 0.16, "warp": 0.50, "stretch": 1.0, "base": Color(0.87, 0.88, 0.90)},
		"OVERCAST": {"visible": true,  "y":  25.0, "scale": 2.0,  "soft": 0.10, "warp": 0.30, "stretch": 1.0, "base": Color(0.62, 0.63, 0.66)},
		"RAIN":     {"visible": true,  "y":  22.0, "scale": 2.5,  "soft": 0.15, "warp": 0.60, "stretch": 1.0, "base": Color(0.32, 0.33, 0.36)},
		"SNOW":     {"visible": true,  "y":  28.0, "scale": 2.5,  "soft": 0.18, "warp": 0.40, "stretch": 1.0, "base": Color(0.58, 0.60, 0.63)},
	}
	var shape: Dictionary = shape_presets.get(weather_type, shape_presets["CLEAR"])
	var coverage: float   = cloud_props["okta"]
	var density: float    = sky_overcast_amt_current

	_cloud_mesh.visible    = shape["visible"]
	_cloud_mesh.position.y = shape["y"]
	_cloud_shader_mat.set_shader_parameter("coverage",    coverage)
	_cloud_shader_mat.set_shader_parameter("density",     clampf(density, 0.0, 1.0))
	_cloud_shader_mat.set_shader_parameter("noise_scale",   shape["scale"])
	_cloud_shader_mat.set_shader_parameter("softness",      shape["soft"])
	_cloud_shader_mat.set_shader_parameter("warp_str",      shape["warp"])
	_cloud_shader_mat.set_shader_parameter("stretch_ratio", shape["stretch"])
	_cloud_shader_mat.set_shader_parameter("cloud_base",    shape["base"])
	_cloud_shader_mat.set_shader_parameter("brightness",    sky_brightness_safe)

	# 태양 방향·색상 → 실버 라이닝 및 바닥 음영 연산
	_cloud_shader_mat.set_shader_parameter("sun_dir",   _altaz_to_dir(sun_altaz.x, sun_altaz.y))
	_cloud_shader_mat.set_shader_parameter("sun_color", _sun_light.light_color)

	# 바람 방향 벡터 — 드리프트(이동) + stretch_dir(이방성) 동시 적용
	var wind_amt: float = wind_speed if wind_enabled else 0.0
	var wind_rad: float = deg_to_rad(wind_direction)
	var wind_vec: Vector2 = Vector2(sin(wind_rad), cos(wind_rad))
	_cloud_shader_mat.set_shader_parameter("stretch_dir", wind_vec)
	var drift_raw = _cloud_shader_mat.get_shader_parameter("drift")
	var drift: Vector2 = drift_raw if drift_raw != null else Vector2.ZERO
	drift += wind_vec * wind_amt * delta * 0.003
	_cloud_shader_mat.set_shader_parameter("drift", drift)

# ── 번개 볼트 형상 ───────────────────────────────────────────────────
func _build_bolt() -> void:
	_bolt_mesh = ImmediateMesh.new()
	_bolt_inst = MeshInstance3D.new()
	_bolt_inst.mesh = _bolt_mesh
	_bolt_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bolt_shader := Shader.new()
	bolt_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float bolt_alpha : hint_range(0.0, 1.0) = 0.0;
void fragment() {
\tALBEDO = vec3(0.72, 0.85, 1.0);
\tALPHA  = bolt_alpha;
}
"""
	_bolt_mat = ShaderMaterial.new()
	_bolt_mat.shader = bolt_shader
	_bolt_mat.set_shader_parameter("bolt_alpha", 0.0)
	_bolt_inst.material_override = _bolt_mat
	_bolt_inst.visible = false
	add_child(_bolt_inst)

# 재귀 중점 변위 — [Vector3, Vector3] 쌍 배열 반환
static func _gen_bolt_segs(from: Vector3, to: Vector3, roughness: float, depth: int) -> Array:
	if depth <= 0:
		return [[from, to]]
	var d: float       = from.distance_to(to)
	var along: Vector3 = (to - from).normalized()
	# along이 거의 수직(Y축)이면 X를 레퍼런스로, 아니면 Y를 레퍼런스로
	var up_ref: Vector3 = Vector3(1.0, 0.0, 0.0) if abs(along.y) >= 0.9 else Vector3(0.0, 1.0, 0.0)
	var perp1: Vector3  = along.cross(up_ref).normalized()
	var perp2: Vector3  = along.cross(perp1).normalized()
	var mid: Vector3    = (from + to) * 0.5
	mid += perp1 * randf_range(-1.0, 1.0) * d * roughness
	mid += perp2 * randf_range(-1.0, 1.0) * d * roughness * 0.5
	var segs: Array = []
	segs.append_array(_gen_bolt_segs(from, mid, roughness * 0.65, depth - 1))
	segs.append_array(_gen_bolt_segs(mid,  to,  roughness * 0.65, depth - 1))
	return segs

func _regen_bolt(dist_km: float) -> void:
	var az_rad: float    = deg_to_rad(_bolt_az)
	var horiz: Vector3   = Vector3(sin(az_rad), 0.0, cos(az_rad))
	# dist_km 0.3→10.5m, 6.0→180m (씬 스케일)
	var bolt_dist: float = clampf(dist_km * 35.0, 25.0, 180.0)
	# 비구름 고도 기준 — 씬 카메라 y≈1.5m, 구름 y≈22m, 시각적 top y=65m
	var top:    Vector3  = horiz * bolt_dist * 0.55 + Vector3(0.0, 65.0, 0.0)
	var bottom: Vector3  = horiz * bolt_dist         + Vector3(0.0, 0.5,  0.0)
	# 주 채널: depth=5 → 최대 32 세그먼트
	_bolt_segs = _gen_bolt_segs(top, bottom, 0.35, 5)
	# 주 채널 세그먼트 ~30%에서 짧은 가지 생성
	var branch_segs: Array = []
	for seg in _bolt_segs:
		if randf() < 0.30:
			var sf: Vector3    = seg[0]
			var st: Vector3    = seg[1]
			var bstart: Vector3 = lerp(sf, st, randf_range(0.2, 0.8))
			var mdir: Vector3  = (st - sf).normalized()
			var up2: Vector3   = Vector3(1.0, 0.0, 0.0) if abs(mdir.y) >= 0.9 else Vector3(0.0, 1.0, 0.0)
			var perp: Vector3  = mdir.cross(up2).normalized()
			# 가지는 주 방향에서 옆으로 벌어지며 약간 아래쪽으로 뻗음
			var bdir: Vector3  = (mdir + perp * randf_range(-1.2, 1.2) + Vector3(0.0, -0.4, 0.0)).normalized()
			var bend: Vector3  = bstart + bdir * randf_range(5.0, 18.0)
			branch_segs.append_array(_gen_bolt_segs(bstart, bend, 0.45, 3))
	_bolt_segs.append_array(branch_segs)

func _draw_bolt() -> void:
	_bolt_mesh.clear_surfaces()
	_bolt_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for seg in _bolt_segs:
		_bolt_mesh.surface_add_vertex(seg[0])
		_bolt_mesh.surface_add_vertex(seg[1])
	_bolt_mesh.surface_end()

func _update_bolt(lightning_flash: float, dist_km: float) -> void:
	if lightning_flash > 0.01:
		if _prev_lightning <= 0.01:
			# 상승 엣지 — 새 섬광마다 볼트 형상 재생성, 방위각 랜덤화
			_bolt_az = randf_range(0.0, 360.0)
			_regen_bolt(dist_km)
			_draw_bolt()
		_bolt_inst.visible = true
		_bolt_mat.set_shader_parameter("bolt_alpha", clampf(lightning_flash * 0.85, 0.0, 0.85))
	else:
		_bolt_inst.visible = false
	_prev_lightning = lightning_flash

# ── 수학 헬퍼 (static) ───────────────────────────────────────────────
static func _altaz_to_dir(alt_deg: float, az_deg: float) -> Vector3:
	var elev := deg_to_rad(alt_deg)
	var az   := deg_to_rad(az_deg)
	return Vector3(sin(az) * cos(elev), sin(elev), cos(az) * cos(elev))

static func _lerp_breakpoints(x: float, xs: Array, ys: Array) -> float:
	if x <= xs[0]: return ys[0]
	for i in range(xs.size() - 1):
		if x <= xs[i + 1]:
			var f: float = (x - xs[i]) / (xs[i + 1] - xs[i])
			return lerp(ys[i], ys[i + 1], f)
	return ys[ys.size() - 1]

static func _sun_illuminance(alt_deg: float) -> float:
	var anchors_alt := [-18.0, -12.0, -6.0, 0.0, 10.0, 30.0, 60.0, 90.0]
	var anchors_lux := [0.0008, 0.008, 3.4, 400.0, 12000.0, 50000.0, 90000.0, 100000.0]
	var a: float = clampf(alt_deg, -18.0, 90.0)
	for i in range(anchors_alt.size() - 1):
		if a <= anchors_alt[i + 1] or i == anchors_alt.size() - 2:
			var t0: float = anchors_alt[i]; var t1: float = anchors_alt[i + 1]
			var f: float = 0.0
			if t1 > t0: f = clampf((a - t0) / (t1 - t0), 0.0, 1.0)
			var l0: float = log(anchors_lux[i]) / log(10.0)
			var l1: float = log(anchors_lux[i + 1]) / log(10.0)
			return pow(10.0, lerp(l0, l1, f))
	return anchors_lux[anchors_lux.size() - 1]

static func _exposure_for_lux(total_lux: float) -> float:
	var anchors_lux := [STARLIGHT_FLOOR_LUX, 0.01, 0.1, 1.0, 3.4, 12.0, 40.0, 120.0, 400.0, 3000.0, 12000.0, 100000.0]
	var anchors_ev  := [19.5, 18.5, 17.2, 15.0, 12.5, 10.0, 8.0, 5.5, 3.5, 1.8, 0.6, 0.0]
	var lux: float     = max(total_lux, STARLIGHT_FLOOR_LUX)
	var log_lux: float = log(lux) / log(10.0)
	for i in range(anchors_lux.size() - 1):
		var l0: float = log(anchors_lux[i]) / log(10.0)
		var l1: float = log(anchors_lux[i + 1]) / log(10.0)
		if log_lux <= l1 or i == anchors_lux.size() - 2:
			var f: float = 0.0
			if l1 > l0: f = clampf((log_lux - l0) / (l1 - l0), 0.0, 1.0)
			return lerp(anchors_ev[i], anchors_ev[i + 1], f)
	return anchors_ev[anchors_ev.size() - 1]
