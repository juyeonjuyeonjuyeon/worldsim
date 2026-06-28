class_name WorldSimSky
extends Node

const STARLIGHT_FLOOR_LUX: float = 0.0008

# 유성우 — [피크 월, 피크 일, 복사점 RA°, 복사점 Dec°, 피크 ZHR, 활동 반폭(일)]
const SHOWERS: Array = [
	[1,  3, 230.1,  49.0, 120, 2],   # 사분의자리   Quadrantids
	[4, 22, 271.4,  33.6,  18, 3],   # 거문고자리   Lyrids
	[5,  6, 338.0,  -1.0,  50, 5],   # 물병자리η    Eta Aquariids
	[7, 29, 339.0,  -5.0,  20, 4],   # 물병자리δ    Delta Aquariids
	[8, 12,  46.4,  58.3, 100, 6],   # 페르세우스자리★ Perseids
	[10,21,  95.0,  15.8,  20, 5],   # 오리온자리   Orionids
	[11,17, 152.3,  21.6,  15, 3],   # 사자자리     Leonids
	[12,14, 112.3,  32.5, 120, 4],   # 쌍둥이자리 ★ Geminids
	[12,22, 102.6,  82.0,  10, 3],   # 작은곰자리   Ursids
]
# 혜성 RA/Dec 키프레임 — [[yr,mo,day,RA°,Dec°,mag], ...]
# 가시 기간(최초~최후 키프레임) + 등급 ≤ 5.5 일 때만 표시
const COMETS: Array = [
	["Hale-Bopp", [
		[1997, 1,  1, 334.0, -1.0, 3.0],
		[1997, 3,  1,   3.8, 35.0, 1.0],
		[1997, 4,  1,  37.5, 56.0, 0.0],
		[1997, 5,  1,  60.0, 64.0, 1.5],
		[1997, 7,  1,  82.5, 62.0, 3.5],
	]],
	["Neowise", [
		[2020, 7,  5,  80.0, 33.0, 0.0],
		[2020, 7, 14,  70.5, 36.0, 1.5],
		[2020, 7, 22,  63.0, 44.0, 2.5],
		[2020, 8,  1,  58.0, 51.0, 3.5],
		[2020, 8, 10,  55.0, 56.0, 5.0],
	]],
]

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
	# 남십자성 (Crux, Southern Cross) ★ — 적위 -57°~-63°, 남위 25°N 이남에서 관측
	# α Cru(Acrux)↔γ Cru(Gacrux) 세로축, β Cru(Mimosa)↔δ Cru 가로축
	[187.791,-57.113,186.650,-63.099],   # γ Cru → α Cru (세로)
	[191.930,-59.689,183.786,-58.749],   # β Cru → δ Cru (가로)
	# 켄타우루스 (Centaurus) — 포인터 별 α·β Cen 이 남십자성을 가리킴
	[219.919,-60.835,210.956,-60.373],   # α Cen → β Cen (포인터 선분)
	[210.956,-60.373,204.972,-53.466],   # β Cen → ε Cen
	[204.972,-53.466,190.379,-48.960],   # ε Cen → γ Cen
	[204.972,-53.466,218.877,-42.158],   # ε Cen → η Cen
	[218.877,-42.158,219.919,-60.835],   # η Cen → α Cen
	# 용골자리 (Carina) — 남쪽 하늘의 밝은 별 카노푸스(α Car) 포함
	[95.988,-52.696,125.629,-59.509],    # α Car(Canopus) → ε Car(Avior)
	[125.629,-59.509,139.274,-59.275],   # ε Car → ι Car
	[139.274,-59.275,138.301,-69.717],   # ι Car → β Car(Miaplacidus)
	# 에리다누스 남부 (Eridanus south) — 포말하우트 근처까지 이어지는 긴 강
	[24.429,-57.237,29.692,-61.400],     # α Eri(Achernar) → β Eri
]

# 외부에서 읽는 출력값
var sky_brightness_safe: float     = 1.0
var sky_overcast_amt_current: float = 0.0
var cloud_tau_current: float        = 0.0
var _cloud_tau_smooth: float        = 0.0   # 날씨 전환 때 tau를 부드럽게 보간 (τ≈3s)

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
var _rainbow_mesh: MeshInstance3D
var _rainbow_mat: ShaderMaterial
var _rainbow_intensity: float = 0.0
var _rainbow_force: bool = false   # true면 기상 조건 무관하게 강제 표시
var _rain_rate_ema: float = 0.0   # 최근 강수 이력 EMA (τ≈30s) — 무지개 조건용
var _fog_density_cur: float   = 0.0
var _bolt_mesh: ImmediateMesh          # 번개 볼트 선분
var _bolt_inst: MeshInstance3D
var _bolt_mat:  ShaderMaterial
var _bolt_segs: Array      = []        # [[Vector3, Vector3], ...] 세그먼트 목록
var _prev_lightning: float = 0.0      # 섬광 상승 엣지 감지용
var _bolt_az: float        = 0.0      # 현재 볼트 방위각 (도)
var _meteor_mesh: ImmediateMesh        # 별똥별 궤적 선분
var _meteor_inst: MeshInstance3D
var _meteor_next: float    = 30.0     # 다음 유성 대기 시간 (초)
var _meteor_t:    float    = -1.0     # 현재 유성 진행도 (-1=비활성)
var _meteor_dur:  float    = 0.3      # 현재 유성 지속시간
var _meteor_head: Vector3  = Vector3.ZERO
var _meteor_dir:  Vector3  = Vector3.DOWN
var _meteor_len:  float    = 20.0     # 꼬리 최대 길이 (sky dome 단위)
var _meteor_color: Color   = Color.WHITE
var _shower_intensity: float  = 0.0        # 현재 유성우 강도 (0=없음, 1=피크)
var _shower_radiant:  Vector3 = Vector3.UP # 복사점 방향 (단위 벡터)
var _comet_test_mode: bool    = false      # 테스트 버튼으로 혜성 강제 표시
var _comet_nuc_inst:  MeshInstance3D       # 혜성 핵
var _comet_nuc_mat:   ShaderMaterial
var _comet_ion_mesh:  ImmediateMesh        # 이온 꼬리 (청백, 직선)
var _comet_ion_inst:  MeshInstance3D
var _comet_dust_mesh: ImmediateMesh        # 먼지 꼬리 (황백, 넓고 약간 굽음)
var _comet_dust_inst: MeshInstance3D
var _star_data: Array = []
var _current_exposure: float = 1.0  # 노출 스무딩 상태 (프레임 간 급격한 변화 방지)
var _eye_view: bool = true           # 사람눈/카메라 모드 — update()에서 매 프레임 수신

# ── 빌드 ─────────────────────────────────────────────────────────────
func build() -> void:
	_load_star_catalog()
	_build_sky_and_lights()
	_build_stars()
	_build_planets()
	_build_constellations()
	_build_clouds()
	_build_rainbow()
	_build_bolt()
	_build_meteor()
	_build_comet()

# ── 외부 트리거 (테스트 버튼용) ──────────────────────────────────────
func trigger_meteor(shower_mode: bool = false) -> void:
	if shower_mode:
		_shower_intensity = 0.80
		# 페르세우스자리 복사점 근사 (alt≈58°, az≈46°)
		_shower_radiant   = _altaz_to_dir(58.0, 46.0)
	else:
		_shower_intensity = 0.0
	_spawn_meteor()
	_draw_meteor()
	_meteor_inst.visible = true

