class_name WorldSimSky
extends Node

const STARLIGHT_FLOOR_LUX: float = 0.0008

# 외부에서 읽는 출력값
var sky_brightness_safe: float     = 1.0
var sky_overcast_amt_current: float = 0.0
var cloud_tau_current: float        = 0.0

var _sun_light: DirectionalLight3D
var _moon_light: DirectionalLight3D
var _moon_mesh: MeshInstance3D
var _moon_shader_mat: ShaderMaterial
var _sun_mesh: MeshInstance3D
var _sun_shader_mat: ShaderMaterial
var _world_env: WorldEnvironment
var _sky_mat: ProceduralSkyMaterial
var _stars_mm: MultiMeshInstance3D
var _cloud_mesh: MeshInstance3D
var _cloud_shader_mat: ShaderMaterial
var _star_data: Array = []
var _current_exposure: float = 1.0  # 노출 스무딩 상태 (프레임 간 급격한 변화 방지)

# ── 빌드 ─────────────────────────────────────────────────────────────
func build() -> void:
	_load_star_catalog()
	_build_sky_and_lights()
	_build_stars()
	_build_clouds()

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
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = max(_star_data.size(), 1)
	_stars_mm.multimesh = mm
	var smat := StandardMaterial3D.new()
	smat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color   = Color(1, 1, 1)
	smat.emission_enabled = true
	smat.emission       = Color(1, 1, 1)
	smat.emission_energy_multiplier = 3.0
	smat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_stars_mm.material_override = smat
	add_child(_stars_mm)

func _build_clouds() -> void:
	_cloud_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	_cloud_mesh.mesh = plane
	_cloud_mesh.position = Vector3(0, 20, 0)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;