func trigger_comet_test() -> void:
	_comet_test_mode = not _comet_test_mode
	if not _comet_test_mode:
		_comet_nuc_inst.visible  = false
		_comet_ion_inst.visible  = false
		_comet_dust_inst.visible = false

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
	# 기본값 30°는 비현실적으로 큰 글로우를 만들고 부분 구름(cirrus/cumulus)이
	# blend_mix로 글로우 일부를 감쇠시켜 검정 후광처럼 보이게 함.
	# 실제 태양 오레올(aureole): 대기 산란으로 약 5-10° 이내에서만 유의미하게 밝음.
	# sun_curve=0.1: 급격한 감쇠로 글로우를 태양 원반(0.53°) 근처에 집중
	_sky_mat.sun_angle_max = 8.0
	_sky_mat.sun_curve     = 0.1
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
	# ProceduralSkyMaterial의 내부 글로우를 사용하지 않음 — 커스텀 sun QuadMesh 셰이더로 대체.
	# 기본값(LIGHT_AND_SKY)이면 ProceduralSky가 태양/달 방향에 8° 글로우를 추가 렌더링해
	# 흐린 날씨에서 구름 blend_mix와 충돌하여 검정색 후광 아티팩트를 유발함.
	_sun_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_sun_light)

	_moon_light = DirectionalLight3D.new()
	_moon_light.light_energy = 0.0
	_moon_light.light_color = Color(0.75, 0.82, 1.0)
	_moon_light.shadow_enabled = false
	# LIGHT_ONLY: 달 방향에도 ProceduralSky 글로우가 생기던 버그 수정.
	# 12월 보름달(서울 고도 76°)에서 8° 글로우 원이 크게 보이던 현상도 함께 해결.
	_moon_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_moon_light)

	_moon_mesh = MeshInstance3D.new()
	var msph := SphereMesh.new()
	msph.radius = 0.46   # 물리 각지름 0.52°: tan(0.26°)×100m = 0.454m → 0.46m
	msph.height = 0.92
	_moon_mesh.mesh = msph
	_moon_shader_mat = ShaderMaterial.new()
	var moon_shader := Shader.new()
	moon_shader.code = """
shader_type spatial;
// blend_add: 어두운 면은 0을 더해 하늘에 흔적 없음, 밝은 면은 빛을 더함
// → blend_mix의 반투명 경계가 낮 하늘보다 어두워 생기던 검은 후광 제거
render_mode unshaded, cull_back, blend_add, depth_draw_never;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 lit_color : source_color = vec3(1.0, 0.98, 0.92);
uniform float brightness : hint_range(0.0, 10.0) = 2.0;
uniform float exposure_safe : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_fade    : hint_range(0.0, 1.0) = 1.0;
uniform float horizon_fade  : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_normal;
varying float v_world_dir_y;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz);
	vec4 vert_view = VIEW_MATRIX * MODEL_MATRIX * vec4(VERTEX, 1.0);
	POSITION = PROJECTION_MATRIX * vert_view;
	// 수평선 클립 기준: 이 버텍스의 월드 방향 Y 성분 (0=수평선, +위, -아래)
	v_world_dir_y = (INV_VIEW_MATRIX * vec4(normalize(vert_view.xyz), 0.0)).y;
}

void fragment() {
	float ndotl = dot(normalize(world_normal), normalize(sun_dir));
	float lit = smoothstep(-0.08, 0.08, ndotl);
	vec3 bright_col = lit_color * brightness * exposure_safe;
	// 구름을 통과할수록 달빛이 파랗고 희게 산란됨
	vec3 cloud_white = vec3(0.78, 0.82, 0.98) * exposure_safe;
	bright_col = mix(bright_col, cloud_white, (1.0 - cloud_fade) * 0.8);
	ALBEDO = bright_col;
	// 수평선 클립: 카메라 기준 실제 지평선에서 달을 자름 (±0.005 ≈ ±0.29° 전환)
	float ground_fade = smoothstep(-0.005, 0.005, v_world_dir_y);
	ALPHA  = lit * cloud_fade * horizon_fade * ground_fade;
}
"""
	_moon_shader_mat.shader = moon_shader
	_moon_shader_mat.set_shader_parameter("sun_dir",      Vector3(0, 1, 0))
	_moon_shader_mat.set_shader_parameter("horizon_fade", 1.0)
	_moon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_moon_mesh.material_override = _moon_shader_mat
	add_child(_moon_mesh)

	# 태양 원반 — 뷰 공간 빌보드 쿼드, 거리 100m
	# 물리 각지름 0.53° (= 반경 0.265°). 100m 거리에서 tan(0.265°)×100 = 0.463m
	# 9m quad half=4.5m → disc UV d = 0.463/4.5 = 0.103
	# quad는 크게 유지해 glare_scale이 큰 광환을 표현할 여유 확보
	_sun_mesh = MeshInstance3D.new()
	var sun_quad := QuadMesh.new()
	sun_quad.size = Vector2(9.0, 9.0)
	_sun_mesh.mesh = sun_quad
	var sun_shader := Shader.new()
	sun_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec3  sun_color    : source_color = vec3(1.0, 0.95, 0.80);
uniform vec3  haze_color   : source_color = vec3(1.0, 0.38, 0.05);
uniform float cloud_fade    : hint_range(0.0, 1.0)   = 1.0;
uniform float horizon_fade  : hint_range(0.0, 1.0)   = 1.0;
// 사람눈 모드: 1.5 (크고 부드러운 광환), 카메라 모드: 0.8 (좁은 렌즈 블룸)
uniform float glare_scale   : hint_range(0.5, 2.0)   = 1.0;

varying float v_world_dir_y;

void vertex() {
	vec4 center_view = VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 vert_view = center_view + vec4(VERTEX.xy, 0.0, 0.0);
	POSITION = PROJECTION_MATRIX * vert_view;
	// 수평선 클립 기준: 이 버텍스의 월드 방향 Y 성분 (0=수평선, +위, -아래)
	v_world_dir_y = (INV_VIEW_MATRIX * vec4(normalize(vert_view.xyz), 0.0)).y;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;

	// 원반: 물리 각지름 0.53° = d=0.103 in 9m quad
	float disc = 1.0 - smoothstep(0.103, 0.115, d);

	// 방사형 마스크: d≥1.0에서 완전 0 → 사각 경계 제거
	float rmask = 1.0 - smoothstep(0.86, 1.0, d);

	// 글로우: glare_scale이 광환 범위·밝기 결정
	float core = exp(-max(0.0, d - 0.10) * (7.0 / glare_scale)) * (1.5 * glare_scale);
	float halo = exp(-d * (1.3 / glare_scale)) * (0.55 * glare_scale);
	float glow = (core + halo) * rmask;

	// 지평선 클립: 카메라 기준 실제 수평선에서 자름
	// ±0.005 ≈ ±0.29° 전환 대역 (디스크 반경 0.265°보다 약간 넓어 앤티앨리어싱)
	float ground_fade = smoothstep(-0.005, 0.005, v_world_dir_y);

	// 대기 헤이즈: 지평선 근처에서 outer glow를 따뜻한 주황으로 블렌딩
	float haze_t     = clamp((1.0 - horizon_fade) * 1.5, 0.0, 1.0);
	float outer_frac = clamp((d - 0.10) * 3.0, 0.0, 1.0);
	ALBEDO = mix(sun_color, haze_color, outer_frac * haze_t);

	// horizon_fade: 고도 −3°→+1° smoothstep (대기 감쇠 / haze_t 연동)
	// ground_fade: 카메라 수평선 기준 지평면 절단
	ALPHA = clamp((disc + glow) * cloud_fade * horizon_fade * ground_fade, 0.0, 1.0);
}
"""
	_sun_shader_mat = ShaderMaterial.new()
	_sun_shader_mat.shader = sun_shader
	_sun_shader_mat.set_shader_parameter("sun_color",    Vector3(1.0, 0.95, 0.80))
	_sun_shader_mat.set_shader_parameter("haze_color",   Vector3(1.0, 0.38, 0.05))
	_sun_shader_mat.set_shader_parameter("cloud_fade",    1.0)
	_sun_shader_mat.set_shader_parameter("horizon_fade", 1.0)
	_sun_shader_mat.set_shader_parameter("glare_scale",  1.5)
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
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
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
	// 밤에는 brightness가 거의 0이므로 ALPHA도 함께 줄여 구름 노이즈 패턴이 남지 않도록 함
	// edge0=0.07 > sky_brightness_safe_min(0.0625=1/16) 이므로 야간엔 ALPHA가 정확히 0
	ALPHA  = a * smoothstep(0.07, 0.5, brightness);
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

func force_rainbow(enabled: bool) -> void:
	_rainbow_force = enabled

func _build_rainbow() -> void:
	_rainbow_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 450.0
	sphere.height = 900.0
	sphere.rings  = 48
	sphere.radial_segments = 96
	_rainbow_mesh.mesh = sphere
	_rainbow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rainbow_mesh.visible = false
	var rshader := Shader.new()
	rshader.code = """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_front, unshaded;
uniform vec3  sun_dir            = vec3(0.0, 1.0, 0.0);
uniform float intensity          : hint_range(0.0, 1.0) = 0.0;
// 부무지개 강도 (0=없음, 0.10=최대). 굵은 물방울+강한 햇빛에서만 열림.
uniform float secondary_strength : hint_range(0.0, 0.15) = 0.0;
varying vec3 vert_os;

vec3 hue_to_rgb(float h) {
	h = fract(h);
	float r = abs(h * 6.0 - 3.0) - 1.0;
	float g = 2.0 - abs(h * 6.0 - 2.0);
	float b = 2.0 - abs(h * 6.0 - 4.0);
	return clamp(vec3(r, g, b), 0.0, 1.0);
}

void vertex() { vert_os = VERTEX; }

void fragment() {
	vec3 antisolar = normalize(-sun_dir);
	vec3 view_dir  = normalize(vert_os);
	float ang = degrees(acos(clamp(dot(view_dir, antisolar), -1.0, 1.0)));

	// 지평선 아래(view_dir.y<0)로 갈수록 빠르게 소멸
	float horizon_fade = clamp(view_dir.y * 12.0 + 0.5, 0.0, 1.0);

	// 1차(주) 무지개: 40.6°~42.5° (보라→빨강)
	float band1 = smoothstep(40.2, 40.6, ang) * smoothstep(42.9, 42.5, ang);
	float hue1  = clamp((ang - 40.6) / (42.5 - 40.6), 0.0, 1.0);
	vec3  col1  = hue_to_rgb(0.75 - hue1 * 0.75) * band1;

	// 알렉산더의 암대(42.5°~50.4°): blend_add 한계로 직접 어둡게는 불가.
	// 두 호 사이에 빛이 추가되지 않아 상대적으로 어두운 띠가 자연스럽게 형성됨.

	// 2차(부) 무지개: 50.4°~53.4° (빨강→보라, 색 순서 반대)
	// secondary_strength로 제어 (기본 0, 최대 0.10 = 주무지개의 10%)
	float band2 = smoothstep(50.0, 50.4, ang) * smoothstep(53.8, 53.4, ang);
	float hue2  = clamp((ang - 50.4) / (53.4 - 50.4), 0.0, 1.0);
	vec3  col2  = hue_to_rgb(hue2 * 0.75) * band2 * secondary_strength;

	vec3 col = col1 + col2;
	float arc_alpha = clamp((band1 + band2 * secondary_strength) * horizon_fade * 2.0, 0.0, 0.55);
	ALBEDO = col * intensity;
	ALPHA  = arc_alpha * intensity;
}
"""
	_rainbow_mat = ShaderMaterial.new()
	_rainbow_mat.shader = rshader
	_rainbow_mat.set_shader_parameter("sun_dir",            Vector3(0.0, 1.0, 0.0))
	_rainbow_mat.set_shader_parameter("intensity",          0.0)
	_rainbow_mat.set_shader_parameter("secondary_strength", 0.0)
	_rainbow_mesh.material_override = _rainbow_mat
	add_child(_rainbow_mesh)

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
	temperature: float,
	ground_wetness: float,
	delta: float,
	eye_view: bool = true
) -> void:
	_eye_view = eye_view
	_update_sky_and_lights(sun_altaz, moon, cloud_props, lightning_flash, delta)
	_update_stars(dt, hour_utc, latitude, longitude, cloud_props)
	_update_planets(dt, hour_utc, latitude, longitude, cloud_props)
	_update_constellations(dt, hour_utc, latitude, longitude, cloud_props)
	_update_bolt(lightning_flash, lightning_bolt_dist_km)
	_update_meteor(sun_altaz, cloud_props, dt, hour_utc, latitude, longitude, delta)
	_update_comet(sun_altaz, dt, hour_utc, latitude, longitude)
	_update_cloud_visual(cloud_props, weather_type, wind_speed, wind_direction, wind_enabled, sun_altaz, delta)
	_update_rainbow(sun_altaz, cloud_props, ground_wetness, delta)
	_update_fog(weather_type, cloud_props.get("rain_rate", 0.0), temperature, wind_speed, cloud_props, dt["hour"], delta)

func _update_rainbow(sun_altaz: Vector2, cloud_props: Dictionary, ground_wetness: float, delta: float) -> void:
	var sky_cam: Camera3D = get_viewport().get_camera_3d()
	var cam_origin: Vector3 = sky_cam.global_position if is_instance_valid(sky_cam) else Vector3.ZERO
	_rainbow_mesh.global_position = cam_origin

	var sun_dir: Vector3 = _altaz_to_dir(sun_altaz.x, sun_altaz.y)
	_rainbow_mat.set_shader_parameter("sun_dir", sun_dir)

	var rain_rate_cur: float = cloud_props.get("rain_rate", 0.0)

	# 최근 강수 이력 EMA (τ≈30s): 비 그쳐도 30초간 높은 값 유지 → "방금 비가 왔음" 신호
	_rain_rate_ema = lerpf(_rain_rate_ema, rain_rate_cur, delta / 30.0)

	# ── 태양 고도 조건: 1°~42° ───────────────────────────────────────────
	# 42° 이상이면 무지개 호 전체가 지평선 아래로 내려가 보이지 않음
	var sun_elev: float = sun_altaz.x
	var elev_factor: float = 0.0
	if sun_elev >= 1.0 and sun_elev <= 42.0:
		elev_factor = smoothstep(1.0, 8.0, sun_elev) * smoothstep(42.0, 34.0, sun_elev)

	# ── 공중 물방울 지수 ─────────────────────────────────────────────────
	# prev_droplet: 직전에 비가 왔어야 공기 중에 물방울이 존재함
	var prev_droplet: float = clampf(_rain_rate_ema / 3.0, 0.0, 1.0)
	# rain_suppress: 현재 폭우(>3mm/hr)면 빗방울이 빛을 소광 → 무지개 억제
	var rain_suppress: float = clampf(1.0 - rain_rate_cur / 3.0, 0.0, 1.0)
	# ground_wetness는 잔류 습도 가중치 (0.3 기저 + 0.7 가중)
	var droplet_air: float = prev_droplet * rain_suppress * (0.3 + 0.7 * ground_wetness)

	# ── 태양 가시도 ──────────────────────────────────────────────────────
	var sun_vis: float = clampf(1.0 - sky_overcast_amt_current * 0.85, 0.0, 1.0)

	var target: float = clampf(elev_factor * droplet_air * sun_vis, 0.0, 1.0)
	if _rainbow_force:
		target = 1.0  # 강제 표시: 기상·태양 조건 무시

	# ── 부무지개: 최근 강수가 강했을 때(굵은 물방울)만 흐릿하게 출현 ──────
	# EMA 기준 5mm/hr 이상 강수 이력이 있어야 2차 반사 확인 가능한 굵은 물방울
	# 최대 0.10 → 주무지개의 10% 밝기 (실제 부무지개 ≈ 5~10%)
	var sec_eligibility: float = clampf((_rain_rate_ema - 5.0) / 15.0, 0.0, 1.0)
	_rainbow_mat.set_shader_parameter("secondary_strength", sec_eligibility * target * 0.10)

	# 출현 속도 낮춤(0.5→0.15): 서서히 뜨게. 소멸은 천천히(0.08) 유지.
	var spd: float = 0.15 if target > _rainbow_intensity else 0.08
	_rainbow_intensity = lerpf(_rainbow_intensity, target, delta * spd)
	_rainbow_mat.set_shader_parameter("intensity", _rainbow_intensity)
	_rainbow_mesh.visible = _rainbow_intensity > 0.005

func _update_fog(weather_type: String, rain_rate: float, temperature: float, wind_speed: float, cloud_props: Dictionary, hour_local: float, delta: float) -> void:
	var env: Environment = _world_env.environment
	var target_density: float = 0.0
	match weather_type:
		"RAIN":
			var frac: float = clampf(rain_rate / 50.0, 0.0, 1.0)
			target_density = lerp(0.002, 0.012, frac)
		"SNOW":
			var frac: float = clampf(rain_rate / 30.0, 0.0, 1.0)
			# 눈보라 조건 — Environment._classify_snow 와 동일 기준
			if wind_speed > 8.0 and temperature < -3.0:
				target_density = 0.025
			else:
				target_density = lerp(0.003, 0.015, frac)
		"OVERCAST":
			target_density = 0.001
		_:
			# 복사안개: 맑은 밤~이른 아침(22:00~10:00), 기온 -2~15°C
			# 실제로는 여름(5~15°C)에도 자주 발생하며, 낮에는 태양열로 소산됨
			var rad_hour: bool = hour_local >= 22.0 or hour_local < 10.0
			if cloud_props["okta"] < 0.3 and temperature > -2.0 and temperature < 15.0 and rad_hour:
				# 기온이 낮을수록 이슬점에 근접 → 더 진한 안개
				var t_factor: float = clampf(1.0 - (temperature - (-2.0)) / 17.0, 0.2, 1.0)
				target_density = lerp(0.002, 0.008, t_factor)
	# target=0(맑아지는 중)이면 1.5배속으로 빠르게 소멸
	var fog_spd: float = 0.3 if target_density > _fog_density_cur else (1.5 if target_density < 0.0001 else 0.1)
	_fog_density_cur = lerpf(_fog_density_cur, target_density, delta * fog_spd)
	var has_fog: bool = _fog_density_cur > 0.001   # 0.0001→0.001: 잔여 안개 조기 컷오프
	env.fog_enabled = has_fog
	if has_fog:
		env.fog_density = _fog_density_cur
		# 안개 색 기준: sky_horizon_color (밤/낮 tonemap에 맞게 이미 스케일됨)
		var h: Color = _sky_mat.sky_horizon_color
		match weather_type:
			"RAIN":  env.fog_light_color = Color(h.r * 0.88, h.g * 0.92, h.b * 1.12)
			"SNOW":  env.fog_light_color = Color(h.r * 1.10, h.g * 1.10, h.b * 1.08)
			_:
				# 비→맑음 전환 중 잔여 안개: sky_horizon이 갑자기 밝아져도
				# 밀도에 비례해 색을 어둡게 유지 → tonemap 증폭 후 큰 광원 방지
				var dim: float = clampf(_fog_density_cur / 0.015, 0.0, 1.0)
				env.fog_light_color = Color(h.r * dim, h.g * dim, h.b * dim)
		env.fog_sun_scatter = 0.25

func _update_sky_and_lights(sun_altaz: Vector2, moon: Dictionary, cloud_props: Dictionary, lightning_flash: float, delta: float) -> void:
	var elevation: float = sun_altaz.x
	var azimuth: float   = sun_altaz.y
	var sun_dir: Vector3 = _altaz_to_dir(elevation, azimuth)
	_sun_light.global_transform = Transform3D(Basis.looking_at(-sun_dir, Vector3.UP), Vector3.ZERO)

	# 카메라 위치 — 태양/달 메시를 카메라 기준으로 배치하여 ProceduralSky glow와 정렬
	var sky_cam: Camera3D = get_viewport().get_camera_3d()
	var cam_origin: Vector3 = sky_cam.global_position if is_instance_valid(sky_cam) else Vector3.ZERO

	var moon_alt: float   = moon["alt"]
	var moon_az: float    = moon["az"]
	var moon_illum: float = moon["illum"]
	var moon_dir: Vector3 = _altaz_to_dir(moon_alt, moon_az)
	_moon_light.global_transform = Transform3D(Basis.looking_at(-moon_dir, Vector3.UP), Vector3.ZERO)
	_moon_mesh.global_position = cam_origin + moon_dir * 100.0
	# 달 지평선 페이드: −3°→+1° smoothstep, 위치 계산은 그대로, 가시성만 조절
	var moon_horizon_fade: float = smoothstep(-3.0, 1.0, moon_alt)
	_moon_mesh.visible = moon_alt > -3.5
	_moon_shader_mat.set_shader_parameter("horizon_fade", moon_horizon_fade)
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

	_sun_mesh.global_position = cam_origin + sun_dir * 100.0
	# 태양 지평선 페이드: −3°→+1° smoothstep, 위치 계산은 그대로, 가시성만 조절
	var sun_horizon_fade: float = smoothstep(-3.0, 1.0, elevation)
	_sun_mesh.visible = elevation > -3.5
	_sun_shader_mat.set_shader_parameter("horizon_fade",  sun_horizon_fade)

	# 태양 색온도: 0°→주황(~3000K), 28°+→흰색(~5800K). 25–30°에서 황백색이 됨(실측).
	var warm: float        = clampf(1.0 - elevation / 28.0, 0.0, 1.0)
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
		# 반대현상(opposition effect) + 위상 비선형성:
		# pow(2.5) → 반달=0.048 lux(실제 0.02–0.05), 초승(25%)=0.008 lux(실제 0.005–0.01)
		moon_lux = 0.27 * pow(moon_illum, 2.5) * sin(deg_to_rad(moon_alt))
	var total_lux: float = sun_lux + moon_lux + STARLIGHT_FLOOR_LUX

	var exposure_ev: float = _exposure_for_lux(total_lux)
	if lightning_flash > 0.01:
		exposure_ev = lerp(exposure_ev, 0.0, lightning_flash)
	# FP16 HDR 버퍼 최솟값(6e-5) 대비 tonemap 보정 상한 = 2^4 = 16×
	# 이 이상은 FP16 양자화 오차가 증폭되어 분홍/초록 노이즈로 나타남
	const EV_MAX: float = 4.0
	var target_exp: float = clampf(pow(2.0, exposure_ev), 0.5, pow(2.0, EV_MAX))
	# 자동진행 중 부드러운 스무딩 (급격한 낮↔밤 밝기 점프 완화)
	# delta=0 시 가중치=0 → _current_exposure 유지 (자정 교차·설정 변경 시 점프 없음)
	_current_exposure = lerp(_current_exposure, target_exp, clampf(delta * 2.0, 0.0, 1.0))
	var exposure_mult: float = _current_exposure
	_sun_light.light_energy  = min(clampf(sun_lux / 100000.0 * 3.0, 0.0, 6.0), 6.0 / exposure_mult)
	# 달 에너지: 위상에 정확히 비례 (이중 min 제거 — 보름달 vs 반달 밝기 구분)
	# 지평선 근처(8° 미만)이거나 위상 40% 미만이면 그림자 비활성
	_moon_light.light_energy = clampf(moon_lux / 0.27 * 0.6, 0.0, 0.6) / exposure_mult * exp(-(cloud_props["tau"] as float))
	# 달그림자: 고도 12°+ (실제 선명한 달 그림자 관측 가능 최소 고도), 위상 40%+ (상현 이후)
	_moon_light.shadow_enabled = moon_alt > 12.0 and moon_illum > 0.40

	sky_brightness_safe = min(1.0, 1.0 / exposure_mult)
	_moon_shader_mat.set_shader_parameter("exposure_safe", sky_brightness_safe)

	# sky_night_blend: 구름 overcast 블렌딩 용도로만 유지 (−6° → −18° = 0→1)
	var sky_night_blend: float = clampf((-elevation - 6.0) / 12.0, 0.0, 1.0)

	# ── 사람눈/카메라 모드 분기 ───────────────────────────────────────────
	var scotopic_boost: float = 4.0 if _eye_view else 1.0
	_sun_shader_mat.set_shader_parameter("glare_scale", 1.5 if _eye_view else 0.8)

	# ── 밤하늘 기본색 (moon_sky_factor: 보름달=2.5×) ─────────────────────
	# ProceduralSkyMaterial은 tonemap_exposure 보정을 받지 않음 → brt 제거, 표시값 직접 지정
	# * 16.0: 표시용 밝기 스케일 (brt=1일 때의 기존 값과 동일)
	var moon_sky_factor: float = 1.0 + clampf(moon_lux / 0.27, 0.0, 1.0) * 1.5
	var scotopic_r: float = scotopic_boost * (0.80 if _eye_view else 1.0)
	var scotopic_g: float = scotopic_boost * (0.90 if _eye_view else 1.0)
	var scotopic_b: float = scotopic_boost * (1.15 if _eye_view else 1.0)
	var night_top := Color(
		0.00190 * moon_sky_factor * scotopic_r,
		0.00218 * moon_sky_factor * scotopic_g,
		0.00358 * moon_sky_factor * scotopic_b) * 16.0
	var night_horizon := Color(
		0.00080 * moon_sky_factor * scotopic_r,
		0.00085 * moon_sky_factor * scotopic_g,
		0.00140 * moon_sky_factor * scotopic_b) * 16.0

	# ── 하늘 색: Preetham(1999) 대기 산란 모델 + 야간 블렌드 ──────────────
	# Layer A (elevation ≥ −2°): Preetham 분석 모델 — 손으로 색 지정 없음
	# Layer B (elevation < −6°): 기존 야간 고정 색 유지 (night_top / night_horizon)
	# 혼합구간 (−2° ∼ −6°): A → B 선형 보간
	var hw_colors := _preetham_sky_colors(maxf(elevation, 0.0), 3.0)
	var _dtn_t := clampf((-elevation - 2.0) / 4.0, 0.0, 1.0)
	var top    : Color = (hw_colors[0] as Color).lerp(night_top,    _dtn_t)
	var horizon: Color = (hw_colors[1] as Color).lerp(night_horizon, _dtn_t)

	# 날씨 전환 시 tau를 부드럽게 보간 — 점프 없이 흐린날→맑음 or 역방향 전환
	# lerpf weight ≈ delta×0.3: 60fps에서 τ≈3s, 빠른 전환도 끊김 없이 반영
	_cloud_tau_smooth = lerpf(_cloud_tau_smooth, cloud_props["tau"], delta * 0.3)
	var cloud_tau: float = _cloud_tau_smooth
	cloud_tau_current = cloud_tau
	var direct_transmittance: float = exp(-cloud_tau)
	var sky_overcast_amt: float = 1.0 - exp(-cloud_tau / 12.0)
	sky_overcast_amt_current = sky_overcast_amt
	# 달/태양 메시: 구름이 두꺼울수록 점점 흐려지다 사라짐
	var moon_cloud_fade: float = clampf(1.0 - sky_overcast_amt * 1.2, 0.0, 1.0)
	_moon_shader_mat.set_shader_parameter("cloud_fade", moon_cloud_fade)
	# visible: 페이드 구간(−3.5°) 포함, cloud_fade·horizon_fade가 실제 투명도 결정
	_moon_mesh.visible = moon_alt > -3.5 and moon_cloud_fade > 0.01
	# 태양은 얇은 구름에서도 어느 정도 보임 (달보다 밝아서)
	var sun_cloud_fade: float = clampf(1.0 - sky_overcast_amt * 0.85, 0.0, 1.0)
	_sun_shader_mat.set_shader_parameter("cloud_fade", sun_cloud_fade)
	var overcast_grey: Color = Color(0.42, 0.44, 0.47)
	top     = top.lerp(overcast_grey,    sky_overcast_amt * (1.0 - sky_night_blend))
	horizon = horizon.lerp(overcast_grey, sky_overcast_amt * (1.0 - sky_night_blend))
	top.a = 1.0; horizon.a = 1.0
	_sky_mat.sky_top_color      = top
	_sky_mat.sky_horizon_color  = horizon
	_sky_mat.ground_horizon_color = horizon
	var ground_bottom: Color    = Color(0.05, 0.05, 0.05)
	ground_bottom.a = 1.0
	_sky_mat.ground_bottom_color = ground_bottom

	_sun_light.light_energy *= direct_transmittance
	_world_env.environment.tonemap_exposure = exposure_mult

	var sat: float = clampf((log(max(total_lux, 1e-5)) / log(10.0) + 2.0) / (log(400.0) / log(10.0) + 2.0), 0.0, 1.0)
	_world_env.environment.adjustment_enabled = true
	# 박명(0°→-18°): 대기 산란 발광은 망막 적응과 무관하게 채색되어 보임 → 채도 바닥 높게
	# 깊은밤(-18°이하): Purkinje 이동으로 청색 감도 잔류 → 기존 0.10에서 0.28로 상향
	# 낮(elevation>0°): twilight_factor=0 → twi_sat_floor 사용, sat≈1.0이라 floor는 영향 없음
	var twilight_factor: float = clampf(-elevation / 18.0, 0.0, 1.0)
	var twi_sat_floor: float   = 0.65 if _eye_view else 0.72   # 박명: 하늘색 채도 유지
	var night_sat_floor: float = 0.28 if _eye_view else 0.30   # 밤: 청색 잔류 (Purkinje)
	var sat_floor: float = lerp(twi_sat_floor, night_sat_floor, twilight_factor)
	_world_env.environment.adjustment_saturation = lerp(sat_floor, 1.0, sat)

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
	var P: Basis  = Astronomy.precession_matrix(jd)   # J2000→현재 에포크 세차 행렬 (프레임당 1회)
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
		# 분광색 조회는 J2000 좌표 그대로 사용 (테이블이 J2000 기준)
		var sc: Color = _star_spectral_color(star["ra"], star["dec"])
		mm.set_instance_color(i, Color(sc.r, sc.g, sc.b, pogson_b * twilight))
		# 세차 보정 후 고도/방위각 계산
		var pr: Vector2    = Astronomy.precess_radec(star["ra"], star["dec"], P)
		var altaz: Vector2 = Astronomy.radec_to_altaz(pr.x, pr.y, g, latitude, longitude)
		var dir: Vector3   = _altaz_to_dir(altaz.x, altaz.y)
		# 포그손 법칙 기반 로그 크기: 5등급차 = 100배 밝기, 크기는 밝기의 0.18승에 비례
		# 포그손 법칙 기반 시각 크기: 밝기 ∝ 10^(-0.4·mag), 크기 ∝ 밝기^0.5 = 10^(-0.20·mag)
		var scale_: float  = clampf(0.45 * pow(10.0, -0.20 * mag), 0.10, 3.0)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(scale_, scale_, scale_)), dir * radius))

func _update_planets(dt: Dictionary, hour_utc: float, latitude: float, longitude: float, cloud_props: Dictionary) -> void:
	var sun_elev: float  = Astronomy.sun_altaz(dt["year"], dt["month"], dt["day"], hour_utc, latitude, longitude).x
	var cloud_block: float = cloud_props["okta"]
	var psmat: ShaderMaterial = _planet_mm.material_override as ShaderMaterial
	# 금성(-4.5등)은 태양 고도 7°까지 육안 관측 가능, 다른 행성은 3° 이하
	# 금성 특유의 극밝기 때문에 낮에도 보이는 현상 반영
	var venus_visible: bool = sun_elev <= 7.0
	var others_visible: bool = sun_elev <= 3.0
	if not venus_visible and not others_visible:
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
		# 금성은 -4.5등 → 최대 태양 고도 7°까지 가시, 다른 행성은 일반 공식
		var max_sun_elev: float = 7.0 if pname == "venus" else 3.0
		if sun_elev > max_sun_elev:
			mm.set_instance_color(idx, Color(pc.r, pc.g, pc.b, 0.0))
			mm.set_instance_transform(idx, Transform3D(Basis(), Vector3(0.0, -2000.0, 0.0)))
			continue
		var appear_elev: float = lerp(-4.0, -14.0, (mag + 1.5) / 6.5)
		var twilight: float    = clampf((sun_elev - appear_elev - 2.0) / -2.0, 0.0, 1.0)
		var pogson_b: float    = clampf(pow(10.0, -mag * 0.40), 0.0, 1.0)
		mm.set_instance_color(idx, Color(pc.r, pc.g, pc.b, pogson_b * twilight))
		var dir: Vector3   = _altaz_to_dir(ps["alt"], ps["az"])
		# 행성은 각지름이 거의 0 → 점(point)으로 렌더; 최대 0.80m @ 400m = 0.11°
		# 달 디스크(0.52°)보다 훨씬 작게 유지
		var scale_: float  = clampf(0.45 * pow(10.0, -0.20 * mag), 0.10, 0.80)
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
	var P: Basis  = Astronomy.precession_matrix(jd)
	var radius: float = 395.0  # 별(400)보다 살짝 안쪽
	_const_mesh.clear_surfaces()
	_const_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for seg in CONST_SEGS:
		var p1: Vector2 = Astronomy.precess_radec(seg[0], seg[1], P)
		var p2: Vector2 = Astronomy.precess_radec(seg[2], seg[3], P)
		var a1: Vector2 = Astronomy.radec_to_altaz(p1.x, p1.y, g, latitude, longitude)
		var a2: Vector2 = Astronomy.radec_to_altaz(p2.x, p2.y, g, latitude, longitude)
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
	# 무한 누적 방지 — hash2의 fract(i*127.1) 연산이 i가 크면 정밀도를 잃어 노이즈 패턴 붕괴
	drift = Vector2(fmod(drift.x, 512.0), fmod(drift.y, 512.0))
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

# ── 별똥별 ───────────────────────────────────────────────────────────
func _build_meteor() -> void:
	_meteor_mesh = ImmediateMesh.new()
	_meteor_inst = MeshInstance3D.new()
	_meteor_inst.mesh = _meteor_mesh
	_meteor_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
void fragment() {
\tALBEDO = COLOR.rgb;
\tALPHA  = COLOR.a;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = s
	_meteor_inst.material_override = mat
	_meteor_inst.visible = false
	add_child(_meteor_inst)

func _spawn_meteor() -> void:
	var r: float = 395.0
	if _shower_intensity > 0.1:
		# 유성우: 하늘 무작위 위치에서 출발, 복사점 반대 방향(-radiant)으로 이동
		# → 뒤로 연장하면 복사점에서 수렴 (원근 수렴 효과 자동 성립)
		var az:  float = randf_range(0.0, 360.0)
		var alt: float = randf_range(10.0, 80.0)
		_meteor_head = _altaz_to_dir(alt, az) * r
		_meteor_dir  = -_shower_radiant.normalized()
	else:
		# 산발 유성: 무작위 방향
		var az:  float = randf_range(0.0, 360.0)
		var alt: float = randf_range(25.0, 75.0)
		_meteor_head = _altaz_to_dir(alt, az) * r
		var down: Vector3 = -_meteor_head.normalized()
		var side: Vector3 = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		_meteor_dir = (down * randf_range(0.6, 1.0) + side * randf_range(0.1, 0.6)).normalized()
	_meteor_len = r * deg_to_rad(randf_range(8.0, 28.0))
	_meteor_dur = randf_range(0.15, 0.55)
	var roll: float = randf()
	if roll < 0.15:
		_meteor_color = Color(0.70, 0.85, 1.00)   # 청백 (Mg/Ca, 고속)
	elif roll < 0.25:
		_meteor_color = Color(1.00, 0.72, 0.38)   # 주황 (Fe, 저속)
	else:
		_meteor_color = Color(1.00, 0.97, 0.88)   # 황백 (일반)
	_meteor_t = 0.0

func _draw_meteor() -> void:
	_meteor_mesh.clear_surfaces()
	_meteor_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	# 머리 위치: t에 따라 이동
	var head: Vector3   = _meteor_head + _meteor_dir * _meteor_len * _meteor_t
	# 꼬리 길이: 전체 궤적의 35%
	var tail_len: float = _meteor_len * 0.35
	# 생애 sin 페이드: 시작·끝 부드럽게
	var fade: float = sin(clampf(_meteor_t * PI, 0.0, PI))
	const N: int = 10
	for i in range(N):
		var t0: float   = float(i)     / N
		var t1: float   = float(i + 1) / N
		var p0: Vector3 = head - _meteor_dir * tail_len * t0
		var p1: Vector3 = head - _meteor_dir * tail_len * t1
		# 머리(t0=0)→꼬리(t0=1) 방향으로 alpha 감소
		var a0: float = (1.0 - t0) * fade
		var a1: float = (1.0 - t1) * fade
		_meteor_mesh.surface_set_color(Color(_meteor_color.r, _meteor_color.g, _meteor_color.b, a0))
		_meteor_mesh.surface_add_vertex(p0)
		_meteor_mesh.surface_set_color(Color(_meteor_color.r, _meteor_color.g, _meteor_color.b, a1))
		_meteor_mesh.surface_add_vertex(p1)
	_meteor_mesh.surface_end()
	_meteor_inst.visible = true

func _update_meteor(sun_altaz: Vector2, cloud_props: Dictionary, dt: Dictionary, hour_utc: float, latitude: float, longitude: float, delta: float) -> void:
	var night_blend: float = clampf(-sun_altaz.x / 6.0, 0.0, 1.0)
	var star_vis: float    = night_blend * (1.0 - cloud_props["okta"])
	if star_vis < 0.15:
		_meteor_inst.visible = false
		_meteor_t = -1.0
		return
	# 유성우 상태 계산 (복사점 방향 + 강도)
	var jd:   float = Astronomy.julian_day(dt["year"], dt["month"], dt["day"], hour_utc)
	var gmst: float = Astronomy.gmst_deg(jd)
	var sh_state: Array = _get_shower_state(dt, gmst, latitude, longitude)
	_shower_intensity = sh_state[0]
	_shower_radiant   = sh_state[1]
	# 진행 중인 유성 업데이트
	if _meteor_t >= 0.0:
		_meteor_t += delta / max(_meteor_dur, 0.01)
		if _meteor_t >= 1.0:
			_meteor_t = -1.0
			_meteor_inst.visible = false
		else:
			_draw_meteor()
		return
	# 다음 유성 대기
	_meteor_next -= delta
	if _meteor_next <= 0.0:
		_spawn_meteor()
		# 산발 유성 실제 빈도: 시간당 5~10개 = 360~720초 간격 (전 하늘 ZHR 기준)
		# 유성우 중: 강도에 비례해 간격 단축 (ZHR 120 → 최대 5× 단축)
		var interval: float = randf_range(360.0, 720.0) / max(star_vis, 0.1)
		interval /= max(1.0, 1.0 + _shower_intensity * 4.0)
		_meteor_next = interval

# ── 유성우 ───────────────────────────────────────────────────────────
# 현재 날짜에서 가장 강한 유성우의 [강도, 복사점 방향] 반환
func _get_shower_state(dt: Dictionary, gmst: float, lat: float, lon: float) -> Array:
	var best_i: float   = 0.0
	var best_r: Vector3 = Vector3.UP
	for sh in SHOWERS:
		var pm: int   = sh[0]; var pd: int   = sh[1]
		var ra: float = sh[2]; var dec: float = sh[3]
		var zhr: int  = sh[4]; var hw: int   = sh[5]
		# 날짜 차이 (일), 연도 경계 처리
		var sim_doy:  int = _day_of_year(dt["month"], dt["day"])
		var peak_doy: int = _day_of_year(pm, pd)
		var diff: int = sim_doy - peak_doy
		if diff >  183: diff -= 366
		if diff < -183: diff += 366
		var intensity: float = exp(-float(diff * diff) / float(hw * hw))
		if intensity < 0.05:
			continue
		# 복사점 고도 계산 — 지평선 아래면 그 지역에서 관측 불가
		var altaz: Vector2 = Astronomy.radec_to_altaz(ra, dec, gmst, lat, lon)
		if altaz.x < 0.0:
			continue
		# ZHR 정규화 (최대 120 기준) × 복사점 고도 sin(alt) × 피크 강도
		intensity *= (float(zhr) / 120.0) * sin(deg_to_rad(altaz.x))
		if intensity > best_i:
			best_i = intensity
			best_r = _altaz_to_dir(altaz.x, altaz.y)
	return [best_i, best_r]

static func _day_of_year(month: int, day: int) -> int:
	const DAYS: Array = [0,31,59,90,120,151,181,212,243,273,304,334]
	return DAYS[month - 1] + day

# ── 혜성 ─────────────────────────────────────────────────────────────
func _build_comet() -> void:
	# 핵: billboard QuadMesh + 방사형 글로우
	# 6×6: 밝은 핵 FWHM≈0.34°, 코마 직경≈0.73° (Hale-Bopp 급 밝은 혜성 기준)
	var quad := QuadMesh.new()
	quad.size = Vector2(6.0, 6.0)
	_comet_nuc_inst = MeshInstance3D.new()
	_comet_nuc_inst.mesh = quad
	_comet_nuc_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var nuc_shader := Shader.new()
	nuc_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float brightness = 0.0;
uniform vec3  nuc_color  = vec3(1.0, 0.98, 0.92);
void vertex() {
\t// 태양과 동일한 뷰 공간 빌보드 — render_mode billboard은 Godot4 spatial에서 무효
\tvec4 center_view = VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
\tPOSITION = PROJECTION_MATRIX * (center_view + vec4(VERTEX.xy, 0.0, 0.0));
}
void fragment() {
\tvec2 uv = UV * 2.0 - 1.0;
\tfloat r2 = dot(uv, uv);
\t// 원형 마스크: r2>1.0에서 0 → 사각 Quad 경계 완전 제거
\tfloat mask = 1.0 - smoothstep(0.7, 1.0, r2);
\t// 날카로운 핵(×18) + 코마 광무(×3.5) 이중 레이어
\tfloat core = exp(-r2 * 18.0) * 1.3;
\tfloat coma = exp(-r2 * 3.5) * 0.4;
\tALBEDO = nuc_color;
\tALPHA  = clamp((core + coma) * mask * brightness, 0.0, 1.0);
}
"""
	_comet_nuc_mat = ShaderMaterial.new()
	_comet_nuc_mat.shader = nuc_shader
	_comet_nuc_mat.set_shader_parameter("brightness", 0.0)
	_comet_nuc_inst.material_override = _comet_nuc_mat
	_comet_nuc_inst.visible = false
	add_child(_comet_nuc_inst)
	# 꼬리용 공유 셰이더: UV.y=0/1이 가장자리, UV.y=0.5가 중심
	# 가우시안 단면으로 날카로운 도형 느낌 제거 → 빛줄기 느낌
	var tail_s := Shader.new()
	tail_s.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