uniform float coverage : hint_range(0.0, 1.0) = 0.4;
uniform float density : hint_range(0.0, 1.0) = 0.5;
uniform float noise_scale : hint_range(1.0, 20.0) = 6.0;
uniform float softness : hint_range(0.02, 0.6) = 0.25;
uniform vec2 drift = vec2(0.0, 0.0);
uniform vec3 cloud_color : source_color = vec3(0.85, 0.86, 0.88);
uniform float brightness : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float a = hash(i); float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0)); float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}
void fragment() {
	vec2 uv = UV * noise_scale + drift;
	float n = noise(uv) * 0.5 + noise(uv * 2.3) * 0.3 + noise(uv * 4.1) * 0.2;
	float a = smoothstep(1.0 - coverage, 1.0 - coverage + softness, n) * density;
	ALBEDO = cloud_color * brightness;
	ALPHA = a;
}
"""
	_cloud_shader_mat = ShaderMaterial.new()
	_cloud_shader_mat.shader = shader
	_cloud_shader_mat.set_shader_parameter("coverage", 0.4)
	_cloud_shader_mat.set_shader_parameter("density", 0.5)
	_cloud_mesh.material_override = _cloud_shader_mat
	add_child(_cloud_mesh)

# ── 갱신 ─────────────────────────────────────────────────────────────
func update(
	sun_altaz: Vector2,
	moon: Dictionary,
	cloud_props: Dictionary,
	weather_type: String,
	wind_speed: float,
	wind_enabled: bool,
	lightning_flash: float,
	dt: Dictionary,
	hour_utc: float,
	latitude: float,
	longitude: float,
	delta: float
) -> void:
	_update_sky_and_lights(sun_altaz, moon, cloud_props, lightning_flash, delta)
	_update_stars(dt, hour_utc, latitude, longitude, cloud_props)
	_update_cloud_visual(cloud_props, weather_type, wind_speed, wind_enabled, delta)

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
	# 달 고도에 따른 색: 지평선 근처=오렌지, 상공=따뜻한 흰색 (대기 산란)
	var moon_warm: float = clampf(1.0 - moon_alt / 18.0, 0.0, 1.0)
	var moon_lit_c := Vector3(1.0, lerp(0.98, 0.62, moon_warm * 0.65), lerp(0.92, 0.28, moon_warm * 0.65))
	_moon_shader_mat.set_shader_parameter("lit_color", moon_lit_c)

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
	if lightning_flash > 0.0:
		exposure_ev = 0.0
	# FP16 HDR 버퍼 최솟값(6e-5) 대비 tonemap 보정 상한 = 2^4 = 16×
	# 이 이상은 FP16 양자화 오차가 증폭되어 분홍/초록 노이즈로 나타남
	# 낮→밤 급전환 방지: delta 기반 부드러운 스무딩 적용
	const EV_MAX: float = 4.0
	var target_exp: float = clampf(pow(2.0, exposure_ev), 0.5, pow(2.0, EV_MAX))
	_current_exposure = lerp(_current_exposure, target_exp, clampf(delta * 2.0, 0.0, 1.0))
	var exposure_mult: float = _current_exposure
	_sun_light.light_energy  = min(clampf(sun_lux / 100000.0 * 3.0, 0.0, 6.0), 6.0 / exposure_mult)
	_moon_light.light_energy = min(clampf(moon_lux / 0.27 * 0.6, 0.0, 0.6), 0.6 / exposure_mult) * exp(-(cloud_props["tau"] as float))

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

	if lightning_flash > 0.0:
		_sky_mat.sky_top_color      = Color(0.75, 0.8, 0.95)
		_sky_mat.sky_horizon_color  = Color(0.85, 0.87, 0.95)
		_world_env.environment.tonemap_exposure = 1.0

func _update_stars(dt: Dictionary, hour_utc: float, latitude: float, longitude: float, cloud_props: Dictionary) -> void:
	if _star_data.is_empty():
		return
	var elev_check: Vector2 = Astronomy.sun_altaz(dt["year"], dt["month"], dt["day"], hour_utc, latitude, longitude)
	var night_blend: float = clampf(-elev_check.x / 6.0, 0.0, 1.0)
	var cloud_block: float = cloud_props["okta"]
	var star_vis: float    = night_blend * (1.0 - cloud_block)
	var mat: StandardMaterial3D = _stars_mm.material_override
	mat.emission_energy_multiplier = lerp(0.0, 4.0, star_vis)
	mat.albedo_color = Color(1.0, 1.0, 1.0, star_vis)
	_stars_mm.visible = true
	if star_vis < 0.001:
		return
	var jd: float = Astronomy.julian_day(dt["year"], dt["month"], dt["day"], hour_utc)
	var g: float  = Astronomy.gmst_deg(jd)
	var mm := _stars_mm.multimesh
	var radius: float = 400.0
	for i in range(_star_data.size()):
		var star: Dictionary = _star_data[i]
		var altaz: Vector2 = Astronomy.radec_to_altaz(star["ra"], star["dec"], g, latitude, longitude)
		var dir: Vector3   = _altaz_to_dir(altaz.x, altaz.y)
		var mag: float     = star["mag"]
		var scale_: float  = clampf(remap(mag, -1.5, 5.0, 2.5, 0.3), 0.3, 2.5)
		var xf := Transform3D(Basis().scaled(Vector3(scale_, scale_, scale_)), dir * radius)
		mm.set_instance_transform(i, xf)

func _update_cloud_visual(cloud_props: Dictionary, weather_type: String, wind_speed: float, wind_enabled: bool, delta: float) -> void:
	var shape_presets := {
		"CLEAR":   {"visible": false, "y": 20.0, "scale": 6.0,  "soft": 0.25},
		"CIRRUS":  {"visible": true,  "y": 32.0, "scale": 14.0, "soft": 0.45},
		"CUMULUS": {"visible": true,  "y": 16.0, "scale": 3.5,  "soft": 0.18},
		"OVERCAST":{"visible": true,  "y": 13.0, "scale": 2.0,  "soft": 0.10},
		"RAIN":    {"visible": true,  "y": 18.0, "scale": 5.0,  "soft": 0.20},
		"SNOW":    {"visible": true,  "y": 18.0, "scale": 4.5,  "soft": 0.22},
	}
	var shape: Dictionary  = shape_presets.get(weather_type, shape_presets["CLEAR"])
	var coverage: float    = cloud_props["okta"]
	var density: float     = sky_overcast_amt_current
	var light_grey := Color(0.95, 0.95, 0.96)
	# 최저 밝기 0.38 제한 — 완전 검은 blob 방지 (실제 비구름도 일부 빛 투과)
	var dark_grey  := Color(0.38, 0.39, 0.42)
	var cloud_color: Color = light_grey.lerp(dark_grey, density)

	_cloud_mesh.visible    = shape["visible"]
	_cloud_mesh.position.y = shape["y"]
	_cloud_shader_mat.set_shader_parameter("coverage",    coverage)
	_cloud_shader_mat.set_shader_parameter("density",     clampf(density, 0.0, 1.0))
	_cloud_shader_mat.set_shader_parameter("noise_scale", shape["scale"])
	_cloud_shader_mat.set_shader_parameter("softness",    shape["soft"])
	_cloud_shader_mat.set_shader_parameter("cloud_color", cloud_color)
	_cloud_shader_mat.set_shader_parameter("brightness",  sky_brightness_safe)

	var wind_amt: float = wind_speed if wind_enabled else 0.0
	var drift_raw = _cloud_shader_mat.get_shader_parameter("drift")
	var drift: Vector2 = drift_raw if drift_raw != null else Vector2.ZERO
	drift += Vector2(wind_amt, wind_amt * 0.6) * delta * 0.05
	_cloud_shader_mat.set_shader_parameter("drift", drift)

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