void fragment() {
\tfloat cx = UV.y * 2.0 - 1.0;          // -1(가장자리) ~ 0(중심) ~ +1(반대 가장자리)
\tfloat soft = exp(-cx * cx * 5.0);      // 가우시안 단면 — 가장자리에서 자연스럽게 0으로
\tALBEDO = COLOR.rgb;
\tALPHA  = COLOR.a * soft;
}
"""
	_comet_ion_mesh  = ImmediateMesh.new()
	_comet_ion_inst  = MeshInstance3D.new()
	_comet_ion_inst.mesh = _comet_ion_mesh
	_comet_ion_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ion_mat := ShaderMaterial.new(); ion_mat.shader = tail_s
	_comet_ion_inst.material_override = ion_mat
	_comet_ion_inst.visible = false
	add_child(_comet_ion_inst)
	_comet_dust_mesh = ImmediateMesh.new()
	_comet_dust_inst = MeshInstance3D.new()
	_comet_dust_inst.mesh = _comet_dust_mesh
	_comet_dust_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dust_mat := ShaderMaterial.new(); dust_mat.shader = tail_s
	_comet_dust_inst.material_override = dust_mat
	_comet_dust_inst.visible = false
	add_child(_comet_dust_inst)

func _draw_comet(cpos: Vector3, sun_altaz: Vector2, bright: float) -> void:
	_comet_nuc_inst.global_position = cpos
	_comet_nuc_mat.set_shader_parameter("brightness", clampf(bright * 1.5, 0.0, 3.0))
	_comet_nuc_inst.visible = true

	var sun3: Vector3      = _altaz_to_dir(sun_altaz.x, sun_altaz.y).normalized()
	var away: Vector3      = -sun3
	var toward: Vector3    = cpos.normalized()   # 관측자 → 혜성 방향
	var ion_len: float     = cpos.length() * deg_to_rad(18.0) * bright

	# 꼬리 리본 폭 방향 — away ⊥ toward 평면에서 결정 (특이점 방지)
	var raw_perp: Vector3 = away.cross(toward)
	if raw_perp.length() < 0.01:
		raw_perp = away.cross(Vector3.UP if abs(away.y) < 0.85 else Vector3.RIGHT)
	var ion_perp: Vector3  = raw_perp.normalized()

	# ── 이온 꼬리: 청백색 테이퍼 리본 ─────────────────────────────────
	# UV.y: 1=+가장자리, 0=-가장자리 → 셰이더 가우시안 단면으로 빛줄기 표현
	# 가우시안 FWHM = 0.372 × 전폭. half-width=0.7° → FWHM≈0.52° (Hale-Bopp/NEOWISE 실측 0.3–1°)
	var ion_base_w: float  = cpos.length() * deg_to_rad(0.7)
	_comet_ion_mesh.clear_surfaces()
	_comet_ion_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	const NT: int = 32
	for i in range(NT + 1):
		var t: float     = float(i) / NT
		var pos: Vector3 = cpos + away * ion_len * t
		var w: float     = ion_base_w * (1.0 - t * 0.85)  # 끝에서 15% 폭 유지 → 급격한 수렴 방지
		var a: float     = (1.0 - t * t) * bright
		var col := Color(0.62, 0.78, 1.0, a)
		_comet_ion_mesh.surface_set_uv(Vector2(t, 1.0))
		_comet_ion_mesh.surface_set_color(col)
		_comet_ion_mesh.surface_add_vertex(pos + ion_perp * w)
		_comet_ion_mesh.surface_set_uv(Vector2(t, 0.0))
		_comet_ion_mesh.surface_set_color(col)
		_comet_ion_mesh.surface_add_vertex(pos - ion_perp * w)
	_comet_ion_mesh.surface_end()
	_comet_ion_inst.visible = true

	# ── 먼지 꼬리: 황백색 넓은 팬 리본 ────────────────────────────────
	# 공전 방향 성분 추가로 살짝 굽음 / 핵 근처가 넓고 끝이 좁음
	var orb_raw: Vector3  = toward.cross(Vector3.UP if abs(toward.y) < 0.85 else Vector3.RIGHT)
	var orb_perp: Vector3 = orb_raw.normalized()
	var dust_dir: Vector3 = (away * 0.80 + orb_perp * 0.35).normalized()
	var dust_len: float   = ion_len * 0.75

	var d_raw: Vector3    = dust_dir.cross(toward)
	if d_raw.length() < 0.01:
		d_raw = dust_dir.cross(Vector3.UP if abs(dust_dir.y) < 0.85 else Vector3.RIGHT)
	var dust_perp: Vector3 = d_raw.normalized()
	# half-width=1.5° → FWHM≈1.12° (실제 먼지 꼬리 1–3°)
	var dust_base_w: float = cpos.length() * deg_to_rad(1.5)

	_comet_dust_mesh.clear_surfaces()
	_comet_dust_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(NT + 1):
		var t: float     = float(i) / NT
		var pos: Vector3 = cpos + dust_dir * dust_len * t
		# 먼지 꼬리: 핵 근처 넓고 끝은 30%로 수렴 (실제 먼지 팬 형태)
		var w: float     = dust_base_w * lerp(1.0, 0.30, t)
		var a: float     = (1.0 - t) * bright * 0.55
		var col := Color(1.0, 0.94, 0.78, a)
		_comet_dust_mesh.surface_set_uv(Vector2(t, 1.0))
		_comet_dust_mesh.surface_set_color(col)
		_comet_dust_mesh.surface_add_vertex(pos + dust_perp * w)
		_comet_dust_mesh.surface_set_uv(Vector2(t, 0.0))
		_comet_dust_mesh.surface_set_color(col)
		_comet_dust_mesh.surface_add_vertex(pos - dust_perp * w)
	_comet_dust_mesh.surface_end()
	_comet_dust_inst.visible = true

func _update_comet(sun_altaz: Vector2, dt: Dictionary, hour_utc: float, latitude: float, longitude: float) -> void:
	# 테스트 모드: 고도 45°, 정남 방향에 밝은 혜성 강제 표시
	# 태양은 서쪽 25°로 고정 — 실제 태양이 정남쪽에 있으면 away·toward가 반평행이 되어
	# 리본 폭 방향이 0벡터로 수렴, 꼬리가 납작한 사각형으로 보이는 문제 방지
	if _comet_test_mode:
		var test_sun_altaz := Vector2(25.0, 270.0)   # 서쪽 고도 25°
		_draw_comet(_altaz_to_dir(45.0, 180.0) * 395.0, test_sun_altaz, 1.0)
		return
	var jd:   float = Astronomy.julian_day(dt["year"], dt["month"], dt["day"], hour_utc)
	var gmst: float = Astronomy.gmst_deg(jd)
	# ── 혜성 위치 보간 ─────────────────────────────────────────────────
	var found:      bool  = false
	var comet_ra:   float = 0.0
	var comet_dec:  float = 0.0
	var comet_mag:  float = 10.0
	for comet in COMETS:
		var frames: Array = comet[1]
		if frames.size() < 2:
			continue
		var jd0: float = Astronomy.julian_day(frames[0][0],                frames[0][1],                frames[0][2],                0.0)
		var jd1: float = Astronomy.julian_day(frames[frames.size()-1][0],  frames[frames.size()-1][1],  frames[frames.size()-1][2],  0.0)
		if jd < jd0 or jd > jd1 + 1.0:
			continue
		for i in range(frames.size() - 1):
			var fa: float = Astronomy.julian_day(frames[i][0],   frames[i][1],   frames[i][2],   0.0)
			var fb: float = Astronomy.julian_day(frames[i+1][0], frames[i+1][1], frames[i+1][2], 0.0)
			if jd >= fa and jd <= fb + 0.001:
				var t: float = clampf((jd - fa) / max(fb - fa, 0.001), 0.0, 1.0)
				comet_ra  = lerp(float(frames[i][3]),   float(frames[i+1][3]),   t)
				comet_dec = lerp(float(frames[i][4]),   float(frames[i+1][4]),   t)
				comet_mag = lerp(float(frames[i][5]),   float(frames[i+1][5]),   t)
				found = true
				break
		if found:
			break
	if not found or comet_mag > 5.5:
		_comet_nuc_inst.visible  = false
		_comet_ion_inst.visible  = false
		_comet_dust_inst.visible = false
		return
	# 고도/방위각
	var ca: Vector2 = Astronomy.radec_to_altaz(comet_ra, comet_dec, gmst, latitude, longitude)
	if ca.x < 3.0:
		_comet_nuc_inst.visible  = false
		_comet_ion_inst.visible  = false
		_comet_dust_inst.visible = false
		return
	var r: float      = 395.0
	var cpos: Vector3 = _altaz_to_dir(ca.x, ca.y) * r
	var bright: float = clampf((5.5 - comet_mag) / 5.5, 0.0, 1.0)
	_draw_comet(cpos, sun_altaz, bright)

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

# B-V 색지수 기반 스펙트럼 색상 — 실제 B-V값에서 변환한 RGB (감마 보정 없음, HDR 값 그대로)
# 참조: Allen's Astrophysical Quantities, 5th ed. / SIMBAD catalog B-V indices
# [RA°, Dec°, R, G, B] — RA/Dec는 J2000.0 도 단위, 허용 오차 ±0.8°
static func _star_spectral_color(ra: float, dec: float) -> Color:
	# 밝은 별 스펙트럼 색 테이블 (1등성 이상 + 색이 특히 뚜렷한 별)
	# 청색(B형): (0.72, 0.82, 1.0) / 청백(A형): (0.84, 0.90, 1.0) / 백색(F형): (1.0, 0.97, 0.88)
	# 황색(G형): (1.0, 0.92, 0.72) / 주황(K형): (1.0, 0.78, 0.48) / 적색(M형): (1.0, 0.55, 0.30)
	const TABLE: Array = [
		# 이름         RA       Dec       R     G     B        스펙트럼
		[101.287, -16.716, 0.87, 0.92, 1.00],  # Sirius      A1V  청백
		[ 95.988, -52.696, 0.98, 0.98, 1.00],  # Canopus     F0I  백
		[213.915,  19.182, 1.00, 0.76, 0.44],  # Arcturus    K1.5 주황
		[279.235,  38.784, 0.82, 0.89, 1.00],  # Vega        A0V  청백
		[ 79.172,  45.998, 1.00, 0.92, 0.70],  # Capella     G5   황
		[ 78.634,  -8.201, 0.78, 0.87, 1.00],  # Rigel       B8I  청백
		[114.828,   5.225, 1.00, 0.97, 0.87],  # Procyon     F5   백황
		[ 24.429, -57.237, 0.76, 0.85, 1.00],  # Achernar    B6V  청
		[ 88.792,   7.407, 1.00, 0.52, 0.28],  # Betelgeuse  M2I  적등
		[297.696,   8.868, 1.00, 0.98, 0.90],  # Altair      A7V  백
		[ 68.980,  16.509, 1.00, 0.72, 0.38],  # Aldebaran   K5   적주황
		[247.352, -26.432, 1.00, 0.46, 0.24],  # Antares     M1.5 적
		[201.298, -11.161, 0.74, 0.84, 1.00],  # Spica       B1V  청
		[116.329,  28.026, 1.00, 0.86, 0.62],  # Pollux      K0   주황
		[344.413, -29.622, 1.00, 0.98, 0.93],  # Fomalhaut   A4V  백
		[310.358,  45.280, 1.00, 0.99, 0.96],  # Deneb       A2I  백
		[152.093,  11.967, 0.80, 0.88, 1.00],  # Regulus     B7V  청백
		[104.656, -28.972, 0.75, 0.84, 1.00],  # Adhara      B2II 청
		[113.649,  31.889, 0.86, 0.92, 1.00],  # Castor      A1V  청백
		[ 81.283,   6.350, 0.75, 0.85, 1.00],  # Bellatrix   B2   청
		[ 81.572,  28.608, 0.82, 0.89, 1.00],  # Elnath      B7   청백
		[253.084, -42.998, 1.00, 0.97, 0.88],  # Sargas      F1   백
		[193.507,  55.960, 0.90, 0.94, 1.00],  # Alioth      A0   청백
		[276.992, -34.385, 0.90, 0.95, 1.00],  # Kaus Aus.   B9   백
		[ 99.428,  16.399, 1.00, 0.99, 0.94],  # Alhena      A0   백
		[219.919, -60.833, 1.00, 0.94, 0.76],  # Rigil Kent. G2V  황
		[210.956, -60.373, 0.73, 0.83, 1.00],  # Hadar       B1   청
		# 남반구 밝은 별 (남위 25° 이남에서 관측 가능)
		[186.650, -63.099, 0.72, 0.82, 1.00],  # Acrux  α Cru B0.5 청
		[191.930, -59.689, 0.72, 0.82, 1.00],  # Mimosa β Cru B0.5 청
		[187.791, -57.113, 1.00, 0.50, 0.25],  # Gacrux γ Cru M4   적 (남반구 붉은 별 대표)
		[125.629, -59.509, 1.00, 0.82, 0.56],  # Avior  ε Car K0+B 주황백
		[138.301, -69.717, 0.90, 0.95, 1.00],  # Miaplacidus β Car A2 청백
		[204.972, -53.466, 0.73, 0.83, 1.00],  # ε Cen  B1   청
		[ 29.692, -61.400, 0.80, 0.88, 1.00],  # β Eri  A3   청백
	]
	const TOL2: float = 0.64   # 허용 오차 0.8°의 제곱
	for entry in TABLE:
		var dra: float  = ra  - entry[0]
		var ddec: float = dec - entry[1]
		if dra * dra + ddec * ddec < TOL2:
			return Color(entry[2], entry[3], entry[4])
	return Color(1.0, 1.0, 1.0)   # 목록에 없는 별: 흰색

static func _sun_illuminance(alt_deg: float) -> float:
	var anchors_alt := [-18.0, -12.0, -6.0, 0.0, 10.0, 30.0, 60.0, 90.0]
	# -12° 실측: 0.002–0.004 lux (항해박명 끝 — 지평선 겨우 구분), 10° 실측: ~9,000 lux
	var anchors_lux := [0.0008, 0.003, 3.4, 400.0, 9000.0, 50000.0, 90000.0, 100000.0]
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

# ── Preetham(1999) 대기 산란 모델 ─────────────────────────────────────────
# "A Practical Analytic Model for Daylight", Preetham, Shirley, Smits (1999)
# sun_elev_deg: 태양 고도각 (0=지평선, 90=천정). 음수는 0으로 클램프 후 호출.
# turbidity: 대기 혼탁도 T (2=맑음, 10=탁함). 권장 기본값 3.0.
# 반환: [Color zenith_top, Color horizon] — 선형 광색(HDR, >1 가능), ProceduralSkyMaterial에 직접 설정.
# 보정 기준: T=3, θ_s=45°(고도45°) 에서 청색 채널 ≈ 0.95 (SCALE=0.05)
static func _preetham_sky_colors(sun_elev_deg: float, turbidity: float) -> Array:
	var T  := clampf(turbidity, 2.0, 10.0)
	var T2 := T * T
	# 태양 천정각 (0=태양이 바로 위, π/2=지평선)
	var ts  := deg_to_rad(clampf(90.0 - sun_elev_deg, 0.0, 90.0))
	var ts2 := ts * ts
	var ts3 := ts2 * ts

	# 천정 휘도 Yz (kcd/m²)
	var chi := (4.0/9.0 - T/120.0) * (PI - 2.0*ts)
	var Yz  := maxf((4.0453*T - 4.9710) * tan(chi) - 0.2155*T + 2.4192, 0.01)

	# 천정 색도 (CIE 1931 x, y)
	var xz := clampf(
		T2*(0.00216*ts3 - 0.00375*ts2 + 0.00209*ts)
		+ T*(-0.02903*ts3 + 0.06377*ts2 - 0.03202*ts + 0.00394)
		+ (0.11693*ts3 - 0.21196*ts2 + 0.06052*ts + 0.25886), 0.01, 0.8)
	var yz := clampf(
		T2*(0.00275*ts3 - 0.00610*ts2 + 0.00317*ts)
		+ T*(-0.04214*ts3 + 0.08970*ts2 - 0.04153*ts + 0.00516)
		+ (0.15346*ts3 - 0.26756*ts2 + 0.06670*ts + 0.26688), 0.01, 0.8)

	# Perez 계수 (Y=휘도, _x=색도x, _yy=색도y)
	var A_Y  :=  0.1787*T - 1.4630; var B_Y  := -0.3554*T + 0.4275
	var C_Y  := -0.0227*T + 5.3251; var D_Y  :=  0.1206*T - 2.5771; var E_Y  := -0.0670*T + 0.3703
	var A_x  := -0.0193*T - 0.2592; var B_x  := -0.0665*T + 0.0008
	var C_x  := -0.0004*T + 0.2125; var D_x  := -0.0641*T - 0.8989; var E_x  := -0.0033*T + 0.0452
	var A_yy := -0.0167*T - 0.2608; var B_yy := -0.0950*T + 0.0092
	var C_yy := -0.0079*T + 0.2102; var D_yy := -0.0441*T - 1.6537; var E_yy := -0.0109*T + 0.0529

	# Perez 분포 F(theta, gamma) = (1+A·e^(B/cosθ))·(1+C·e^(D·γ)+E·cos²γ)
	# 천정 기준값 (θ=0, γ=ts): cos(0)=1, cos(ts)=cos_ts
	var cos_ts := cos(ts)
	var f0Y  := (1.0+A_Y *exp(B_Y ))*(1.0+C_Y *exp(D_Y *ts)+E_Y *cos_ts*cos_ts)
	var f0x  := (1.0+A_x *exp(B_x ))*(1.0+C_x *exp(D_x *ts)+E_x *cos_ts*cos_ts)
	var f0yy := (1.0+A_yy*exp(B_yy))*(1.0+C_yy*exp(D_yy*ts)+E_yy*cos_ts*cos_ts)

	# 지평선 샘플 (θ=89°, γ = π/2−ts : 태양 방향 기준 지평선)
	var th_h  := deg_to_rad(89.0)
	var gm_h  := maxf(0.0, PI * 0.5 - ts)
	var ct_h  := maxf(cos(th_h), 0.001)
	var cg_h  := cos(gm_h)
	var fhY  := (1.0+A_Y *exp(B_Y /ct_h))*(1.0+C_Y *exp(D_Y *gm_h)+E_Y *cg_h*cg_h)
	var fhx  := (1.0+A_x *exp(B_x /ct_h))*(1.0+C_x *exp(D_x *gm_h)+E_x *cg_h*cg_h)
	var fhyy := (1.0+A_yy*exp(B_yy/ct_h))*(1.0+C_yy*exp(D_yy*gm_h)+E_yy*cg_h*cg_h)

	# 지평선 xyY
	var hor_x := clampf(xz * fhx  / maxf(f0x,  0.001), 0.01, 0.8)
	var hor_y := clampf(yz * fhyy / maxf(f0yy, 0.001), 0.01, 0.8)
	var hor_Y := Yz * fhY / maxf(f0Y, 0.001)

	# xyY → XYZ → 선형 sRGB. SCALE=0.05: T=3, θ_s=45° 기준 청색채널≈0.95 목표
	const SCALE := 0.05
	var _to_rgb := func(cx:float, cy:float, Y:float) -> Color:
		if cy < 0.001: return Color(0.0, 0.0, 0.0)
		var X := Y * cx / cy
		var Z := Y * (1.0 - cx - cy) / cy
		return Color(
			maxf( 3.2405*X - 1.5371*Y - 0.4985*Z, 0.0),
			maxf(-0.9693*X + 1.8760*Y + 0.0416*Z, 0.0),
			maxf( 0.0556*X - 0.2040*Y + 1.0572*Z, 0.0))

	return [_to_rgb.call(xz,  yz,  Yz  * SCALE),
	        _to_rgb.call(hor_x, hor_y, hor_Y * SCALE)]
